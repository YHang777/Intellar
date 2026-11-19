import test from 'node:test';
import assert from 'node:assert/strict';
import type { Firestore } from 'firebase-admin/firestore';
import { expireUnpaidOrders, PAYMENT_WINDOW_MS } from './checkout.service';

type Doc = Record<string, unknown>;

class FakeDb {
  readonly docs = new Map<string, Doc>();
  seed(path: string, doc: Doc) {
    this.docs.set(path, doc);
  }
  private ref(key: string, id: string) {
    return {
      id,
      path: key,
      get: async () => ({
        exists: this.docs.has(key),
        id,
        data: () => (this.docs.has(key) ? { ...this.docs.get(key) } : undefined),
      }),
    };
  }
  collection(path: string) {
    return {
      doc: (id: string) => this.ref(`${path}/${id}`, id),
      where: (field: string, _op: string, value: unknown) => ({
        get: async () => ({
          docs: [...this.docs.entries()]
            .filter(([k, v]) => k.startsWith(`${path}/`) && v[field] === value)
            .map(([k, v]) => {
              const id = k.slice(path.length + 1);
              return { id, ref: this.ref(k, id), data: () => ({ ...v }) };
            }),
        }),
      }),
    };
  }
  runTransaction<T>(fn: (txn: unknown) => Promise<T>): Promise<T> {
    const txn = {
      get: async (ref: { path: string }) => ({
        exists: this.docs.has(ref.path),
        data: () => (this.docs.has(ref.path) ? { ...this.docs.get(ref.path) } : undefined),
      }),
      update: async (ref: { path: string }, data: Doc) => {
        this.docs.set(ref.path, { ...(this.docs.get(ref.path) ?? {}), ...data });
      },
      delete: async (ref: { path: string }) => {
        this.docs.delete(ref.path);
      },
    };
    return fn(txn);
  }
  stock(id: string) {
    return Number(this.docs.get(`products/${id}`)?.stock);
  }
  asFirestore() {
    return this as unknown as Firestore;
  }
}

const NOW = Date.parse('2026-11-19T10:00:00Z');
const minutesAgo = (m: number) => new Date(NOW - m * 60 * 1000).toISOString();

function seed(db: FakeDb, id: string, ageMin: number, extra: Doc = {}) {
  db.seed(`orders/${id}`, {
    status: 'pending',
    paymentStatus: 'unpaid',
    customerId: 'buyer',
    createdAt: minutesAgo(ageMin),
    items: [{ productId: 'p1', quantity: 2 }],
    ...extra,
  });
}

test('the payment window is 15 minutes', () => {
  assert.equal(PAYMENT_WINDOW_MS, 15 * 60 * 1000);
});

test('an unpaid checkout older than 15 minutes is cancelled and its stock returned', async () => {
  const db = new FakeDb();
  db.seed('products/p1', { stock: 3 });
  seed(db, 'fresh', 10, { paymentIntentId: 'pi_fresh' });
  seed(db, 'expired', 16, { paymentIntentId: 'pi_old' });
  const cancelled: string[] = [];

  const r = await expireUnpaidOrders(db.asFirestore(), {
    now: () => NOW,
    intentState: async () => ({ state: 'failed', paymentMethod: '' }),
    cancelIntent: async (id) => {
      cancelled.push(id);
    },
  });

  assert.equal(r.released, 1);
  assert.ok(db.docs.has('orders/fresh'), 'still inside the window');
  assert.ok(!db.docs.has('orders/expired'));
  assert.equal(db.stock('p1'), 5, 'both reserved units are back');
  assert.deepEqual(cancelled, ['pi_old'], 'the Stripe payment is cancelled too');
});

test('a payment still processing is left alone until an hour has passed', async () => {
  const db = new FakeDb();
  db.seed('products/p1', { stock: 3 });
  seed(db, 'bank-step', 30, { paymentIntentId: 'pi_proc' });
  const r = await expireUnpaidOrders(db.asFirestore(), {
    now: () => NOW,
    intentState: async () => ({ state: 'pending', paymentMethod: '' }),
    cancelIntent: async () => undefined,
  });
  assert.equal(r.released, 0);
  assert.ok(db.docs.has('orders/bank-step'));
  assert.equal(db.stock('p1'), 3);
});

test('a processing payment Stripe refuses to cancel keeps its reservation', async () => {
  const db = new FakeDb();
  db.seed('products/p1', { stock: 3 });
  seed(db, 'stuck', 90, { paymentIntentId: 'pi_stuck' });
  const r = await expireUnpaidOrders(db.asFirestore(), {
    now: () => NOW,
    intentState: async () => ({ state: 'pending', paymentMethod: '' }),
    cancelIntent: async () => {
      throw new Error('cannot cancel a processing intent');
    },
  });
  assert.equal(r.released, 0);
  assert.ok(db.docs.has('orders/stuck'));
});

test('paid and already-cancelled orders are never touched', async () => {
  const db = new FakeDb();
  db.seed('products/p1', { stock: 3 });
  seed(db, 'paid', 60, { paymentStatus: 'paid' });
  seed(db, 'cancelled', 60, { status: 'cancelled' });
  const r = await expireUnpaidOrders(db.asFirestore(), {
    now: () => NOW,
    intentState: async () => ({ state: 'failed', paymentMethod: '' }),
    cancelIntent: async () => undefined,
  });
  assert.equal(r.released, 0);
  assert.equal(db.stock('p1'), 3);
});
