// Procedural 3D models (everything is built from primitives - no external assets).
import * as THREE from 'three';

const matCache = new Map();
export function mat(color, o = {}) {
  const key = color + JSON.stringify(o);
  let m = matCache.get(key);
  if (!m) {
    m = new THREE.MeshStandardMaterial({ color, roughness: 0.85, metalness: 0.05, ...o });
    matCache.set(key, m);
  }
  return m;
}

// Shared glass material; the game raises its emissive intensity at night.
export const windowMat = new THREE.MeshStandardMaterial({
  color: 0x223344, emissive: 0xffc864, emissiveIntensity: 0, roughness: 0.2, metalness: 0.3,
});

const boxGeo = new THREE.BoxGeometry(1, 1, 1);
export function box(w, h, d, material, x = 0, y = 0, z = 0, cast = true) {
  const m = new THREE.Mesh(boxGeo, material);
  m.scale.set(w, h, d);
  m.position.set(x, y, z);
  m.castShadow = cast;
  m.receiveShadow = true;
  return m;
}
export function cyl(rt, rb, h, material, seg = 12, x = 0, y = 0, z = 0) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, h, seg), material);
  m.position.set(x, y, z);
  m.castShadow = true;
  m.receiveShadow = true;
  return m;
}

// Billboard text label (used for the day counter above the player's head, door signs ...)
export function makeLabel(text, color = '#ffffff', height = 0.5, font = 'bold 34px sans-serif') {
  const c = document.createElement('canvas');
  c.width = 256; c.height = 64;
  const x = c.getContext('2d');
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false }));
  sp.scale.set(height * 4, height, 1);
  let cur = '';
  sp.userData.set = (t, col = color) => {
    if (t + col === cur) return;
    cur = t + col;
    x.clearRect(0, 0, 256, 64);
    x.fillStyle = 'rgba(0,0,0,0.55)';
    x.fillRect(4, 6, 248, 52);
    x.strokeStyle = col; x.lineWidth = 2; x.strokeRect(4, 6, 248, 52);
    x.fillStyle = col;
    x.font = font; x.textAlign = 'center'; x.textBaseline = 'middle';
    x.fillText(t, 128, 33);
    tex.needsUpdate = true;
  };
  sp.userData.set(text, color);
  return sp;
}

// ------------------------------------------------------------------ people
export function makeHumanoid({ skin = 0xe0b090, shirt = 0x3b6ea5, pants = 0x2b2b3a, hair = 0x3a2a1a, zombie = false } = {}) {
  const g = new THREE.Group();
  const skinM = mat(skin), shirtM = mat(shirt), pantsM = mat(pants);
  g.add(box(0.52, 0.66, 0.3, shirtM, 0, 1.05, 0));
  const head = new THREE.Group();
  head.position.set(0, 1.4, 0);
  head.add(box(0.34, 0.34, 0.34, skinM, 0, 0.17, 0));
  if (zombie) {
    const eye = mat(0xff2200, { emissive: 0xff2200, emissiveIntensity: 1.2 });
    head.add(box(0.07, 0.05, 0.02, eye, -0.08, 0.2, 0.175, false));
    head.add(box(0.07, 0.05, 0.02, eye, 0.08, 0.2, 0.175, false));
    head.add(box(0.14, 0.04, 0.02, mat(0x3a0f0f), 0, 0.07, 0.175, false));
  } else {
    head.add(box(0.37, 0.12, 0.37, mat(hair), 0, 0.33, -0.01));
    const eye = mat(0x111111);
    head.add(box(0.05, 0.05, 0.02, eye, -0.08, 0.2, 0.175, false));
    head.add(box(0.05, 0.05, 0.02, eye, 0.08, 0.2, 0.175, false));
  }
  g.add(head);

  const legs = [], arms = [];
  for (const s of [-1, 1]) {
    const leg = new THREE.Group();
    leg.position.set(s * 0.14, 0.72, 0);
    leg.add(box(0.21, 0.72, 0.23, pantsM, 0, -0.36, 0));
    g.add(leg); legs.push(leg);
    const arm = new THREE.Group();
    arm.position.set(s * 0.37, 1.34, 0);
    arm.add(box(0.16, 0.3, 0.16, shirtM, 0, -0.15, 0));
    arm.add(box(0.14, 0.34, 0.14, skinM, 0, -0.47, 0));
    g.add(arm); arms.push(arm);
  }
  // tools held in the right arm (arms[1])
  const gun = new THREE.Group();
  gun.add(box(0.07, 0.34, 0.1, mat(0x1c1c1c, { metalness: 0.6 }), 0, -0.76, 0));
  gun.add(box(0.06, 0.12, 0.08, mat(0x1c1c1c), 0, -0.6, -0.07));
  gun.visible = false;
  arms[1].add(gun);
  const bat = new THREE.Group();
  bat.add(cyl(0.035, 0.06, 0.95, mat(0x8a6038), 8, 0, -0.7, 0));
  bat.visible = false;
  arms[1].add(bat);
  g.userData = { legL: legs[0], legR: legs[1], armL: arms[0], armR: arms[1], head, gun, bat, zombie };
  return g;
}

// Walk cycle. phase advances with distance travelled, amount 0..1.
export function poseWalk(g, phase, amount) {
  const u = g.userData;
  const s = Math.sin(phase) * 0.95 * amount;
  u.legL.rotation.x = s;
  u.legR.rotation.x = -s;
  if (u.zombie) {
    u.armL.rotation.x = -1.4 + Math.sin(phase * 0.5) * 0.12;
    u.armR.rotation.x = -1.4 - Math.sin(phase * 0.5) * 0.12;
    u.head.rotation.z = Math.sin(phase * 0.35) * 0.15;
    u.head.rotation.x = 0.2;
  } else {
    u.armL.rotation.x = -s * 0.8;
    u.armR.rotation.x = s * 0.8;
  }
  g.children[0].position.y = 1.05 + Math.abs(Math.sin(phase)) * 0.04 * amount;
}

// ------------------------------------------------------------------ bike
export function buildBike() {
  const g = new THREE.Group();
  const red = mat(0xb01818, { metalness: 0.5, roughness: 0.4 });
  const black = mat(0x181818, { metalness: 0.3 });
  const chrome = mat(0xb8b8c0, { metalness: 0.9, roughness: 0.25 });
  const mkWheel = () => {
    const w = new THREE.Group();
    const tire = new THREE.Mesh(new THREE.TorusGeometry(0.3, 0.09, 8, 20), black);
    tire.rotation.y = Math.PI / 2; tire.castShadow = true;
    w.add(tire);
    const hub = cyl(0.1, 0.1, 0.12, chrome, 10);
    hub.rotation.z = Math.PI / 2;
    w.add(hub);
    const spoke = box(0.02, 0.56, 0.02, chrome); w.add(spoke);
    const spoke2 = box(0.02, 0.02, 0.56, chrome); w.add(spoke2);
    return w;
  };
  const rear = mkWheel(); rear.position.set(0, 0.39, -0.72); g.add(rear);
  const steer = new THREE.Group(); steer.position.set(0, 0.95, 0.68); g.add(steer);
  const front = mkWheel(); front.position.set(0, -0.56, 0.1); steer.add(front);
  const fork = box(0.08, 0.7, 0.08, chrome, 0, -0.25, 0.05); fork.rotation.x = -0.18; steer.add(fork);
  steer.add(box(0.74, 0.05, 0.05, black, 0, 0.12, 0));
  steer.add(box(0.08, 0.06, 0.2, black, -0.36, 0.12, 0), box(0.08, 0.06, 0.2, black, 0.36, 0.12, 0));
  const lamp = new THREE.Mesh(new THREE.SphereGeometry(0.11, 10, 8), mat(0xfff3c0, { emissive: 0xfff3c0, emissiveIntensity: 0.8 }));
  lamp.position.set(0, 0.0, 0.18); steer.add(lamp);
  g.add(box(0.14, 0.16, 1.25, red, 0, 0.65, 0.0));
  g.add(box(0.34, 0.24, 0.5, red, 0, 0.9, 0.22));
  g.add(box(0.28, 0.1, 0.62, black, 0, 0.83, -0.4));
  g.add(box(0.3, 0.32, 0.42, mat(0x55555d, { metalness: 0.7 }), 0, 0.45, 0.02));
  const pipe = cyl(0.04, 0.05, 0.9, chrome, 8, 0.2, 0.38, -0.35); pipe.rotation.x = Math.PI / 2; g.add(pipe);
  g.add(box(0.12, 0.05, 0.3, black, -0.2, 0.28, 0.0), box(0.12, 0.05, 0.3, black, 0.2, 0.28, 0.0));
  g.userData = { rear, front, steer };
  return g;
}

export function buildCar(color) {
  const g = new THREE.Group();
  const body = mat(color, { metalness: 0.4, roughness: 0.55 });
  g.add(box(1.9, 0.7, 4.2, body, 0, 0.6, 0));
  g.add(box(1.65, 0.62, 2.1, mat(0x1b2530, { metalness: 0.6, roughness: 0.2 }), 0, 1.25, -0.2));
  g.add(box(1.7, 0.08, 2.15, body, 0, 1.58, -0.2));
  for (const sx of [-1, 1]) for (const sz of [-1.3, 1.3]) {
    const w = cyl(0.37, 0.37, 0.28, mat(0x151515), 12, sx * 0.95, 0.37, sz);
    w.rotation.z = Math.PI / 2; g.add(w);
  }
  g.add(box(0.3, 0.12, 0.05, mat(0xffd9a0, { emissive: 0xffd9a0, emissiveIntensity: 0.3 }), -0.6, 0.65, 2.1));
  g.add(box(0.3, 0.12, 0.05, mat(0xffd9a0, { emissive: 0xffd9a0, emissiveIntensity: 0.3 }), 0.6, 0.65, 2.1));
  return g;
}

// ------------------------------------------------------------------ loot
export function makeLootMesh(id) {
  const g = new THREE.Group();
  const glow = (c) => mat(c, { emissive: c, emissiveIntensity: 0.25 });
  if (id === 'ammo' || id === 'ammoBig') {
    const s = id === 'ammoBig' ? 1.3 : 1;
    g.add(box(0.3 * s, 0.18 * s, 0.2 * s, glow(0x5d6b2f), 0, 0, 0, false));
    g.add(box(0.31 * s, 0.05 * s, 0.21 * s, glow(0xe3b341), 0, 0.02, 0, false));
  } else if (id === 'medkit') {
    g.add(box(0.36, 0.24, 0.24, glow(0xf2f2f2), 0, 0, 0, false));
    g.add(box(0.2, 0.05, 0.06, glow(0xd01818), 0, 0.125, 0, false));
    g.add(box(0.06, 0.05, 0.2, glow(0xd01818), 0, 0.125, 0, false));
  } else {
    const can = cyl(0.1, 0.1, 0.18, glow(0xc9ced4), 12);
    can.castShadow = false; g.add(can);
    const lab = cyl(0.102, 0.102, 0.09, glow(0xd9622b), 12); lab.castShadow = false; g.add(lab);
  }
  return g;
}

// ------------------------------------------------------------------ cupboard
export function buildCupboard({ h = 1.9, w = 1.1, d = 0.5, color = 0x7a5232, counter = false } = {}) {
  const g = new THREE.Group();
  const wood = mat(color), inner = mat(0x3b2614), metal = mat(0xc0c0c8, { metalness: 0.8, roughness: 0.3 });
  const t = 0.05;
  g.add(box(w, h, t, inner, 0, h / 2, -d / 2 + t / 2));
  g.add(box(t, h, d, wood, -(w / 2 - t / 2), h / 2, 0));
  g.add(box(t, h, d, wood, (w / 2 - t / 2), h / 2, 0));
  g.add(box(w, t, d, wood, 0, h - t / 2, 0));
  g.add(box(w - 2 * t, t, d, wood, 0, 0.1, 0));
  const shelves = h > 1.4 ? 3 : 1;
  for (let i = 1; i <= shelves; i++) g.add(box(w - 2 * t, 0.03, d - 0.06, wood, 0, 0.1 + (h - 0.2) * i / (shelves + 1), 0));
  if (counter) g.add(box(w + 0.08, 0.05, d + 0.06, mat(0xd8d2c4), 0, h + 0.02, 0.01));
  const mkDoor = (side) => {
    const hinge = new THREE.Group();
    hinge.position.set(side * w / 2, 0, d / 2);
    hinge.add(box(w / 2 - 0.01, h - 0.14, 0.04, wood, -side * (w / 4), h / 2, 0));
    hinge.add(box(0.03, 0.2, 0.03, metal, -side * (w / 2 - 0.09), h / 2, 0.04));
    g.add(hinge);
    return hinge;
  };
  const hL = mkDoor(-1), hR = mkDoor(1);
  return { group: g, hL, hR, h, w, d };
}

// ------------------------------------------------------------------ house
// Local space: centered on origin, front (door side) toward +z.
// 10 wide (x) x 8 deep (z). A partition splits it into bedroom (left) and living room (right).
export function buildHouse({ wallColor = 0xc9b79c, roofColor = 0x8a3b2a, trimColor = 0xf0eadc } = {}) {
  const g = new THREE.Group();
  const wallM = mat(wallColor), trimM = mat(trimColor), woodM = mat(0x6b4a2b), roofM = mat(roofColor, { roughness: 0.9 });
  const walls = [];
  const addWall = (x0, x1, z0, z1, y0 = 0, y1 = 3, m = wallM) => {
    g.add(box(x1 - x0, y1 - y0, z1 - z0, m, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2));
    walls.push({ x0, x1, z0, z1, y0, y1 });
  };
  // floor + ceiling + porch step
  g.add(box(9.6, 0.02, 7.6, woodM, 0, 0.01, 0, false));
  g.add(box(9.8, 0.04, 7.8, mat(0xe8e2d2), 0, 2.98, 0, false));
  g.add(box(1.8, 0.1, 0.9, mat(0x8b8b8b), 2, 0.05, 4.45));
  // outer walls (front has a door gap x 1.3..2.7)
  addWall(-5, 5, -4, -3.75);
  addWall(-5, -4.75, -4, 4);
  addWall(4.75, 5, -4, 4);
  addWall(-5, 1.3, 3.75, 4);
  addWall(2.7, 5, 3.75, 4);
  addWall(1.3, 2.7, 3.75, 4, 2.2, 3);
  // partition with open doorway z 0.5..2.1
  addWall(-1, -0.75, -3.75, 0.5);
  addWall(-1, -0.75, 2.1, 3.75);
  addWall(-1, -0.75, 0.5, 2.1, 2.2, 3);
  // trim at the corners
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) g.add(box(0.3, 3.05, 0.3, trimM, sx * 4.92, 1.52, sz * 3.92));
  // windows (glass is slightly thicker than the wall so it shows on both sides)
  const addWindow = (x, z, alongX) => {
    const fw = alongX ? 1.4 : 0.32, fd = alongX ? 0.32 : 1.4;
    g.add(box(fw, 1.2, fd, trimM, x, 1.6, z));
    const pw = alongX ? 1.2 : 0.36, pd = alongX ? 0.36 : 1.2;
    const pane = box(pw, 1.0, pd, windowMat, x, 1.6, z, false);
    g.add(pane);
  };
  addWindow(-3, 3.875, true);
  addWindow(-2.5, -3.875, true);
  addWindow(2, -3.875, true);
  addWindow(-4.875, 1.2, false);
  addWindow(4.875, -1, false);
  addWindow(4.875, 1.8, false);
  // door
  const pivot = new THREE.Group();
  pivot.position.set(1.3, 0, 3.875);
  pivot.add(box(1.4, 2.2, 0.08, mat(0x5a3a1e), 0.7, 1.1, 0));
  pivot.add(new THREE.Mesh(new THREE.SphereGeometry(0.05, 8, 6), mat(0xd4af37, { metalness: 0.9, roughness: 0.3 })));
  pivot.children[1].position.set(1.2, 1.05, 0.07);
  g.add(pivot);
  g.add(box(1.5, 0.12, 0.34, trimM, 2, 2.24, 3.875));
  // roof (gabled prism)
  const shape = new THREE.Shape();
  shape.moveTo(-4.9, 0); shape.lineTo(4.9, 0); shape.lineTo(0, 2.3); shape.closePath();
  const geo = new THREE.ExtrudeGeometry(shape, { depth: 11.4, bevelEnabled: false });
  geo.translate(0, 0, -5.7); geo.rotateY(Math.PI / 2);
  const roof = new THREE.Mesh(geo, roofM);
  roof.position.y = 3; roof.castShadow = true; roof.receiveShadow = true;
  g.add(roof);
  g.add(box(11.5, 0.12, 0.3, mat(0x3a1f18), 0, 5.3, 0));
  g.add(box(0.6, 2.4, 0.6, mat(0x7a4a3a), -3.2, 4.6, -1.8));
  // furniture
  const furniture = [];
  const addFurn = (x0, x1, z0, z1) => furniture.push({ x0, x1, z0, z1 });
  // bed
  g.add(box(1.1, 0.35, 2.1, woodM, -3.95, 0.2, 0.85));
  g.add(box(1.0, 0.18, 1.95, mat(0xb8c4d8), -3.95, 0.47, 0.9));
  g.add(box(0.8, 0.12, 0.35, mat(0xf4f4f4), -3.95, 0.62, -0.0));
  g.add(box(1.1, 0.8, 0.1, woodM, -3.95, 0.5, -0.2));
  addFurn(-4.55, -3.35, -0.25, 1.9);
  // table + chairs + rug
  g.add(box(2.6, 0.02, 1.8, mat(0x8d3a3a), 1.3, 0.025, -0.8, false));
  g.add(box(1.4, 0.07, 0.9, woodM, 1.3, 0.78, -0.8));
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) g.add(box(0.08, 0.76, 0.08, woodM, 1.3 + sx * 0.62, 0.38, -0.8 + sz * 0.37));
  addFurn(0.55, 2.05, -1.3, -0.3);
  for (const [cx, cz, tilt] of [[1.3, -1.6, 0], [1.3, 0.1, 0]]) {
    const ch = new THREE.Group(); ch.position.set(cx, 0, cz); ch.rotation.z = tilt;
    ch.add(box(0.42, 0.06, 0.42, woodM, 0, 0.45, 0));
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) ch.add(box(0.05, 0.45, 0.05, woodM, sx * 0.17, 0.22, sz * 0.17));
    ch.add(box(0.42, 0.5, 0.05, woodM, 0, 0.75, cz < -0.8 ? -0.19 : 0.19));
    g.add(ch);
  }
  // lamp on a side table
  g.add(box(0.5, 0.5, 0.5, woodM, -2.0, 0.25, 3.3));
  g.add(new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.18, 0.3, 10), mat(0xf5deb3, { emissive: 0xf5deb3, emissiveIntensity: 0.3 })));
  g.children[g.children.length - 1].position.set(-2.0, 0.65, 3.3);
  addFurn(-2.25, -1.75, 3.05, 3.55);
  // cupboards: tall wardrobe (bedroom), dresser (bedroom, faces +x), kitchen cabinet (living)
  const cupboards = [];
  const place = (opts, x, z, rotY, fx0, fx1, fz0, fz1) => {
    const c = buildCupboard(opts);
    c.group.position.set(x, 0, z); c.group.rotation.y = rotY;
    g.add(c.group);
    addFurn(fx0, fx1, fz0, fz1);
    // interaction point: 0.8 in front of the cupboard (local coords)
    const fx = x + Math.sin(rotY) * 0.8, fz = z + Math.cos(rotY) * 0.8;
    cupboards.push({ ...c, lx: x, lz: z, rotY, frontX: fx, frontZ: fz, name: opts.name });
  };
  place({ h: 1.95, w: 1.1, color: 0x7a5232, name: 'Wardrobe' }, -3.0, -3.5, 0, -3.55, -2.45, -3.75, -3.2);
  place({ h: 1.1, w: 1.1, color: 0x9a6b3e, name: 'Dresser' }, -4.5, -1.6, Math.PI / 2, -4.75, -4.25, -2.15, -1.05);
  place({ h: 0.95, w: 1.2, color: 0xe9e4d6, counter: true, name: 'Kitchen cabinet' }, 3.5, -3.5, 0, 2.9, 4.1, -3.75, -3.2);
  g.add(box(0.7, 0.9, 0.6, mat(0xdddddd, { metalness: 0.4 }), 4.25, 0.45, -2.6)); // fridge
  addFurn(3.9, 4.6, -2.9, -2.3);

  g.userData = { walls, furniture, cupboards, doorPivot: pivot };
  return {
    group: g, walls, furniture, cupboards, doorPivot: pivot, roof,
    roofBox: { x0: -5.7, x1: 5.7, z0: -4.9, z1: 4.9, y0: 3, y1: 5.3 },
  };
}
