import { Router, type Request, type Response, type RequestHandler } from 'express';
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { validateBody } from '../middleware/validate';
import { authenticate } from '../middleware/authenticate';
import { requireUser } from '../middleware/types';
import { env } from '../config/env';
import { fbAuth, fbDb } from '../config/firebase';
import { VerificationEmailException, VerificationMailer } from '../lib/verification-mailer';
import { getAuthUserOrNull } from '../services/identity.service';
import { auditQuietly, type AuditEntry } from '../services/audit.service';

/**
 * Email one-time codes for the mobile app (mounted at /api/account):
 *
 *   POST /2fa/send              {}                → 200 {sentTo, expiresAt}
 *   POST /2fa/verify            {code}            → 200 {verified: true}
 *   POST /2fa/settings          {enabled, code}   → 200 {twoFactorEnabled}
 *   POST /email/change-request  {newEmail}        → 200 {sentTo, expiresAt}
 *   POST /email/change-confirm  {code}            → 200 {email}
 *
 * Failures: 400 INVALID_CODE {attemptsLeft} · 404 NO_ACTIVE_CODE ·
 * 409 EMAIL_IN_USE / SAME_EMAIL · 410 CODE_EXPIRED · 429 RESEND_TOO_SOON /
 * TOO_MANY_ATTEMPTS · 502 SEND_FAILED · 503 NOT_CONFIGURED.
 *
 * Only an HMAC of the code is stored (`security_codes/{uid}__{purpose}`);
 * a code is single-use and dies after 10 minutes or 5 wrong tries.
 */

export type CodePurpose = 'login' | 'email_change';

export const CODE_TTL_MS = 10 * 60 * 1000;
export const RESEND_COOLDOWN_MS = 30 * 1000;
export const MAX_ATTEMPTS = 5;
const COLLECTION = 'security_codes';

export interface SecurityCodeDeps {
  secret: string;
  mailer: Pick<VerificationMailer, 'isConfigured' | 'sendSecurityCode'>;
  authorize: RequestHandler;
  db: () => ReturnType<typeof fbDb>;
  getAuthEmail: (uid: string) => Promise<string | null>;
  emailInUse: (email: string) => Promise<boolean>;
  updateAuthEmail: (uid: string, email: string) => Promise<void>;
  now?: () => Date;
  generateCode?: () => string;
  audit?: (entry: AuditEntry) => void;
  log?: (message: string) => void;
}

export function defaultSecurityCodeDeps(): SecurityCodeDeps {
  return {
    secret: env.verifyTokenSecret,
    mailer: new VerificationMailer({
      apiKey: env.brevoApiKey,
      senderEmail: env.brevoSenderEmail,
      senderName: env.brevoSenderName,
      publicBaseUrl: env.publicBaseUrl,
    }),
    authorize: authenticate,
    db: fbDb,
    getAuthEmail: async (uid) => (await getAuthUserOrNull(uid))?.email ?? null,
    emailInUse: async (email) => {
      try {
        await fbAuth().getUserByEmail(email);
        return true;
      } catch (err) {
        if ((err as { code?: string }).code === 'auth/user-not-found') return false;
        throw err;
      }
    },
    updateAuthEmail: async (uid, email) => {
      await fbAuth().updateUser(uid, { email, emailVerified: true });
    },
    audit: (entry) => auditQuietly(entry),
    log: (message) => console.log(message),
  };
}

const codeSchema = z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit code.');
const emptyBody = z.object({});
const verifyBody = z.object({ code: codeSchema });
const settingsBody = z.object({ enabled: z.boolean(), code: codeSchema });
const changeRequestBody = z.object({ newEmail: z.string().trim().toLowerCase().email().max(320) });

interface StoredCode {
  codeHash: string;
  expiresAtMs: number;
  sentAtMs: number;
  attempts: number;
  email: string;
  newEmail?: string;
}

export function hashCode(secret: string, uid: string, purpose: CodePurpose, code: string): string {
  return createHmac('sha256', secret).update(`${uid}:${purpose}:${code}`).digest('hex');
}

export function maskEmail(email: string): string {
  const [local, domain] = email.split('@');
  if (!domain) return email;
  const head = local.slice(0, Math.min(2, local.length));
  return `${head}${'*'.repeat(Math.max(1, local.length - head.length))}@${domain}`;
}

export function createSecurityCodeRouter(deps: SecurityCodeDeps): Router {
  const router = Router();
  const now = () => (deps.now ? deps.now() : new Date());
  const docRef = (uid: string, purpose: CodePurpose) =>
    deps.db().collection(COLLECTION).doc(`${uid}__${purpose}`);

  function ensureConfigured(): void {
    if (deps.secret.trim().length === 0 || !deps.mailer.isConfigured) {
      throw new ApiError(503, 'NOT_CONFIGURED', 'Email codes are not available right now.');
    }
  }

  async function issue(uid: string, purpose: CodePurpose, email: string, newEmail?: string) {
    ensureConfigured();
    const ref = docRef(uid, purpose);
    const snap = await ref.get();
    const t = now().getTime();
    if (snap.exists) {
      const prev = snap.data() as StoredCode;
      const wait = prev.sentAtMs + RESEND_COOLDOWN_MS - t;
      if (wait > 0 && prev.expiresAtMs > t && (prev.newEmail ?? '') === (newEmail ?? '')) {
        throw new ApiError(
          429,
          'RESEND_TOO_SOON',
          `Please wait ${Math.ceil(wait / 1000)} seconds before asking for a new code.`
        );
      }
    }
    const code = deps.generateCode ? deps.generateCode() : String(randomInt(0, 1_000_000)).padStart(6, '0');
    const record: StoredCode = {
      codeHash: hashCode(deps.secret, uid, purpose, code),
      expiresAtMs: t + CODE_TTL_MS,
      sentAtMs: t,
      attempts: 0,
      email,
      ...(newEmail ? { newEmail } : {}),
    };
    await ref.set(record);
    try {
      await deps.mailer.sendSecurityCode({ email: newEmail ?? email, code, purpose });
    } catch (err) {
      await ref.delete();
      if (err instanceof VerificationEmailException) {
        deps.log?.(`[security-code] send failed: ${err.message}`);
        throw new ApiError(502, 'SEND_FAILED', 'Could not send the code email. Please try again.');
      }
      throw err;
    }
    return { sentTo: maskEmail(newEmail ?? email), expiresAt: new Date(record.expiresAtMs).toISOString() };
  }

  async function consume(uid: string, purpose: CodePurpose, code: string): Promise<StoredCode> {
    ensureConfigured();
    const ref = docRef(uid, purpose);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new ApiError(404, 'NO_ACTIVE_CODE', 'No code is waiting. Ask for a new one.');
    }
    const stored = snap.data() as StoredCode;
    if (stored.expiresAtMs <= now().getTime()) {
      await ref.delete();
      throw new ApiError(410, 'CODE_EXPIRED', 'That code has expired. Ask for a new one.');
    }
    const expected = Buffer.from(stored.codeHash, 'hex');
    const actual = Buffer.from(hashCode(deps.secret, uid, purpose, code), 'hex');
    if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
      const attempts = stored.attempts + 1;
      if (attempts >= MAX_ATTEMPTS) {
        await ref.delete();
        throw new ApiError(429, 'TOO_MANY_ATTEMPTS', 'Too many wrong codes. Ask for a new one.');
      }
      await ref.update({ attempts });
      throw new ApiError(400, 'INVALID_CODE', 'That code is not right. Check the email and try again.', {
        attemptsLeft: MAX_ATTEMPTS - attempts,
      });
    }
    await ref.delete();
    return stored;
  }

  async function authEmailOf(uid: string): Promise<string> {
    const email = await deps.getAuthEmail(uid);
    if (!email) throw new ApiError(400, 'NO_EMAIL', 'Your account has no email address.');
    return email;
  }

  router.post(
    '/2fa/send',
    deps.authorize,
    validateBody(emptyBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      res.json(await issue(uid, 'login', await authEmailOf(uid)));
    })
  );

  router.post(
    '/2fa/verify',
    deps.authorize,
    validateBody(verifyBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const { code } = verifyBody.parse(req.body);
      await consume(uid, 'login', code);
      res.json({ verified: true });
    })
  );

  router.post(
    '/2fa/settings',
    deps.authorize,
    validateBody(settingsBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const { enabled, code } = settingsBody.parse(req.body);
      // Any account (sellers included) may switch it off, but only with a
      // valid emailed code.
      await consume(uid, 'login', code);
      await deps.db().collection('users').doc(uid).set({ twoFactorEnabled: enabled }, { merge: true });
      deps.audit?.({ actorId: uid, action: enabled ? '2fa.enabled' : '2fa.disabled', targetType: 'user', targetId: uid });
      res.json({ twoFactorEnabled: enabled });
    })
  );

  router.post(
    '/email/change-request',
    deps.authorize,
    validateBody(changeRequestBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const { newEmail } = changeRequestBody.parse(req.body);
      const current = await authEmailOf(uid);
      if (current.toLowerCase() === newEmail) {
        throw new ApiError(409, 'SAME_EMAIL', 'That is already your email address.');
      }
      if (await deps.emailInUse(newEmail)) {
        throw new ApiError(409, 'EMAIL_IN_USE', 'Another account already uses that email.');
      }
      res.json(await issue(uid, 'email_change', current, newEmail));
    })
  );

  router.post(
    '/email/change-confirm',
    deps.authorize,
    validateBody(verifyBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { uid } = requireUser(req);
      const { code } = verifyBody.parse(req.body);
      const stored = await consume(uid, 'email_change', code);
      const newEmail = stored.newEmail;
      if (!newEmail) throw new ApiError(404, 'NO_ACTIVE_CODE', 'No email change is waiting.');
      if (await deps.emailInUse(newEmail)) {
        throw new ApiError(409, 'EMAIL_IN_USE', 'Another account already uses that email.');
      }
      await deps.updateAuthEmail(uid, newEmail);
      await deps.db().collection('users').doc(uid).set({ email: newEmail }, { merge: true });
      deps.log?.(`[security-code] email changed uid=${uid}`);
      deps.audit?.({ actorId: uid, action: 'email.changed', targetType: 'user', targetId: uid });
      res.json({ email: newEmail });
    })
  );

  return router;
}
