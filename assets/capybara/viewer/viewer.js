import * as THREE from 'three';
import { GLTFLoader } from './vendor/GLTFLoader.js';
import { OrbitControls } from './vendor/OrbitControls.js';
const $=id=>document.getElementById(id),stage=$('stage');
const renderer=new THREE.WebGLRenderer({antialias:true,alpha:false});renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.shadowMap.enabled=true;renderer.shadowMap.type=THREE.PCFSoftShadowMap;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.05;stage.prepend(renderer.domElement);renderer.domElement.setAttribute('aria-label','Drag to rotate the 3D capybara');
const scene=new THREE.Scene();scene.background=new THREE.Color('#f0ece5');scene.fog=new THREE.Fog('#f0ece5',5,14);
const camera=new THREE.OrthographicCamera(-1,1,.72,-.72,.01,40);camera.position.set(1.55,1.0,2.5);
const controls=new OrbitControls(camera,renderer.domElement);controls.target.set(0,.48,0);controls.enableDamping=true;controls.minZoom=.5;controls.maxZoom=3.5;controls.maxPolarAngle=Math.PI*.52;controls.autoRotateSpeed=.65;
scene.add(new THREE.HemisphereLight('#ffefdc','#c5bbae',1.3));
const key=new THREE.DirectionalLight('#fff1dc',1.8);key.position.set(-2,4,3);key.castShadow=true;key.shadow.mapSize.set(2048,2048);Object.assign(key.shadow.camera,{left:-1.5,right:1.5,top:1.8,bottom:-1.2,near:.1,far:12});key.shadow.normalBias=.006;key.shadow.bias=-.0002;scene.add(key);
const fill=new THREE.DirectionalLight('#eaf0ff',.65);fill.position.set(3,2,-2);scene.add(fill);
const ground=new THREE.Mesh(new THREE.PlaneGeometry(200,200),new THREE.MeshStandardMaterial({color:'#e9e2d8',roughness:1}));ground.rotation.x=-Math.PI/2;ground.position.y=-.002;ground.receiveShadow=true;scene.add(ground);
const grid=new THREE.GridHelper(4,40,'#c4ae95','#dacbb9');grid.material.transparent=true;grid.material.opacity=.45;grid.position.y=.0005;grid.visible=false;scene.add(grid);
// Reference-scale interaction props. They are deliberately excluded from the GLB.
const props=new THREE.Group();scene.add(props);props.visible=false;
const wood=new THREE.MeshStandardMaterial({color:'#ba9470',roughness:.8}),metal=new THREE.MeshStandardMaterial({color:'#4b514b',roughness:.65});
function box(w,h,d,x,y,z,mat,parent=props){const m=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),mat);m.position.set(x,y,z);m.castShadow=m.receiveShadow=true;parent.add(m);return m;}
box(.62,.025,.30,0,.46,.35,wood);for(const x of [-.27,.27])for(const z of [.23,.47])box(.025,.44,.025,x,.22,z,metal);
box(.30,.025,.26,0,.115,-.02,wood);box(.30,.28,.025,0,.24,-.15,wood);for(const x of [-.13,.13])for(const z of [-.12,.08])box(.019,.11,.019,x,.055,z,metal);
const laptop=new THREE.MeshStandardMaterial({color:'#777a79',metalness:.4,roughness:.4});box(.22,.009,.15,0,.479,.33,laptop);const lid=box(.22,.14,.009,0,.545,.395,laptop);lid.rotation.x=-.16;
const object=new THREE.Group();scene.add(object);object.visible=false;box(.15,.055,.11,0,0,0,new THREE.MeshStandardMaterial({color:'#849880',roughness:.9}),object);
let model,mixer,current,skeleton,manifest,clips=[],morphMeshes=[],bones={},playing=true,sequence=null,sequenceElapsed=0,elapsed=0;
const label=name=>name.replaceAll('_',' ').replace(/\b\w/g,c=>c.toUpperCase());
const positions={front:[0,.53,2.7],back:[0,.53,-2.7],left:[2.7,.53,0],right:[-2.7,.53,0],quarter:[1.55,1.0,2.5],rear:[-1.55,1.0,-2.5]};
function selectView(name){camera.position.set(...positions[name]);controls.target.set(0,.49,0);controls.update();document.querySelectorAll('[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===name));}
document.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>selectView(b.dataset.view)));
const seatedVariants=new Map();
function seatedVariant(name){
 if(!seatedVariants.has(name)){
  const source=clips.find(c=>c.name===name),sit=clips.find(c=>c.name==='sit_idle');
  const lower=t=>/^(root|pelvis|upper_leg|lower_leg|foot)/.test(t.name);
  seatedVariants.set(name,new THREE.AnimationClip(name+'_seated',source.duration,[...source.tracks.filter(t=>!lower(t)).map(t=>t.clone()),...sit.tracks.filter(lower).map(t=>t.clone())]));
 }
 return seatedVariants.get(name);
}
function setClip(name,fade=Number($('fade').value),seated=false){
 const clip=seated?seatedVariant(name):clips.find(c=>c.name===name);if(!clip)return;const next=mixer.clipAction(clip),meta=manifest.clips.find(c=>c.name===name);
 next.reset().setEffectiveTimeScale(1).setEffectiveWeight(1);next.setLoop(meta.loop?THREE.LoopRepeat:THREE.LoopOnce,meta.loop?Infinity:1);next.clampWhenFinished=!meta.loop;next.play();
 if(current&&current!==next){if(fade>0)next.crossFadeFrom(current,fade,false);else current.stop();}current=next;
 $('clip').value=name;$('timeline').max=clip.duration;$('clipHint').textContent=`${clip.duration.toFixed(2)} s · ${meta.loop?'Seamless loop':'One shot · holds final pose'} · In place`;
 $('status').textContent=label(name)+(seated?' · seated':'');if(!playing){playing=true;$('play').textContent='Pause';}
}
function applyFace(){
 const chosen=$('expression').value,expr=chosen==='neutral'&&current?.getClip().name==='sleep'?'content':chosen,amount=Number($('strength').value);
 const speech=$('speech').checked ? (.35+.65*Math.max(0,Math.sin(elapsed*12)))*.7 : 0;
 const blink=$('blink').checked?Math.max(0,1-Math.abs((elapsed%4.1)-3.8)/.085):0;
 for(const m of morphMeshes){m.morphTargetInfluences.fill(0);const map=m.morphTargetDictionary;
  if(expr!=='neutral'&&map[expr]!==undefined)m.morphTargetInfluences[map[expr]]=amount;
  if(speech&&map.talk_open!==undefined){for(const n of ['talk_open','talk_small','surprised','big_smile'])if(map[n]!==undefined)m.morphTargetInfluences[map[n]]=0;m.morphTargetInfluences[map.talk_open]=speech;}
  if(blink&&map.blink_both!==undefined){for(const n of ['blink_left','blink_right','blink_both','content'])if(map[n]!==undefined)m.morphTargetInfluences[map[n]]=0;m.morphTargetInfluences[map.blink_both]=blink;}
 }
}
try{
 manifest=await fetch('../manifest.json').then(r=>{if(!r.ok)throw new Error('Manifest missing');return r.json()});
 const gltf=await new GLTFLoader().loadAsync('../capybara.glb');model=gltf.scene;scene.add(model);clips=gltf.animations;mixer=new THREE.AnimationMixer(model);
 model.traverse(o=>{if(o.isMesh){o.castShadow=true;o.receiveShadow=true;if(o.morphTargetDictionary)morphMeshes.push(o);}if(o.isBone)bones[o.name.replaceAll('.','')]=o;});
 skeleton=new THREE.SkeletonHelper(model);skeleton.material.depthTest=false;skeleton.material.transparent=true;skeleton.material.opacity=.85;skeleton.renderOrder=10;skeleton.visible=false;scene.add(skeleton);
 $('clip').replaceChildren(...clips.map(c=>new Option(label(c.name),c.name)));$('expression').replaceChildren(...manifest.morphs.map(n=>new Option(label(n),n)));
 for(const id of ['clip','expression','play','restart','rest','sequence'])$(id).disabled=false;
 $('metrics').textContent=`${manifest.triangles.toLocaleString()} triangles · ${manifest.bones} joints\n${clips.length} body clips · ${manifest.morphs.length} facial targets\n1.0 m tall · Y up · +Z forward`;
 const tree=(name,depth=0)=>'  '.repeat(depth)+name+'\n'+Object.entries(manifest.skeleton).filter(([_,b])=>b.parent===name).map(([n])=>tree(n,depth+1)).join('');$('hierarchy').textContent=tree('root');
 $('loading').hidden=true;setClip('idle',0);
 // Read-only runtime inspection surface used by the validation harness.
 window.capybaraStudio={scene,model,mixer,clips,manifest,morphMeshes,bones,setClip,applyFace,selectView,get current(){return current},get renderer(){return renderer}};
}catch(error){$('loading').textContent=`Could not load character: ${error.message}. Run the included serve.py and open its local URL.`;console.error(error);}
$('clip').addEventListener('change',()=>{sequence=null;setClip($('clip').value)});
$('play').addEventListener('click',()=>{playing=!playing;$('play').textContent=playing?'Pause':'Play'});
$('restart').addEventListener('click',()=>{if(current){current.reset().play();playing=true;$('play').textContent='Pause'}});
$('rest').addEventListener('click',()=>{sequence=null;mixer.stopAllAction();current=null;model.traverse(o=>{if(o.isSkinnedMesh)o.skeleton.pose()});$('status').textContent='Canonical T-pose';$('timeValue').textContent='Rest pose';});
for(const [id,out,format] of [['speed','speedValue',v=>Number(v).toFixed(2)+'×'],['fade','fadeValue',v=>Number(v).toFixed(2)+' s'],['strength','strengthValue',v=>Math.round(v*100)+'%']])$(id).addEventListener('input',()=>$(out).textContent=format($(id).value));
$('timeline').addEventListener('input',()=>{if(current){playing=false;$('play').textContent='Play';current.paused=false;current.time=Number($('timeline').value);mixer.update(0);}});
$('rig').addEventListener('change',()=>{if(skeleton)skeleton.visible=$('rig').checked});$('wire').addEventListener('change',()=>{model?.traverse(o=>{if(o.isMesh)for(const m of (Array.isArray(o.material)?o.material:[o.material]))m.wireframe=$('wire').checked;})});
$('grid').addEventListener('change',()=>grid.visible=$('grid').checked);$('rotate').addEventListener('change',()=>controls.autoRotate=$('rotate').checked);$('props').addEventListener('change',()=>props.visible=$('props').checked);$('object').addEventListener('change',()=>object.visible=$('object').checked);
$('sequence').addEventListener('click',()=>{sequence=[['walk',2.4],['sit_down',1.4],['type_at_computer',4],['think',4,true],['type_at_computer',4],['stand_up',1.4],['celebrate',2.6],['idle',4]];sequenceElapsed=0;setClip(sequence[0][0]);});
const resize=()=>{const w=stage.clientWidth,h=stage.clientHeight;renderer.setSize(w,h);camera.left=-.72*w/h;camera.right=.72*w/h;camera.updateProjectionMatrix()};new ResizeObserver(resize).observe(stage);resize();
const clock=new THREE.Clock(),left=new THREE.Vector3(),right=new THREE.Vector3();
renderer.setAnimationLoop(()=>{const dt=Math.min(clock.getDelta(),.08),scaled=playing?dt*Number($('speed').value):0;elapsed+=scaled;
 if(mixer){mixer.update(scaled);applyFace();if(current){$('timeline').value=current.time;$('timeValue').textContent=`${current.time.toFixed(2)} / ${current.getClip().duration.toFixed(2)} s`;}
 if(sequence){sequenceElapsed+=scaled;if(sequenceElapsed>=sequence[0][1]){sequenceElapsed-=sequence[0][1];sequence.shift();if(sequence.length)setClip(sequence[0][0],Number($('fade').value),sequence[0][2]||false);else sequence=null;}}
 if(object.visible&&bones.handL&&bones.handR){bones.handL.getWorldPosition(left);bones.handR.getWorldPosition(right);object.position.copy(left).add(right).multiplyScalar(.5);object.position.z+=.03;}
 }controls.update();renderer.render(scene,camera);
});
