import type { Request, Response, NextFunction } from 'express';
import { ApiError } from '../lib/errors';
import { fbAuth } from '../config/firebase';

/**
 * Step 1 of the chain — AUTH CHECK.
 *
 * Verifies the `Authorization: Bearer <firebase-id-token>` header with the
 * Firebase Admin SDK and attaches the decoded identity to `req.user`.
 * Every route except `/api/health` and `/api/auth/login` runs this.
 */
export async function authenticate(req: Request, res: Response, next: NextFunction): Promise<void> {
  await verify(req, res, next, false);
}

/**
 * Same check, but also lets in guests (Firebase anonymous sign-in). Only for
 * what guests may use: the design assistant, the room-scan material read and
 * product-view counting. Everything else stays account-only.
 */
export async function authenticateAllowGuest(req: Request, res: Response, next: NextFunction): Promise<void> {
  await verify(req, res, next, true);
}

async function verify(req: Request, _res: Response, next: NextFunction, allowGuest: boolean): Promise<void> {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'));
    return;
  }
  const token = header.slice('Bearer '.length).trim();
  if (!token) {
    next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'));
    return;
  }
  try {
    const decoded = await fbAuth().verifyIdToken(token);
    if (decoded.firebase?.sign_in_provider === 'anonymous' && !allowGuest) {
      next(new ApiError(403, 'ACCOUNT_REQUIRED', 'Create a free account to do this.'));
      return;
    }
    req.user = {
      uid: decoded.uid,
      email: decoded.email ?? null,
      name: decoded.name ?? null,
      adminClaim: decoded.admin === true,
    };
    next();
  } catch (err) {
    if (err instanceof ApiError && err.code === 'FIREBASE_NOT_CONFIGURED') {
      next(err);
      return;
    }
    const message = (err as Error).message ?? '';
    if (message.includes('credential') || message.includes('not configured')) {
      next(new ApiError(503, 'FIREBASE_NOT_CONFIGURED', message));
      return;
    }
    // Token invalid/expired — never echo token material back.
    next(new ApiError(401, 'UNAUTHENTICATED', 'Invalid or expired sign-in token.'));
  }
}
