import * as THREE from 'three';
import {
  mat, box, cyl, makeHumanoid, poseWalk, buildHouse, buildCupboard, buildBike, buildCar,
  makeLabel, makeLootMesh, windowMat,
} from './models.js';
import { A, falloff } from './audio.js';

// ============================================================ constants & helpers
const DAY_LEN = 120, NIGHT_LEN = 180, CYCLE = DAY_LEN + NIGHT_LEN; // day = 2 min, night = 3 min
const WORLD = 104;
const V3 = THREE.Vector3;
const rand = (a, b) => a + Math.random() * (b - a);
const rint = (a, b) => Math.floor(rand(a, b + 1));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const dist2 = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);
function angDiff(a, b) { let d = b - a; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return d; }
function turnToward(cur, target, rate) { return cur + clamp(angDiff(cur, target), -rate, rate); }
const $ = (id) => document.getElementById(id);

// darkness 0 (full day) .. 1 (full night), smooth dawn/dusk
function darkness(t) {
  if (t < 10) return 1 - t / 10;
  if (t < DAY_LEN - 10) return 0;
  if (t < DAY_LEN + 10) return (t - (DAY_LEN - 10)) / 20;
  return 1;
}

// ============================================================ renderer / input
const canvas = $('c');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.75));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
const camera = new THREE.PerspectiveCamera(65, 1, 0.1, 420);
function resize() {
  renderer.setSize(innerWidth, innerHeight, false);
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
}
addEventListener('resize', resize); resize();

const keys = {}, pressed = {};
let lmb = false, locked = false, camYaw = 0, camPitch = 0.28, camShake = 0;
addEventListener('keydown', (e) => {
  if (e.repeat) return;
  keys[e.code] = true; pressed[e.code] = true;
  if (['Space', 'ArrowUp', 'ArrowDown', 'Tab'].includes(e.code)) e.preventDefault();
  A.resume();
  if (e.code === 'KeyM') flash(A.toggleMute() ? 'Sound off' : 'Sound on', '#aaa');
});
addEventListener('keyup', (e) => { keys[e.code] = false; });
canvas.addEventListener('mousedown', (e) => {
  A.resume();
  if (e.button === 0) lmb = true;
  if (!locked && mode !== 'title') canvas.requestPointerLock && canvas.requestPointerLock();
});
addEventListener('mouseup', (e) => { if (e.button === 0) lmb = false; });
document.addEventListener('pointerlockchange', () => { locked = document.pointerLockElement === canvas; });
addEventListener('mousemove', (e) => {
  if (!locked) return;
  camYaw -= e.movementX * 0.0024;
  camPitch = clamp(camPitch + e.movementY * 0.0024, -0.45, 1.2);
});
addEventListener('blur', () => { for (const k in keys) keys[k] = false; lmb = false; });

// ============================================================ HUD helpers
function flash(text, color = '#fff') {
  const d = document.createElement('div');
  d.className = 'toast'; d.textContent = text; d.style.color = color;
  $('toasts').appendChild(d);
  setTimeout(() => d.remove(), 2400);
}
function banner(text, color) {
  const b = $('banner'); b.textContent = text; b.style.color = color; b.style.opacity = 1;
  setTimeout(() => (b.style.opacity = 0), 2600);
}
function setPrompt(text) {
  const p = $('prompt');
  if (text) { p.textContent = text; p.classList.remove('hidden'); } else p.classList.add('hidden');
}
function fadeThen(cb) {
  const f = $('fade'); f.classList.add('on');
  setTimeout(() => { cb(); setTimeout(() => f.classList.remove('on'), 80); }, 520);
}

// ============================================================ shared geometry helpers
// collider: {minX,maxX,minZ,maxZ,door?}
function pushOut(pos, r, cols) {
  let hit = false;
  for (const c of cols) {
    if (c.door && c.door.open) continue;
    if (pos.x < c.minX - r || pos.x > c.maxX + r || pos.z < c.minZ - r || pos.z > c.maxZ + r) continue;
    const cx = clamp(pos.x, c.minX, c.maxX), cz = clamp(pos.z, c.minZ, c.maxZ);
    const dx = pos.x - cx, dz = pos.z - cz, d2 = dx * dx + dz * dz;
    if (d2 >= r * r) continue;
    hit = true;
    if (d2 > 1e-8) { const d = Math.sqrt(d2); pos.x = cx + (dx / d) * r; pos.z = cz + (dz / d) * r; }
    else {
      const l = pos.x - c.minX, rr = c.maxX - pos.x, t = pos.z - c.minZ, b = c.maxZ - pos.z, m = Math.min(l, rr, t, b);
      if (m === l) pos.x = c.minX - r; else if (m === rr) pos.x = c.maxX + r; else if (m === t) pos.z = c.minZ - r; else pos.z = c.maxZ + r;
    }
  }
  return hit;
}
// segment (o + d*t, 0<=t<=len) vs axis aligned box, returns entry t or null
function segBox(o, d, len, b) {
  let t0 = 0, t1 = len;
  const ax = [['x', 'minX', 'maxX'], ['y', 'y0', 'y1'], ['z', 'minZ', 'maxZ']];
  for (const [k, lo, hi] of ax) {
    const dk = d[k], ok = o[k];
    if (Math.abs(dk) < 1e-9) { if (ok < b[lo] || ok > b[hi]) return null; }
    else {
      let a = (b[lo] - ok) / dk, c = (b[hi] - ok) / dk;
      if (a > c) [a, c] = [c, a];
      t0 = Math.max(t0, a); t1 = Math.min(t1, c);
      if (t0 > t1) return null;
    }
  }
  return t0;
}

// ============================================================ lobby
const BOT_NAMES = ['Rex', 'Mila', 'Jax', 'Nova', 'Kane', 'Zoe', 'Finn', 'Ivy', 'Dax', 'Luna', 'Remy', 'Sage'];
const DOOR_COLORS = [0xe05a47, 0x4aa8e8, 0x57c26b, 0xe8b13a];
const LOBBY_DOOR_X = [-10.5, -3.5, 3.5, 10.5];
let L = null; // lobby state

function buildLobby() {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x12151c);
  scene.fog = new THREE.Fog(0x12151c, 25, 60);
  scene.add(new THREE.HemisphereLight(0xbfd0ff, 0x4a4440, 1.5));
  for (const x of [-8, 0, 8]) {
    const p = new THREE.PointLight(0xfff0d0, 22, 24, 1.6); p.position.set(x, 5.2, 0); scene.add(p);
  }
  // floor with checker texture
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const x = c.getContext('2d');
  x.fillStyle = '#3a3d44'; x.fillRect(0, 0, 128, 128);
  x.fillStyle = '#2f3238'; x.fillRect(0, 0, 64, 64); x.fillRect(64, 64, 64, 64);
  const tex = new THREE.CanvasTexture(c); tex.wrapS = tex.wrapT = THREE.RepeatWrapping; tex.repeat.set(14, 11);
  tex.colorSpace = THREE.SRGBColorSpace;
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(28, 22), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.6 }));
  floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; scene.add(floor);
  const wallM = mat(0x505660);
  scene.add(box(28, 6, 0.4, wallM, 0, 3, -11.2), box(28, 6, 0.4, wallM, 0, 3, 11.2));
  scene.add(box(0.4, 6, 22, wallM, -14.2, 3, 0), box(0.4, 6, 22, wallM, 14.2, 3, 0));
  scene.add(box(28, 0.3, 22, mat(0x22252b), 0, 6.1, 0));
  // hazard stripe line in front of the doors
  scene.add(box(28, 0.02, 0.3, mat(0xe8b13a, { emissive: 0xe8b13a, emissiveIntensity: 0.3 }), 0, 0.02, -7.6));
  const title = makeLabel('SURVIVOR LOBBY', '#f2b134', 1.0, 'bold 30px sans-serif');
  title.position.set(0, 5.3, 10.6); scene.add(title);
  // props
  const colliders = [];
  const addCrate = (cx, cz, s) => {
    scene.add(box(s, s, s, mat(0x6b5130), cx, s / 2, cz));
    colliders.push({ minX: cx - s / 2, maxX: cx + s / 2, minZ: cz - s / 2, maxZ: cz + s / 2 });
  };
  addCrate(-12.5, 8.5, 1.4); addCrate(-12.5, 6.9, 1); addCrate(12.5, 8.8, 1.6); addCrate(12.2, -5.5, 1.2);
  for (const bx of [-6, 6]) {
    scene.add(box(3, 0.45, 0.8, mat(0x3a3f4a), bx, 0.25, 7.5), box(3, 0.7, 0.15, mat(0x3a3f4a), bx, 0.7, 7.85));
    colliders.push({ minX: bx - 1.5, maxX: bx + 1.5, minZ: 7.1, maxZ: 7.95 });
  }
  const doors = LOBBY_DOOR_X.map((dx, i) => {
    const col = DOOR_COLORS[i];
    const post = mat(0x1c1f25, { metalness: 0.5 });
    scene.add(box(0.35, 4.0, 0.7, post, dx - 1.45, 2, -10.75), box(0.35, 4.0, 0.7, post, dx + 1.45, 2, -10.75), box(3.25, 0.4, 0.7, post, dx, 4.0, -10.75));
    // glowing portal behind the door (revealed when it opens)
    const glow = new THREE.Mesh(new THREE.PlaneGeometry(2.6, 3.6), new THREE.MeshBasicMaterial({ color: col }));
    glow.position.set(dx, 1.8, -11.0); scene.add(glow);
    const pivot = new THREE.Group(); pivot.position.set(dx - 1.2, 0, -10.6); scene.add(pivot);
    pivot.add(box(2.4, 3.6, 0.14, mat(0x2d3139, { metalness: 0.6, roughness: 0.4 }), 1.2, 1.8, 0));
    pivot.add(box(2.0, 0.5, 0.16, mat(col, { emissive: col, emissiveIntensity: 0.5 }), 1.2, 2.9, 0));
    const pad = new THREE.Mesh(new THREE.PlaneGeometry(2.8, 2.6), new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0.28 }));
    pad.rotation.x = -Math.PI / 2; pad.position.set(dx, 0.03, -9.2); scene.add(pad);
    const l1 = makeLabel('DOOR ' + (i + 1), '#' + col.toString(16).padStart(6, '0'), 0.7);
    l1.position.set(dx, 5.0, -10.2); scene.add(l1);
    const l2 = makeLabel('0 / 5', '#ffffff', 0.5);
    l2.position.set(dx, 4.45, -10.2); scene.add(l2);
    return { i, x: dx, pivot, a: 0, target: 0, count: 0, cap: rint(1, 3), names: [], label: l2 };
  });
  // wandering lobby players (other humans)
  const bots = [];
  const names = [...BOT_NAMES].sort(() => Math.random() - 0.5);
  for (let i = 0; i < 9; i++) {
    const model = makeHumanoid({
      shirt: pick([0xc0453a, 0x3f8a5a, 0x7a58b8, 0xd29a2e, 0x3b86a8, 0x8a8a8a]), pants: 0x2b2b3a,
      hair: pick([0x2a1a10, 0x6b4a2a, 0xaa8a3a, 0x151515]), skin: pick([0xe0b090, 0xc58c64, 0x8d5a3c]),
    });
    const pos = new V3(rand(-11, 11), 0, rand(-4, 9));
    model.position.copy(pos);
    const nm = makeLabel(names[i], '#cfe9d2', 0.2, 'bold 30px sans-serif'); nm.position.set(0, 2.15, 0); model.add(nm);
    scene.add(model);
    bots.push({ model, pos, yaw: rand(0, 6.28), goal: null, wait: rand(0, 3), phase: rand(0, 6), name: names[i], mode: 'wander', door: -1, vis: true });
  }
  // the human player
  const pm = makeHumanoid({ shirt: 0x2f6fb0, hair: 0x3a2a1a });
  const nm = makeLabel('YOU', '#f2b134', 0.22); nm.position.set(0, 2.15, 0); pm.add(nm);
  scene.add(pm);
  const pl = { model: pm, pos: new V3(0, 0, 8.5), yaw: Math.PI, vel: new V3(), phase: 0 };
  return { scene, doors, bots, colliders, pl, joined: -1, squad: 1, near: -1 };
}

function lobbyBotUpdate(b, dt) {
  if (!b.vis) return;
  b.wait -= dt;
  if (b.mode === 'wander') {
    if (!b.goal && b.wait <= 0) {
      // sometimes pick a door that still has room
      const open = L.doors.filter((d) => d.count < d.cap && d.count < 5 && !d.reserved);
      if (open.length && Math.random() < 0.35) {
        const d = pick(open); d.reserved = true; b.door = d.i; b.mode = 'door';
        b.goal = new V3(d.x + rand(-0.6, 0.6), 0, -9.4);
      } else { b.goal = new V3(rand(-11, 11), 0, rand(-4, 9)); }
    }
  }
  let speed = 0;
  if (b.goal) {
    const dx = b.goal.x - b.pos.x, dz = b.goal.z - b.pos.z, d = Math.hypot(dx, dz);
    if (d < 0.35) {
      b.goal = null; b.wait = rand(1.5, 5);
      if (b.mode === 'door') {
        const door = L.doors[b.door]; door.target = 1; b.mode = 'entering'; b.wait = 0.9;
      }
    } else {
      speed = 2.2;
      b.pos.x += (dx / d) * speed * dt; b.pos.z += (dz / d) * speed * dt;
      b.yaw = turnToward(b.yaw, Math.atan2(dx, dz), 8 * dt);
      pushOut(b.pos, 0.35, L.colliders);
    }
  } else if (b.mode === 'entering' && b.wait <= 0) {
    const door = L.doors[b.door];
    b.vis = false; b.model.visible = false; door.count++; door.names.push(b.name); door.reserved = false;
    if (L.joined !== door.i) door.target = 0;
    A.doorClose(0.5);
    updateDoorLabel(door);
    if (L.joined === door.i) refreshSquadPanel();
  }
  b.phase += speed * dt * 2.4;
  poseWalk(b.model, b.phase, speed > 0 ? 1 : 0);
  b.model.position.copy(b.pos); b.model.rotation.y = b.yaw;
}
function updateDoorLabel(d) {
  const n = L.joined === d.i ? L.squad : d.count;
  d.label.userData.set(n + ' / 5', n >= 5 ? '#ff7766' : '#ffffff');
}

function onFootMove(p, dt, cols, bounds, speedOverride) {
  const f = (keys.KeyW ? 1 : 0) - (keys.KeyS ? 1 : 0), s = (keys.KeyD ? 1 : 0) - (keys.KeyA ? 1 : 0);
  const sneak = !!keys.KeyC, run = !!(keys.ShiftLeft || keys.ShiftRight);
  const speed = speedOverride || (sneak ? 1.7 : run ? 6.3 : 3.7);
  const fx = -Math.sin(camYaw), fz = -Math.cos(camYaw);
  let dx = fx * f + -fz * s, dz = fz * f + fx * s;
  const len = Math.hypot(dx, dz);
  let tvx = 0, tvz = 0;
  if (len > 0) { tvx = (dx / len) * speed; tvz = (dz / len) * speed; }
  const k = 1 - Math.exp(-14 * dt);
  p.vel.x += (tvx - p.vel.x) * k; p.vel.z += (tvz - p.vel.z) * k;
  p.pos.x += p.vel.x * dt; p.pos.z += p.vel.z * dt;
  pushOut(p.pos, 0.38, cols);
  p.pos.x = clamp(p.pos.x, -bounds.x, bounds.x); p.pos.z = clamp(p.pos.z, bounds.zmin, bounds.zmax);
  const sp = Math.hypot(p.vel.x, p.vel.z);
  p.speed = sp; p.sneak = sneak && len > 0; p.running = run && len > 0 && !sneak;
  if (sp > 0.3 && !p.aimFace) p.yaw = turnToward(p.yaw, Math.atan2(p.vel.x, p.vel.z), 14 * dt);
  p.phase += sp * dt * 2.3;
  return len > 0;
}

function lobbyUpdate(dt) {
  const pl = L.pl;
  const free = L.joined < 0 && mode === 'lobby';
  if (free) {
    const moved = onFootMove(pl, dt, L.colliders, { x: 13.2, zmin: -9.9, zmax: 10.4 });
    if (moved && Math.floor(pl.phase / 2.2) !== pl.lastStep) { pl.lastStep = Math.floor(pl.phase / 2.2); A.step(pl.running ? 0.12 : 0.07); }
  } else { pl.vel.set(0, 0, 0); pl.speed = 0; }
  poseWalk(pl.model, pl.phase, clamp((pl.speed || 0) / 3, 0, 1));
  pl.model.position.copy(pl.pos); pl.model.rotation.y = pl.yaw;
  for (const b of L.bots) lobbyBotUpdate(b, dt);
  // doors animate
  for (const d of L.doors) {
    d.a += (d.target - d.a) * (1 - Math.exp(-6 * dt));
    d.pivot.rotation.y = d.a * 1.7;
    if (d.target === 1 && d.a > 0.95 && L.joined !== d.i && !d.holdOpen) { /* bots close it again shortly */ }
  }
  for (const d of L.doors) if (L.joined !== d.i && d.target === 1) { d.t = (d.t || 0) + dt; if (d.t > 1.4) { d.target = 0; d.t = 0; } }
  // nearest door
  L.near = -1;
  if (free) {
    for (const d of L.doors) if (Math.abs(pl.pos.x - d.x) < 1.7 && pl.pos.z < -7.6) L.near = d.i;
    const hint = $('lobbyhint');
    if (L.near >= 0) {
      const d = L.doors[L.near];
      hint.textContent = d.count >= 5 ? `Door ${d.i + 1} is full` : `[E] Enter Door ${d.i + 1}  (${d.count}/5 waiting)`;
    } else hint.textContent = 'Walk to one of the four doors';

    if (pressed.KeyE && L.near >= 0 && L.doors[L.near].count < 5) joinDoor(L.near);
  } else if (L.joined >= 0) {
    $('lobbyhint').textContent = '';
    if (pressed.KeyE || pressed.Backspace) leaveDoor();
    for (let n = 1; n <= 5; n++) if (pressed['Digit' + n] || pressed['Numpad' + n]) setSquad(n);
    if (pressed.ArrowUp) setSquad(L.squad + 1);
    if (pressed.ArrowDown) setSquad(L.squad - 1);
    if (pressed.Enter || pressed.NumpadEnter) startGame();
  }
  // camera: third person behind the player
  const target = new V3(pl.pos.x, 1.5, pl.pos.z);
  const d = new V3(-Math.sin(camYaw) * Math.cos(camPitch), -Math.sin(camPitch), -Math.cos(camYaw) * Math.cos(camPitch));
  const cp = target.clone().addScaledVector(d, -5.5);
  cp.x = clamp(cp.x, -13.4, 13.4); cp.z = clamp(cp.z, -10.4, 10.6); cp.y = clamp(cp.y, 0.6, 5.6);
  camera.position.copy(cp);
  camera.lookAt(target);
}

function joinDoor(i) {
  const d = L.doors[i];
  L.joined = i; L.squad = clamp(d.count + 1, 1, 5);
  d.target = 1; d.t = 0;
  L.pl.pos.set(d.x, 0, -9.9); L.pl.yaw = Math.PI; L.pl.vel.set(0, 0, 0);
  A.doorOpen(0.8); A.click();
  $('squad-panel').classList.remove('hidden');
  $('sq-title').textContent = 'DOOR ' + (i + 1);
  $('sq-title').style.color = '#' + DOOR_COLORS[i].toString(16).padStart(6, '0');
  refreshSquadPanel();
  if (document.pointerLockElement) document.exitPointerLock();
}
function leaveDoor() {
  const d = L.doors[L.joined];
  d.target = 0; d.t = 0;
  L.pl.pos.set(d.x, 0, -8.2);
  const j = L.joined; L.joined = -1;
  updateDoorLabel(L.doors[j]);
  $('squad-panel').classList.add('hidden');
  A.doorClose(0.8);
}
function setSquad(n) {
  n = clamp(n, 1, 5);
  if (n === L.squad) return;
  L.squad = n; A.click(); refreshSquadPanel();
}
function refreshSquadPanel() {
  const d = L.doors[L.joined];
  const slots = $('slots'); slots.innerHTML = '';
  for (let i = 0; i < 5; i++) {
    const s = document.createElement('div');
    s.className = 'slot' + (i < L.squad ? ' on' : '') + (i === 0 ? ' you' : '');
    let label = 'empty', icon = '+';
    if (i === 0) { label = 'YOU'; icon = '★'; }
    else if (i < L.squad) { const nm = d.names[i - 1]; label = nm || 'AI survivor'; icon = nm ? '☺' : '⚙'; }
    s.innerHTML = `<i>${icon}</i>${label}`;
    s.onclick = () => setSquad(i + 1);
    slots.appendChild(s);
  }
  $('sq-count').textContent = L.squad;
  updateDoorLabel(d);
}
$('sq-start').onclick = () => { if (mode === 'lobby' && L && L.joined >= 0) startGame(); };
$('sq-leave').onclick = () => { if (mode === 'lobby' && L && L.joined >= 0) leaveDoor(); };

// ============================================================ world
let W = null, mode = 'title';
const treeTrunk = new THREE.CylinderGeometry(0.22, 0.32, 2.4, 7);
const treeLeaf = new THREE.ConeGeometry(1.6, 4.2, 8);

function groundTexture(base, spots, size = 256, rep = 70) {
  const c = document.createElement('canvas'); c.width = c.height = size;
  const x = c.getContext('2d');
  x.fillStyle = base; x.fillRect(0, 0, size, size);
  for (let i = 0; i < 1800; i++) {
    x.fillStyle = pick(spots); x.globalAlpha = 0.35;
    x.fillRect(Math.random() * size, Math.random() * size, rand(1, 4), rand(1, 4));
  }
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(rep, rep);
  t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return t;
}

function makeSurvivor({ name, isPlayer, shirt, pos, yaw }) {
  const model = makeHumanoid({ shirt, hair: pick([0x2a1a10, 0x6b4a2a, 0x151515, 0xaa8a3a]), skin: pick([0xe0b090, 0xc58c64]) });
  const lab = makeLabel(name, isPlayer ? '#f2b134' : '#cfe9d2', 0.2, 'bold 30px sans-serif');
  lab.position.set(0, isPlayer ? 2.55 : 2.15, 0); model.add(lab);
  model.position.copy(pos);
  return {
    isPlayer, name, model, pos: pos.clone(), yaw, vel: new V3(), hp: 100, alive: true, phase: 0, speed: 0,
    cd: 0, swing: 0, aimT: 0, fallT: 0, sneak: false, running: false, stepT: 0, noiseT: 0,
    label: lab, followAng: rand(0, 6.28), offT: 0, stuck: 0,
  };
}

function buildWorld(squad, mateNames) {
  const scene = new THREE.Scene();
  scene.fog = new THREE.Fog(0x87b8e8, 40, 170);
  const hemi = new THREE.HemisphereLight(0xcfe3ff, 0x4a5a3a, 0.9); scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xfff2d0, 1.1);
  sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048);
  Object.assign(sun.shadow.camera, { left: -46, right: 46, top: 46, bottom: -46, near: 1, far: 220 });
  sun.shadow.bias = -0.0005; sun.shadow.normalBias = 0.05;
  scene.add(sun, sun.target);
  const torch = new THREE.SpotLight(0xfff0c8, 0, 40, 0.5, 0.55, 1.3); scene.add(torch, torch.target);
  const lantern = new THREE.PointLight(0xffd9a0, 0, 9, 2); scene.add(lantern);
  const houseLight = new THREE.PointLight(0xffe1b0, 0, 14, 1.5); scene.add(houseLight);
  const muzzle = new THREE.PointLight(0xffa040, 0, 14, 2); scene.add(muzzle);

  // sky bodies
  const sunMesh = new THREE.Mesh(new THREE.SphereGeometry(9, 16, 12), new THREE.MeshBasicMaterial({ color: 0xfff1b0, fog: false }));
  const moonMesh = new THREE.Mesh(new THREE.SphereGeometry(6, 16, 12), new THREE.MeshBasicMaterial({ color: 0xdfe8ff, fog: false }));
  scene.add(sunMesh, moonMesh);
  const starGeo = new THREE.BufferGeometry();
  const sp = new Float32Array(700 * 3);
  for (let i = 0; i < 700; i++) {
    const u = Math.random() * 2 - 1, a = Math.random() * 6.283, r = Math.sqrt(1 - u * u);
    sp[i * 3] = Math.cos(a) * r * 380; sp[i * 3 + 1] = Math.abs(u) * 380 + 20; sp[i * 3 + 2] = Math.sin(a) * r * 380;
  }
  starGeo.setAttribute('position', new THREE.BufferAttribute(sp, 3));
  const starMat = new THREE.PointsMaterial({ color: 0xffffff, size: 1.8, sizeAttenuation: false, fog: false, transparent: true, opacity: 0 });
  const stars = new THREE.Points(starGeo, starMat); stars.frustumCulled = false; scene.add(stars);

  // ground + roads
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(600, 600),
    new THREE.MeshStandardMaterial({ map: groundTexture('#4b6b39', ['#587a42', '#405c30', '#6a7a45', '#52703c']), roughness: 1 }));
  ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true; scene.add(ground);
  const roadTex = (() => {
    const c = document.createElement('canvas'); c.width = 64; c.height = 128;
    const x = c.getContext('2d'); x.fillStyle = '#3b3b40'; x.fillRect(0, 0, 64, 128);
    for (let i = 0; i < 300; i++) { x.fillStyle = Math.random() < 0.5 ? '#46464c' : '#303034'; x.fillRect(Math.random() * 64, Math.random() * 128, 2, 2); }
    x.fillStyle = '#d8c25a'; x.fillRect(30, 8, 4, 50);
    const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(1, 26); t.colorSpace = THREE.SRGBColorSpace;
    return t;
  })();
  const roadM = new THREE.MeshStandardMaterial({ map: roadTex, roughness: 0.95 });
  const road1 = new THREE.Mesh(new THREE.PlaneGeometry(8, 210), roadM); road1.rotation.x = -Math.PI / 2; road1.position.y = 0.01; road1.receiveShadow = true;
  const road2 = road1.clone(); road2.rotation.z = Math.PI / 2;
  scene.add(road1, road2);
  const plaza = new THREE.Mesh(new THREE.CircleGeometry(9, 32), new THREE.MeshStandardMaterial({ color: 0x585a60, roughness: 0.9 }));
  plaza.rotation.x = -Math.PI / 2; plaza.position.y = 0.02; plaza.receiveShadow = true; scene.add(plaza);
  const sign = makeLabel('SAFE START', '#f2b134', 0.5); sign.position.set(0, 3.2, 6); scene.add(sign);
  const parking = box(1.5, 0.02, 3, mat(0xe8e8e8), 3, 0.035, 0, false); scene.add(parking);

  const colliders = [], occluders = [], houses = [], items = [], particles = [], tracers = [];
  const addCol = (c) => colliders.push(c);

  // ---------- houses
  const palettes = [
    [0xc9b79c, 0x8a3b2a], [0xb7c7b0, 0x4a4a55], [0xd8c9a0, 0x6d3b2a], [0xa9b7c9, 0x5a3f33],
    [0xd9b9a5, 0x3d4a5a], [0xc4c4b0, 0x7a3a2a], [0xbfa98a, 0x2f4a3a], [0xe0d6c0, 0x8a4a2a],
  ];
  const spots = [];
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) for (const [ax, az] of [[24, 24], [62, 24], [24, 62], [62, 62]]) spots.push([sx * ax, sz * az]);
  for (const [bx, bz] of spots) {
    const px = bx + rand(-4, 4), pz = bz + rand(-4, 4);
    const f = Math.abs(bx) < Math.abs(bz) ? [-Math.sign(bx), 0] : [0, -Math.sign(bz)];
    const rotY = Math.atan2(f[0], f[1]);
    const pal = pick(palettes);
    const hb = buildHouse({ wallColor: pal[0], roofColor: pal[1] });
    hb.group.position.set(px, 0, pz); hb.group.rotation.y = rotY;
    scene.add(hb.group);
    const cs = Math.cos(rotY), sn = Math.sin(rotY);
    const toWorld = (lx, lz) => new V3(px + lx * cs + lz * sn, 0, pz - lx * sn + lz * cs);
    const toLocal = (p) => { const dx = p.x - px, dz = p.z - pz; return { x: cs * dx - sn * dz, z: sn * dx + cs * dz }; };
    const wbox = (b, y0, y1) => {
      const cs4 = [toWorld(b.x0, b.z0), toWorld(b.x1, b.z0), toWorld(b.x0, b.z1), toWorld(b.x1, b.z1)];
      return {
        minX: Math.min(...cs4.map((c) => c.x)), maxX: Math.max(...cs4.map((c) => c.x)),
        minZ: Math.min(...cs4.map((c) => c.z)), maxZ: Math.max(...cs4.map((c) => c.z)), y0, y1,
      };
    };
    const house = {
      group: hb.group, px, pz, rotY, toWorld, toLocal, hasLoot: Math.random() < 0.55, cupboards: [], door: null,
      roof: hb.roof,
    };
    // door state
    const doorState = { open: false, a: 0, hp: 100, broken: false, pivot: hb.doorPivot, pos: toWorld(2, 4.0), outPos: toWorld(2, 5.3), inPos: toWorld(2, 2.5), house };
    house.door = doorState;
    for (const w of hb.walls) {
      const wb = wbox(w, w.y0, w.y1);
      occluders.push(wb);
      if (w.y0 === 0) addCol(wb);
    }
    const dcol = { ...wbox({ x0: 1.3, x1: 2.7, z0: 3.75, z1: 4 }, 0, 2.2), door: doorState };
    addCol(dcol); occluders.push(dcol);
    for (const fb of hb.furniture) addCol(wbox(fb, 0, 1));
    occluders.push(wbox(hb.roofBox, hb.roofBox.y0, hb.roofBox.y1));
    // cupboards + loot
    for (const cb of hb.cupboards) {
      const loot = [];
      if (house.hasLoot && Math.random() < 0.8) {
        const n = rint(1, 3);
        for (let k = 0; k < n; k++) {
          const r = Math.random();
          loot.push(r < 0.42 ? 'ammo' : r < 0.52 ? 'ammoBig' : r < 0.72 ? 'medkit' : 'food');
        }
      }
      const fp = toWorld(cb.frontX, cb.frontZ);
      const ctr = toWorld(cb.lx, cb.lz);
      house.cupboards.push({
        c: cb, state: 'closed', a: 0, loot, looted: false, fpos: fp, center: ctr.setY(cb.h * 0.55), house, name: cb.name,
      });
    }
    // interior bounds in world coords for "inside house" tests
    house.inside = (p) => { const l = toLocal(p); return Math.abs(l.x) < 4.8 && Math.abs(l.z) < 3.8; };
    houses.push(house);
  }

  // ---------- trees (instanced) + wrecked cars
  const treeSpots = [];
  const nearHouse = (x, z, m) => houses.some((h) => Math.hypot(x - h.px, z - h.pz) < 9 + m);
  while (treeSpots.length < 170) {
    const x = rand(-WORLD, WORLD), z = rand(-WORLD, WORLD);
    if (Math.abs(x) < 7 || Math.abs(z) < 7 || Math.hypot(x, z) < 14 || nearHouse(x, z, 2)) continue;
    treeSpots.push([x, z]);
  }
  for (let i = 0; i < 40; i++) { // dense edge ring
    const a = (i / 40) * 6.283; treeSpots.push([Math.cos(a) * 107 + rand(-2, 2), Math.sin(a) * 107 + rand(-2, 2)]);
  }
  const trunks = new THREE.InstancedMesh(treeTrunk, mat(0x5a3b22), treeSpots.length);
  const leaves = new THREE.InstancedMesh(treeLeaf, mat(0x2f5a2c), treeSpots.length);
  const dummy = new THREE.Object3D();
  treeSpots.forEach(([x, z], i) => {
    const s = rand(0.8, 1.5);
    dummy.position.set(x, 1.2 * s, z); dummy.scale.set(s, s, s); dummy.rotation.y = rand(0, 6); dummy.updateMatrix(); trunks.setMatrixAt(i, dummy.matrix);
    dummy.position.set(x, 3.6 * s, z); dummy.updateMatrix(); leaves.setMatrixAt(i, dummy.matrix);
    addCol({ minX: x - 0.35 * s, maxX: x + 0.35 * s, minZ: z - 0.35 * s, maxZ: z + 0.35 * s });
  });
  trunks.castShadow = leaves.castShadow = true; trunks.receiveShadow = leaves.receiveShadow = true;
  scene.add(trunks, leaves);
  const carSpots = [[-1.5, -30, 0], [2, 44, 0], [28, 1.5, 1], [-52, -2, 1], [1.5, -72, 0], [75, 2, 1], [-2, 88, 0], [-34, 2, 1]];
  for (const [x, z, r] of carSpots) {
    const car = buildCar(pick([0x8a2a2a, 0x2a4a8a, 0x777777, 0x3a6a3a, 0xc8b050]));
    car.position.set(x, 0, z); car.rotation.y = r ? Math.PI / 2 + rand(-0.1, 0.1) : rand(-0.1, 0.1) + (Math.random() < 0.5 ? 0 : Math.PI);
    scene.add(car);
    const hx = r ? 2.2 : 1.1, hz = r ? 1.1 : 2.2;
    addCol({ minX: x - hx, maxX: x + hx, minZ: z - hz, maxZ: z + hz });
  }

  // ---------- survivors + bike
  const player = makeSurvivor({ name: 'YOU', isPlayer: true, shirt: 0x2f6fb0, pos: new V3(0, 0, 0), yaw: Math.PI });
  player.ammo = 18; player.medkits = 0; player.food = 0; player.weapon = 'pistol'; player.dayLabel = makeLabel('DAY 1', '#f2b134', 0.42, 'bold 38px sans-serif');
  player.dayLabel.position.set(0, 2.2, 0); player.model.add(player.dayLabel);
  player.label.visible = false;
  scene.add(player.model);
  const survivors = [player];
  const colors = [0xb04a3a, 0x3f8a5a, 0x7a58b8, 0xd29a2e];
  for (let i = 0; i < squad - 1; i++) {
    const m = makeSurvivor({ name: mateNames[i] || 'AI-' + (i + 1), isPlayer: false, shirt: colors[i % 4], pos: new V3([-1.8, 1.8, -3.4, 3.4][i], 0, [2.4, 2.8, 3.8, 3.8][i]), yaw: Math.PI });
    m.aimCd = rand(0, 1); m.idx = i;
    scene.add(m.model); survivors.push(m);
  }
  const bikeModel = buildBike();
  const bike = { model: bikeModel, pos: new V3(3, 0, 0), yaw: Math.PI, speed: 0, steer: 0, on: false, spin: 0, noiseT: 0 };
  bikeModel.position.copy(bike.pos); bikeModel.rotation.y = bike.yaw;
  scene.add(bikeModel);

  // pooled particles + tracers
  const partGeo = new THREE.BoxGeometry(0.1, 0.1, 0.1);
  for (let i = 0; i < 60; i++) {
    const m = new THREE.Mesh(partGeo, new THREE.MeshBasicMaterial({ color: 0xaa0000 }));
    m.visible = false; scene.add(m); particles.push({ m, v: new V3(), life: 0 });
  }
  for (let i = 0; i < 8; i++) {
    const g = new THREE.BufferGeometry().setFromPoints([new V3(), new V3(0, 0, 1)]);
    const l = new THREE.Line(g, new THREE.LineBasicMaterial({ color: 0xffe9a0, transparent: true }));
    l.visible = false; l.frustumCulled = false; scene.add(l); tracers.push({ l, life: 0 });
  }

  W = {
    scene, hemi, sun, torch, lantern, houseLight, muzzle, sunMesh, moonMesh, stars, starMat, colliders, occluders, houses, items, particles, tracers,
    player, survivors, bike, zombies: [], time: 15, day: 1, kills: 0, noiseLevel: 0, popT: 0, over: false, overT: 0,
    lastPhaseDark: false, muzzleT: 0, spectate: 0, gen: 0, bashT: 0, groanT: 3,
  };
  camYaw = 0; camPitch = 0.3;
  // initial zombie population
  for (let i = 0; i < 14; i++) {
    for (let k = 0; k < 12; k++) {
      const x = rand(-WORLD + 8, WORLD - 8), z = rand(-WORLD + 8, WORLD - 8);
      if (Math.hypot(x, z) < 32) continue;
      if (spawnZombie(x, z)) break;
    }
  }
  // a few zombies waiting indoors in houses that hold loot
  for (const h of houses) {
    if (h.hasLoot && Math.random() < 0.3) { const p = h.toWorld(rand(0.5, 3.5), rand(-2, 1)); spawnZombie(p.x, p.z, true); }
  }
  return W;
}

// ============================================================ zombies
function spawnZombie(x, z, indoor = false) {
  const pos = new V3(x, 0, z);
  if (!indoor && pushOut(pos.clone(), 0.5, W.colliders)) return null;
  if (!indoor && W.houses.some((h) => h.inside(pos))) return null;
  const model = makeHumanoid({
    zombie: true, skin: pick([0x6f8f5a, 0x7a9a64, 0x5f7f56, 0x8aa070]),
    shirt: pick([0x4a3a3a, 0x3a4a3a, 0x2f3a4f, 0x5a5040, 0x6a2a2a]), pants: pick([0x2a2a33, 0x3a3226, 0x23283a]),
  });
  model.position.copy(pos); model.rotation.y = rand(0, 6.28);
  W.scene.add(model);
  const z0 = {
    model, pos, yaw: model.rotation.y, hp: Math.min(120, 55 + W.day * 4), state: 'idle', target: null, noisePos: null,
    wander: null, wanderT: rand(0, 4), senseT: rand(0, 0.3), phase: rand(0, 6), kb: new V3(), dead: false, deadT: 0,
    atkCd: rand(0, 1), wind: 0, groanT: rand(2, 9), spd: rand(0.9, 1.15), indoor, speedNow: 0, lastHit: 0,
  };
  W.zombies.push(z0);
  return z0;
}

function houseAt(p) { for (const h of W.houses) if (h.inside(p)) return h; return null; }

// Route around walls: head for a house door / the partition doorway when needed.
function route(from, to) {
  const hf = houseAt(from), ht = houseAt(to);
  if (hf !== ht) {
    if (hf) return dist2(from, hf.door.inPos) < 1.2 ? hf.door.outPos : hf.door.inPos; // leave via the door
    return dist2(from, ht.door.outPos) < 1.2 ? ht.door.inPos : ht.door.outPos;       // enter via the door
  }
  if (hf) {
    const a = hf.toLocal(from), b = hf.toLocal(to);
    const leftA = a.x < -0.9;
    if (leftA !== (b.x < -0.9)) { // through the partition doorway (z ~ 1.3)
      const pre = leftA ? hf.toWorld(-1.8, 1.3) : hf.toWorld(-0.3, 1.3);
      const post = leftA ? hf.toWorld(-0.3, 1.3) : hf.toWorld(-1.8, 1.3);
      const needPre = leftA ? a.x < -1.2 : a.x > -0.7;
      return needPre && dist2(from, pre) > 0.6 ? pre : post;
    }
  }
  return to;
}

function emitNoise(pos, radius, source) {
  if (!W) return;
  W.noiseLevel = Math.max(W.noiseLevel, radius / 90);
  const dark = darkness(W.time);
  const hear = lerp(0.45, 1.3, dark); // zombies hear much better at night
  const eff = radius * hear;
  for (const z of W.zombies) {
    if (z.dead) continue;
    const d = dist2(z.pos, pos);
    if (d > eff) continue;
    if (z.state === 'chase' && z.target && z.target.alive && dist2(z.pos, z.target.pos) < 9) continue;
    if (z.state !== 'chase' || d < dist2(z.pos, z.target ? z.target.pos : pos)) {
      z.state = 'investigate'; z.noisePos = new V3(pos.x + rand(-2, 2), 0, pos.z + rand(-2, 2)); z.target = null;
      if (Math.random() < 0.3) { z.groanT = 0; }
    }
  }
}

function senseTarget(z) {
  const dark = darkness(W.time);
  let best = null, bd = 1e9;
  for (const s of W.survivors) {
    if (!s.alive) continue;
    const d = dist2(z.pos, s.pos);
    let vis = lerp(22, 10, dark);
    if (s.sneak) vis *= 0.45;
    if (s === W.player && W.bike.on) vis *= 1.4;
    const h = houseAt(s.pos);
    const hidden = h && !h.door.open && h !== houseAt(z.pos);
    if (hidden) continue;
    if (d < vis && d < bd) { bd = d; best = s; }
  }
  return best;
}

function updateZombie(z, dt) {
  if (z.dead) {
    z.deadT += dt;
    z.model.rotation.x = -Math.min(1, z.deadT * 2.5) * 1.5;
    z.model.position.y = Math.min(1, z.deadT * 2.5) * 0.18;
    if (z.deadT > 6) { W.scene.remove(z.model); z.gone = true; }
    return;
  }
  z.atkCd -= dt; z.groanT -= dt;
  if (z.kb.lengthSq() > 0.01) {
    z.pos.addScaledVector(z.kb, dt); z.kb.multiplyScalar(Math.max(0, 1 - 7 * dt));
    pushOut(z.pos, 0.38, W.colliders);
  }
  z.senseT -= dt;
  if (z.senseT <= 0) {
    z.senseT = rand(0.2, 0.4);
    const t = senseTarget(z);
    if (t) {
      if (z.state !== 'chase') {
        z.state = 'chase'; z.groanT = 0;
        for (const o of W.zombies) if (!o.dead && o !== z && o.state !== 'chase' && dist2(o.pos, z.pos) < 7) { o.state = 'investigate'; o.noisePos = z.pos.clone(); }
      }
      z.target = t;
    } else if (z.state === 'chase') {
      if (z.target && z.target.alive && dist2(z.pos, z.target.pos) < 40) { /* keep chasing a bit */ }
      else { z.state = 'investigate'; z.noisePos = z.target ? z.target.pos.clone() : z.pos.clone(); z.target = null; }
    }
  }
  if (z.groanT <= 0) {
    z.groanT = z.state === 'chase' ? rand(3, 6) : rand(8, 18);
    const d = dist2(z.pos, W.player.pos);
    if (d < 50) A.groan(falloff(d, 9) * (z.state === 'chase' ? 1 : 0.7));
  }
  let goal = null, speed = 0;
  const dark = darkness(W.time);
  if (z.state === 'chase' && z.target) {
    goal = route(z.pos, z.target.pos);
    speed = (3.2 + Math.min(W.day * 0.12, 1.0) + dark * 0.5) * z.spd;
  } else if (z.state === 'investigate' && z.noisePos) {
    goal = route(z.pos, z.noisePos);
    speed = (2.0 + dark * 0.4) * z.spd;
    if (dist2(z.pos, z.noisePos) < 1.8) { z.state = 'idle'; z.wanderT = rand(2, 5); z.noisePos = null; }
  } else {
    z.wanderT -= dt;
    if (z.wanderT <= 0) {
      z.wanderT = rand(3, 8);
      z.wander = Math.random() < 0.5 ? null : new V3(z.pos.x + rand(-7, 7), 0, z.pos.z + rand(-7, 7));
    }
    if (z.wander && !z.indoor) { goal = z.wander; speed = 0.8; if (dist2(z.pos, goal) < 1) z.wander = null; }
  }
  // door bashing: a zombie leaning on a closed door slowly wrecks it
  z.speedNow = 0;
  if (goal) {
    const dx = goal.x - z.pos.x, dz = goal.z - z.pos.z, d = Math.hypot(dx, dz);
    if (d > 0.2) {
      z.yaw = turnToward(z.yaw, Math.atan2(dx, dz), 7 * dt);
      const mx = Math.sin(z.yaw), mz = Math.cos(z.yaw);
      const before = z.pos.x * 1e3 + z.pos.z;
      z.pos.x += mx * speed * dt; z.pos.z += mz * speed * dt;
      const hit = pushOut(z.pos, 0.38, W.colliders);
      z.pos.x = clamp(z.pos.x, -WORLD, WORLD); z.pos.z = clamp(z.pos.z, -WORLD, WORLD);
      z.speedNow = hit ? speed * 0.4 : speed;
      if (hit && z.state !== 'idle') {
        for (const h of W.houses) {
          const dr = h.door;
          if (!dr.open && dist2(z.pos, dr.pos) < 1.9) {
            dr.hp -= 9 * dt;
            if (Math.random() < dt * 2.2) A.thud(0.25 * falloff(dist2(z.pos, W.player.pos), 12));
            if (dr.hp <= 0) { dr.open = true; dr.broken = true; A.doorBreak(falloff(dist2(z.pos, W.player.pos), 14)); emitNoise(dr.pos, 30); }
          }
        }
      }
    }
  }
  // attack
  if (z.state === 'chase' && z.target && z.target.alive) {
    const d = dist2(z.pos, z.target.pos);
    if (z.wind > 0) {
      z.wind -= dt;
      if (z.wind <= 0) {
        if (d < 1.9 && z.target.alive) hurtSurvivor(z.target, (8 + 7 * dark) * (1 + 0.04 * (W.day - 1)), z);
        z.atkCd = 1.1;
      }
    } else if (d < 1.45 && z.atkCd <= 0) z.wind = 0.45;
  } else z.wind = 0;
  z.phase += z.speedNow * dt * 2.1;
  poseWalk(z.model, z.phase, clamp(z.speedNow / 2.5, 0, 1));
  if (z.wind > 0) { z.model.userData.armL.rotation.x = z.model.userData.armR.rotation.x = -1.4 - (0.45 - z.wind) * 2; }
  z.model.position.set(z.pos.x, 0, z.pos.z); z.model.rotation.y = z.yaw;
}

function damageZombie(z, dmg, from, kbForce = 0) {
  if (z.dead) return;
  z.hp -= dmg; z.lastHit = performance.now();
  burst(new V3(z.pos.x, 1.2, z.pos.z), 0x7a0e0e, 7, 3);
  A.zombieHit(falloff(dist2(z.pos, W.player.pos), 10));
  if (kbForce && from) { const dx = z.pos.x - from.x, dz = z.pos.z - from.z, d = Math.hypot(dx, dz) || 1; z.kb.set((dx / d) * kbForce, 0, (dz / d) * kbForce); }
  // being shot makes them aware
  if (z.state !== 'chase') {
    const t = from && W.survivors.find((s) => s.alive && dist2(s.pos, from) < 1.5) || W.player;
    z.state = 'chase'; z.target = t.alive ? t : W.survivors.find((s) => s.alive) || null;
  }
  if (z.hp <= 0) {
    z.dead = true; z.deadT = 0; W.kills++;
    A.zombieDie(falloff(dist2(z.pos, W.player.pos), 10));
    burst(new V3(z.pos.x, 1, z.pos.z), 0x7a0e0e, 12, 4);
  }
}

function hurtSurvivor(s, dmg, src) {
  if (!s.alive) return;
  s.hp -= dmg;
  if (s.isPlayer) {
    A.hurt(); camShake = 0.35;
    $('vignette').style.boxShadow = 'inset 0 0 160px 50px rgba(214,0,0,.55)';
    setTimeout(() => ($('vignette').style.boxShadow = 'inset 0 0 160px 40px rgba(214,0,0,0)'), 220);
    if (W.bike.on) { dismountBike(true); }
  } else A.hurt();
  burst(new V3(s.pos.x, 1.2, s.pos.z), 0xaa1111, 6, 2.5);
  if (s.hp <= 0) {
    s.hp = 0; s.alive = false; s.fallT = 0;
    A.death();
    flash(s.isPlayer ? 'You died! Spectating your squad...' : s.name + ' has fallen', '#ff6655');
    s.label.visible = false;
    if (s.isPlayer && s.dayLabel) s.dayLabel.visible = false;
    if (!W.survivors.some((x) => x.alive)) endGame();
  }
}

// ============================================================ particles / tracers
function burst(pos, color, n, speed) {
  let k = 0;
  for (const p of W.particles) {
    if (p.life > 0) continue;
    p.life = rand(0.35, 0.8); p.m.visible = true; p.m.position.copy(pos);
    p.m.material.color.setHex(color);
    p.v.set(rand(-1, 1) * speed, rand(0.2, 1.4) * speed, rand(-1, 1) * speed);
    if (++k >= n) break;
  }
}
function tracer(from, to) {
  const t = W.tracers.find((q) => q.life <= 0) || W.tracers[0];
  const pa = t.l.geometry.attributes.position;
  pa.setXYZ(0, from.x, from.y, from.z); pa.setXYZ(1, to.x, to.y, to.z); pa.needsUpdate = true;
  t.l.material.opacity = 1; t.l.visible = true; t.life = 0.09;
}

// ============================================================ player actions
const ITEM_DEF = {
  ammo: { label: '+12 Ammo', color: '#f0d060', apply: (p) => (p.ammo += 12) },
  ammoBig: { label: '+24 Ammo', color: '#f0d060', apply: (p) => (p.ammo += 24) },
  medkit: { label: 'Medkit', color: '#ff7a7a', apply: (p) => p.medkits++ },
  food: { label: 'Canned food', color: '#9ad77a', apply: (p) => p.food++ },
};

function aimRay() {
  const d = new V3(); camera.getWorldDirection(d);
  return { o: camera.position.clone(), d };
}
function shootPlayer(p) {
  if (p.cd > 0) return;
  if (p.ammo <= 0) { A.empty(); p.cd = 0.3; flash('Out of ammo', '#ff9a5a'); return; }
  p.ammo--; p.cd = 0.33;
  const { o, d } = aimRay();
  p.yaw = Math.atan2(d.x, d.z); p.aimT = 0.6;
  const muz = new V3(p.pos.x + Math.sin(p.yaw) * 0.6, 1.3, p.pos.z + Math.cos(p.yaw) * 0.6);
  A.gun(1); emitNoise(p.pos, 80);
  W.muzzle.position.copy(muz); W.muzzle.intensity = 6; W.muzzleT = 0.05;
  camShake = Math.max(camShake, 0.12);
  fireRay(o, d, 22, muz, true);
}
function fireRay(o, d, dmg, muz, headshots) {
  let best = null, bt = 70;
  for (const z of W.zombies) {
    if (z.dead) continue;
    const cx = z.pos.x - o.x, cy = 1.0 - o.y, cz = z.pos.z - o.z;
    const t = cx * d.x + cy * d.y + cz * d.z;
    if (t < 0.5 || t > bt) continue;
    const px = o.x + d.x * t, py = o.y + d.y * t, pz = o.z + d.z * t;
    if (py < 0 || py > 2.0) continue;
    const dh = Math.hypot(px - z.pos.x, pz - z.pos.z);
    if (dh < 0.5) { best = { z, py }; bt = t; }
  }
  // walls stop bullets
  let wall = 1e9;
  for (const b of W.occluders) { if (b.door && b.door.open) continue; if (b.y0 >= 3) continue; const t = segBox(o, d, bt < 70 ? bt : 70, b); if (t !== null && t < wall) wall = t; }
  const end = new V3();
  if (best && bt < wall) {
    end.set(o.x + d.x * bt, o.y + d.y * bt, o.z + d.z * bt);
    const head = headshots && best.py > 1.55;
    damageZombie(best.z, head ? dmg * 2 : dmg, W.player.pos, 2);
    if (head) flash('HEADSHOT', '#ffd84a');
  } else {
    const t = Math.min(wall, 70);
    end.set(o.x + d.x * t, o.y + d.y * t, o.z + d.z * t);
    if (wall < 70) burst(end, 0xc9c0a8, 4, 2);
  }
  tracer(muz, end);
}
function swingBat(p) {
  if (p.cd > 0) return;
  p.cd = 0.6; p.swing = 0.01;
  const { d } = aimRay(); p.yaw = Math.atan2(d.x, d.z);
  A.bat(false);
  setTimeout(() => {
    if (!W || !p.alive) return;
    let hit = false;
    const fx = Math.sin(p.yaw), fz = Math.cos(p.yaw);
    for (const z of W.zombies) {
      if (z.dead) continue;
      const dx = z.pos.x - p.pos.x, dz = z.pos.z - p.pos.z, dd = Math.hypot(dx, dz);
      if (dd < 2.5 && (dx * fx + dz * fz) / (dd || 1) > 0.25) { damageZombie(z, 30, p.pos, 7); hit = true; }
    }
    if (hit) { A.bat(true); camShake = 0.15; }
    emitNoise(p.pos, hit ? 22 : 8);
  }, 160);
}
function useHeal() {
  const p = W.player;
  if (!p.alive || p.hp >= 100) return;
  if (p.medkits > 0) { p.medkits--; p.hp = Math.min(100, p.hp + 55); }
  else if (p.food > 0) { p.food--; p.hp = Math.min(100, p.hp + 20); }
  else { flash('Nothing to heal with', '#ccc'); return; }
  A.heal(); flash('Healed', '#7be08a');
}

// ---------- bike
function mountBike() {
  const b = W.bike, p = W.player;
  b.on = true; b.speed = 0; p.onBike = true; b.noiseT = 0;
  A.bikeStart(); A.pickup();
  emitNoise(b.pos, 28);
  flash('Engine running - noise attracts zombies!', '#f2b134');
}
function dismountBike(forced) {
  const b = W.bike, p = W.player;
  b.on = false; p.onBike = false;
  A.bikeStop();
  const sx = -Math.cos(b.yaw), sz = Math.sin(b.yaw); // bike's right side
  p.pos.set(b.pos.x + sx * 1.2, 0, b.pos.z + sz * 1.2);
  pushOut(p.pos, 0.38, W.colliders);
  p.vel.set(0, 0, 0); p.yaw = b.yaw;
  if (forced) b.speed *= 0.3;
}
function updateBike(dt) {
  const b = W.bike, p = W.player;
  const th = (keys.KeyW ? 1 : 0) - (keys.KeyS ? 1 : 0), st = (keys.KeyA ? 1 : 0) - (keys.KeyD ? 1 : 0);
  if (b.on && p.alive) {
    if (th > 0) b.speed += (b.speed < 0 ? 28 : 15) * dt;
    else if (th < 0) b.speed -= (b.speed > 0 ? 24 : 6) * dt;
    else b.speed -= Math.sign(b.speed) * Math.min(Math.abs(b.speed), 5 * dt);
    b.speed = clamp(b.speed, -5, 25);
    b.steer += (st - b.steer) * (1 - Math.exp(-8 * dt));
    const sf = clamp(b.speed / 5, -1, 1);
    b.yaw += b.steer * (1.9 - Math.abs(b.speed) / 25 * 0.9) * sf * dt;
  } else {
    b.speed -= Math.sign(b.speed) * Math.min(Math.abs(b.speed), 9 * dt);
    b.steer *= 0.9;
  }
  const fx = Math.sin(b.yaw), fz = Math.cos(b.yaw);
  b.pos.x += fx * b.speed * dt; b.pos.z += fz * b.speed * dt;
  const before = b.pos.clone();
  if (pushOut(b.pos, 0.55, W.colliders)) {
    if (Math.abs(b.speed) > 7) { A.bikeCrash(); camShake = 0.4; emitNoise(b.pos, 55); if (b.on) hurtSurvivor(p, Math.abs(b.speed) * 0.8, null); }
    b.speed *= 0.35;
  }
  b.pos.x = clamp(b.pos.x, -WORLD, WORLD); b.pos.z = clamp(b.pos.z, -WORLD, WORLD);
  // run zombies over
  if (Math.abs(b.speed) > 5) {
    for (const z of W.zombies) {
      if (z.dead) continue;
      if (dist2(z.pos, b.pos) < 1.15 + 0.01 * Math.abs(b.speed)) {
        damageZombie(z, Math.abs(b.speed) * 4, b.pos, 10);
        b.speed *= 0.92; A.thud(0.5); camShake = 0.2;
      }
    }
  }
  b.spin += b.speed * dt / 0.38;
  const u = b.model.userData;
  u.rear.rotation.x = b.spin; u.front.rotation.x = b.spin; u.steer.rotation.y = b.steer * 0.5;
  b.model.position.copy(b.pos); b.model.rotation.y = b.yaw;
  b.model.rotation.z = -b.steer * clamp(Math.abs(b.speed) / 25, 0, 1) * 0.35;
  if (b.on) {
    p.pos.copy(b.pos); p.yaw = b.yaw;
    A.bikeUpdate(clamp(Math.abs(b.speed) / 25, 0, 1), Math.max(th, 0));
    b.noiseT -= dt;
    if (b.noiseT <= 0) { b.noiseT = 0.5; emitNoise(b.pos, 14 + Math.abs(b.speed) * 3.2); }
  }
}

// ============================================================ interaction
function findInteract() {
  const p = W.player;
  if (!p.alive) return null;
  if (W.bike.on) return { label: '[E] Get off the bike', act: () => dismountBike(false) };
  let best = null, bd = 1e9;
  const consider = (d, max, label, act) => { if (d < max && d < bd) { bd = d; best = { label, act }; } };
  consider(dist2(p.pos, W.bike.pos), 3.6, '[E] Ride the bike', mountBike);
  for (const h of W.houses) {
    if (dist2(p.pos, h.door.pos) > 14) continue;
    const dr = h.door;
    if (!dr.broken) consider(dist2(p.pos, dr.pos), 2.3, dr.open ? '[E] Close the door' : '[E] Open the door', () => {
      dr.open = !dr.open; dr.open ? A.doorOpen() : A.doorClose(); emitNoise(dr.pos, 9);
    });
    for (const c of h.cupboards) {
      const lbl = c.state === 'closed' || c.state === 'closing' ? `[E] Open ${c.name.toLowerCase()}` : `[E] Close ${c.name.toLowerCase()}`;
      consider(dist2(p.pos, c.fpos), 1.7, lbl, () => {
        if (c.state === 'closed' || c.state === 'closing') { c.state = 'opening'; A.cupboardOpen(); emitNoise(c.center, 5); }
        else { c.state = 'closing'; A.cupboardClose(); }
      });
    }
  }
  return best;
}

function updateCupboards(dt) {
  const p = W.player;
  for (const h of W.houses) for (const c of h.cupboards) {
    if (c.state === 'opening') { c.a = Math.min(1, c.a + dt * 1.8); if (c.a >= 1) { c.state = 'open'; revealLoot(c); } }
    else if (c.state === 'closing') { c.a = Math.max(0, c.a - dt * 2.2); if (c.a <= 0) c.state = 'closed'; }
    const e = 1 - Math.pow(1 - c.a, 3);
    c.c.hL.rotation.y = -e * 1.95; c.c.hR.rotation.y = e * 1.95;
  }
}
function revealLoot(c) {
  if (c.looted) return;
  c.looted = true;
  if (!c.loot.length) { flash('Empty...', '#aaa'); burst(c.center, 0x9a8f78, 8, 1.2); return; }
  c.loot.forEach((id, i) => {
    const mesh = makeLootMesh(id); mesh.position.copy(c.center); mesh.scale.setScalar(0.01);
    W.scene.add(mesh);
    W.items.push({ mesh, id, t: -i * 0.28, start: c.center.clone() });
  });
}
function updateItems(dt) {
  const p = W.player;
  for (const it of W.items) {
    it.t += dt;
    if (it.t < 0) continue;
    if (!it.popped) { it.popped = true; A.lootPop(W.items.indexOf(it) % 4); }
    const m = it.mesh;
    if (it.t < 0.75) {
      const k = it.t / 0.75;
      m.position.set(it.start.x, it.start.y + 0.2 + Math.sin(k * Math.PI * 0.5) * 0.8, it.start.z);
      m.scale.setScalar(Math.min(1, k * 2.5) * 1.5);
      m.rotation.y += dt * 6;
    } else {
      const k = Math.min(1, (it.t - 0.75) / 0.4);
      const tx = p.pos.x, ty = 1.2, tz = p.pos.z;
      m.position.set(lerp(m.position.x, tx, k * 0.5 + 0.1), lerp(m.position.y, ty, k * 0.5 + 0.1), lerp(m.position.z, tz, k * 0.5 + 0.1));
      m.scale.setScalar(1.5 * (1 - k * 0.6)); m.rotation.y += dt * 10;
      if (k >= 1) {
        it.done = true; W.scene.remove(m);
        const def = ITEM_DEF[it.id]; def.apply(p); A.pickup(); flash(def.label, def.color);
      }
    }
  }
  W.items = W.items.filter((i) => !i.done);
}

// ============================================================ squad AI
function updateMate(m, dt) {
  if (!m.alive) {
    m.fallT = Math.min(1, m.fallT + dt * 2.5);
    m.model.rotation.x = -m.fallT * 1.5; m.model.position.y = m.fallT * 0.15;
    return;
  }
  m.cd -= dt;
  const leader = W.player.alive ? W.player : W.survivors.find((s) => s.alive && s !== m) || m;
  // target the nearest zombie
  let tz = null, td = 26;
  for (const z of W.zombies) {
    if (z.dead) continue;
    const d = dist2(z.pos, m.pos);
    if (d < td) { td = d; tz = z; }
  }
  let want = null, speed = 0;
  const ang = m.followAng + (m.idx || 0) * 1.7;
  const slot = new V3(leader.pos.x + Math.cos(ang) * 3.4, 0, leader.pos.z + Math.sin(ang) * 3.4);
  const dl = dist2(m.pos, leader.pos);
  if (leader !== m && dl > 4.5) { want = slot; speed = dl > 12 ? 6.4 : 3.9; }
  if (tz && td < 4 && leader === m) { want = null; }
  if (tz) {
    m.yaw = turnToward(m.yaw, Math.atan2(tz.pos.x - m.pos.x, tz.pos.z - m.pos.z), 10 * dt);
    m.aimT = 0.5;
    if (m.cd <= 0 && td < 22) {
      m.cd = rand(0.8, 1.4);
      const muz = new V3(m.pos.x + Math.sin(m.yaw) * 0.6, 1.3, m.pos.z + Math.cos(m.yaw) * 0.6);
      A.gun(0.55 * falloff(dist2(m.pos, W.player.pos), 18)); emitNoise(m.pos, 70);
      const hit = Math.random() < 0.6;
      tracer(muz, new V3(tz.pos.x + (hit ? 0 : rand(-1, 1)), 1.1, tz.pos.z));
      if (hit) damageZombie(tz, 22, m.pos, 1.5);
    }
    if (td < 3.5 && speed === 0) { // back away a bit while firing
      want = new V3(m.pos.x - (tz.pos.x - m.pos.x), 0, m.pos.z - (tz.pos.z - m.pos.z)); speed = 3.2;
    }
  }
  m.speed = 0;
  if (want) {
    const goal = route(m.pos, want);
    const dx = goal.x - m.pos.x, dz = goal.z - m.pos.z, d = Math.hypot(dx, dz);
    if (d > 0.3) {
      if (!tz) m.yaw = turnToward(m.yaw, Math.atan2(dx, dz), 10 * dt);
      m.pos.x += (dx / d) * speed * dt; m.pos.z += (dz / d) * speed * dt;
      const hit = pushOut(m.pos, 0.38, W.colliders);
      m.speed = speed;
      // open doors that block the way
      if (hit) for (const h of W.houses) if (!h.door.open && !h.door.broken && dist2(m.pos, h.door.pos) < 1.8) { h.door.open = true; A.doorOpen(0.6 * falloff(dist2(m.pos, W.player.pos), 10)); }
      m.stuck = hit ? m.stuck + dt : 0;
    }
  }
  // fell far behind (e.g. leader on the bike): catch up
  if (leader !== m && dl > 38) { m.offT += dt; if (m.offT > 2.5) { m.pos.set(leader.pos.x + rand(-4, 4), 0, leader.pos.z + rand(-4, 4)); m.offT = 0; } } else m.offT = 0;
  m.phase += m.speed * dt * 2.3;
  poseWalk(m.model, m.phase, clamp(m.speed / 3, 0, 1));
  m.aimT -= dt;
  const u = m.model.userData;
  u.gun.visible = m.aimT > 0;
  if (m.aimT > 0) u.armR.rotation.x = -1.5;
  m.model.position.set(m.pos.x, 0, m.pos.z); m.model.rotation.y = m.yaw;
}

// ============================================================ player update
function updatePlayer(dt) {
  const p = W.player;
  p.cd -= dt;
  if (!p.alive) {
    p.fallT = Math.min(1, p.fallT + dt * 2.5);
    p.model.rotation.x = -p.fallT * 1.5; p.model.position.y = p.fallT * 0.15;
    return;
  }
  const u = p.model.userData;
  if (W.bike.on) {
    // seated pose
    u.legL.rotation.x = u.legR.rotation.x = -1.0; u.armL.rotation.x = u.armR.rotation.x = -1.0;
    p.model.position.set(W.bike.pos.x, 0.12, W.bike.pos.z);
    p.model.position.x -= Math.sin(W.bike.yaw) * 0.3; p.model.position.z -= Math.cos(W.bike.yaw) * 0.3;
    p.model.rotation.y = W.bike.yaw; p.model.rotation.z = W.bike.model.rotation.z;
    u.gun.visible = u.bat.visible = false;
    p.speed = Math.abs(W.bike.speed);
    return;
  }
  p.model.rotation.z = 0;
  p.aimFace = p.aimT > 0;
  const moved = onFootMove(p, dt, W.colliders, { x: WORLD, zmin: -WORLD, zmax: WORLD });
  if (p.aimT > 0) { p.aimT -= dt; const d = aimRay().d; p.yaw = turnToward(p.yaw, Math.atan2(d.x, d.z), 18 * dt); }
  // weapons
  if (pressed.Digit1) { p.weapon = 'pistol'; A.click(); }
  if (pressed.Digit2) { p.weapon = 'bat'; A.click(); }
  if (pressed.KeyH) useHeal();
  if (lmb && document.pointerLockElement) {
    if (p.weapon === 'pistol') shootPlayer(p); else swingBat(p);
  }
  // footsteps + the noise they make
  if (moved && p.speed > 0.8) {
    p.stepT -= dt * p.speed;
    if (p.stepT <= 0) { p.stepT = 2.2; A.step(p.running ? 0.14 : p.sneak ? 0.03 : 0.08); }
    p.noiseT -= dt;
    if (p.noiseT <= 0) { p.noiseT = 0.6; emitNoise(p.pos, p.running ? 20 : p.sneak ? 3 : 8); }
  }
  poseWalk(p.model, p.phase, clamp(p.speed / 3.5, 0, 1));
  u.gun.visible = p.weapon === 'pistol' && p.aimT > 0;
  u.bat.visible = p.weapon === 'bat';
  if (p.aimT > 0 && p.weapon === 'pistol') u.armR.rotation.x = -1.5;
  if (p.swing > 0) { p.swing += dt * 4; u.armR.rotation.x = -2.3 + p.swing * 3.4; if (p.swing > 1) p.swing = 0; }
  p.model.position.set(p.pos.x, p.sneak ? -0.12 : 0, p.pos.z); p.model.rotation.y = p.yaw;
}

// ============================================================ day / night
function updateTime(dt) {
  const prevDark = darkness(W.time) > 0.5;
  W.time += dt;
  if (W.time >= CYCLE) { W.time -= CYCLE; W.day++; banner('DAY ' + W.day, '#f2b134'); A.dawn(); }
  const dark = darkness(W.time);
  const night = dark > 0.5;
  if (night && !prevDark) { banner('NIGHT FALLS', '#8fa8ff'); A.dusk(); }
  const sky = new THREE.Color(0x87b8e8).lerp(new THREE.Color(0x03050c), dark);
  // warm tint around sunrise / sunset
  const warm = Math.max(0, 1 - Math.abs(dark - 0.5) * 3.2) * (dark > 0 && dark < 1 ? 1 : 0);
  sky.lerp(new THREE.Color(0xd2704a), warm * 0.45);
  W.scene.background = sky; W.scene.fog.color.copy(sky);
  W.scene.fog.near = lerp(40, 6, dark); W.scene.fog.far = lerp(170, 62, dark);
  W.hemi.intensity = lerp(0.9, 0.16, dark);
  W.hemi.color.set(0xcfe3ff).lerp(new THREE.Color(0x4a5a99), dark);
  W.sun.intensity = lerp(1.15, 0.28, dark);
  W.sun.color.set(0xfff2d0).lerp(new THREE.Color(0x7d90d0), dark);
  windowMat.emissiveIntensity = dark * 0.9;
  W.starMat.opacity = clamp((dark - 0.4) * 1.7, 0, 1);
  // celestial positions
  const inDay = W.time < DAY_LEN;
  const a = inDay ? Math.PI * (W.time / DAY_LEN) : Math.PI * ((W.time - DAY_LEN) / NIGHT_LEN);
  const dir = new V3(Math.cos(a), Math.max(Math.sin(a), 0.001), 0.3).normalize();
  const cp = camera.position;
  (inDay ? W.sunMesh : W.moonMesh).position.set(cp.x + dir.x * 320, dir.y * 320, cp.z + dir.z * 320);
  (inDay ? W.moonMesh : W.sunMesh).position.set(0, -500, 0);
  W.stars.position.copy(cp);
  const ldir = new V3(dir.x, Math.max(dir.y, 0.35), dir.z).normalize();
  const t = W.player.alive ? W.player.pos : (W.survivors.find((s) => s.alive) || W.player).pos;
  W.sun.position.set(t.x + ldir.x * 90, ldir.y * 90, t.z + ldir.z * 90);
  W.sun.target.position.set(t.x, 0, t.z);
  W.sun.target.updateMatrixWorld();
  return dark;
}

// ============================================================ zombie population
function managePopulation(dt, dark) {
  W.popT -= dt;
  if (W.popT > 0) return;
  W.popT = 1.0;
  const alive = W.zombies.filter((z) => !z.dead);
  const target = Math.min(48, Math.round(lerp(12 + W.day, 26 + W.day * 3, dark)));
  const livingS = W.survivors.filter((s) => s.alive);
  if (!livingS.length) return;
  if (alive.length < target) {
    for (let n = 0; n < 2; n++) {
      const ref = pick(livingS);
      for (let k = 0; k < 8; k++) {
        const a = rand(0, 6.283), r = rand(38, 70);
        const x = clamp(ref.pos.x + Math.cos(a) * r, -WORLD + 4, WORLD - 4), z = clamp(ref.pos.z + Math.sin(a) * r, -WORLD + 4, WORLD - 4);
        if (livingS.some((s) => Math.hypot(s.pos.x - x, s.pos.z - z) < 34)) continue;
        const zz = spawnZombie(x, z);
        if (zz) {
          // new arrivals shamble toward the action
          zz.state = 'investigate'; zz.noisePos = new V3(ref.pos.x + rand(-15, 15), 0, ref.pos.z + rand(-15, 15)); break;
        }
      }
    }
  } else if (alive.length > target + 3) {
    let far = null, fd = 55;
    for (const z of alive) {
      const d = Math.min(...livingS.map((s) => dist2(z.pos, s.pos)));
      if (d > fd) { fd = d; far = z; }
    }
    if (far) { W.scene.remove(far.model); far.gone = true; far.dead = true; }
  }
  W.zombies = W.zombies.filter((z) => !z.gone);
}

// ============================================================ camera
function updateCamera(dt) {
  const p = W.player;
  const focus = p.alive ? p : W.survivors.find((s) => s.alive) || p;
  const onBike = W.bike.on && p.alive;
  const target = new V3(focus.pos.x, onBike ? 1.5 : 1.6, focus.pos.z);
  const d = new V3(-Math.sin(camYaw) * Math.cos(camPitch), -Math.sin(camPitch), -Math.cos(camYaw) * Math.cos(camPitch));
  const right = new V3(-d.z, 0, d.x).normalize();
  const origin = target.clone().addScaledVector(right, 0.55);
  let dist = onBike ? 6.5 : 4.4;
  // keep the camera outside walls / roofs
  const dirBack = d.clone().negate();
  for (const b of W.occluders) {
    if (b.door && b.door.open) continue;
    if (Math.abs((b.minX + b.maxX) / 2 - origin.x) > 14 || Math.abs((b.minZ + b.maxZ) / 2 - origin.z) > 14) continue;
    const t = segBox(origin, dirBack, dist + 0.3, b);
    if (t !== null && t - 0.3 < dist) dist = Math.max(0.5, t - 0.3);
  }
  const cp = origin.clone().addScaledVector(dirBack, dist);
  cp.y = Math.max(cp.y, 0.35);
  if (camShake > 0) { cp.x += rand(-1, 1) * camShake * 0.25; cp.y += rand(-1, 1) * camShake * 0.25; camShake = Math.max(0, camShake - dt * 1.5); }
  camera.position.copy(cp);
  camera.lookAt(cp.clone().add(d));
  camera.fov = lerp(camera.fov, onBike ? 65 + clamp(Math.abs(W.bike.speed) * 0.7, 0, 18) : 65, 0.1);
  camera.updateProjectionMatrix();
  // hide the player's own model when the camera squeezes into it
  p.model.visible = dist > 1.1 || !p.alive;
}

// ============================================================ HUD update + minimap
const mapCtx = $('map').getContext('2d');
let hudCache = {};
function setText(id, v) { if (hudCache[id] !== v) { hudCache[id] = v; $(id).innerHTML = v; } }
function updateHUD(dark) {
  const p = W.player;
  const night = dark > 0.5;
  const t = W.time;
  const inDay = t < DAY_LEN;
  const left = Math.ceil(inDay ? DAY_LEN - t : CYCLE - t);
  const mm = String(Math.floor(left / 60)), ss = String(left % 60).padStart(2, '0');
  const cl = $('clock');
  setText('clock', `DAY ${W.day} &middot; ${inDay ? 'DAYTIME' : 'NIGHT'} ${mm}:${ss}`);
  cl.className = inDay ? 'day' : 'night';
  const frac = inDay ? t / DAY_LEN : (t - DAY_LEN) / NIGHT_LEN;
  $('phasefill').style.width = (frac * 100).toFixed(1) + '%';
  $('phasefill').style.background = inDay ? '#f2b134' : '#6f86e8';
  $('hpfill').style.width = p.hp + '%';
  const sq = W.survivors.slice(1).map((m) => `<small><span>${m.name}</span><span>${m.alive ? Math.ceil(m.hp) : 'DOWN'}</span></small><div class="bar mate ${m.alive ? '' : 'dead'}"><div style="width:${m.hp}%"></div></div>`).join('');
  setText('squad', sq);
  const wpn = p.weapon === 'pistol' ? `Pistol <b>${p.ammo}</b> ammo` : 'Baseball bat';
  setText('bottom', `HP <b>${Math.ceil(p.hp)}</b> &nbsp; ${wpn}<br>Medkits <b>${p.medkits}</b> &nbsp; Food <b>${p.food}</b> &nbsp; Kills <b>${W.kills}</b><br><span style="opacity:.7;font-size:12px">[1] pistol [2] bat [H] heal</span>`);
  W.noiseLevel = Math.max(0, W.noiseLevel - 0.6 * (1 / 60));
  $('noisefill').style.width = clamp(W.noiseLevel * 100, 0, 100) + '%';
  $('cross').style.display = p.alive && !W.bike.on ? 'block' : 'none';
  // day counter above the player's head
  if (p.dayLabel) p.dayLabel.userData.set(`DAY ${W.day} ${inDay ? '☀' : '☾'}`, inDay ? '#f2b134' : '#9fb4ff');
  // minimap
  const R = 75, c = mapCtx, s = 150 / (R * 2);
  const fp = (p.alive ? p : W.survivors.find((x) => x.alive) || p).pos;
  c.clearRect(0, 0, 150, 150);
  c.save(); c.beginPath(); c.arc(75, 75, 75, 0, 6.283); c.clip();
  c.fillStyle = 'rgba(40,60,36,.7)'; c.fillRect(0, 0, 150, 150);
  c.translate(75, 75); c.rotate(camYaw);
  const mx = (x) => (x - fp.x) * s, mz = (z) => (z - fp.z) * s;
  c.fillStyle = '#3b3b40'; c.fillRect(mx(-200), mz(-4), 400 * s, 8 * s); c.fillRect(mx(-4), mz(-200), 8 * s, 400 * s);
  for (const h of W.houses) { c.fillStyle = '#b5a58a'; c.fillRect(mx(h.px) - 5, mz(h.pz) - 4, 10, 8); }
  c.fillStyle = '#e04a3a';
  for (const z of W.zombies) if (!z.dead && dist2(z.pos, fp) < 45) c.fillRect(mx(z.pos.x) - 1.5, mz(z.pos.z) - 1.5, 3, 3);
  c.fillStyle = '#f2b134'; c.fillRect(mx(W.bike.pos.x) - 2, mz(W.bike.pos.z) - 2, 4, 4);
  c.fillStyle = '#5fbf6a';
  for (const m of W.survivors) if (m.alive && !m.isPlayer) c.fillRect(mx(m.pos.x) - 2, mz(m.pos.z) - 2, 4, 4);
  c.restore();
  c.fillStyle = '#fff'; c.beginPath(); c.arc(75, 75, 3, 0, 6.283); c.fill();
}

// ============================================================ lights follow the player
function updateLights(dark, dt) {
  const p = W.player.alive ? W.player : W.survivors.find((s) => s.alive) || W.player;
  const head = new V3(p.pos.x, 1.5, p.pos.z);
  const d = new V3(); camera.getWorldDirection(d);
  W.torch.position.copy(head).addScaledVector(d, 0.3);
  W.torch.target.position.copy(head).addScaledVector(d, 12);
  W.torch.intensity = dark * 45;
  W.lantern.position.set(head.x, 1.8, head.z); W.lantern.intensity = dark * 9;
  const h = houseAt(p.pos);
  if (h) { const c = h.toWorld(0, 0); W.houseLight.position.set(c.x, 2.5, c.z); W.houseLight.intensity = 14; }
  else W.houseLight.intensity = 0;
  if (W.muzzleT > 0) { W.muzzleT -= dt; if (W.muzzleT <= 0) W.muzzle.intensity = 0; }
}

// ============================================================ main world update
function updateWorld(dt) {
  const dark = updateTime(dt);
  // doors animate
  for (const h of W.houses) {
    const dr = h.door;
    dr.a += ((dr.open ? 1 : 0) - dr.a) * (1 - Math.exp(-7 * dt));
    dr.pivot.rotation.y = dr.a * (dr.broken ? 1.25 : 1.75);
  }
  updateCupboards(dt);
  updatePlayer(dt);
  updateBike(dt);
  for (const m of W.survivors) if (!m.isPlayer) updateMate(m, dt);
  if (!W.player.alive) { /* spectating */ }
  for (const z of W.zombies) updateZombie(z, dt);
  managePopulation(dt, dark);
  updateItems(dt);
  // interactions
  const it = findInteract();
  setPrompt(it ? it.label : '');
  if (it && pressed.KeyE) it.act();
  // particles / tracers
  for (const p of W.particles) if (p.life > 0) {
    p.life -= dt; p.v.y -= 9 * dt; p.m.position.addScaledVector(p.v, dt);
    if (p.m.position.y < 0.05) { p.m.position.y = 0.05; p.v.multiplyScalar(0.4); }
    if (p.life <= 0) p.m.visible = false;
  }
  for (const t of W.tracers) if (t.life > 0) { t.life -= dt; t.l.material.opacity = Math.max(0, t.life / 0.09); if (t.life <= 0) t.l.visible = false; }
  updateCamera(dt);
  updateLights(dark, dt);
  updateHUD(dark);
  A.ambient(dark, dt);
}

// ============================================================ game flow
function startGame() {
  if (mode !== 'lobby') return;
  mode = 'transition';
  const squad = L.squad, d = L.doors[L.joined];
  const names = d.names.slice(0, squad - 1);
  while (names.length < squad - 1) names.push('AI-' + (names.length + 1));
  A.click();
  $('squad-panel').classList.add('hidden');
  fadeThen(() => {
    buildWorld(squad, names);
    mode = 'play';
    $('lobbytop').classList.add('hidden'); $('lobbyui').classList.add('hidden');
    $('hud').classList.remove('hidden');
    hudCache = {};
    banner('DAY 1', '#f2b134');
    flash(`Squad of ${squad}: the bike is on your right - press E`, '#f2b134');
    if (!document.pointerLockElement && canvas.requestPointerLock) { try { canvas.requestPointerLock(); } catch (e) { /* needs a gesture */ } }
  });
}
function endGame() {
  if (W.over) return;
  W.over = true; W.overT = 0;
  A.bikeStop(); A.gameOver();
  setTimeout(() => {
    if (mode !== 'play') return;
    mode = 'over';
    $('overstats').innerHTML = `You survived <b>${W.day}</b> day${W.day > 1 ? 's' : ''}<br>Zombies killed: <b>${W.kills}</b><br>Squad size: <b>${W.survivors.length}</b>`;
    $('over').classList.remove('hidden'); $('hud').classList.add('hidden');
    if (document.pointerLockElement) document.exitPointerLock();
  }, 2500);
}
function toLobby() {
  if (mode !== 'over') return;
  mode = 'transition';
  $('over').classList.add('hidden');
  fadeThen(() => {
    A.bikeStop();
    W = null; L = buildLobby();
    mode = 'lobby'; camYaw = 0; camPitch = 0.25;
    $('lobbytop').classList.remove('hidden'); $('lobbyui').classList.remove('hidden');
    windowMat.emissiveIntensity = 0;
  });
}
$('overbtn').onclick = toLobby;
$('playbtn').onclick = () => {
  A.init(); A.resume(); A.click();
  $('title').classList.add('hidden');
  mode = 'lobby';
  $('lobbytop').classList.remove('hidden'); $('lobbyui').classList.remove('hidden');
  if (canvas.requestPointerLock) { try { canvas.requestPointerLock(); } catch (e) { /* ignore */ } }
};

// ============================================================ loop
L = buildLobby();
const clock = new THREE.Clock();
let activeScene = null;
function loop() {
  requestAnimationFrame(loop);
  const dt = Math.min(clock.getDelta(), 0.05);
  if (mode === 'title' || mode === 'lobby' || (mode === 'transition' && !W)) {
    if (mode === 'title') { camYaw += dt * 0.15; L.joined = -1; }
    lobbyUpdate(dt);
    if (mode === 'title') {
      const t = performance.now() / 6000;
      camera.position.set(Math.sin(t) * 9, 4.5, 4 + Math.cos(t) * 3); camera.lookAt(0, 1.5, -4);
    }
    activeScene = L.scene;
  } else if (W) {
    if (mode === 'play') updateWorld(dt);
    else if (mode === 'over') { for (const z of W.zombies) updateZombie(z, dt); updateCamera(dt); }
    if (mode === 'over' && pressed.Enter) toLobby();
    activeScene = W.scene;
  }
  if (activeScene) renderer.render(activeScene, camera);
  for (const k in pressed) delete pressed[k];
}
loop();

// handy for debugging / automated tests
window.__game = {
  get mode() { return mode; }, get world() { return W; }, get lobby() { return L; },
  keys, pressed, THREE,
  emitNoise,
  setCam(y, p) { camYaw = y; camPitch = p; },
};
