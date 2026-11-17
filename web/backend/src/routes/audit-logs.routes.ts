import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../lib/errors';
import { authenticate } from '../middleware/authenticate';
import { requireAdmin } from '../middleware/requireAdmin';
import { validateQuery } from '../middleware/validate';
import { fbDb } from '../config/firebase';

/**
 * GET /api/audit-logs?limit=&actorId=&action=  (admin only)
 * Newest first. Timestamps are returned as ISO strings.
 */
const query = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(50),
  actorId: z.string().trim().max(128).optional(),
  action: z.string().trim().max(64).optional(),
});

export function createAuditLogsRouter(db: () => ReturnType<typeof fbDb> = fbDb): Router {
  const router = Router();
  router.use(authenticate, requireAdmin);
  router.get(
    '/',
    validateQuery(query),
    asyncHandler(async (req: Request, res: Response) => {
      const q = query.parse(req.query);
      let ref: FirebaseFirestore.Query = db().collection('audit_logs');
      if (q.actorId) ref = ref.where('actorId', '==', q.actorId);
      if (q.action) ref = ref.where('action', '==', q.action);
      const snap = await ref.orderBy('at', 'desc').limit(q.limit).get();
      res.json({
        logs: snap.docs.map((d) => {
          const x = d.data();
          const at = x.at && typeof x.at.toDate === 'function' ? x.at.toDate().toISOString() : null;
          return {
            id: d.id,
            actorId: x.actorId ?? '',
            action: x.action ?? '',
            targetType: x.targetType ?? '',
            targetId: x.targetId ?? '',
            details: x.details ?? {},
            at,
          };
        }),
      });
    })
  );
  return router;
}
