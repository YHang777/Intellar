import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import { createSharedDesignsRouter, createSharedPagesRouter } from './shared-designs.routes';
import { createModelsRouter, isGlb } from './models.routes';

type Doc = Record<string, unknown>;

function fakeDb(docs: Map<string, Doc>) {
  const ref = (path: string) => ({
    get: async () => ({ exists: docs.has(path), data: () => docs.get(path) }),
    set: async (d: Doc, opts?: { merge?: boolean }) => {
      docs.set(path, opts?.merge ? { ...(docs.get(path) ?? {}), ...d } : { ...d });
    },
  });
  return { collection: (c: string) => ({ doc: (id: string) => ref(`${c}/${id}`) }) };
}

const asUser = (uid: string | null): RequestHandler => (req, res, next) => {
  if (!uid) {
    res.status(401).json({});
    return;
  }
  req.user = { uid, email: null, name: null, adminClaim: false };
  next();
};

async function serve(app: express.Express, fn: (base: string) => Promise<void>) {
  app.use((err: { statusCode?: number }, _q: express.Request, res: express.Response, _n: express.NextFunction) => {
    res.status(err.statusCode ?? 500).json({});
  });
  const server = app.listen(0);
  try {
    await fn(`http://127.0.0.1:${(server.address() as AddressInfo).port}`);
  } finally {
    server.close();
  }
}

const scene = {
  name: 'Living room',
  room: { widthCm: 400, heightCm: 500, walls: [[0, 0], [400, 0], [400, 500], [0, 500]] },
  items: [
    { id: 'a', name: 'Sofa', x: 10, y: 20, widthCm: 200, depthCm: 90, heightCm: 80, rotation: 0, model: 'assets/models/sofa.glb' },
  ],
};

function sharedApp(docs: Map<string, Doc>, uid: string | null) {
  let n = 0;
  const app = express();
  app.use(express.json());
  app.use(
    '/s',
    createSharedDesignsRouter({
      authorize: asUser(uid),
      db: () => fakeDb(docs) as never,
      newToken: () => `tok${++n}abcdefgh`,
      publicBaseUrl: 'https://host',
    })
  );
  return app;
}

const post = (base: string, body: unknown) =>
  fetch(`${base}/s`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

test('sharing gives a link anyone can open; re-sharing keeps it', async () => {
  const docs = new Map<string, Doc>();
  await serve(sharedApp(docs, 'u1'), async (base) => {
    const first = await post(base, { designId: 'd1', scene });
    assert.equal(first.status, 201);
    const { token, url } = (await first.json()) as { token: string; url: string };
    assert.equal(url, `https://host/d/${token}`);

    const again = await post(base, { designId: 'd1', scene: { ...scene, name: 'Renamed' } });
    assert.equal(again.status, 200);
    assert.equal(((await again.json()) as { token: string }).token, token, 'same link');

    const other = (await (await post(base, { scene })).json()) as { token: string };
    assert.notEqual(other.token, token, 'an unsaved plan gets its own link');

    const got = await fetch(`${base}/s/${token}`);
    assert.equal(got.status, 200);
    const body = (await got.json()) as { scene: { name: string }; ownerUid?: string };
    assert.equal(body.scene.name, 'Renamed');
    assert.equal(body.ownerUid, undefined, 'no owner details leak');
    assert.equal((await fetch(`${base}/s/nope12345`)).status, 404);
  });
});

test('sharing needs sign-in and a valid scene', async () => {
  await serve(sharedApp(new Map(), null), async (base) => {
    assert.equal((await post(base, { scene })).status, 401);
  });
  await serve(sharedApp(new Map(), 'u1'), async (base) => {
    const bad = { ...scene, items: [{ ...scene.items[0], model: 'javascript:alert(1)' }] };
    assert.equal((await post(base, { scene: bad })).status, 400);
    assert.equal((await post(base, { designId: '../x', scene })).status, 400);
  });
});

test('viewer page, bundled models and app links are served publicly', async () => {
  const app = express();
  app.use(createSharedPagesRouter());
  await serve(app, async (base) => {
    const page = await fetch(`${base}/d/abcdefgh12`);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /__SHARE_TOKEN__ = "abcdefgh12"/);
    assert.equal((await fetch(`${base}/d/%3Cscript%3E`)).status, 404);
    const links = (await (await fetch(`${base}/.well-known/assetlinks.json`)).json()) as Array<{
      target: { package_name: string };
    }>;
    assert.equal(links[0].target.package_name, 'com.example.interior_design_recommendation');
    assert.equal((await fetch(`${base}/shared-models/..%2Fpubspec.yaml`)).status, 404);
  });
});

// ── model uploads ──

const glb = () => {
  const b = Buffer.alloc(20);
  b.writeUInt32LE(0x46546c67, 0);
  return b;
};

function modelsApp(docs: Map<string, Doc>, uid: string, calls: string[]) {
  const app = express();
  app.use(
    '/m',
    createModelsRouter({
      authorize: asUser(uid),
      db: () => fakeDb(docs) as never,
      supabaseUrl: 'https://ref.supabase.co/rest/v1',
      serviceRoleKey: 'service',
      bucket: 'product_models',
      fetchFn: (async (url: string, init: RequestInit) => {
        calls.push(`${init.method} ${url}`);
        return new Response('{}', { status: 200 });
      }) as never,
    })
  );
  return app;
}

test('only the listing owner can upload or delete its 3D model', async () => {
  const docs = new Map<string, Doc>([
    ['products/p1', { supplierId: 'seller' }],
    ['products/p2', { supplier: { id: 'seller' } }],
  ]);
  const calls: string[] = [];
  const put = (base: string, id: string, body: Buffer) => fetch(`${base}/m/${id}`, { method: 'PUT', body });

  await serve(modelsApp(docs, 'seller', calls), async (base) => {
    const ok = await put(base, 'p1', glb());
    assert.equal(ok.status, 201);
    assert.equal(
      ((await ok.json()) as { url: string }).url,
      'https://ref.supabase.co/storage/v1/object/public/product_models/product_models/p1.glb'
    );
    assert.equal((await put(base, 'p2', glb())).status, 201, 'nested supplier.id owner');
    assert.equal((await put(base, 'p1', Buffer.from('not a model'))).status, 400);
    assert.equal((await put(base, 'gone', glb())).status, 404);
    assert.equal((await fetch(`${base}/m/gone`, { method: 'DELETE' })).status, 204, 'orphan clean-up');
  });
  await serve(modelsApp(docs, 'stranger', calls), async (base) => {
    assert.equal((await put(base, 'p1', glb())).status, 403);
    assert.equal((await fetch(`${base}/m/p1`, { method: 'DELETE' })).status, 403);
  });
  assert.deepEqual(calls, [
    'POST https://ref.supabase.co/storage/v1/object/product_models/product_models/p1.glb',
    'POST https://ref.supabase.co/storage/v1/object/product_models/product_models/p2.glb',
    'DELETE https://ref.supabase.co/storage/v1/object/product_models/product_models/gone.glb',
  ]);
  assert.equal(isGlb(Buffer.from('glTF')), false, 'too short');
});
