import express, { Router, type Request, type Response, type RequestHandler } from 'express';
import { z } from 'zod';
import type { Firestore } from 'firebase-admin/firestore';
import { ApiError, asyncHandler } from '../lib/errors';
import { authenticate } from '../middleware/authenticate';
import { requireUser } from '../middleware/types';
import { env } from '../config/env';
import { fbDb } from '../config/firebase';
import { supabaseAuthHeaders, supabaseOrigin } from '../lib/supabase-headers';

// Product 3D models (Tripo output) are stored in a public Supabase Storage
// bucket. The app used to upload and delete with the public anon key, which
// meant anyone holding that key could overwrite or delete any model. Now the
// app sends the bytes here: the Firebase sign-in says who is calling, the
// listing must be theirs, and the service-role key does the write. The bucket
// can then refuse anon writes entirely (public reads keep working).

export interface ModelsDeps {
  authorize: RequestHandler;
  db: () => Firestore;
  supabaseUrl: string;
  serviceRoleKey: string;
  bucket: string;
  fetchFn: typeof fetch;
}

export function defaultModelsDeps(): ModelsDeps {
  return {
    authorize: authenticate,
    db: fbDb,
    supabaseUrl: env.supabaseUrl,
    serviceRoleKey: env.supabaseServiceRoleKey,
    bucket: process.env.SUPABASE_MODELS_BUCKET || 'product_models',
    fetchFn: fetch,
  };
}

export const MAX_MODEL_BYTES = 40 * 1024 * 1024;

const productIdSchema = z.string().trim().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/);

const GLB_MAGIC = 0x46546c67; // "glTF"

export function isGlb(bytes: Buffer): boolean {
  return bytes.length >= 12 && bytes.readUInt32LE(0) === GLB_MAGIC;
}

function ownerOf(data: Record<string, unknown> | undefined): string | null {
  if (!data) return null;
  if (typeof data.supplierId === 'string' && data.supplierId) return data.supplierId;
  const supplier = data.supplier as Record<string, unknown> | undefined;
  return typeof supplier?.id === 'string' && supplier.id ? supplier.id : null;
}

export function createModelsRouter(deps: ModelsDeps): Router {
  const router = Router();
  router.use(deps.authorize);

  const base = supabaseOrigin(deps.supabaseUrl);

  function requireConfigured(): void {
    if (!base || !deps.serviceRoleKey.trim() || !deps.bucket.trim()) {
      throw new ApiError(503, 'MODELS_UNAVAILABLE', '3D model storage is not available right now.');
    }
  }

  // The caller must own the listing. A listing that no longer exists may
  // still have its leftover model cleaned up (deleteOrphan).
  async function checkOwner(uid: string, productId: string, deleteOrphan: boolean): Promise<void> {
    const snap = await deps.db().collection('products').doc(productId).get();
    if (!snap.exists) {
      if (deleteOrphan) return;
      throw new ApiError(404, 'NOT_FOUND', 'That listing was not found.');
    }
    if (ownerOf(snap.data()) !== uid) {
      throw new ApiError(403, 'FORBIDDEN', 'You can only change models for your own listings.');
    }
  }

  const objectPath = (productId: string) => `product_models/${productId}.glb`;

  router.put(
    '/:productId',
    express.raw({ type: () => true, limit: MAX_MODEL_BYTES }),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      requireConfigured();
      const productId = productIdSchema.parse(req.params.productId);
      const body = req.body as unknown;
      if (!Buffer.isBuffer(body) || !isGlb(body)) {
        throw new ApiError(400, 'INVALID_MODEL', 'That file is not a 3D model.');
      }
      await checkOwner(uid, productId, false);
      const path = objectPath(productId);
      const upstream = await deps.fetchFn(`${base}/storage/v1/object/${deps.bucket}/${path}`, {
        method: 'POST',
        headers: {
          ...supabaseAuthHeaders(deps.serviceRoleKey),
          'Content-Type': 'model/gltf-binary',
          'x-upsert': 'true',
        },
        body,
      });
      if (!upstream.ok) {
        console.error(`[models] upload ${upstream.status}: ${(await upstream.text()).slice(0, 300)}`);
        throw new ApiError(502, 'MODEL_UPLOAD_FAILED', 'Could not save the 3D model. Please try again.', {
          upstreamStatus: upstream.status,
        });
      }
      res.status(201).json({ url: `${base}/storage/v1/object/public/${deps.bucket}/${path}` });
    })
  );

  router.delete(
    '/:productId',
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      requireConfigured();
      const productId = productIdSchema.parse(req.params.productId);
      await checkOwner(uid, productId, true);
      const upstream = await deps.fetchFn(
        `${base}/storage/v1/object/${deps.bucket}/${objectPath(productId)}`,
        { method: 'DELETE', headers: supabaseAuthHeaders(deps.serviceRoleKey) }
      );
      if (!upstream.ok && upstream.status !== 404 && upstream.status !== 400) {
        throw new ApiError(502, 'MODEL_DELETE_FAILED', 'Could not remove the 3D model.', {
          upstreamStatus: upstream.status,
        });
      }
      res.status(204).end();
    })
  );

  return router;
}
