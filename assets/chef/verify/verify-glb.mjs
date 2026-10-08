// Re-import the exported runtime GLB and check skin, joints, weights, clips and sockets.
import { NodeIO } from '@gltf-transform/core';
import { readFileSync } from 'node:fs';

const [glbPath, manifestPath] = process.argv.slice(2);
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const doc = await new NodeIO().read(glbPath);
const root = doc.getRoot();
let failures = 0;
const check = (ok, msg) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${msg}`); if (!ok) failures++; };

const skins = root.listSkins();
check(skins.length === 1, `one skin (found ${skins.length})`);
const skin = skins[0];
const joints = skin.listJoints().map((j) => j.getName());
check(joints.length > 0, `${joints.length} joints: ${joints.join(', ')}`);
check(!!skin.getInverseBindMatrices() && skin.getInverseBindMatrices().getCount() === joints.length,
  'inverse bind matrices present for every joint');
for (const d of manifest.bones.deform) check(joints.includes(d), `deform bone ${d} exported`);
for (const s of manifest.bones.sockets) check(joints.includes(s) || root.listNodes().some((n) => n.getName() === s), `socket ${s} exported`);

const mesh = root.listMeshes()[0];
const prim = mesh.listPrimitives()[0];
const J = prim.getAttribute('JOINTS_0'), W = prim.getAttribute('WEIGHTS_0');
check(!!J && !!W, 'JOINTS_0 and WEIGHTS_0 present');
let bad = 0, maxDev = 0, nonzero = 0;
const w = [], j = [];
for (let i = 0; i < W.getCount(); i++) {
  W.getElement(i, w); J.getElement(i, j);
  const s = w[0] + w[1] + w[2] + w[3];
  maxDev = Math.max(maxDev, Math.abs(1 - s));
  if (s > 0) nonzero++;
  if (j.some((x) => x >= joints.length)) bad++;
}
check(nonzero === W.getCount(), `all ${W.getCount()} vertices weighted`);
check(maxDev < 1e-3, `weights normalised (max deviation ${maxDev.toExponential(2)})`);
check(bad === 0, 'joint indices in range');
check(prim.getAttribute('POSITION').getCount() === 26437, `vertex count preserved (${prim.getAttribute('POSITION').getCount()})`);
check(prim.getIndices().getCount() / 3 === 30934, `triangle count preserved (${prim.getIndices().getCount() / 3})`);

const mat = prim.getMaterial();
check(!!mat.getBaseColorTexture() && !!mat.getNormalTexture() && !!mat.getMetallicRoughnessTexture(),
  'base colour, normal and metallic/roughness textures connected');
check(mat.getDoubleSided(), 'material still double-sided');

const anims = Object.fromEntries(root.listAnimations().map((a) => [a.getName(), a]));
for (const [name, meta] of Object.entries(manifest.clips)) {
  const a = anims[name];
  if (!a) { check(false, `clip ${name} exported`); continue; }
  let maxT = 0; const targets = new Set();
  for (const ch of a.listChannels()) {
    targets.add(ch.getTargetNode().getName());
    const input = ch.getSampler().getInput();
    maxT = Math.max(maxT, input.getMax([])[0]);
  }
  const drivesLimbs = ['upperarm.L', 'forearm.R', 'thigh.L', 'head'].every((b) => targets.has(b));
  check(Math.abs(maxT - meta.duration) < 1 / 30 + 1e-3 && drivesLimbs,
    `clip ${name}: ${maxT.toFixed(3)}s (manifest ${meta.duration}s), ${targets.size} nodes animated`);
  if (meta.loop) {
    // loop continuity: first and last rotation samples equal for every channel
    let worst = 0;
    for (const ch of a.listChannels()) {
      const out = ch.getSampler().getOutput(); const n = out.getCount();
      const a0 = out.getElement(0, []), a1 = out.getElement(n - 1, []);
      let d = 0; for (let k = 0; k < a0.length; k++) d = Math.max(d, Math.abs(a0[k] - a1[k]));
      if (ch.getTargetPath() === 'rotation') {
        let d2 = 0; for (let k = 0; k < a0.length; k++) d2 = Math.max(d2, Math.abs(a0[k] + a1[k])); d = Math.min(d, d2);
      }
      worst = Math.max(worst, d);
    }
    check(worst < 2e-3, `  loop seam continuous for ${name} (max delta ${worst.toExponential(2)})`);
  }
}
check(Object.keys(anims).length === Object.keys(manifest.clips).length,
  `exactly ${Object.keys(manifest.clips).length} clips exported (found ${Object.keys(anims).length}: no ctrl_ actions)`);

// root motion: root node must not translate in any clip
for (const a of root.listAnimations()) {
  for (const ch of a.listChannels()) {
    if (ch.getTargetNode().getName() === 'root' && ch.getTargetPath() === 'translation') {
      const out = ch.getSampler().getOutput(); let m = 0; const e = [];
      for (let i = 0; i < out.getCount(); i++) { out.getElement(i, e); m = Math.max(m, Math.hypot(...e)); }
      if (m > 1e-4) check(false, `root translates in ${a.getName()}`);
    }
  }
}
console.log(failures ? `\n${failures} FAILURES` : '\nALL CHECKS PASSED');
process.exit(failures ? 1 : 0);
