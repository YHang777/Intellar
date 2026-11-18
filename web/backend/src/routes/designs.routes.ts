import { Router, type Request, type Response, type RequestHandler } from 'express';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { authenticate } from '../middleware/authenticate';
import { requireUser } from '../middleware/types';
import { env } from '../config/env';
import { supabaseAuthHeaders } from '../lib/supabase-headers';

// Saved room designs live in Supabase (`room_designs`). The app used to call
// Supabase directly with the public anon key, so with RLS off anyone holding
// that key could read or change every user's designs. Now every request goes
// through here: the Firebase sign-in says who the caller is, the service-role
// key talks to Supabase, and every query is pinned to the caller's own rows.
// RLS on the table can then deny the anon key entirely.

export interface DesignsDeps {
  authorize: RequestHandler;
  supabaseUrl: string;
  serviceRoleKey: string;
  fetchFn: typeof fetch;
}

export function defaultDesignsDeps(): DesignsDeps {
  return {
    authorize: authenticate,
    supabaseUrl: env.supabaseUrl,
    serviceRoleKey: env.supabaseServiceRoleKey,
    fetchFn: fetch,
  };
}

const TABLE = 'room_designs';
const idSchema = z.string().trim().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/, 'Invalid design id.');

// Columns a client may write. user_id is never taken from the body.
const rowSchema = z
  .object({
    name: z.string().max(200).optional(),
    room_type: z.string().max(60).optional(),
    width_cm: z.number().finite().optional(),
    height_cm: z.number().finite().optional(),
    furniture: z.unknown().optional(),
    detected_items: z.unknown().optional(),
    image_path: z.string().max(2000).nullable().optional(),
    created_at: z.string().max(40).optional(),
    updated_at: z.string().max(40).optional(),
  })
  .strip();

const createSchema = rowSchema.extend({ id: idSchema });

export function createDesignsRouter(deps: DesignsDeps): Router {
  const router = Router();
  router.use(deps.authorize);

  const base = deps.supabaseUrl.replace(/\/+$/, '');

  async function call(path: string, init: RequestInit = {}): Promise<unknown[]> {
    if (!base || !deps.serviceRoleKey.trim()) {
      throw new ApiError(503, 'DESIGNS_UNAVAILABLE', 'Saved designs are not available right now.');
    }
    const res = await deps.fetchFn(`${base}/rest/v1/${TABLE}${path}`, {
      ...init,
      headers: {
        ...supabaseAuthHeaders(deps.serviceRoleKey),
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
        ...(init.headers ?? {}),
      },
    });
    if (!res.ok) {
      const text = (await res.text()).slice(0, 300);
      console.error(`[designs] supabase ${res.status}: ${text}`);
      throw new ApiError(502, 'DESIGNS_FAILED', 'Could not reach your saved designs. Please try again.');
    }
    const text = await res.text();
    if (!text) return [];
    const parsed = JSON.parse(text) as unknown;
    return Array.isArray(parsed) ? parsed : [parsed];
  }

  const mine = (uid: string) => `user_id=eq.${encodeURIComponent(uid)}`;

  router.get(
    '/',
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      res.json({ designs: await call(`?${mine(uid)}&order=updated_at.desc`) });
    })
  );

  router.get(
    '/:id',
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const id = idSchema.parse(req.params.id);
      const rows = await call(`?id=eq.${encodeURIComponent(id)}&${mine(uid)}&limit=1`);
      if (rows.length === 0) throw new ApiError(404, 'NOT_FOUND', 'That design was not found.');
      res.json({ design: rows[0] });
    })
  );

  router.post(
    '/',
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const parsed = createSchema.safeParse(req.body ?? {});
      if (!parsed.success) throw new ApiError(400, 'INVALID_DESIGN', 'That design could not be saved.');
      const rows = await call('', {
        method: 'POST',
        body: JSON.stringify({ ...parsed.data, user_id: uid }),
      });
      res.status(201).json({ design: rows[0] ?? null });
    })
  );

  router.patch(
    '/:id',
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const id = idSchema.parse(req.params.id);
      const parsed = rowSchema.safeParse(req.body ?? {});
      if (!parsed.success) throw new ApiError(400, 'INVALID_DESIGN', 'That design could not be saved.');
      const rows = await call(`?id=eq.${encodeURIComponent(id)}&${mine(uid)}`, {
        method: 'PATCH',
        body: JSON.stringify(parsed.data),
      });
      // Someone else's design (or none): nothing matched, nothing changed.
      if (rows.length === 0) throw new ApiError(404, 'NOT_FOUND', 'That design was not found.');
      res.json({ design: rows[0] });
    })
  );

  router.delete(
    '/:id',
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const id = idSchema.parse(req.params.id);
      await call(`?id=eq.${encodeURIComponent(id)}&${mine(uid)}`, { method: 'DELETE' });
      res.status(204).end();
    })
  );

  return router;
}
