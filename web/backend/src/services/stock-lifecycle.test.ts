import test from 'node:test';
import assert from 'node:assert/strict';
import { cancelOrder } from './checkout.service';

type Doc = Record<string, unknown>;

/**
 * Stock must survive a full order lifecycle: reserved when the order is
 * placed, given back in full when it is released — and given back only once.
 */
class FakeDb {
  readonly docs = new Map<string, Doc>();

  seed(path: string, doc: Doc) {
    this.docs.set(path, doc);
  }

  collection(path: string) {
    return {
      doc: (id: string) => {
        const key = `${path}/${id}`;
        return {
          id,
          path: key,
          get: async () => ({
            exists: this.docs.has(key),
            id,
            data: () => (this.docs.has(key) ? { ...this.docs.get(key) } : undefined),
          }),
          update: async (data: Doc) => {
            this.docs.set(key, { ...(this.docs.get(key) ?? {}), ...data });
          },
          set: async (data: Doc, opts?: { merge?: boolean }) => {
            this.docs.set(
              key,
              opts?.merge ? { ...(this.docs.get(key) ?? {}), ...data } : { ...data }
            );
          },
          delete: async () => {
            this.docs.delete(key);
          },
        };
      },
    };
  }

  runTransaction<T>(fn: (txn: unknown) => Promise<T>): Promise<T> {
    const txn = {
      get: async (ref: { path: string }) => ({
        exists: this.docs.has(ref.path),
        data: () => (this.docs.has(ref.path) ? { ...this.docs.get(ref.path) } : undefined),
      }),
      set: async (ref: { path: string }, data: Doc) => {
        this.docs.set(ref.path, { ...(this.docs.get(ref.path) ?? {}), ...data });
      },
      update: async (ref: { path: string }, data: Doc) => {
        this.docs.set(ref.path, { ...(this.docs.get(ref.path) ?? {}), ...data });
      },
      delete: async (ref: { path: string }) => {
        this.docs.delete(ref.path);
      },
    };
    return fn(txn);
  }

  stock(id: string): number {
    return Number(this.docs.get(`products/${id}`)?.stock ?? -999);
  }
}

const BUYER = 'buyer-1';

function seedOrder(db: FakeDb, { qty, stock }: { qty: number; stock: number }) {
  db.seed('products/p-1', { name: 'Sofa', stock, supplierId: 'sup-1' });
  db.seed('orders/o-1', {
    orderNumber: 'ORD-1',
    status: 'pending',
    paymentStatus: 'unpaid',
    customerId: BUYER,
    supplierIds: ['sup-1'],
    items: [{ productId: 'p-1', quantity: qty, name: 'Sofa', price: 100 }],
  });
}

test('a released order gives the stock back in full (4 → 3 → 4)', async () => {
  const db = new FakeDb();
  // Stock sits at 3 because the order is holding 1 of the original 4.
  seedOrder(db, { qty: 1, stock: 3 });
  assert.equal(db.stock('p-1'), 3);

  await cancelOrder(BUYER, 'o-1', db as never);

  assert.equal(db.stock('p-1'), 4, 'the reserved unit is returned to stock');
  // A never-charged order is dropped outright — there is no money to show.
  assert.equal(db.docs.has('orders/o-1'), false);
});

test('a multi-unit order returns every unit', async () => {
  const db = new FakeDb();
  seedOrder(db, { qty: 2, stock: 2 }); // 4 units total, 2 held

  await cancelOrder(BUYER, 'o-1', db as never);

  assert.equal(db.stock('p-1'), 4);
});

test('cancelling twice never returns the stock twice', async () => {
  const db = new FakeDb();
  seedOrder(db, { qty: 1, stock: 3 });

  await cancelOrder(BUYER, 'o-1', db as never);
  assert.equal(db.stock('p-1'), 4);

  await assert.rejects(() => cancelOrder(BUYER, 'o-1', db as never));
  assert.equal(db.stock('p-1'), 4, 'the second attempt changed nothing');
});

test('an order only speaks for its own units', async () => {
  const db = new FakeDb();
  seedOrder(db, { qty: 1, stock: 3 });
  db.seed('products/p-2', { name: 'Lamp', stock: 7, supplierId: 'sup-1' });

  await cancelOrder(BUYER, 'o-1', db as never);

  assert.equal(db.stock('p-1'), 4);
  assert.equal(db.stock('p-2'), 7, 'products the order never touched are unchanged');
});
