import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { errorHandler } from '../middleware/errorHandler';
import { VerificationEmailException } from '../lib/verification-mailer';
import {
  CODE_TTL_MS,
  MAX_ATTEMPTS,
  RESEND_COOLDOWN_MS,
  createSecurityCodeRouter,
  maskEmail,
  type SecurityCodeDeps,
} from './security-code.routes';

type Doc = Record<string, unknown>;

class FakeDb {
  readonly store = new Map<string, Doc>();
  collection(col: string) {
    return {
      doc: (id: string) => {
        const key = `${col}/${id}`;
        return {
          get: async () => ({ exists: this.store.has(key), data: () => ({ ...this.store.get(key) }) }),
          set: async (data: Doc, opts?: { merge?: boolean }) => {
            this.store.set(key, opts?.merge ? { ...(this.store.get(key) ?? {}), ...data } : { ...data });
          },
          update: async (data: Doc) => {
            this.store.set(key, { ...(this.store.get(key) ?? {}), ...data });
          },
          delete: async () => {
            this.store.delete(key);
          },
        };
      },
    };
  }
}

interface Harness {
  base: string;
  db: FakeDb;
  sent: { email: string; code: string; purpose: string }[];
  clock: { t: number };
  authEmails: Map<string, string>;
  close: () => Promise<void>;
}

async function harness(overrides: Partial<SecurityCodeDeps> = {}): Promise<Harness> {
  const db = new FakeDb();
  const sent: Harness['sent'] = [];
  const clock = { t: Date.parse('2026-11-16T10:00:00Z') };
  const authEmails = new Map<string, string>([['u1', 'owner@example.com']]);
  let next = 100000;
  const authorize: RequestHandler = (req, _res, nextFn) => {
    req.user = { uid: 'u1', email: 'owner@example.com', name: null, adminClaim: false };
    nextFn();
  };
  const deps: SecurityCodeDeps = {
    secret: 'test-secret',
    mailer: {
      isConfigured: true,
      sendSecurityCode: async (args) => {
        sent.push(args);
      },
    },
    authorize,
    db: () => db as never,
    getAuthEmail: async (uid) => authEmails.get(uid) ?? null,
    emailInUse: async (email) => [...authEmails.values()].includes(email),
    updateAuthEmail: async (uid, email) => {
      authEmails.set(uid, email);
    },
    now: () => new Date(clock.t),
    generateCode: () => String(next++),
    ...overrides,
  };
  const app = express();
  app.use(express.json());
  app.use('/api/account', createSecurityCodeRouter(deps));
  app.use(errorHandler);
  const server: Server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  return {
    base: `http://127.0.0.1:${port}/api/account`,
    db,
    sent,
    clock,
    authEmails,
    close: () => new Promise((r) => server.close(() => r())),
  };
}

async function post(url: string, body: unknown) {
  const resp = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: resp.status, body: (await resp.json()) as Record<string, any> };
}

test('2fa send emails a code and verify accepts it once', async () => {
  const h = await harness();
  try {
    const sent = await post(`${h.base}/2fa/send`, {});
    assert.equal(sent.status, 200);
    assert.equal(sent.body.sentTo, 'ow***@example.com');
    assert.equal(h.sent.length, 1);
    assert.equal(h.sent[0].purpose, 'login');
    const stored = h.db.store.get('security_codes/u1__login')!;
    assert.notEqual(stored.codeHash, h.sent[0].code);

    const ok = await post(`${h.base}/2fa/verify`, { code: h.sent[0].code });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.verified, true);

    const again = await post(`${h.base}/2fa/verify`, { code: h.sent[0].code });
    assert.equal(again.status, 404);
  } finally {
    await h.close();
  }
});

test('wrong codes count down and lock after the max attempts', async () => {
  const h = await harness();
  try {
    await post(`${h.base}/2fa/send`, {});
    for (let i = 1; i < MAX_ATTEMPTS; i++) {
      const bad = await post(`${h.base}/2fa/verify`, { code: '999999' });
      assert.equal(bad.status, 400);
      assert.equal(bad.body.error.code, 'INVALID_CODE');
      assert.equal(bad.body.error.details.attemptsLeft, MAX_ATTEMPTS - i);
    }
    const locked = await post(`${h.base}/2fa/verify`, { code: '999999' });
    assert.equal(locked.status, 429);
    const late = await post(`${h.base}/2fa/verify`, { code: h.sent[0].code });
    assert.equal(late.status, 404);
  } finally {
    await h.close();
  }
});

test('codes expire and resends are rate limited', async () => {
  const h = await harness();
  try {
    await post(`${h.base}/2fa/send`, {});
    const tooSoon = await post(`${h.base}/2fa/send`, {});
    assert.equal(tooSoon.status, 429);
    assert.equal(tooSoon.body.error.code, 'RESEND_TOO_SOON');

    h.clock.t += RESEND_COOLDOWN_MS + 1;
    const resent = await post(`${h.base}/2fa/send`, {});
    assert.equal(resent.status, 200);
    assert.equal(h.sent.length, 2);
    const old = await post(`${h.base}/2fa/verify`, { code: h.sent[0].code });
    assert.equal(old.status, 400);

    h.clock.t += CODE_TTL_MS + 1;
    const expired = await post(`${h.base}/2fa/verify`, { code: h.sent[1].code });
    assert.equal(expired.status, 410);
  } finally {
    await h.close();
  }
});

test('2fa settings needs a valid code and writes the user flag', async () => {
  const h = await harness();
  try {
    const noCode = await post(`${h.base}/2fa/settings`, { enabled: true, code: '123456' });
    assert.equal(noCode.status, 404);
    await post(`${h.base}/2fa/send`, {});
    const on = await post(`${h.base}/2fa/settings`, { enabled: true, code: h.sent[0].code });
    assert.equal(on.status, 200);
    assert.equal(h.db.store.get('users/u1')?.twoFactorEnabled, true);
  } finally {
    await h.close();
  }
});

test('a seller can switch two-step sign-in off, but only with the emailed code', async () => {
  const h = await harness();
  try {
    h.db.store.set('users/u1', { role: 'supplier', twoFactorEnabled: true });
    await post(`${h.base}/2fa/send`, {});
    const wrong = await post(`${h.base}/2fa/settings`, { enabled: false, code: '000000' });
    assert.notEqual(wrong.status, 200);
    assert.equal(h.db.store.get('users/u1')?.twoFactorEnabled, true, 'wrong code changes nothing');
    const off = await post(`${h.base}/2fa/settings`, { enabled: false, code: h.sent[0].code });
    assert.equal(off.status, 200);
    assert.equal(h.db.store.get('users/u1')?.twoFactorEnabled, false);
  } finally {
    await h.close();
  }
});

test('email change sends the code to the new address and swaps the email', async () => {
  const h = await harness();
  try {
    const same = await post(`${h.base}/email/change-request`, { newEmail: 'Owner@Example.com' });
    assert.equal(same.status, 409);
    h.authEmails.set('u2', 'taken@example.com');
    const taken = await post(`${h.base}/email/change-request`, { newEmail: 'taken@example.com' });
    assert.equal(taken.body.error.code, 'EMAIL_IN_USE');

    const req = await post(`${h.base}/email/change-request`, { newEmail: 'new@example.com' });
    assert.equal(req.status, 200);
    assert.equal(h.sent[0].email, 'new@example.com');
    assert.equal(h.sent[0].purpose, 'email_change');

    const loginCode = await post(`${h.base}/2fa/verify`, { code: h.sent[0].code });
    assert.equal(loginCode.status, 404);

    const done = await post(`${h.base}/email/change-confirm`, { code: h.sent[0].code });
    assert.equal(done.status, 200);
    assert.equal(done.body.email, 'new@example.com');
    assert.equal(h.authEmails.get('u1'), 'new@example.com');
    assert.equal(h.db.store.get('users/u1')?.email, 'new@example.com');
  } finally {
    await h.close();
  }
});

test('send failures clear the code and report 502; missing config is 503', async () => {
  const failing = await harness({
    mailer: {
      isConfigured: true,
      sendSecurityCode: async () => {
        throw new VerificationEmailException('Brevo HTTP 500');
      },
    },
  });
  try {
    const r = await post(`${failing.base}/2fa/send`, {});
    assert.equal(r.status, 502);
    assert.equal(failing.db.store.has('security_codes/u1__login'), false);
  } finally {
    await failing.close();
  }
  const off = await harness({ secret: '' });
  try {
    const r = await post(`${off.base}/2fa/send`, {});
    assert.equal(r.status, 503);
  } finally {
    await off.close();
  }
});

test('rejects malformed codes before touching storage', async () => {
  const h = await harness();
  try {
    const r = await post(`${h.base}/2fa/verify`, { code: '12ab' });
    assert.equal(r.status, 400);
    assert.equal(r.body.error.code, 'VALIDATION_ERROR');
  } finally {
    await h.close();
  }
});

test('maskEmail keeps the domain and the first two letters', () => {
  assert.equal(maskEmail('ab@x.com'), 'ab*@x.com');
  assert.equal(maskEmail('jonathan@mail.my'), 'jo******@mail.my');
});
