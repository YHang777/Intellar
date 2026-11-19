import { ANDROID_PACKAGE_FOR_VIEWER } from './viewer-constants';

// The shared-design page (/d/<token>): a three.js dollhouse of the plan that
// people can drag to look around, pinch/scroll to zoom and two-finger drag to
// move, matching the app's 3D planner. Placement maths mirrors
// planner_scene_bridge.dart (footprint centre, per-axis fit, quarter turn when
// the model's long side disagrees, yaw = -rotation).

const THREE_VERSION = '0.160.0';

export function renderViewerPage(token: string): string {
  const cdn = `https://cdn.jsdelivr.net/npm/three@${THREE_VERSION}`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Shared room design</title>
<meta name="description" content="A room design shared from the Intellar app. Drag to look around.">
<meta property="og:title" content="Shared room design">
<meta property="og:description" content="Open to look around this room in 3D.">
<link rel="icon" href="/admin/app-logo.png">
<style>
  :root {
    --bg: #f4f2ee; --panel: rgba(255,255,255,0.92); --text: #1d1b19; --muted: #6b655e;
    --accent: #6d4aff; --accent-text: #ffffff; --border: rgba(0,0,0,0.08);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --bg: #17161a; --panel: rgba(32,30,36,0.92); --text: #f2f0ec; --muted: #a39d96;
      --accent: #8f73ff; --accent-text: #ffffff; --border: rgba(255,255,255,0.1);
    }
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; background: var(--bg); color: var(--text);
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; overflow: hidden; }
  #stage { position: fixed; inset: 0; touch-action: none; }
  #stage canvas { display: block; }
  .bar { position: fixed; left: 16px; right: 16px; top: max(16px, env(safe-area-inset-top));
    display: flex; gap: 12px; align-items: center; padding: 12px 14px; border-radius: 16px;
    background: var(--panel); border: 1px solid var(--border); backdrop-filter: blur(8px);
    box-shadow: 0 6px 24px rgba(0,0,0,0.08); }
  .bar .logo { width: 36px; height: 36px; border-radius: 10px; flex: none; }
  .bar .titles { min-width: 0; flex: 1; }
  .bar h1 { margin: 0; font-size: 16px; font-weight: 650; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .bar p { margin: 2px 0 0; font-size: 12px; color: var(--muted); }
  .open-app { flex: none; display: none; text-decoration: none; font-size: 13px; font-weight: 600;
    padding: 9px 12px; border-radius: 999px; background: var(--accent); color: var(--accent-text); }
  .hint { position: fixed; left: 50%; bottom: max(20px, env(safe-area-inset-bottom)); transform: translateX(-50%);
    padding: 8px 14px; border-radius: 999px; background: var(--panel); border: 1px solid var(--border);
    font-size: 12px; color: var(--muted); white-space: nowrap; transition: opacity .6s; }
  .tools { position: fixed; right: 16px; bottom: max(64px, calc(env(safe-area-inset-bottom) + 64px));
    display: flex; flex-direction: column; gap: 8px; }
  .tools button { width: 44px; height: 44px; border-radius: 12px; border: 1px solid var(--border);
    background: var(--panel); color: var(--text); font-size: 18px; cursor: pointer; }
  .status { position: fixed; inset: 0; display: flex; align-items: center; justify-content: center;
    padding: 24px; text-align: center; color: var(--muted); font-size: 14px; pointer-events: none; }
  .status.error { pointer-events: auto; }
  .status .card { max-width: 340px; padding: 20px; border-radius: 16px; background: var(--panel); border: 1px solid var(--border); }
  .status h2 { margin: 0 0 6px; font-size: 17px; color: var(--text); }
</style>
<script type="importmap">
{ "imports": {
  "three": "${cdn}/build/three.module.js",
  "three/addons/": "${cdn}/examples/jsm/"
} }
</script>
</head>
<body>
<div id="stage" aria-label="3D view of the room. Drag to look around."></div>
<header class="bar">
  <img class="logo" src="/admin/app-logo.png" alt="">
  <div class="titles">
    <h1 id="title">Shared room design</h1>
    <p id="subtitle">Loading…</p>
  </div>
  <a class="open-app" id="openApp" href="#">Open in app</a>
</header>
<div class="tools">
  <button id="reset" type="button" aria-label="Reset view" title="Reset view">⟲</button>
</div>
<div class="hint" id="hint">Drag to look around · pinch or scroll to zoom</div>
<div class="status" id="status">Loading the room…</div>
<script>window.__SHARE_TOKEN__ = ${JSON.stringify(token)}; window.__ANDROID_PACKAGE__ = ${JSON.stringify(ANDROID_PACKAGE_FOR_VIEWER)};</script>
<script type="module">
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { DRACOLoader } from 'three/addons/loaders/DRACOLoader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const token = window.__SHARE_TOKEN__;
const statusEl = document.getElementById('status');
const WALL_H = 2.7, WALL_T = 0.1;

function fail(title, text) {
  statusEl.className = 'status error';
  statusEl.innerHTML = '';
  const card = document.createElement('div'); card.className = 'card';
  const h = document.createElement('h2'); h.textContent = title;
  const p = document.createElement('p'); p.textContent = text;
  card.append(h, p); statusEl.append(card);
  document.getElementById('subtitle').textContent = '';
}

if (/Android/i.test(navigator.userAgent) && token) {
  const a = document.getElementById('openApp');
  a.href = 'intent://open/d/' + token + '#Intent;scheme=intellar;package=' + window.__ANDROID_PACKAGE__ + ';end';
  a.style.display = 'inline-block';
}

let data;
try {
  if (!token) throw Object.assign(new Error('missing'), { status: 404 });
  const res = await fetch('/api/shared-designs/' + encodeURIComponent(token));
  if (!res.ok) throw Object.assign(new Error('http'), { status: res.status });
  data = await res.json();
  if (!data || !data.scene) throw Object.assign(new Error('empty'), { status: 404 });
} catch (e) {
  if (e.status === 404) fail('Design not found', 'This link may be wrong, or the design was removed.');
  else fail('Could not load the design', 'Please check your connection and try again.');
  throw e;
}

const scene3 = data.scene;
const room = scene3.room || {};
document.getElementById('title').textContent = scene3.name || 'Shared room design';
document.title = (scene3.name || 'Shared room design') + ' · Intellar';
const n = (scene3.items || []).length;
document.getElementById('subtitle').textContent = n === 1 ? '1 piece of furniture' : n + ' pieces of furniture';

// ── renderer ──
const stage = document.getElementById('stage');
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
stage.append(renderer.domElement);

const dark = matchMedia('(prefers-color-scheme: dark)').matches;
const scene = new THREE.Scene();
scene.background = new THREE.Color(dark ? 0x17161a : 0xf4f2ee);
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(renderer), 0.04).texture;

scene.add(new THREE.HemisphereLight(0xfff6ea, 0x8a8178, 0.55));
const sun = new THREE.DirectionalLight(0xfff1dc, 1.6);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.bias = -0.0004;
scene.add(sun, sun.target);

// ── room shell ──
const cm = (v) => v / 100;
let outline = (room.walls || []).map(([x, y]) => [cm(x), cm(y)]);
if (outline.length < 3) {
  const w = cm(room.widthCm || 400), h = cm(room.heightCm || 500);
  outline = [[0, 0], [w, 0], [w, h], [0, h]];
}
const xs = outline.map((p) => p[0]), zs = outline.map((p) => p[1]);
const minX = Math.min(...xs), maxX = Math.max(...xs), minZ = Math.min(...zs), maxZ = Math.max(...zs);
const centre = new THREE.Vector3((minX + maxX) / 2, 0, (minZ + maxZ) / 2);
const span = Math.max(maxX - minX, maxZ - minZ, 2);

const hex = (argb, fallback) => (typeof argb === 'number' ? new THREE.Color(argb & 0xffffff) : new THREE.Color(fallback));
const floorMat = new THREE.MeshStandardMaterial({ color: hex(room.floorColor, 0xcfb08c), roughness: 0.8 });
const wallColour = hex(room.wallColor, 0xf0ebe3);

const shape = new THREE.Shape(outline.map(([x, z]) => new THREE.Vector2(x, -z)));
const floorGeo = new THREE.ShapeGeometry(shape);
floorGeo.rotateX(-Math.PI / 2);
const floor = new THREE.Mesh(floorGeo, floorMat);
floor.receiveShadow = true;
scene.add(floor);

const ground = new THREE.Mesh(
  new THREE.CircleGeometry(span * 3, 64).rotateX(-Math.PI / 2),
  new THREE.ShadowMaterial({ opacity: dark ? 0.35 : 0.12 })
);
ground.position.set(centre.x, -0.002, centre.z);
ground.receiveShadow = true;
scene.add(ground);

const walls = [];
function addWall(a, b, outer) {
  const dx = b[0] - a[0], dz = b[1] - a[1];
  const len = Math.hypot(dx, dz);
  if (len < 0.05) return;
  const mat = new THREE.MeshStandardMaterial({ color: wallColour, roughness: 0.95, transparent: true, opacity: 1 });
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(len + WALL_T, WALL_H, WALL_T), mat);
  const mid = new THREE.Vector3((a[0] + b[0]) / 2, WALL_H / 2, (a[1] + b[1]) / 2);
  mesh.position.copy(mid);
  mesh.rotation.y = -Math.atan2(dz, dx);
  mesh.castShadow = true; mesh.receiveShadow = true;
  scene.add(mesh);
  let normal = null;
  if (outer) {
    normal = new THREE.Vector3(-dz, 0, dx).normalize();
    if (normal.dot(new THREE.Vector3().subVectors(mid, centre).setY(0)) < 0) normal.negate();
  }
  walls.push({ mesh, mid, normal, a, b });
}
for (let i = 0; i < outline.length; i++) addWall(outline[i], outline[(i + 1) % outline.length], true);
for (const chain of room.interiorWalls || []) {
  for (let i = 0; i + 1 < chain.length; i++) addWall([cm(chain[i][0]), cm(chain[i][1])], [cm(chain[i + 1][0]), cm(chain[i + 1][1])], false);
}

// ── furniture ──
const loader = new GLTFLoader();
const draco = new DRACOLoader();
draco.setDecoderPath('https://www.gstatic.com/draco/versioned/decoders/1.5.6/');
loader.setDRACOLoader(draco);
loader.setMeshoptDecoder(MeshoptDecoder);
const cache = new Map();
function loadModel(ref) {
  const url = ref.startsWith('assets/models/') ? '/shared-models/' + ref.slice('assets/models/'.length) : ref;
  if (!cache.has(url)) cache.set(url, loader.loadAsync(url).then((g) => g.scene));
  return cache.get(url).then((s) => s.clone(true));
}

function longAxisDisagrees(nw, nd, tw, td) {
  if (nw <= 1e-6 || nd <= 1e-6 || tw <= 1e-6 || td <= 1e-6) return false;
  if (Math.max(nw, nd) / Math.min(nw, nd) < 1.2 || Math.max(tw, td) / Math.min(tw, td) < 1.2) return false;
  return (nw >= nd) !== (tw >= td);
}

function standIn(w, h, d) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), new THREE.MeshStandardMaterial({ color: 0xb9ab9a, roughness: 0.7 }));
  m.position.y = h / 2;
  return m;
}

function place(item, model) {
  const W = cm(item.widthCm), D = cm(item.depthCm), H = cm(item.heightCm);
  const quarter = (((item.rotation % 180) + 180) % 180) === 90;
  const fw = quarter ? item.depthCm : item.widthCm, fd = quarter ? item.widthCm : item.depthCm;
  const pivot = new THREE.Group();
  pivot.position.set(cm(item.x + fw / 2), cm(item.elevationCm || 0), cm(item.y + fd / 2));
  let yaw = -item.rotation;
  if (model) {
    const box = new THREE.Box3().setFromObject(model);
    const size = box.getSize(new THREE.Vector3()), c = box.getCenter(new THREE.Vector3());
    const turn = longAxisDisagrees(size.x, size.z, W, D);
    const sx = size.x > 1e-6 ? (turn ? D : W) / size.x : 1;
    const sy = size.y > 1e-6 ? H / size.y : 1;
    const sz = size.z > 1e-6 ? (turn ? W : D) / size.z : 1;
    if (turn) yaw += 90;
    model.position.set(-c.x, -box.min.y, -c.z);
    const scaler = new THREE.Group();
    scaler.scale.set(sx, sy, sz);
    scaler.add(model);
    pivot.add(scaler);
    model.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  } else {
    pivot.add(standIn(W, H, D));
  }
  pivot.rotation.y = THREE.MathUtils.degToRad(yaw);
  scene.add(pivot);
}

for (const item of scene3.items || []) {
  if (!(item.widthCm > 0 && item.depthCm > 0)) continue;
  if (!(item.heightCm > 0)) item.heightCm = 60;
  if (item.model) loadModel(item.model).then((m) => place(item, m), () => place(item, null));
  else place(item, null);
}

// ── camera + controls ──
const camera = new THREE.PerspectiveCamera(45, window.innerWidth / window.innerHeight, 0.05, 200);
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.target.set(centre.x, 0.6, centre.z);
controls.minDistance = 1.2;
controls.maxDistance = span * 4;
controls.maxPolarAngle = THREE.MathUtils.degToRad(84);
controls.screenSpacePanning = false;

// Portrait phones see less width, so start further back to fit the room.
const homeDistance = () => span * 1.8 * Math.pow(Math.max(1, 0.75 / camera.aspect), 0.75);
const homeDir = new THREE.Vector3(0.95, 1.05, 1.15).normalize();
const homePos = () => homeDir.clone().multiplyScalar(homeDistance()).add(new THREE.Vector3(centre.x, 0, centre.z));
const home = homePos();
function frameSun() {
  sun.position.set(centre.x - span, span * 2.2, centre.z + span * 0.6);
  sun.target.position.copy(centre);
  const s = sun.shadow.camera; const r = span * 1.2;
  s.left = -r; s.right = r; s.top = r; s.bottom = -r; s.near = 0.5; s.far = span * 6; s.updateProjectionMatrix();
}
frameSun();

// Intro: ease from a high wide shot down to the home view.
let intro = { t: 0, from: new THREE.Vector3(centre.x + span * 2.2, span * 2.6, centre.z + span * 2.4), to: home.clone() };
camera.position.copy(intro.from);
document.getElementById('reset').addEventListener('click', () => {
  intro = { t: 0, from: camera.position.clone(), to: homePos() };
  controls.target.set(centre.x, 0.6, centre.z);
});

const hint = document.getElementById('hint');
controls.addEventListener('start', () => { intro = null; hint.style.opacity = '0'; });

// An inside wall fades when it stands between the camera and the room centre.
function crosses(p1, p2, q1, q2) {
  const d = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  return d(p1, p2, q1) * d(p1, p2, q2) < 0 && d(q1, q2, p1) * d(q1, q2, p2) < 0;
}
function blocksView(a, b) {
  return crosses([camera.position.x, camera.position.z], [controls.target.x, controls.target.z], a, b);
}

// Dollhouse cutaway: walls between the camera and the room fade out.
const toCam = new THREE.Vector3();
function updateCutaway() {
  toCam.subVectors(camera.position, controls.target).setY(0).normalize();
  for (const w of walls) {
    const hide = w.normal ? w.normal.dot(toCam) > 0.25 : blocksView(w.a, w.b);
    const target = hide ? 0.08 : 1;
    w.mesh.material.opacity += (target - w.mesh.material.opacity) * 0.2;
    w.mesh.castShadow = !hide;
    w.mesh.material.depthWrite = w.mesh.material.opacity > 0.5;
  }
}

const clock = new THREE.Clock();
function tick() {
  const dt = clock.getDelta();
  if (intro) {
    intro.t = Math.min(1, intro.t + dt / 1.6);
    const e = 1 - Math.pow(1 - intro.t, 3);
    camera.position.lerpVectors(intro.from, intro.to, e);
    if (intro.t >= 1) intro = null;
  }
  controls.update();
  updateCutaway();
  renderer.render(scene, camera);
  requestAnimationFrame(tick);
}
statusEl.style.display = 'none';
tick();

addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});
</script>
</body>
</html>`;
}
