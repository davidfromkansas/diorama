// Check every fitted character against the chef: the same nodes in the same order (the app plays
// the chef's clips on them by node index), the same skin joints, complete weights, textures, and
// the counts recorded in chef-variants.json.
//   node verify-variants.mjs <resource dir> [list file, default chef-variants.json]
import { NodeIO } from '@gltf-transform/core';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = process.argv[2];
const listFile = process.argv[3] ?? 'chef-variants.json';
const io = new NodeIO();
const list = JSON.parse(readFileSync(join(dir, listFile), 'utf8'));
const base = (await io.read(join(dir, list.base))).getRoot();
const baseNodes = base.listNodes().map((n) => n.getName());
const baseJoints = base.listSkins()[0].listJoints().map((j) => j.getName());
let failures = 0;
const check = (ok, msg) => { if (!ok) { console.log(`FAIL ${msg}`); failures++; } };

for (const c of list.characters) {
  const root = (await io.read(join(dir, c.asset))).getRoot();
  const nodes = root.listNodes().map((n) => n.getName());
  check(JSON.stringify(nodes) === JSON.stringify(baseNodes), `${c.id}: nodes match the chef's (${nodes.length} vs ${baseNodes.length})`);
  const skins = root.listSkins();
  check(skins.length === 1, `${c.id}: one skin`);
  const joints = skins[0].listJoints().map((j) => j.getName());
  check(JSON.stringify(joints) === JSON.stringify(baseJoints), `${c.id}: skin joints match the chef's`);
  check(root.listAnimations().length === 0, `${c.id}: no clips of its own`);
  const prims = root.listMeshes().flatMap((m) => m.listPrimitives());
  check(prims.length === 1, `${c.id}: one primitive (found ${prims.length})`);
  const prim = prims[0];
  const J = prim.getAttribute('JOINTS_0'), W = prim.getAttribute('WEIGHTS_0');
  let unweighted = 0, maxDev = 0, outOfRange = 0;
  const w = [], j = [];
  for (let i = 0; i < W.getCount(); i++) {
    W.getElement(i, w); J.getElement(i, j);
    const s = w[0] + w[1] + w[2] + w[3];
    if (s === 0) unweighted++;
    maxDev = Math.max(maxDev, Math.abs(1 - s));
    if (j.some((x) => x >= joints.length)) outOfRange++;
  }
  check(unweighted === 0 && maxDev < 1e-3, `${c.id}: weights complete and normalised (${unweighted} unweighted, deviation ${maxDev.toExponential(2)})`);
  check(outOfRange === 0, `${c.id}: joint indices in range`);
  const tris = prim.getIndices().getCount() / 3;
  check(Math.abs(tris - c.triangles) <= c.triangles * 0.02 && tris <= 16000, `${c.id}: ${tris} triangles (recorded ${c.triangles}, budget 16,000)`);
  const mat = prim.getMaterial();
  check(!!mat.getBaseColorTexture() && !!mat.getNormalTexture() && !!mat.getMetallicRoughnessTexture(), `${c.id}: three textures connected`);
  for (const t of [mat.getBaseColorTexture(), mat.getNormalTexture(), mat.getMetallicRoughnessTexture()]) {
    const size = t?.getSize();
    check(!!size && size[0] <= 1024, `${c.id}: texture ${size?.join('x')} within 1024 px`);
  }
  console.log(`${failures ? '…' : 'PASS'} ${c.id}: ${nodes.length} nodes, ${tris} triangles, ${W.getCount()} vertices`);
}
console.log(failures ? `\n${failures} FAILURES` : `\nALL ${list.characters.length} CHARACTERS PASS`);
process.exit(failures ? 1 : 0);
