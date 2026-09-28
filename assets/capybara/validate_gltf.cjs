// npm install && npm run validate (development only; the viewer needs no install).
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const validator = require('gltf-validator');
const root = __dirname;
async function main() {
  const bytes = fs.readFileSync(path.join(root, 'capybara.glb'));
  const doc = JSON.parse(bytes.subarray(20, 20 + bytes.readUInt32LE(12)).toString());
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
  assert.deepEqual(doc.animations.map(a => a.name).sort(), manifest.clips.map(c => c.name).sort());
  for (const clip of manifest.clips) {
    const animation = doc.animations.find(a => a.name === clip.name);
    const end = Math.max(...animation.samplers.map(s => doc.accessors[s.input].max[0]));
    const start = Math.min(...animation.samplers.map(s => doc.accessors[s.input].min[0]));
    assert.ok(Math.abs(start) < 1e-6, `${clip.name} starts at ${start}`);
    assert.ok(Math.abs(end - clip.duration) < 1e-5, `${clip.name} duration ${end}`);
    assert.equal(animation.extras.loop, clip.loop);
  }
  const face = doc.meshes.find(m => m.extras?.targetNames);
  assert.deepEqual(face.extras.targetNames, manifest.morphs);
  for (const image of doc.images) {
    assert.equal(image.uri, undefined, 'Texture must be embedded');
    assert.equal(typeof image.bufferView, 'number');
  }
  const triangles = doc.meshes.flatMap(m => m.primitives).reduce((sum, p) => sum + doc.accessors[p.indices].count / 3, 0);
  assert.equal(triangles, manifest.triangles);
  assert.ok(triangles <= 30000);
  const report = await validator.validateBytes(new Uint8Array(bytes), {uri: 'capybara.glb', maxIssues: 100});
  fs.writeFileSync(path.join(root, 'validation_gltf.json'), JSON.stringify(report, null, 2) + '\n');
  assert.equal(report.issues.numErrors, 0);
  assert.equal(report.issues.numWarnings, 0);
  console.log(`${triangles} triangles; ${doc.animations.length} clips; ${manifest.morphs.length} morphs; embedded textures; zero glTF errors/warnings.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
