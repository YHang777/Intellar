import test from 'node:test';
import assert from 'node:assert/strict';
import { platformFee } from './checkout.service';
import { summariseRevenue } from './users.service';
import { toSettings } from './settings.service';

test('commission is taken on goods after discount, to the sen', () => {
  assert.equal(platformFee(10, 0, 0.03), 0.3);
  assert.equal(platformFee(1500, 75, 0.03), 42.75);
  assert.equal(platformFee(100, 0, 0), 0);
});

test('revenue counts paid, non-cancelled orders only; a later rate change never revalues old orders', () => {
  const now = new Date('2026-11-19T04:00:00Z');
  const orders = [
    { paymentStatus: 'paid', status: 'collected', subtotal: 1000, discount: 0, platformFee: 30, paidAt: '2026-11-02T03:00:00Z' },
    { paymentStatus: 'paid', status: 'confirmed', subtotal: 500, discount: 50, paidAt: '2026-10-31T17:30:00Z' }, // no fee recorded; MY time = Nov 1
    { paymentStatus: 'paid', status: 'cancelled', subtotal: 999, discount: 0, platformFee: 29.97, paidAt: '2026-11-03T00:00:00Z' },
    { paymentStatus: 'unpaid', status: 'pending', subtotal: 300, discount: 0, platformFee: 9 },
  ];
  const r = summariseRevenue(orders, 0.1, now); // admin has since raised the rate to 10%
  assert.equal(r.paidOrders, 2);
  assert.equal(r.grossSales, 1450);
  assert.equal(r.platformRevenue, 43.5, 'recorded fee kept; unrecorded order at the 3% launch rate');
  assert.equal(r.commissionRate, 0.1);
  assert.equal(r.monthly.length, 6);
  assert.equal(r.monthly[5].month, '2026-11');
  assert.equal(r.monthly[5].platformRevenue, 43.5, 'the late-October UTC payment is November in Malaysia');
});

test('commission rate outside 0-30% falls back to 3%', () => {
  assert.equal(toSettings({ commissionRate: 0.05 }).commissionRate, 0.05);
  assert.equal(toSettings({ commissionRate: 0.9 }).commissionRate, 0.03);
  assert.equal(toSettings({}).commissionRate, 0.03);
});
