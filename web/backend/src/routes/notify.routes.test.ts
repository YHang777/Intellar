import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { errorHandler } from '../middleware/errorHandler';
import { createNotifyRouter, type NotifyRouteDeps } from './notify.routes';
import { notifyUser, type NotificationDeps, type PushMessage } from '../services/notifications.service';
import type { AuditEntry } from '../services/audit.service';

type Doc = Record<string, unknown>;

// Minimal path-keyed Firestore fake: collection/doc chains, get/set/update/
// delete/add, sub-collection listing and an array-contains where().limit().
class FakeDb {
  readonly docs = new Map<string, Doc>();
  private seq = 0;

  collection(path: string) {
    return new FakeCollection(this, path);
  }

  seed(path: string, doc: Doc) {
    this.docs.set(path, doc);
  }

  children(path: string): [string, Doc][] {
    const prefix = `${path}/`;
    return [...this.docs.entries()].filter(
      ([k]) => k.startsWith(prefix) && !k.slice(prefix.length).includes('/')
    );
  }

  nextId() {
    this.seq += 1;
    return `auto${this.seq}`;
  }
}

class FakeCollection {
  constructor(private db: FakeDb, private path: string, private filters: [string, unknown][] = [], private max = 1e9) {}

  doc(id?: string) {
    return new FakeDocRef(this.db, `${this.path}/${id ?? this.db.nextId()}`);
  }

  async add(data: Doc) {
    const ref = this.doc();
    await ref.set(data);
    return ref;
  }

  where(field: string, _op: string, value: unknown) {
    return new FakeCollection(this.db, this.path, [...this.filters, [field, value]], this.max);
  }

  limit(n: number) {
    return new FakeCollection(this.db, this.path, this.filters, n);
  }

  async get() {
    const pick = (doc: Doc, field: string) =>
      field.split('.').reduce<unknown>((acc, k) => (acc as Doc | undefined)?.[k], doc);
    const rows = this.db
      .children(this.path)
      .filter(([, d]) =>
        this.filters.every(([f, v]) => {
          const got = pick(d, f);
          return Array.isArray(got) ? got.includes(v) : got === v;
        })
      )
      .slice(0, this.max);
    return {
      docs: rows.map(([k, d]) => ({ id: k.split('/').pop()!, data: () => ({ ...d }) })),
    };
  }
}

class FakeDocRef {
  constructor(private db: FakeDb, readonly path: string) {}

  get id() {
    return this.path.split('/').pop()!;
  }

  collection(name: string) {
    return new FakeCollection(this.db, `${this.path}/${name}`);
  }

  async get() {
    const d = this.db.docs.get(this.path);
    return { exists: d !== undefined, id: this.id, data: () => (d ? { ...d } : undefined) };
  }

  async set(data: Doc, opts?: { merge?: boolean }) {
    this.db.docs.set(this.path, opts?.merge ? { ...(this.db.docs.get(this.path) ?? {}), ...data } : { ...data });
  }

  async update(data: Doc) {
    this.db.docs.set(this.path, { ...(this.db.docs.get(this.path) ?? {}), ...data });
  }

  async delete() {
    this.db.docs.delete(this.path);
  }
}

function notificationDeps(db: FakeDb, pushes: PushMessage[], invalid: string[] = []): NotificationDeps {
  return {
    db: () => db as never,
    push: async (msg) => {
      pushes.push(msg);
      return { invalidTokens: msg.tokens.filter((t) => invalid.includes(t)) };
    },
  };
}

async function harness(db: FakeDb, callerUid: string, opts: { now?: Date } = {}) {
  const pushes: PushMessage[] = [];
  const audits: AuditEntry[] = [];
  const authorize: RequestHandler = (req, _res, next) => {
    req.user = { uid: callerUid, email: null, name: null, adminClaim: false };
    next();
  };
  const deps: NotifyRouteDeps = {
    authorize,
    db: () => db as never,
    notifications: notificationDeps(db, pushes),
    audit: async (e) => {
      audits.push(e);
    },
    now: () => opts.now ?? new Date('2026-11-17T03:00:00Z'),
  };
  const app = express();
  app.use(express.json());
  app.use('/api', createNotifyRouter(deps));
  app.use(errorHandler);
  const server: Server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api`;
  const post = async (path: string, body: unknown) => {
    const r = await fetch(base + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    return { status: r.status, body: (await r.json()) as Record<string, any> };
  };
  return { post, pushes, audits, close: () => new Promise<void>((r) => server.close(() => r())) };
}

function inbox(db: FakeDb, uid: string) {
  return db.children(`users/${uid}/notifications`).map(([, d]) => d);
}

test('notifyUser stores, pushes and prunes dead tokens', async () => {
  const db = new FakeDb();
  db.seed('users/u1', { role: 'homeowner' });
  db.seed('users/u1/fcmTokens/good', {});
  db.seed('users/u1/fcmTokens/dead', {});
  const pushes: PushMessage[] = [];
  const out = await notifyUser(notificationDeps(db, pushes, ['dead']), 'u1', {
    kind: 'order_update',
    title: 'Order confirmed',
    body: 'Hi',
    data: { orderId: 'o1' },
  });
  assert.deepEqual(out, { stored: true, pushed: 1 });
  assert.equal(inbox(db, 'u1').length, 1);
  assert.equal(pushes[0].data.orderId, 'o1');
  assert.equal(pushes[0].data.kind, 'order_update');
  assert.ok(pushes[0].data.notificationId);
  assert.equal(db.docs.has('users/u1/fcmTokens/dead'), false);
  assert.equal(db.docs.has('users/u1/fcmTokens/good'), true);
});

test('settings: order pushes can be muted, promotions dropped entirely', async () => {
  const db = new FakeDb();
  db.seed('users/u1', { notificationSettings: { orderUpdates: false, promotions: false } });
  db.seed('users/u1/fcmTokens/t', {});
  const pushes: PushMessage[] = [];
  const deps = notificationDeps(db, pushes);
  const order = await notifyUser(deps, 'u1', { kind: 'order_update', title: 'a', body: 'b' });
  assert.deepEqual(order, { stored: true, pushed: 0 }, 'transactional rows stay in the inbox');
  const promo = await notifyUser(deps, 'u1', { kind: 'promotion', title: 'a', body: 'b' });
  assert.deepEqual(promo, { stored: false, pushed: 0 });
  assert.equal(pushes.length, 0);
  assert.equal(inbox(db, 'u1').length, 1);
});

test('order-status: only a seller on the order can announce, buyer gets it', async () => {
  const db = new FakeDb();
  db.seed('users/buyer', {});
  db.seed('orders/o1', { supplierIds: ['seller'], customerId: 'buyer', status: 'waitingCollection', orderNumber: 'ORD-1' });
  const outsider = await harness(db, 'stranger');
  try {
    assert.equal((await outsider.post('/notify/order-status', { orderId: 'o1' })).status, 403);
  } finally {
    await outsider.close();
  }
  const seller = await harness(db, 'seller');
  try {
    const r = await seller.post('/notify/order-status', { orderId: 'o1' });
    assert.equal(r.status, 200);
    const rows = inbox(db, 'buyer');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].title, 'Ready for collection');
    assert.deepEqual(seller.audits[0], {
      actorId: 'seller', action: 'order.status', targetType: 'order', targetId: 'o1', details: { status: 'waitingCollection' },
    });
  } finally {
    await seller.close();
  }
});

test('quote: created pings the seller, contacted pings the buyer, roles enforced', async () => {
  const db = new FakeDb();
  db.seed('users/buyer', {});
  db.seed('users/seller', {});
  db.seed('quote_requests/q1', { customerId: 'buyer', supplierId: 'seller', productName: 'Sofa', quantity: 10, customerName: 'Aina' });
  const buyer = await harness(db, 'buyer');
  try {
    assert.equal((await buyer.post('/notify/quote', { quoteId: 'q1', event: 'contacted' })).status, 403);
    assert.equal((await buyer.post('/notify/quote', { quoteId: 'q1', event: 'created' })).status, 200);
    assert.match(String(inbox(db, 'seller')[0].body), /Aina asked for 10 × Sofa/);
  } finally {
    await buyer.close();
  }
  const seller = await harness(db, 'seller');
  try {
    assert.equal((await seller.post('/notify/quote', { quoteId: 'q1', event: 'contacted' })).status, 200);
    assert.equal(inbox(db, 'buyer')[0].title, 'The seller contacted you');
  } finally {
    await seller.close();
  }
});

test('new-product: fans out once to matching homeowners only', async () => {
  const db = new FakeDb();
  db.seed('products/p1', { supplierId: 'seller', name: 'Oak Table', designStyle: 'Classic', isActive: true, createdAt: '2026-11-17T02:50:00Z' });
  db.seed('users/fan', { role: 'homeowner', designPreferences: { styles: ['Classic'] } });
  db.seed('users/optout', { role: 'homeowner', designPreferences: { styles: ['Classic'] }, privacySettings: { personalisedRecommendations: false } });
  db.seed('users/other', { role: 'homeowner', designPreferences: { styles: ['Modern'] } });
  db.seed('users/rival', { role: 'supplier', designPreferences: { styles: ['Classic'] } });
  const seller = await harness(db, 'seller');
  try {
    const first = await seller.post('/notify/new-product', { productId: 'p1' });
    assert.equal(first.body.notified, 1);
    assert.equal(inbox(db, 'fan').length, 1);
    assert.equal(inbox(db, 'optout').length, 0);
    assert.equal(inbox(db, 'other').length, 0);
    assert.equal(inbox(db, 'rival').length, 0);
    const again = await seller.post('/notify/new-product', { productId: 'p1' });
    assert.equal(again.body.notified, 0, 'a retry never fans out twice');
    assert.equal(inbox(db, 'fan').length, 1);
  } finally {
    await seller.close();
  }
});

test('new-product: stale listings and other sellers are refused', async () => {
  const db = new FakeDb();
  db.seed('products/old', { supplierId: 'seller', name: 'Old', designStyle: 'Modern', isActive: true, createdAt: '2026-11-10T00:00:00Z' });
  db.seed('users/fan', { role: 'homeowner', designPreferences: { styles: ['Modern'] } });
  const seller = await harness(db, 'seller');
  try {
    assert.equal((await seller.post('/notify/new-product', { productId: 'old' })).body.notified, 0);
  } finally {
    await seller.close();
  }
  const rival = await harness(db, 'rival');
  try {
    assert.equal((await rival.post('/notify/new-product', { productId: 'old' })).status, 403);
  } finally {
    await rival.close();
  }
});

test('audit: only allow-listed client actions are recorded', async () => {
  const db = new FakeDb();
  const h = await harness(db, 'u1');
  try {
    assert.equal((await h.post('/audit', { action: 'profile.update' })).status, 200);
    assert.equal((await h.post('/audit', { action: 'order.paid' })).status, 400);
    assert.equal(h.audits.length, 1);
    assert.equal(h.audits[0].actorId, 'u1');
  } finally {
    await h.close();
  }
});
