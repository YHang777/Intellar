import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import express, { Router, type Request, type Response, type RequestHandler } from 'express';
import { z } from 'zod';
import type { Firestore } from 'firebase-admin/firestore';
import { ApiError, asyncHandler } from '../lib/errors';
import { authenticate } from '../middleware/authenticate';
import { requireUser } from '../middleware/types';
import { fbDb, FieldValue } from '../config/firebase';
import { renderViewerPage } from '../lib/viewer-page';
import { ANDROID_PACKAGE_FOR_VIEWER } from '../lib/viewer-constants';

// Share a room design as a link. The app sends a snapshot of the plan; anyone
// with the link sees it in 3D in a browser (/d/<token>), or in the app when it
// is installed. Snapshots live in Firestore (sharedDesigns, no client access),
// carry no owner details, and re-sharing the same design keeps the same link.

export interface SharedDesignsDeps {
  authorize: RequestHandler;
  db: () => Firestore;
  newToken: () => string;
  publicBaseUrl: string;
}

export function defaultSharedDesignsDeps(): SharedDesignsDeps {
  return {
    authorize: authenticate,
    db: fbDb,
    newToken: () => crypto.randomBytes(9).toString('base64url'),
    publicBaseUrl:
      process.env.PUBLIC_BASE_URL || 'https://interior-design-recommendation.onrender.com',
  };
}

export const SHARED = 'sharedDesigns';
export const SHARED_KEYS = 'sharedDesignKeys';

const tokenSchema = z.string().regex(/^[A-Za-z0-9_-]{8,32}$/);
const num = z.number().finite();
const point = z.tuple([num, num]);
const colour = z.number().int().nullable().optional();
const modelRef = z
  .string()
  .max(2000)
  .regex(/^(https:\/\/[^\s"'<>\\]+|assets\/models\/[A-Za-z0-9_-]+\.glb)$/)
  .nullable()
  .optional();

export const sceneSchema = z.object({
  name: z.string().max(200),
  roomType: z.string().max(60).optional(),
  room: z.object({
    widthCm: num,
    heightCm: num,
    walls: z.array(point).max(400),
    interiorWalls: z.array(z.array(point).max(400)).max(60).optional(),
    floorColor: colour,
    wallColor: colour,
    floorType: z.string().max(40).nullable().optional(),
    wallType: z.string().max(40).nullable().optional(),
  }),
  items: z
    .array(
      z.object({
        id: z.string().max(128),
        name: z.string().max(200),
        iconName: z.string().max(80).optional(),
        x: num,
        y: num,
        widthCm: num,
        depthCm: num,
        heightCm: num,
        rotation: num,
        elevationCm: num.optional(),
        model: modelRef,
        productId: z.string().max(128).nullable().optional(),
      })
    )
    .max(300),
});

const shareBody = z.object({
  designId: z.string().max(128).regex(/^[A-Za-z0-9_-]*$/).optional(),
  scene: sceneSchema,
  // The app's own design JSON, so the installed app can reopen the plan
  // exactly. Opaque to the server (owner fields are stripped by the app).
  design: z.record(z.unknown()).optional(),
});

export function createSharedDesignsRouter(deps: SharedDesignsDeps): Router {
  const router = Router();

  router.post(
    '/',
    deps.authorize,
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const parsed = shareBody.safeParse(req.body ?? {});
      if (!parsed.success) {
        throw new ApiError(400, 'INVALID_SHARE', 'That design could not be shared.');
      }
      const { designId, scene, design } = parsed.data;
      const db = deps.db();
      let token: string | null = null;
      const keyRef = designId ? db.collection(SHARED_KEYS).doc(`${uid}__${designId}`) : null;
      if (keyRef) {
        const key = await keyRef.get();
        const existing = key.exists ? key.data()?.token : null;
        if (typeof existing === 'string' && tokenSchema.safeParse(existing).success) token = existing;
      }
      const fresh = token == null;
      token ??= deps.newToken();
      await db
        .collection(SHARED)
        .doc(token)
        .set(
          {
            ownerUid: uid,
            scene,
            design: design ?? null,
            updatedAt: FieldValue.serverTimestamp(),
            ...(fresh ? { createdAt: FieldValue.serverTimestamp() } : {}),
          },
          { merge: true }
        );
      if (keyRef && fresh) await keyRef.set({ token });
      res.status(fresh ? 201 : 200).json({ token, url: `${deps.publicBaseUrl}/d/${token}` });
    })
  );

  router.get(
    '/:token',
    asyncHandler(async (req: Request, res: Response) => {
      const token = tokenSchema.safeParse(req.params.token);
      if (!token.success) throw new ApiError(404, 'NOT_FOUND', 'This shared design was not found.');
      const snap = await deps.db().collection(SHARED).doc(token.data).get();
      if (!snap.exists) throw new ApiError(404, 'NOT_FOUND', 'This shared design was not found.');
      const data = snap.data() ?? {};
      res.set('Cache-Control', 'no-cache');
      res.json({ scene: data.scene ?? null, design: data.design ?? null });
    })
  );

  return router;
}

// ── public pages: viewer, bundled models, Android app-link proof ──

export const ANDROID_PACKAGE = ANDROID_PACKAGE_FOR_VIEWER;
export const ANDROID_CERT_SHA256 =
  '0F:98:A9:1D:FB:5C:42:12:12:56:4C:B8:6C:7C:01:BE:C8:85:04:42:8C:0A:24:48:3D:7A:79:ED:91:43:21:1A';

export function resolveSharedModelsDir(): string {
  return process.env.SHARED_MODELS_DIR || path.resolve(__dirname, '../../../../assets/models');
}

export function createSharedPagesRouter(modelsDir = resolveSharedModelsDir()): Router {
  const router = Router();

  router.get('/d/:token', (req, res) => {
    const token = tokenSchema.safeParse(req.params.token);
    res
      .status(token.success ? 200 : 404)
      .type('html')
      .set('Cache-Control', 'no-cache')
      .send(renderViewerPage(token.success ? token.data : ''));
  });

  if (fs.existsSync(modelsDir)) {
    router.use(
      '/shared-models',
      (req, res, next) => (/^\/[A-Za-z0-9_-]+\.glb$/.test(req.path) ? next() : res.status(404).end()),
      express.static(modelsDir, { maxAge: '7d', index: false, dotfiles: 'deny' })
    );
  }

  router.get('/.well-known/assetlinks.json', (_req, res) => {
    res.json([
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: ANDROID_PACKAGE,
          sha256_cert_fingerprints: [ANDROID_CERT_SHA256],
        },
      },
    ]);
  });

  return router;
}
