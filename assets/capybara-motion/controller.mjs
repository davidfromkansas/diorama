import * as THREE from '../capybara/viewer/vendor/three.module.js';

const angleDelta = (a, b) => Math.atan2(Math.sin(b-a), Math.cos(b-a));
const approach = (value, target, amount) => value + Math.max(-amount, Math.min(amount, target-value));

/** Semantic P0 controller. The outer group owns travel; clips own local pose.
 * Supply a path from the host navigator with followPath(), or use moveTo() on clear floor.
 * No bone access is required by callers. Distances are metres; +Z is forward.
 */
export class CapybaraMotion {
  constructor(model, clips, manifest) {
    for (const name of ['idle','walk','run']) {
      if (!clips.some(c=>c.name===name)) throw new Error(`Missing required clip: ${name}`);
    }
    this.root = new THREE.Group();
    this.root.name = 'CapybaraMotionRoot';
    this.root.add(model);
    this.model = model;
    this.mixer = new THREE.AnimationMixer(model);
    this.actions = Object.fromEntries(clips.map(c=>[c.name,this.mixer.clipAction(c).play()]));
    this.speeds = Object.fromEntries(manifest.clips.map(c=>[c.name,c.nominalSpeed]));
    this.velocity = 0;
    this.phase = 0;
    this.weights = {idle:1,walk:0,run:0};
    this.path = [];
    this.mode = 'walk';
    this.state = 'idle';
    this.turnTarget = null;
    this.reducedMotion = false;
    this.elapsed = 0;
    this.update(0);
  }
  moveTo(position, {gait='walk'}={}) { this.followPath([position], {gait}); }
  followPath(points, {gait='walk'}={}) {
    if (!['walk','run'].includes(gait)) throw new Error('Gait must be walk or run');
    const path = points.map(p=>{
      if (![p.x,p.y,p.z].every(Number.isFinite)) throw new Error('Destination must be a finite world-space point');
      if (Math.abs(p.y-this.root.position.y)>.001) throw new Error('P0 navigation requires a level floor');
      return new THREE.Vector3(p.x,p.y,p.z);
    });
    this.path=path; this.mode=gait; this.turnTarget=null;
  }
  setGait(gait) {
    if (!['walk','run'].includes(gait)) throw new Error('Gait must be walk or run');
    this.mode=gait;
  }
  stop() { this.path=[]; this.turnTarget=null; }
  turnTo(yaw) {
    if (!Number.isFinite(yaw)) throw new Error('Yaw must be finite');
    this.path=[];this.turnTarget=yaw;
  }
  update(dt) {
    if (!Number.isFinite(dt)||dt<0) throw new Error('Delta time must be finite and nonnegative');
    // Substeps preserve acceleration, arrival, and turn behavior after a delayed frame.
    let remaining=Math.min(dt,.25);
    do { const step=Math.min(remaining,1/60);this.step(step);remaining-=step; } while(remaining>1e-8);
  }
  step(dt) {
    this.elapsed+=dt;
    let distance=0, heading=this.turnTarget, target=this.path[0];
    if (target) {
      distance=this.root.position.distanceTo(target);
      if(distance<.003 && this.velocity<.015){this.root.position.copy(target);this.path.shift();target=this.path[0];distance=target?this.root.position.distanceTo(target):0;}
      if(target)heading=Math.atan2(target.x-this.root.position.x,target.z-this.root.position.z);
    }
    const delta=heading===null?0:angleDelta(this.root.rotation.y,heading);
    const turn=Math.max(-dt*2.4,Math.min(dt*2.4,delta));
    this.root.rotation.y+=turn;
    if(this.turnTarget!==null&&Math.abs(delta)<.005)this.turnTarget=null;
    const maxSpeed=this.speeds[this.mode], acceleration=.8;
    const desired=target?Math.min(maxSpeed,Math.sqrt(2*acceleration*distance))*Math.max(0,Math.cos(delta))**4:0;
    this.velocity=approach(this.velocity,desired,acceleration*dt);
    if(this.velocity>0){
      const travel=Math.min(this.velocity*dt,target?distance:Infinity);
      this.root.position.x+=Math.sin(this.root.rotation.y)*travel;
      this.root.position.z+=Math.cos(this.root.rotation.y)*travel;
    }
    const turning=Math.abs(delta)>.04&&this.velocity<.025;
    const poseSpeed=Math.max(this.velocity,turning?this.speeds.walk*.65:0);
    const activity=Math.min(1,poseSpeed/this.speeds.walk);
    const run=Math.max(0,Math.min(1,(poseSpeed-this.speeds.walk)/(this.speeds.run-this.speeds.walk)));
    const desiredWeights={idle:1-activity,walk:activity*(1-run),run:activity*run};
    const alpha=1-Math.exp(-dt/0.10);
    for(const n of Object.keys(this.weights)) this.weights[n]+=(desiredWeights[n]-this.weights[n])*alpha;
    const cycleSpeed=(1-run)*this.speeds.walk+run*this.speeds.run;
    const duration=(1-run)*1.2+run*.7;
    this.phase=(this.phase+dt/duration*Math.min(1.8,poseSpeed/cycleSpeed))%1;
    for(const [name,action] of Object.entries(this.actions)){
      action.enabled=true;action.setEffectiveWeight(this.weights[name]??0);
      action.time=name==='idle'?(this.reducedMotion?0:this.elapsed%action.getClip().duration):this.phase*action.getClip().duration;
    }
    // Sampling all locomotion clips at one phase prevents opposing feet during blends.
    this.mixer.update(0);
    this.state=turning?'turning':this.velocity>.01?(this.mode==='run'&&run>.5?'running':'walking'):target?'starting':'idle';
    if(!target&&this.velocity>.01)this.state='stopping';
    this.root.updateMatrixWorld(true);
  }
  get debug() { return {state:this.state,speed:this.velocity,phase:this.phase,weights:{...this.weights},remainingWaypoints:this.path.length}; }
  dispose() { this.mixer.stopAllAction();this.mixer.uncacheRoot(this.model); }
}
