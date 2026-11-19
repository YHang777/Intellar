import test from 'node:test';
import assert from 'node:assert/strict';
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
  const written: [string, number][] = [];
  const stock: Record<string, number> = { p1: 0, p2: 0 };
  const fake = {
    runTransaction: async (fn: (txn: unknown) => Promise<unknown>) =>
      fn({
        get: async (ref: { id: string }) => ({
          exists: ref.id in stock,
          data: () => (ref.id in stock ? { soldCount: stock[ref.id] } : undefined),
        }),
        update: async (ref: { id: string }, data: { soldCount: number }) => {
          stock[ref.id] = data.soldCount;
          written.push([ref.id, data.soldCount]);
        },
      }),
    collection: (c: string) => ({ doc: (id: string) => ({ id, path: `${c}/${id}` }) }),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any;

  await applySoldCountDelta(fake, [
    { productId: 'p1', quantity: 2 },
    { productId: 'p2', quantity: 1 },
  ], 1);
  assert.deepEqual(stock, { p1: 2, p2: 1 });

  await applySoldCountDelta(fake, [{ productId: 'p1', quantity: 2 }], -1);
  assert.equal(stock.p1, 0);

  // A refund of an order paid before the counter existed must not go
  // negative — it has nothing to give back.
  await applySoldCountDelta(fake, [{ productId: 'p1', quantity: 5 }], -1);
  assert.equal(stock.p1, 0);
  assert.ok(written.every(([, v]) => v >= 0), 'never stores a negative count');

  written.length = 0;
  await applySoldCountDelta(fake, [], 1);
  assert.deepEqual(written, [], 'an order with no items bumps nothing');

  // The seller deleted the listing before the refund: nothing is written,
  // so no bare { soldCount } document reappears in the catalogue.
  await applySoldCountDelta(fake, [{ productId: 'gone', quantity: 1 }], -1);
  assert.equal('gone' in stock, false);
  assert.deepEqual(written, []);
});

test('low-stock alerts: once per level, again after a restock', async () => {
  const { stockLevel, shouldAlertStock } = await import('./checkout.service');
  assert.equal(stockLevel(5), null, '5 is not low (seller screens use < 5)');
  assert.equal(stockLevel(4), 'low');
  assert.equal(stockLevel(0), 'out');

  assert.equal(shouldAlertStock(8, undefined), false, 'plenty left');
  assert.equal(shouldAlertStock(4, undefined), true, 'first drop below 5');
  assert.equal(shouldAlertStock(3, { level: 'low', stock: 4 }), false, 'not on every sale');
  assert.equal(shouldAlertStock(0, { level: 'low', stock: 3 }), true, 'sold out is news');
  assert.equal(shouldAlertStock(0, { level: 'out', stock: 0 }), false);
  assert.equal(shouldAlertStock(4, { level: 'out', stock: 0 }), true,
    'restocked then dropped low again');
});
