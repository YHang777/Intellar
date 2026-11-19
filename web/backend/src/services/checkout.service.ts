import { auditQuietly } from './audit.service';
import {
  defaultNotificationDeps,
  notifyQuietly,
  notifyUser,
  type NotificationDeps,
} from './notifications.service';
import { randomInt } from 'node:crypto';
import type { RequestHandler } from 'express';
import type { DocumentReference, Firestore, Transaction } from 'firebase-admin/firestore';
import Stripe from 'stripe';
import { fbDb } from '../config/firebase';
import { env } from '../config/env';
import { ApiError } from '../lib/errors';
import { authenticate } from '../middleware/authenticate';
import { getSettings, DEFAULT_TAX_RATE, DEFAULT_COMMISSION_RATE } from './settings.service';

export interface CheckoutItemInput {
  productId: string;
  quantity: number;
}

export interface CheckoutIntentResult {
  orderId: string;
  orderNumber: string;
  clientSecret: string;
  publishableKey: string;
  total: number;
}

export interface PaymentVerificationResult {
  paid: boolean;
  paymentMethod: string;
}

export interface CheckoutDeps {
  createIntent: (
    uid: string,
    email: string | null,
    items: CheckoutItemInput[],
    customerName: string,
    customerPhone: string
  ) => Promise<CheckoutIntentResult>;
  verify: (uid: string, orderId: string) => Promise<PaymentVerificationResult>;
  abandon: (uid: string, orderId: string) => Promise<void>;
  cancel: (uid: string, orderId: string) => Promise<PaymentVerificationResult>;
  handleWebhook: (rawBody: Buffer, signature: string) => Promise<void>;
  authorize: RequestHandler;
  log?: (message: string) => void;
}

export function defaultCheckoutDeps(): CheckoutDeps {
  return {
    createIntent: (uid, email, items, customerName, customerPhone) =>
      createCheckoutIntent(uid, email, items, customerName, customerPhone),
    verify: (uid, orderId) => verifyPayment(uid, orderId),
    abandon: (uid, orderId) => abandonOrder(uid, orderId),
    cancel: (uid, orderId) => cancelOrder(uid, orderId),
    handleWebhook: (rawBody, signature) =>
      handleStripeWebhook(rawBody, signature),
    authorize: authenticate,
    log: (message) => console.log(message),
  };
}

// ── Stripe client ───────────────────────────────────────────────────────────

let stripeClient: Stripe | null = null;

export function stripeConfigured(): boolean {
  return env.stripeSecretKey.trim().length > 0;
}

function stripe(): Stripe {
  if (!stripeConfigured()) {
    throw new ApiError(
      503,
      'STRIPE_NOT_CONFIGURED',
      'Payments are not configured on this server yet.'
    );
  }
  if (!stripeClient) {
    stripeClient = new Stripe(env.stripeSecretKey.trim());
  }
  return stripeClient;
}

// ── Money math (mirrors lib/core/utils/pricing.dart — integer MYR) ──────────

export interface OrderTotals {
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
}

export function computeTotals(
  subtotal: number,
  discountPercent: number,
  taxRate: number
): OrderTotals {
  const discount = Math.round((subtotal * discountPercent) / 100);
  const chargeable = subtotal - discount;
  const tax = Math.round(chargeable * taxRate);
  return { subtotal, discount, tax, total: chargeable + tax };
}

/** Intellar's cut of the goods value (after discount, before tax), in RM to the sen. */
export function platformFee(subtotal: number, discount: number, commissionRate: number): number {
  return Math.round((subtotal - discount) * commissionRate * 100) / 100;
}

/** Mirrors the app's `AppConfigData.membershipTiers` constants. */
export const MEMBERSHIP_TIERS = [
  { name: 'Free', discountPercent: 0, minOrders: 0 },
  { name: 'Silver', discountPercent: 5, minOrders: 5 },
  { name: 'Gold', discountPercent: 10, minOrders: 15 },
] as const;

export function tierForOrderCount(collectedCount: number): {
  name: string;
  discountPercent: number;
} {
  let current: { name: string; discountPercent: number; minOrders: number } =
    MEMBERSHIP_TIERS[0];
  for (const tier of MEMBERSHIP_TIERS) {
    if (collectedCount >= tier.minOrders) current = tier;
  }
  return { name: current.name, discountPercent: current.discountPercent };
}

// ── Firestore helpers ───────────────────────────────────────────────────────

interface OrderDoc {
  id: string;
  orderNumber: string;
  customerId: string;
  customerName: string;
  customerEmail: string;
  customerPhone: string;
  items: Array<{
    productId: string;
    name: string;
    image: string;
    unitPrice: number;
    quantity: number;
    supplierId: string;
}>;
  status: string;
  paymentStatus: string;
  paymentMethod: string;
  paymentIntentId?: string;
  paidAt?: string;
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  membershipTier: string;
  supplierIds: string[];
  createdAt: string;
  statusHistory: Record<string, string>;
  invoices: Record<string, unknown>;
  refundStatus?: string;
  refundAmount?: number;
  taxRate?: number;
  commissionRate?: number;
  platformFee?: number;
}

function isoNow(): string {
  return new Date().toISOString();
}

/** Malaysia is UTC+8 all year (no DST) — order numbers carry the local day. */
const MYT_OFFSET_MS = 8 * 60 * 60 * 1000;

export function orderNumberFor(now: Date): string {
  const local = new Date(now.getTime() + MYT_OFFSET_MS);
  const y = local.getUTCFullYear();
  const m = String(local.getUTCMonth() + 1).padStart(2, '0');
  const d = String(local.getUTCDate()).padStart(2, '0');
  return `ORD-${y}${m}${d}-${randomInt(1000, 10000)}`;
}

function newOrderId(): string {
  return `${Date.now()}${randomInt(0, 99999)}`.slice(0, 20);
}

function asRecord(raw: unknown): Record<string, unknown> {
  return raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function asNumber(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function stockQuantities(items: unknown): Map<string, number> {
  const quantities = new Map<string, number>();
  if (!Array.isArray(items)) return quantities;
  for (const raw of items) {
    const item = asRecord(raw);
    const productId = asString(item.productId);
    if (!productId) continue;
    const quantity = Math.max(1, Math.round(asNumber(item.quantity)));
    quantities.set(productId, (quantities.get(productId) ?? 0) + quantity);
  }
  return quantities;
}

/** All product reads first (Firestore transaction rule), then stock writes. */
async function restoreStock(
  db: Firestore,
  txn: Transaction,
  quantities: Map<string, number>
): Promise<void> {
  const productRefs = [...quantities.keys()].map((id) =>
    db.collection('products').doc(id)
  );
  const snaps = await Promise.all(productRefs.map((ref) => txn.get(ref)));
  for (let i = 0; i < productRefs.length; i++) {
    const snap = snaps[i];
    if (!snap.exists) continue;
    const stock = Math.round(asNumber((snap.data() ?? {}).stock));
    txn.update(productRefs[i], {
      stock: stock + (quantities.get(productRefs[i].id) ?? 0),
    });
  }
}

async function collectedOrderCount(
  db: Firestore,
  uid: string
): Promise<number> {
  const snap = await db.collection('orders').where('customerId', '==', uid).get();
  let count = 0;
  for (const doc of snap.docs) {
    if (doc.data().status === 'collected') count++;
  }
  return count;
}

// ── Payment-state transitions (webhook + verify share one idempotent path) ──

async function markOrderPaid(
  db: Firestore,
  orderId: string,
  paymentIntentId: string,
  paymentMethod: string
): Promise<boolean> {
  const ref = db.collection('orders').doc(orderId);
  return db.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) return false;
    const data = asRecord(snap.data());
    const current = asString(data.paymentStatus);
    if (current === 'paid' || current === 'refunded') return false;
    txn.update(ref, {
      paymentStatus: 'paid',
      paidAt: isoNow(),
      paymentIntentId,
      ...(paymentMethod ? { paymentMethod } : {}),
    });
    return true;
  }).then((paid) => {
    if (paid) void announcePaidOrder(db, orderId);
    return paid;
  });
}

// First transition to paid: tell each seller and record the purchase.
async function announcePaidOrder(db: Firestore, orderId: string): Promise<void> {
  try {
    const snap = await db.collection('orders').doc(orderId).get();
    const order = asRecord(snap.data());
    const orderNumber = asString(order.orderNumber) || orderId;
    const supplierIds = Array.isArray(order.supplierIds)
      ? (order.supplierIds as unknown[]).map((s) => String(s))
      : [];
    const deps = defaultNotificationDeps();
    for (const sid of supplierIds) {
      notifyQuietly(deps, sid, {
        kind: 'new_order',
        title: 'New paid order',
        body: `Order ${orderNumber} is paid — confirm it to start preparing.`,
        data: { orderId },
      });
    }
    void applySoldCountDelta(db, order.items, 1).catch((err) =>
      console.log(`[checkout] soldCount bump skipped: ${err.message}`)
    );
    void alertLowStock(db, order.items, { notifications: deps }).catch((err) =>
      console.log(`[checkout] low-stock alert skipped: ${err.message}`)
    );
    auditQuietly(
      {
        actorId: asString(order.customerId),
        action: 'order.paid',
        targetType: 'order',
        targetId: orderId,
        details: { total: asNumber(order.total), method: asString(order.paymentMethod) },
      },
      db
    );
  } catch (err) {
    console.log(`[checkout] paid-order announce skipped: ${(err as Error).message}`);
  }
}

async function paymentIntentState(
  paymentIntentId: string
): Promise<{ state: 'paid' | 'failed' | 'pending'; paymentMethod: string }> {
  const pi = await stripe().paymentIntents.retrieve(paymentIntentId, {
    expand: ['payment_method'],
  });
  if (pi.status === 'succeeded') {
    const method = pi.payment_method;
    const type =
      method && typeof method === 'object' && 'type' in method
        ? String(method.type)
        : '';
    return { state: 'paid', paymentMethod: type === 'fpx' ? 'fpx' : 'card' };
  }
  if (pi.status === 'canceled' || pi.status === 'requires_payment_method') {
    return { state: 'failed', paymentMethod: '' };
  }
  return { state: 'pending', paymentMethod: '' };
}

// ── createCheckoutIntent ────────────────────────────────────────────────────

export async function createCheckoutIntent(
  uid: string,
  email: string | null,
  items: CheckoutItemInput[],
  customerName: string,
  customerPhone: string,
  dbOverride?: Firestore
): Promise<CheckoutIntentResult> {
  const db = dbOverride ?? fbDb();
  const now = new Date();

  await sweepStaleUnpaidOrders(db, uid);

  // Membership tier from the customer's collected orders (server-side truth).
  const tier = tierForOrderCount(await collectedOrderCount(db, uid));
  const settings = await getSettings(db);
  const taxRate = settings.taxRate ?? DEFAULT_TAX_RATE;
  const commissionRate = settings.commissionRate ?? DEFAULT_COMMISSION_RATE;

  // Validate products + snapshot prices inside one transaction.
  const orderId = newOrderId();
  const prepared = await db.runTransaction(async (txn) => {
    const productRefs = items.map((i) =>
      db.collection('products').doc(i.productId)
    );
    const productSnaps = await Promise.all(productRefs.map((ref) => txn.get(ref)));

    const orderItems: OrderDoc['items'] = [];
    const supplierIds = new Set<string>();
    let subtotal = 0;
    for (let i = 0; i < items.length; i++) {
      const snap = productSnaps[i];
      const wanted = items[i];
      if (!snap.exists) {
        throw new ApiError(409, 'PRODUCT_UNAVAILABLE', 'An item in your cart is no longer available.');
      }
      const product = asRecord(snap.data());
      const name = asString(product.name) || 'Unknown product';
      if (product.isActive !== true) {
        throw new ApiError(409, 'PRODUCT_INACTIVE', `"${name}" is no longer on sale.`);
      }
      const stock = Math.round(asNumber(product.stock));
      if (stock < wanted.quantity) {
        throw new ApiError(
          409,
          'INSUFFICIENT_STOCK',
          stock <= 0
            ? `"${name}" is out of stock.`
            : `Only ${stock} of "${name}" left.`
        );
      }
      const price = Math.round(asNumber(product.price));
      const supplierId = asString(product.supplierId) || asString(asRecord(product.supplier).id);
      subtotal += price * wanted.quantity;
      if (supplierId) supplierIds.add(supplierId);
      orderItems.push({
        productId: snap.id,
        name,
        image: asString(product.image),
        unitPrice: price,
        quantity: wanted.quantity,
        supplierId,
      });
    }

    if (subtotal <= 0) {
      throw new ApiError(400, 'EMPTY_CART', 'Your cart is empty.');
    }

    const totals = computeTotals(subtotal, tier.discountPercent, taxRate);

    // Reserve stock now; released by abandon/sweep if the payment never lands.
    for (let i = 0; i < items.length; i++) {
      const snap = productSnaps[i];
      const stock = Math.round(asNumber((snap.data() ?? {}).stock));
      txn.update(productRefs[i], { stock: stock - items[i].quantity });
    }

    const order: OrderDoc = {
      id: orderId,
      orderNumber: orderNumberFor(now),
      customerId: uid,
      customerName: customerName.trim(),
      customerEmail: email ?? '',
      customerPhone: customerPhone.trim(),
      items: orderItems,
      status: 'pending',
      paymentStatus: 'unpaid',
      paymentMethod: 'card_fpx',
      ...totals,
      taxRate,
      commissionRate,
      platformFee: platformFee(totals.subtotal, totals.discount, commissionRate),
      membershipTier: tier.name,
      supplierIds: [...supplierIds],
      createdAt: now.toISOString(),
      statusHistory: { pending: now.toISOString() },
      invoices: {},
    };
    txn.set(db.collection('orders').doc(orderId), order);
    return order;
  });

  // PaymentIntent after the order exists; compensate if Stripe refuses.
  let clientSecret: string;
  try {
    const intent = await stripe().paymentIntents.create(
      {
        amount: prepared.total * 100, // integer MYR → sen
        currency: 'myr',
        payment_method_types: ['card', 'fpx'],
        metadata: { orderId },
        ...(prepared.customerEmail ? { receipt_email: prepared.customerEmail } : {}),
      },
      { idempotencyKey: `checkout_${orderId}` }
    );
    clientSecret = intent.client_secret ?? '';
    if (!clientSecret) throw new Error('missing client_secret');
    await db
      .collection('orders')
      .doc(orderId)
      .update({ paymentIntentId: intent.id });
  } catch (err) {
    // Roll the reservation back so a Stripe failure never strands stock.
    await db.runTransaction(async (txn) => {
      const orderRef = db.collection('orders').doc(orderId);
      const snap = await txn.get(orderRef);
      if (snap.exists && asString(snap.data()?.paymentStatus) === 'unpaid') {
        await restoreStock(db, txn, stockQuantities(snap.data()?.items));
        txn.delete(orderRef);
      }
    });
    if (err instanceof ApiError) throw err;
    throw new ApiError(
      502,
      'PAYMENT_PROVIDER_ERROR',
      'Could not start the payment. Please try again.'
    );
  }

  return {
    orderId,
    orderNumber: prepared.orderNumber,
    clientSecret,
    publishableKey: env.stripePublishableKey.trim(),
    total: prepared.total,
  };
}

// ── verify (app polls after the Payment Sheet closes) ───────────────────────

export async function verifyPayment(
  uid: string,
  orderId: string,
  dbOverride?: Firestore
): Promise<PaymentVerificationResult> {
  const db = dbOverride ?? fbDb();
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists || asString(snap.data()?.customerId) !== uid) {
    throw new ApiError(404, 'ORDER_NOT_FOUND', 'That order could not be found.');
  }
  const data = asRecord(snap.data());
  const paymentStatus = asString(data.paymentStatus);
  if (paymentStatus === 'paid' || paymentStatus === 'refunded') {
    return { paid: true, paymentMethod: asString(data.paymentMethod) };
  }
  const paymentIntentId = asString(data.paymentIntentId);
  if (!paymentIntentId) return { paid: false, paymentMethod: '' };

  const intent = await paymentIntentState(paymentIntentId);
  if (intent.state === 'paid') {
    await markOrderPaid(db, orderId, paymentIntentId, intent.paymentMethod);
    return { paid: true, paymentMethod: intent.paymentMethod || 'card' };
  }
  return { paid: false, paymentMethod: '' };
}

// ── abandon (user closed/failed the sheet — release the reservation) ────────

export async function abandonOrder(
  uid: string,
  orderId: string,
  dbOverride?: Firestore
): Promise<void> {
  const db = dbOverride ?? fbDb();
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) return;
  const data = asRecord(snap.data());
  if (asString(data.customerId) !== uid) {
    throw new ApiError(404, 'ORDER_NOT_FOUND', 'That order could not be found.');
  }
  if (asString(data.paymentStatus) !== 'unpaid') return;

  // The sheet can report a close just as the payment lands — Stripe decides.
  const paymentIntentId = asString(data.paymentIntentId);
  if (paymentIntentId) {
    const intent = await paymentIntentState(paymentIntentId);
    if (intent.state === 'paid') {
      await markOrderPaid(db, orderId, paymentIntentId, intent.paymentMethod);
      return;
    }
  }
  await releaseUnpaidOrder(db, ref, data);
}

async function releaseUnpaidOrder(
  db: Firestore,
  ref: DocumentReference,
  data: Record<string, unknown>,
  cancelIntent: (id: string) => Promise<unknown> = (id) =>
    stripe().paymentIntents.cancel(id)
): Promise<void> {
  const paymentIntentId = asString(data.paymentIntentId);
  await db.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) return;
    const current = asRecord(snap.data());
    if (asString(current.paymentStatus) !== 'unpaid') return;
    await restoreStock(db, txn, stockQuantities(current.items));
    txn.delete(ref);
  });
  // Best effort: kill the intent so a stray sheet retry cannot charge later.
  if (paymentIntentId) {
    await cancelIntent(paymentIntentId).catch(() => undefined);
  }
}

// ── cancel (after payment — refunds through Stripe, restores stock) ─────────

export async function cancelOrder(
  uid: string,
  orderId: string,
  dbOverride?: Firestore
): Promise<PaymentVerificationResult> {
  const db = dbOverride ?? fbDb();
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new ApiError(404, 'ORDER_NOT_FOUND', 'That order could not be found.');
  }
  const data = asRecord(snap.data());
  const supplierIds = Array.isArray(data.supplierIds)
    ? (data.supplierIds as unknown[]).map((s) => String(s))
    : [];
  if (asString(data.customerId) !== uid && !supplierIds.includes(uid)) {
    throw new ApiError(403, 'FORBIDDEN', 'You cannot cancel this order.');
  }
  const status = asString(data.status);
  if (status === 'cancelled' || status === 'collected') {
    throw new ApiError(409, 'ORDER_NOT_CANCELLABLE', 'This order can no longer be cancelled.');
  }

  const paymentStatus = asString(data.paymentStatus);

  if (paymentStatus === 'paid') {
    // Refund first: stock/status only move once the money is on its way back.
    await refundOrderIfPaid(orderId, db);
  } else if (paymentStatus === 'unpaid') {
    // Never charged — just release the reservation and drop the order.
    await releaseUnpaidOrder(db, ref, data);
    return { paid: false, paymentMethod: '' };
  }

  await db.runTransaction(async (txn) => {
    const orderSnap = await txn.get(ref);
    if (!orderSnap.exists) return;
    const current = asRecord(orderSnap.data());
    if (asString(current.status) === 'cancelled') return;
    await restoreStock(db, txn, stockQuantities(current.items));
    txn.update(ref, {
      status: 'cancelled',
      statusHistory: {
        ...asRecord(current.statusHistory),
        cancelled: isoNow(),
      },
    });
  });

  announceCancelled(db, uid, orderId, data, paymentStatus === 'paid');
  return { paid: true, paymentMethod: asString(data.paymentMethod) };
}

function announceCancelled(
  db: Firestore,
  actorId: string,
  orderId: string,
  data: Record<string, unknown>,
  refunded: boolean
): void {
  const orderNumber = asString(data.orderNumber) || orderId;
  const customerId = asString(data.customerId);
  const supplierIds = Array.isArray(data.supplierIds)
    ? (data.supplierIds as unknown[]).map((s) => String(s))
    : [];
  const deps = defaultNotificationDeps();
  if (actorId === customerId) {
    for (const sid of supplierIds) {
      notifyQuietly(deps, sid, {
        kind: 'order_update',
        title: 'Order cancelled',
        body: `The buyer cancelled order ${orderNumber}.`,
        data: { orderId },
      });
    }
  } else if (customerId) {
    notifyQuietly(deps, customerId, {
      kind: 'order_update',
      title: 'Order cancelled by the seller',
      body: refunded
        ? `Order ${orderNumber} was cancelled and your payment refunded.`
        : `Order ${orderNumber} was cancelled.`,
      data: { orderId },
    });
  }
  auditQuietly(
    {
      actorId,
      action: 'order.cancelled',
      targetType: 'order',
      targetId: orderId,
      details: { refunded },
    },
    db
  );
}

/**
 * Idempotent Stripe refund for a paid order — shared by the app's cancel
 * endpoint and the admin PATCH cancel path. Returns false when there is
 * nothing to refund (already refunded, unpaid, or predates Stripe).
 */
export async function refundOrderIfPaid(
  orderId: string,
  dbOverride?: Firestore
): Promise<boolean> {
  const db = dbOverride ?? fbDb();
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) return false;
  const data = asRecord(snap.data());
  if (asString(data.paymentStatus) !== 'paid') return false;
  const paymentIntentId = asString(data.paymentIntentId);
  if (!paymentIntentId) return false;
  try {
    await stripe().refunds.create({ payment_intent: paymentIntentId });
  } catch (err) {
    const message = (err as { message?: string }).message ?? '';
    if (!message.toLowerCase().includes('already been refunded')) {
      // The Stripe reason is what support actually needs to act on; the
      // caller-facing line stays generic.
      console.error(`[checkout] refund failed for ${orderId}: ${message}`);
      throw new ApiError(
        502,
        'REFUND_FAILED',
        'Could not start the refund. Please contact support.',
        { reason: message }
      );
    }
  }
  await markRefunded(db, orderId, asNumber(data.total));
  return true;
}

// ── Low-stock alerts (FR29) ─────────────────────────────────────────────────
// Same thresholds as the seller's screens: under 5 is low, 0 is sold out.
// After a paid sale each item's seller hears once per level (low, then sold
// out), and afresh after a restock — never on every sale.
export const LOW_STOCK_BELOW = 5;

export type StockLevel = 'low' | 'out' | null;

export function stockLevel(stock: number): StockLevel {
  if (stock <= 0) return 'out';
  if (stock < LOW_STOCK_BELOW) return 'low';
  return null;
}

/** Whether this stock reading deserves an alert, given the last one sent. */
export function shouldAlertStock(
  stock: number,
  last: { level?: unknown; stock?: unknown } | undefined
): boolean {
  const level = stockLevel(stock);
  if (level === null) return false;
  const lastLevel = (last?.level as StockLevel | undefined) ?? null;
  const lastStock = Number(last?.stock);
  // Restocked since the last alert, then dropped again: news again.
  const restocked = Number.isFinite(lastStock) && stock > lastStock;
  return level !== lastLevel || restocked;
}

export async function alertLowStock(
  db: Firestore,
  items: unknown,
  deps: { notifications: NotificationDeps } = { notifications: defaultNotificationDeps() }
): Promise<void> {
  for (const productId of stockQuantities(items).keys()) {
    const ref = db.collection('products').doc(productId);
    const snap = await ref.get();
    if (!snap.exists) continue;
    const p = asRecord(snap.data());
    const stock = Math.round(asNumber(p.stock));
    const last = asRecord(p.lowStockAlert);
    if (stockLevel(stock) === null) {
      if (p.lowStockAlert != null) await ref.update({ lowStockAlert: null });
      continue;
    }
    if (!shouldAlertStock(stock, last)) continue;
    await ref.update({ lowStockAlert: { level: stockLevel(stock), stock } });
    const supplierId = asString(p.supplierId) || asString(asRecord(p.supplier).id);
    if (!supplierId) continue;
    const name = asString(p.name) || 'A product';
    await notifyUser(deps.notifications, supplierId, {
      kind: 'low_stock',
      title: stock <= 0 ? `${name} is sold out` : `Low stock: ${name}`,
      body: stock <= 0
        ? 'Restock it so buyers can order again.'
        : `Only ${stock} left. Restock soon so it does not sell out.`,
      data: { productId },
    });
  }
}

// Popularity counter on each product, kept by the payment path only.
// Read-modify-write per product so a refund can never push the counter below
// zero — an order paid before the counter existed has nothing to give back.
export async function applySoldCountDelta(
  db: Firestore,
  items: unknown,
  delta: number
): Promise<void> {
  const quantities = stockQuantities(items);
  if (quantities.size === 0) return;
  await Promise.all(
    [...quantities.entries()].map(async ([productId, qty]) => {
      const ref = db.collection('products').doc(productId);
      await db.runTransaction(async (txn) => {
        const snap = await txn.get(ref);
        // A listing deleted since the sale: writing here would recreate it as
        // a bare { soldCount } document in the catalogue.
        if (!snap.exists) return;
        const current = asNumber((snap.data() as Record<string, unknown> | undefined)?.soldCount);
        txn.update(ref, { soldCount: Math.max(0, current + delta * qty) });
      });
    })
  );
}

async function markRefunded(db: Firestore, orderId: string, amount: number): Promise<void> {
  const ref = db.collection('orders').doc(orderId);
  const refundedItems = await db.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) return null;
    const current = asRecord(snap.data());
    if (asString(current.paymentStatus) === 'refunded') return null;
    txn.update(ref, {
      paymentStatus: 'refunded',
      refundStatus: 'processed',
      refundAmount: amount,
    });
    return current.items;
  });
  // The sale is undone — the popularity counter follows the money, once:
  // only the call that actually flipped the order rolls it back.
  if (refundedItems == null) return;
  void applySoldCountDelta(db, refundedItems, -1).catch((err) =>
    console.log(`[checkout] soldCount rollback skipped: ${err.message}`)
  );
}

// ── payment window (unpaid orders expire after 15 minutes) ─────────────────

/** How long a buyer has to finish paying before the reservation is released. */
export const PAYMENT_WINDOW_MS = 15 * 60 * 1000;
/** A payment Stripe is still processing (e.g. a bank step) gets this long. */
const PROCESSING_GIVE_UP_MS = 60 * 60 * 1000;

type IntentState = { state: 'paid' | 'failed' | 'pending'; paymentMethod: string };

export interface PaymentWindowDeps {
  intentState?: (paymentIntentId: string) => Promise<IntentState>;
  cancelIntent?: (paymentIntentId: string) => Promise<unknown>;
  now?: () => number;
}

export interface ExpireResult {
  released: number;
  paid: number;
}

async function expireUnpaidDocs(
  db: Firestore,
  docs: { id: string; ref: DocumentReference; data: () => unknown }[],
  deps: PaymentWindowDeps
): Promise<ExpireResult> {
  const intentState = deps.intentState ?? paymentIntentState;
  const cancelIntent = deps.cancelIntent ?? ((id: string) => stripe().paymentIntents.cancel(id));
  const now = deps.now ? deps.now() : Date.now();
  const result: ExpireResult = { released: 0, paid: 0 };
  for (const doc of docs) {
    const data = asRecord(doc.data());
    if (asString(data.paymentStatus) !== 'unpaid') continue;
    if (asString(data.status) !== 'pending') continue;
    const createdAt = Date.parse(asString(data.createdAt));
    if (!Number.isFinite(createdAt)) continue;
    const age = now - createdAt;
    if (age < PAYMENT_WINDOW_MS) continue;

    const paymentIntentId = asString(data.paymentIntentId);
    if (paymentIntentId) {
      // Stripe decides: a payment that just landed must keep its order.
      const intent = await intentState(paymentIntentId).catch(() => null);
      if (!intent) continue;
      if (intent.state === 'paid') {
        await markOrderPaid(db, doc.id, paymentIntentId, intent.paymentMethod);
        result.paid += 1;
        continue;
      }
      if (intent.state === 'pending') {
        // Still processing: leave it, unless it is very old AND Stripe agrees
        // to cancel it (a processing payment cannot be cancelled).
        if (age < PROCESSING_GIVE_UP_MS) continue;
        const cancelled = await cancelIntent(paymentIntentId).then(
          () => true,
          () => false
        );
        if (!cancelled) continue;
        await releaseUnpaidOrder(db, doc.ref, data, async () => undefined);
        result.released += 1;
        continue;
      }
    }
    await releaseUnpaidOrder(db, doc.ref, data, cancelIntent);
    result.released += 1;
  }
  return result;
}

/** One buyer's expired checkouts — run before they start a new one. */
async function sweepStaleUnpaidOrders(db: Firestore, uid: string): Promise<void> {
  const snap = await db.collection('orders').where('customerId', '==', uid).get();
  await expireUnpaidDocs(db, snap.docs, {});
}

/**
 * Every expired checkout on the platform: cancels the Stripe payment and puts
 * the reserved stock back. Runs on a timer from index.ts.
 */
export async function expireUnpaidOrders(
  dbOverride?: Firestore,
  deps: PaymentWindowDeps = {}
): Promise<ExpireResult> {
  const db = dbOverride ?? fbDb();
  const snap = await db.collection('orders').where('paymentStatus', '==', 'unpaid').get();
  return expireUnpaidDocs(db, snap.docs, deps);
}

// ── webhook ─────────────────────────────────────────────────────────────────

export async function handleStripeWebhook(
  rawBody: Buffer,
  signature: string,
  dbOverride?: Firestore
): Promise<void> {
  if (!env.stripeWebhookSecret.trim()) {
    throw new ApiError(
      503,
      'WEBHOOK_NOT_CONFIGURED',
      'Webhooks are not configured on this server.'
    );
  }
  let event: Stripe.Event;
  try {
    event = stripe().webhooks.constructEvent(
      rawBody,
      signature,
      env.stripeWebhookSecret.trim()
    );
  } catch {
    throw new ApiError(400, 'BAD_SIGNATURE', 'Invalid webhook signature.');
  }

  const db = dbOverride ?? fbDb();
  if (event.type === 'payment_intent.succeeded') {
    const pi = event.data.object as Stripe.PaymentIntent;
    const orderId = asString(pi.metadata?.orderId);
    if (!orderId) return;
    const method =
      pi.payment_method && typeof pi.payment_method === 'object' && 'type' in pi.payment_method
        ? String((pi.payment_method as Stripe.PaymentMethod).type)
        : '';
    await markOrderPaid(db, orderId, pi.id, method === 'fpx' ? 'fpx' : 'card');
    return;
  }
  // payment_intent.payment_failed is deliberately ignored: the sheet may
  // still be retrying. Cleanup happens via the app's abandon call or sweep.
}
