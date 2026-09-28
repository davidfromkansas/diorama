import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import * as THREE from '../capybara/viewer/vendor/three.module.js';
import {CapybaraMotion} from './controller.mjs';
const manifest=JSON.parse(fs.readFileSync(new URL('./manifest.json',import.meta.url)));
const make=()=>new CapybaraMotion(new THREE.Group(),manifest.clips.map(c=>new THREE.AnimationClip(c.name,c.duration,[])),manifest);
function advance(m,seconds,fps=60){for(let i=0;i<seconds*fps;i++){m.update(1/fps);assert.ok(Number.isFinite(m.root.position.x));assert.ok(Math.abs(Object.values(m.weights).reduce((a,b)=>a+b)-1)<1e-8);}}
for(const gait of ['walk','run'])for(const fps of [30,60,120])test(`${gait} arrives behind starting orientation at ${fps} fps`,()=>{
 const m=make(),target=new THREE.Vector3(.4,0,-.6);m.moveTo(target,{gait});advance(m,18,fps);assert.equal(m.path.length,0);assert.ok(m.root.position.distanceTo(target)<.005);assert.equal(m.state,'idle');
});
test('stop decelerates and interrupted turns retarget continuously',()=>{const m=make();m.moveTo(new THREE.Vector3(0,0,3),{gait:'run'});advance(m,2);const before=m.velocity;m.stop();m.update(1/60);assert.ok(m.velocity>0&&m.velocity<before);advance(m,2);assert.equal(m.velocity,0);m.turnTo(Math.PI);advance(m,.3);const yaw=m.root.rotation.y;m.turnTo(-Math.PI/2);m.update(1/60);assert.ok(Math.abs(m.root.rotation.y-yaw)<.05);advance(m,3);assert.ok(Math.abs(m.root.rotation.y+Math.PI/2)<.01);});
test('path completes, invalid commands preserve current path',()=>{const m=make();m.followPath([new THREE.Vector3(.2,0,0),new THREE.Vector3(.2,0,.2)]);assert.throws(()=>m.moveTo(new THREE.Vector3(NaN,0,0)));assert.equal(m.path.length,2);assert.throws(()=>m.moveTo(new THREE.Vector3(0,1,0)));advance(m,15);assert.equal(m.path.length,0);assert.ok(m.root.position.distanceTo(new THREE.Vector3(.2,0,.2))<.005);});
test('pause and delayed frames stay finite; missing clips fail visibly',()=>{const m=make();m.moveTo(new THREE.Vector3(0,0,1));m.update(0);assert.equal(m.velocity,0);m.update(30);assert.ok(m.velocity<=.2);assert.throws(()=>m.update(NaN));assert.throws(()=>new CapybaraMotion(new THREE.Group(),[],manifest));});
test('walk/run changes preserve gait phase and decelerate smoothly',()=>{const m=make();m.moveTo(new THREE.Vector3(0,0,10));advance(m,2);const phase=m.phase,speed=m.velocity;m.setGait('run');assert.equal(m.phase,phase);m.update(1/60);assert.ok(m.velocity>speed&&m.velocity-speed<.02);advance(m,2);assert.ok(m.weights.run>.95);m.setGait('walk');advance(m,3);assert.ok(m.weights.walk>.99);});
