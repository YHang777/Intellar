import test from 'node:test';
import assert from 'node:assert/strict';
import type { Firestore } from 'firebase-admin/firestore';
import { changeUserRole } from './role.service';
import { ApiError } from '../lib/errors';

type Doc = Record<string, unknown>;

function get(doc: Doc, path: string): unknown {
  return path.split('.').reduce<unknown>((v, k) => (v as Doc | undefined)?.[k], doc);
}

class FakeDb {
  readonly docs = new Map<string, Doc>();
  seed(path: string, doc: Doc) {
    this.docs.set(path, doc);
  }
  collection(path: string) {
    const rows = () =>
      [...this.docs.entries()].filter(([k]) => k.startsWith(`${path}/`)).map(([, v]) => v);
    return {
      doc: (id: string) => {
        const key = `${path}/${id}`;
        return {
          get: async () => ({ exists: this.docs.has(key), data: () => this.docs.get(key) }),
          update: async (data: Doc) => {
            this.docs.set(key, { ...(this.docs.get(key) ?? {}), ...data });
          },
        };
      },
      where: (field: string, op: string, value: unknown) => ({
        limit: () => ({
          get: async () => {
            const hits = rows().filter((r) => {
              const v = get(r, field);
              return op === 'array-contains' ? Array.isArray(v) && v.includes(value) : v === value;
            });
            return { empty: hits.length === 0 };
          },
        }),
      }),
    };
  }
  asFirestore() {
    return this as unknown as Firestore;
  }
}

test('a new account registered as a seller can be switched to homeowner', async () => {
  const db = new FakeDb();
  db.seed('users/u1', { role: 'supplier', name: 'Ana', businessName: 'Ana', verificationStatus: 'pending' });
  const r = await changeUserRole('u1', 'homeowner', db.asFirestore());
  assert.equal(r.changed, true);
  assert.equal(db.docs.get('users/u1')?.role, 'homeowner');
  assert.equal(db.docs.get('users/u1')?.businessName, '');
  assert.equal(db.docs.get('users/u1')?.verificationStatus, 'none');
});

test('switching to seller fills the business details from the profile', async () => {
  const db = new FakeDb();
  db.seed('users/u2', { role: 'homeowner', name: 'Ben', phone: '012', address: 'Penang' });
  await changeUserRole('u2', 'supplier', db.asFirestore());
  const u = db.docs.get('users/u2');
  assert.equal(u?.role, 'supplier');
  assert.equal(u?.businessName, 'Ben');
  assert.equal(u?.businessAddress, 'Penang');
});

test('accounts with orders or listings are refused', async () => {
  const db = new FakeDb();
  db.seed('users/buyer', { role: 'homeowner' });
  db.seed('users/seller', { role: 'supplier' });
  db.seed('users/lister', { role: 'supplier' });
  db.seed('orders/o1', { customerId: 'buyer', supplierIds: ['seller'] });
  db.seed('products/p1', { supplier: { id: 'lister' } });

  for (const [uid, role] of [['buyer', 'supplier'], ['seller', 'homeowner'], ['lister', 'homeowner']] as const) {
    await assert.rejects(changeUserRole(uid, role, db.asFirestore()), (e: unknown) => {
      assert.ok(e instanceof ApiError);
      assert.equal(e.statusCode, 409);
      return true;
    });
  }
  assert.equal(db.docs.get('users/seller')?.role, 'supplier', 'nothing changed');
});

test('choosing the current role changes nothing', async () => {
  const db = new FakeDb();
  db.seed('users/u3', { role: 'homeowner' });
  const r = await changeUserRole('u3', 'homeowner', db.asFirestore());
  assert.equal(r.changed, false);
});
