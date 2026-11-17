import test from 'node:test';
import assert from 'node:assert/strict';
import { FieldValue } from 'firebase-admin/firestore';
import { computeTotals, tierForOrderCount } from './checkout.service';

// ── computeTotals (mirrors the app's pricing.dart breakdown) ────────────────

test('totals → no discount, 6% tax', () => {
  assert.deepEqual(computeTotals(1000, 0, 0.06), {
    subtotal: 1000,
    discount: 0,
    tax: 60,
    total: 1060,
  });
});

test('totals → 5% Silver discount, tax on the chargeable amount', () => {
  assert.deepEqual(computeTotals(1000, 5, 0.06), {
    subtotal: 1000,
    discount: 50,
    tax: 57,
    total: 1007,
  });
});

test('totals → 10% Gold discount', () => {
  assert.deepEqual(computeTotals(2000, 10, 0.06), {
    subtotal: 2000,
    discount: 200,
    tax: 108,
    total: 1908,
  });
});

test('totals → rounding: discount and tax both round half up', () => {
  // 999 * 5% = 49.95 → 50; chargeable 949; tax 56.94 → 57; total 1006.
  assert.deepEqual(computeTotals(999, 5, 0.06), {
    subtotal: 999,
    discount: 50,
    tax: 57,
    total: 1006,
  });
});

test('totals → zero tax rate', () => {
  assert.deepEqual(computeTotals(500, 0, 0), {
    subtotal: 500,
    discount: 0,
    tax: 0,
    total: 500,
  });
});

test('totals → free cart stays zero', () => {
  assert.deepEqual(computeTotals(0, 0, 0.06), {
    subtotal: 0,
    discount: 0,
    tax: 0,
    total: 0,
  });
});

// ── tierForOrderCount (mirrors AppConfigData.membershipTiers) ────────────────

test('tier → 0 collected orders is Free', () => {
  assert.deepEqual(tierForOrderCount(0), { name: 'Free', discountPercent: 0 });
});

test('tier → 4 collected orders is still Free (Silver starts at 5)', () => {
  assert.deepEqual(tierForOrderCount(4), { name: 'Free', discountPercent: 0 });
});

test('tier → 5 collected orders is Silver', () => {
  assert.deepEqual(tierForOrderCount(5), { name: 'Silver', discountPercent: 5 });
});

test('tier → 14 collected orders is still Silver (Gold starts at 15)', () => {
  assert.deepEqual(tierForOrderCount(14), { name: 'Silver', discountPercent: 5 });
});

test('tier → 15 collected orders is Gold', () => {
  assert.deepEqual(tierForOrderCount(15), { name: 'Gold', discountPercent: 10 });
});

test('tier → 100 collected orders stays Gold', () => {
  assert.deepEqual(tierForOrderCount(100), { name: 'Gold', discountPercent: 10 });
});

test('order numbers carry the Malaysian calendar day', async () => {
  const { orderNumberFor } = await import('./checkout.service');
  assert.match(orderNumberFor(new Date('2026-11-16T17:29:00Z')), /^ORD-20261117-\d{4}$/);
  assert.match(orderNumberFor(new Date('2026-11-16T15:59:00Z')), /^ORD-20261116-\d{4}$/);
});

test('sold count follows the money: up on payment, down on refund', async () => {
  const { applySoldCountDelta } = await import('./checkout.service');
  const updates: [string, unknown][] = [];
  const fake = {
    batch: () => ({
      update: (ref: { path: string }, data: Record<string, unknown>) => {
        updates.push([ref.path, data.soldCount]);
      },
      commit: async () => {},
    }),
    collection: (c: string) => ({ doc: (id: string) => ({ path: `${c}/${id}` }) }),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any;

  await applySoldCountDelta(
    fake,
    [{ productId: 'p1', quantity: 2 }, { productId: 'p2', quantity: 1 }],
    1
  );
  assert.deepEqual(updates.map(([p]) => p), ['products/p1', 'products/p2']);
  assert.deepEqual(updates[0][1], FieldValue.increment(2));
  assert.deepEqual(updates[1][1], FieldValue.increment(1));

  updates.length = 0;
  await applySoldCountDelta(fake, [{ productId: 'p1', quantity: 2 }], -1);
  assert.deepEqual(updates.map(([p]) => p), ['products/p1']);
  assert.deepEqual(updates[0][1], FieldValue.increment(-2));

  updates.length = 0;
  await applySoldCountDelta(fake, [], 1);
  assert.deepEqual(updates, [], 'an order with no items bumps nothing');
});
