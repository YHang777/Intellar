import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import { createProductViewsRouter, malaysiaDay } from './product-views.routes';

type Doc = Record<string, unknown>;

function fakeDb(docs: Map<string, Doc>) {
  const ref = (path: string) => ({ path });
  return {
    collection: (c: string) => ({ doc: (id: string) => ref(`${c}/${id}`) }),
    runTransaction: async <T>(fn: (txn: unknown) => Promise<T>) =>
      fn({
        get: async (r: { path: string }) => ({ exists: docs.has(r.path), data: () => docs.get(r.path) }),
        set: (r: { path: string }, d: Doc) => docs.set(r.path, { ...d }),
        update: (r: { path: string }, d: Doc) => {
          const cur = docs.get(r.path) ?? {};
          // FieldValue.increment(1) is opaque here; count calls instead.
          docs.set(r.path, { ...cur, viewCount: Number(cur.viewCount ?? 0) + 1, _incremented: d.viewCount !== undefined });
        },
      }),
  };
}

async function call(docs: Map<string, Doc>, uid: string, productId: string, now: Date) {
  const authorize: RequestHandler = (req, _res, next) => {
    req.user = { uid, email: null, name: null, adminClaim: false };
    next();
  };
  const app = express();
  app.use(express.json());
  app.use('/v', createProductViewsRouter({ authorize, db: () => fakeDb(docs) as never, now: () => now }));
  app.use((err: { statusCode?: number }, _q: express.Request, res: express.Response, _n: express.NextFunction) => {
    res.status(err.statusCode ?? 500).json({});
  });
  const server = app.listen(0);
  try {
    const r = await fetch(`http://127.0.0.1:${(server.address() as AddressInfo).port}/v`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ productId }),
    });
    return { status: r.status, body: (await r.json()) as { counted?: boolean } };
  } finally {
    server.close();
  }
}

test('one view per buyer per product per day; never the seller', async () => {
  const docs = new Map<string, Doc>([['products/p1', { supplierId: 'seller', viewCount: 0 }]]);
  const day1 = new Date('2026-11-19T03:00:00Z');
  const day2 = new Date('2026-11-20T03:00:00Z');

  assert.equal((await call(docs, 'buyer', 'p1', day1)).body.counted, true);
  assert.equal((await call(docs, 'buyer', 'p1', day1)).body.counted, false, 'refresh does not count');
  assert.equal((await call(docs, 'other', 'p1', day1)).body.counted, true, 'another buyer counts');
  assert.equal((await call(docs, 'seller', 'p1', day1)).body.counted, false, "seller's own view ignored");
  assert.equal((await call(docs, 'buyer', 'p1', day2)).body.counted, true, 'next day counts again');
  assert.equal(docs.get('products/p1')?.viewCount, 3);
  assert.equal((await call(docs, 'buyer', 'missing', day1)).status, 404);
});

test('days follow Malaysian time', () => {
  // 17:00 UTC is 01:00 next day in Malaysia.
  assert.equal(malaysiaDay(new Date('2026-11-19T17:00:00Z')), '2026-11-20');
  assert.equal(malaysiaDay(new Date('2026-11-19T15:59:00Z')), '2026-11-19');
});
