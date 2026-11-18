import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import { createDesignsRouter } from './designs.routes';

const asUser = (uid: string): RequestHandler => (req, _res, next) => {
  req.user = { uid, email: null, name: null, adminClaim: false };
  next();
};

async function run(uid: string, fn: (base: string, calls: { url: string; init: RequestInit }[]) => Promise<void>, reply: unknown[] = []) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn = (async (url: string, init: RequestInit = {}) => {
    calls.push({ url: String(url), init });
    return new Response(JSON.stringify(reply), { status: 200 });
  }) as typeof fetch;
  const app = express();
  app.use(express.json());
  app.use('/api/designs', createDesignsRouter({ authorize: asUser(uid), supabaseUrl: 'https://sb.test', serviceRoleKey: 'svc', fetchFn }));
  app.use((err: { statusCode?: number }, _q: express.Request, res: express.Response, _n: express.NextFunction) => {
    res.status(err.statusCode ?? 500).end();
  });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api/designs`;
  try { await fn(base, calls); } finally { server.close(); }
}

test('listing is pinned to the caller, with the service key', async () => {
  await run('alice', async (base, calls) => {
    assert.equal((await fetch(base)).status, 200);
    assert.match(calls[0].url, /user_id=eq\.alice/);
    assert.equal((calls[0].init.headers as Record<string, string>).apikey, 'svc');
  });
});

test('a create can never claim another user', async () => {
  await run('alice', async (base, calls) => {
    const r = await fetch(base, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: 'd1', name: 'Lounge', user_id: 'mallory' }) });
    assert.equal(r.status, 201);
    assert.equal(JSON.parse(String(calls[0].init.body)).user_id, 'alice');
  }, [{ id: 'd1' }]);
});

test("someone else's design: update finds nothing and says not found", async () => {
  await run('alice', async (base, calls) => {
    const r = await fetch(`${base}/d9`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: 'x' }) });
    assert.equal(r.status, 404);
    assert.match(calls[0].url, /id=eq\.d9&user_id=eq\.alice/);
  }, []);
});

test('delete and get are pinned to the caller too', async () => {
  await run('alice', async (base, calls) => {
    await fetch(`${base}/d1`, { method: 'DELETE' });
    assert.match(calls[0].url, /id=eq\.d1&user_id=eq\.alice/);
    assert.equal((await fetch(`${base}/d2`)).status, 404, 'not mine / missing');
    assert.match(calls[1].url, /id=eq\.d2&user_id=eq\.alice/);
  }, []);
});
