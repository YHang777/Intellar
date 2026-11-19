import { Router, type Request, type Response, type RequestHandler } from 'express';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { validateBody } from '../middleware/validate';
import { authenticate } from '../middleware/authenticate';
import { requireUser } from '../middleware/types';
import { fbDb, FieldValue } from '../config/firebase';
import {
  defaultNotificationDeps,
  notifyUser,
  orderStatusMessage,
  type NotificationDeps,
} from '../services/notifications.service';
import { CLIENT_AUDIT_ACTIONS, writeAudit, type AuditEntry } from '../services/audit.service';

/**
 * Events the app performs directly in Firestore (supplier status changes,
 * quote requests, new listings) are announced here so the server can fan
 * out notifications. Every route re-reads the document and checks the
 * caller's role on it — a client can only trigger what it was allowed to do.
 *
 *   POST /api/notify/order-status {orderId}
 *   POST /api/notify/quote        {quoteId, event: 'created'|'contacted'}
 *   POST /api/notify/new-product  {productId}
 *   POST /api/audit               {action, targetType?, targetId?, details?}
 */

export interface NotifyRouteDeps {
  authorize: RequestHandler;
  db: () => ReturnType<typeof fbDb>;
  notifications: NotificationDeps;
  audit: (entry: AuditEntry) => Promise<void>;
  now?: () => Date;
}

export function defaultNotifyRouteDeps(): NotifyRouteDeps {
  return {
    authorize: authenticate,
    db: fbDb,
    notifications: defaultNotificationDeps(),
    audit: (entry) => writeAudit(entry),
  };
}

const idSchema = z.string().trim().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/);
const orderBody = z.object({ orderId: idSchema });
const quoteBody = z.object({ quoteId: idSchema, event: z.enum(['created', 'contacted']) });
const productBody = z.object({ productId: idSchema });
const auditBody = z.object({
  action: z.string().trim().min(1).max(64),
  targetType: z.string().trim().max(32).optional(),
  targetId: z.string().trim().max(128).optional(),
  details: z.record(z.union([z.string().max(200), z.number(), z.boolean()])).optional(),
});

export const RECOMMENDATION_FANOUT_LIMIT = 200;
const NEW_PRODUCT_WINDOW_MS = 60 * 60 * 1000;

export function createNotifyRouter(deps: NotifyRouteDeps): Router {
  const router = Router();
  const now = () => (deps.now ? deps.now() : new Date());

  router.post(
    '/notify/order-status',
    deps.authorize,
    validateBody(orderBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const { orderId } = orderBody.parse(req.body);
      const snap = await deps.db().collection('orders').doc(orderId).get();
      if (!snap.exists) throw new ApiError(404, 'ORDER_NOT_FOUND', 'That order could not be found.');
      const order = snap.data() ?? {};
      const supplierIds = Array.isArray(order.supplierIds) ? order.supplierIds.map(String) : [];
      if (!supplierIds.includes(uid)) {
        throw new ApiError(403, 'FORBIDDEN', 'Only a seller on this order can announce it.');
      }
      const status = String(order.status ?? '');
      const orderNumber = String(order.orderNumber ?? orderId);
      const message = orderStatusMessage(status, orderNumber);
      const customerId = String(order.customerId ?? '');
      let notified = false;
      if (message && customerId) {
        const out = await notifyUser(deps.notifications, customerId, {
          kind: 'order_update',
          ...message,
          data: { orderId },
        });
        notified = out.stored;
      }
      await deps.audit({
        actorId: uid,
        action: 'order.status',
        targetType: 'order',
        targetId: orderId,
        details: { status },
      });
      res.json({ notified });
    })
  );

  router.post(
    '/notify/quote',
    deps.authorize,
    validateBody(quoteBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const { quoteId, event } = quoteBody.parse(req.body);
      const snap = await deps.db().collection('quote_requests').doc(quoteId).get();
      if (!snap.exists) throw new ApiError(404, 'QUOTE_NOT_FOUND', 'That quote request could not be found.');
      const q = snap.data() ?? {};
      const product = String(q.productName ?? 'a product');
      if (event === 'created') {
        if (String(q.customerId) !== uid) throw new ApiError(403, 'FORBIDDEN', 'Not your quote request.');
        await notifyUser(deps.notifications, String(q.supplierId), {
          kind: 'quote',
          title: 'New bulk quote request',
          body: `${String(q.customerName || 'A buyer')} asked for ${Number(q.quantity) || 1} × ${product}.`,
          data: { quoteId },
        });
      } else {
        if (String(q.supplierId) !== uid) throw new ApiError(403, 'FORBIDDEN', 'Not your quote request.');
        await notifyUser(deps.notifications, String(q.customerId), {
          kind: 'quote',
          title: 'The seller contacted you',
          body: `The seller has reached out about your bulk quote for ${product}.`,
          data: { quoteId },
        });
      }
      await deps.audit({
        actorId: uid,
        action: `quote.${event}`,
        targetType: 'quote',
        targetId: quoteId,
      });
      res.json({ notified: true });
    })
  );

  router.post(
    '/notify/new-product',
    deps.authorize,
    validateBody(productBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const { productId } = productBody.parse(req.body);
      const db = deps.db();
      const ref = db.collection('products').doc(productId);
      const snap = await ref.get();
      if (!snap.exists) throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
      const p = snap.data() ?? {};
      if (String(p.supplierId) !== uid) throw new ApiError(403, 'FORBIDDEN', 'Not your product.');
      const created = Date.parse(String(p.createdAt ?? ''));
      const fresh = Number.isFinite(created) && now().getTime() - created < NEW_PRODUCT_WINDOW_MS;
      const style = String(p.designStyle ?? '').trim();
      if (p.recommendationNotifiedAt || p.isActive === false || !fresh || !style) {
        res.json({ notified: 0 });
        return;
      }
      // Claim first so a retry can never fan out twice.
      await ref.set({ recommendationNotifiedAt: FieldValue.serverTimestamp() }, { merge: true });
      const fans = await db
        .collection('users')
        .where('designPreferences.styles', 'array-contains', style)
        .limit(RECOMMENDATION_FANOUT_LIMIT)
        .get();
      let notified = 0;
      for (const doc of fans.docs) {
        const u = doc.data();
        if (doc.id === uid || u.role !== 'homeowner') continue;
        if (u.privacySettings?.personalisedRecommendations === false) continue;
        const out = await notifyUser(deps.notifications, doc.id, {
          kind: 'recommendation',
          title: `New ${style} piece for you`,
          body: `${String(p.name)} matches your saved ${style} style.`,
          data: { productId },
        });
        if (out.stored) notified++;
      }
      res.json({ notified });
    })
  );

  // Promotions (FR20): a seller puts a listing on sale. Buyers who saved it
  // or whose style matches hear about it once per price: the same discount
  // never re-notifies, a deeper cut later does. Buyers with Promotions
  // switched off are skipped by notifyUser.
  router.post(
    '/notify/promotion',
    deps.authorize,
    validateBody(productBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const { productId } = productBody.parse(req.body);
      const db = deps.db();
      const ref = db.collection('products').doc(productId);
      const snap = await ref.get();
      if (!snap.exists) throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
      const p = snap.data() ?? {};
      if (String(p.supplierId) !== uid) throw new ApiError(403, 'FORBIDDEN', 'Not your product.');
      const price = Number(p.price);
      const was = Number(p.originalPrice);
      const onSale = Number.isFinite(price) && Number.isFinite(was) && was > price && price > 0;
      const already = Number(p.promotionNotifiedPrice);
      if (!onSale || p.isActive === false || (Number.isFinite(already) && price >= already)) {
        res.json({ notified: 0 });
        return;
      }
      // Claim first so a retry can never fan out twice for this price.
      await ref.set({ promotionNotifiedPrice: price }, { merge: true });

      const recipients = new Set<string>();
      const saved = await db
        .collectionGroup('wishlist')
        .where('productId', '==', productId)
        .limit(RECOMMENDATION_FANOUT_LIMIT)
        .get();
      for (const d of saved.docs) {
        const owner = d.ref.parent.parent?.id;
        if (owner) recipients.add(owner);
      }
      const style = String(p.designStyle ?? '').trim();
      if (style) {
        const fans = await db
          .collection('users')
          .where('designPreferences.styles', 'array-contains', style)
          .limit(RECOMMENDATION_FANOUT_LIMIT)
          .get();
        for (const d of fans.docs) recipients.add(d.id);
      }
      recipients.delete(uid);

      const percent = Math.round((1 - price / was) * 100);
      let notified = 0;
      for (const rid of recipients) {
        const u = (await db.collection('users').doc(rid).get()).data();
        if (!u || u.role !== 'homeowner') continue;
        const out = await notifyUser(deps.notifications, rid, {
          kind: 'promotion',
          title: `${percent}% off ${String(p.name)}`,
          body: `Now RM ${price} (was RM ${was}).`,
          data: { productId },
        });
        if (out.stored) notified++;
      }
      res.json({ notified });
    })
  );

  router.post(
    '/audit',
    deps.authorize,
    validateBody(auditBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const body = auditBody.parse(req.body);
      if (!CLIENT_AUDIT_ACTIONS.has(body.action)) {
        throw new ApiError(400, 'UNKNOWN_ACTION', 'That action is not recorded.');
      }
      await deps.audit({ actorId: uid, ...body });
      res.json({ recorded: true });
    })
  );

  return router;
}
