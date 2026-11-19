import { Router, type Request, type Response, type RequestHandler } from 'express';
import { z } from 'zod';
import type { Firestore } from 'firebase-admin/firestore';
import { ApiError, asyncHandler } from '../lib/errors';
import { validateBody } from '../middleware/validate';
import { authenticateAllowGuest } from '../middleware/authenticate';
import { requireUser } from '../middleware/types';
import { fbDb, FieldValue } from '../config/firebase';

// Product views for seller analytics (report 1.5.1: "track product views").
// viewCount is server-owned (clients cannot write it). One view per buyer
// per product per Malaysian day, and never the seller's own, so refreshing a
// page or a seller checking their listing cannot inflate it.

export interface ProductViewsDeps {
  authorize: RequestHandler;
  db: () => Firestore;
  now: () => Date;
}

export function defaultProductViewsDeps(): ProductViewsDeps {
  return { authorize: authenticateAllowGuest, db: fbDb, now: () => new Date() };
}

const body = z.object({
  productId: z.string().trim().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/),
});

/** Calendar day in Malaysia (UTC+8), e.g. 2026-11-19. */
export function malaysiaDay(now: Date): string {
  return new Date(now.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

export function createProductViewsRouter(deps: ProductViewsDeps): Router {
  const router = Router();

  router.post(
    '/',
    deps.authorize,
    validateBody(body),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const { productId } = body.parse(req.body);
      const db = deps.db();
      const productRef = db.collection('products').doc(productId);
      const markRef = db.collection('productViews').doc(`${productId}_${uid}`);
      const day = malaysiaDay(deps.now());

      const counted = await db.runTransaction(async (txn) => {
        const [product, mark] = await Promise.all([txn.get(productRef), txn.get(markRef)]);
        if (!product.exists) throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
        const p = product.data() ?? {};
        const owner = String(p.supplierId ?? (p.supplier as { id?: string } | undefined)?.id ?? '');
        if (owner === uid) return false;
        if (mark.exists && mark.data()?.day === day) return false;
        txn.set(markRef, { productId, uid, day });
        txn.update(productRef, { viewCount: FieldValue.increment(1) });
        return true;
      });
      res.json({ counted });
    })
  );

  return router;
}
