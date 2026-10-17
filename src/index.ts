import { Engine } from '@babylonjs/core/Engines/engine';
import { Scene } from '@babylonjs/core/scene';
import { ArcRotateCamera } from '@babylonjs/core/Cameras/arcRotateCamera';
import { Vector3, Matrix } from '@babylonjs/core/Maths/math.vector';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { MeshBuilder } from '@babylonjs/core/Meshes/meshBuilder';
import { Color3 } from '@babylonjs/core/Maths/math.color';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import { LinesMesh } from '@babylonjs/core/Meshes/linesMesh';
import { PointerEventTypes } from '@babylonjs/core/Events/pointerEvents';
import '@babylonjs/core/Culling/ray';
import { ActorRenderer, type ActorRole } from './actors';
import { SourceHotelWorld } from './world/source-map';
import { CameraController } from './camera';
import { createGameFlow } from './flow';
import { createBattle, createBattleRules, currentUnit, chooseEnemyCommand, type BattleState, type Command, type BattleEvent, type Unit } from './rules';
import { PARTY_SPAWNS, ENEMY_SPAWNS, ENCOUNTER_TRIGGER, INTERACTIONS, distance, inRect, type Point, type Interaction } from './shared';
import { renderHud, type HotbarTab } from './ui/hud';
import { updateMinimap as refreshMinimap } from './ui/minimap';
import './style.css';

const canvas = document.getElementById('renderCanvas') as HTMLCanvasElement;
const ui = document.getElementById('ui')!;
const flow = createGameFlow();
const partyIds = ['amiya', 'hoshiguma', 'ansel'];
let engine: Engine;
let scene: Scene;
let camera: ArcRotateCamera;
let cameraControl: CameraController;
let world: SourceHotelWorld;
let actors: ActorRenderer;
let rules: ReturnType<typeof createBattleRules>;
let battle: BattleState | null = null;
let checkpoint: BattleState | null = null;
let selected = 'amiya';
let intent: 'move' | 'attack' | 'skill' = 'move';
let checkedIn = false;
let supplies = false;
let cleared = false;
let gardenUnlocked = false;
let help = false;
let dialogue = '';
let hotbarTab: HotbarTab = 'common';
let mapZoom = 2;
let invalidTimer: ReturnType<typeof setTimeout>;
let pathLine: LinesMesh | null = null;
let targetRing: Mesh;
let areaRing: Mesh;
let rangeRing: Mesh;
let effectTime = 0;
let actionSpeed = 1;
let aiRunning = false;
let following = true;
let activeNavigation = 0;
let playEpoch = 0;
let nearest: Interaction | null = null;
const movementJobs = new Map<string, { path: Point[]; segment: number; speed: number; blockedTime?: number; resolve: (arrived: boolean) => void }>();
const followTrail: Point[] = [];
let followTick = 0;
let minimapTick = 0;
let lastHover = 0;
const mode = () => String(flow.getSnapshot().value);
const isBattle = () => mode() === 'battle' || mode() === 'presenting';
const unit = (id: string) => battle?.units.find(u => u.id === id);
const active = () => battle ? currentUnit(battle) : null;
function notify(_reason: string) {
 canvas.classList.add('invalid-action'); clearTimeout(invalidTimer);
 invalidTimer = setTimeout(()=>canvas.classList.remove('invalid-action'),300);
}
function setLoading(_text: string) { renderUI(); }
function focusPoint(): Point { return actors ? actors.getPosition(isBattle() ? active()?.id ?? selected : selected) : PARTY_SPAWNS[0]; }

function renderUI() {
 const party = battle?.units.filter(u=>u.team==='party') ?? createBattle(PARTY_SPAWNS).units.filter(u=>u.team==='party');
 ui.innerHTML = renderHud({mode:mode(),battle,party,active:active(),selected,intent,checkedIn,supplies,cleared,
  nearest:nearest?.id??null,paused:help,dialogue,speed:actionSpeed,tab:hotbarTab,canRetry:!!checkpoint,inventory:hotbarTab==='items'});
 updateMinimap();
}
function updateMinimap() {
 if(!actors || !camera) return;
 const units = battle && isBattle() ? battle.units.filter(u=>u.hp>0).map(u=>({id:u.id,team:u.team,selected:u.id===selected,point:actors.getPosition(u.id)})) : partyIds.map(id=>({id,team:'party' as const,selected:id===selected,point:actors.getPosition(id)}));
 refreshMinimap({positions:units,focus:focusPoint(),zoom:mapZoom,heading:camera.alpha});
}

function clearPreview() { pathLine?.dispose(); pathLine = null; if (targetRing) targetRing.setEnabled(false); if (areaRing) areaRing.setEnabled(false); }
function showPath(path: Point[], valid = true) {
 pathLine?.dispose();
 pathLine = MeshBuilder.CreateLines('approved-path', { points: path.map(p => new Vector3(p.x, world.heightAt(p)+.18, p.z)) }, scene);
 pathLine.color = Color3.FromHexString(valid ? '#e8d2a0' : '#ed8f7b'); pathLine.isPickable = false;
 const last = path[path.length - 1]; targetRing.position.set(last.x, world.heightAt(last)+.13, last.z); targetRing.setEnabled(true); targetRing.scaling.setAll(1);
}
function stopMovements() { for (const [id, job] of movementJobs) { job.resolve(false); actors.setAnimation(id, 'idle'); } movementJobs.clear(); }
function walk(id: string, path: Point[], speed = 5): Promise<boolean> {
 const old = movementJobs.get(id); if (old) old.resolve(false);
 if (path.length < 2) return Promise.resolve(true);
 return new Promise(resolve => { movementJobs.set(id, { path, segment: 1, speed, resolve }); actors.setAnimation(id, 'move'); });
}
async function exploreMove(to: Point) {
 if (mode() !== 'exploring' || help) return;
 const path = world.navigation.findPath(actors.getPosition(selected), to);
 if (!path) { notify(world.navigation.doorOpen ? '此处不可达，请选择可通行的地面。' : '路线被阻挡。先开启庭院通行点。'); return; }
 const token = ++activeNavigation;
 following = true; cameraControl.follow(true); followTrail.length = 0; followTrail.push(actors.getPosition(selected));
 showPath(path); 
 await walk(selected, path);
 if (token === activeNavigation && mode() === 'exploring') { clearPreview();  }
}
function followLeader(dt: number) {
 if (!following || mode() !== 'exploring') return;
 followTick += dt;
 const leader = actors.getPosition(selected);
 if (!followTrail.length || distance(followTrail[followTrail.length - 1], leader) > .35) followTrail.push({ ...leader });
 while (followTrail.length > 150) followTrail.shift();
 if (followTick < .5) return; followTick = 0;
 const followers = partyIds.filter(id => id !== selected);
 followers.forEach((id, index) => {
  let remaining = 1.8 + index * 1.7; let target = followTrail[0];
  for (let i = followTrail.length - 1; i > 0; i--) { remaining -= distance(followTrail[i], followTrail[i - 1]); target = followTrail[i - 1]; if (remaining <= 0) break; }
  const here = actors.getPosition(id);
  if (distance(here, target) < .6) return;
  const blockers = partyIds.filter(who => who !== id).map(who => ({...actors.getPosition(who),radius:.45}));
  const candidates = [target, ...[0,Math.PI/2,Math.PI,Math.PI*1.5].map(angle => ({x:target.x+Math.cos(angle)*1.1,z:target.z+Math.sin(angle)*1.1}))];
  const path = candidates.map(p => world.navigation.findPath(here,p,blockers)).find(Boolean);
  if (path) void walk(id, path, 5.7);
 });
}
async function interact(id: Interaction['id']) {
 if (mode() !== 'exploring') return;
 const token = ++activeNavigation;
 const entry = INTERACTIONS.find(i => i.id === id)!;
 let target: Point = entry;
 if (id === 'door') target = entry;
 if (distance(actors.getPosition(selected), entry) > entry.radius || id === 'door' && !world.navigation.doorOpen) {
  const path = world.navigation.findPath(actors.getPosition(selected), target);
  if (!path) { notify('暂时无法抵达该交互点。'); return; }
  following = true; cameraControl.follow(true); followTrail.length = 0; followTrail.push(actors.getPosition(selected)); showPath(path);
  const arrived = await walk(selected, path);
  if (!arrived) return;
 }
 if (token !== activeNavigation || mode() !== 'exploring' || distance(actors.getPosition(selected), entry) > entry.radius + .1) return;
 clearPreview();
 if (id === 'reception') {
  stopMovements(); dialogue = '“欢迎各位。房间已经准备好了，庭院就在木廊尽头。”<br><br>接待员递来房卡，又指了指一旁的补给处：<br>“带上这些旅行用品吧。庭院里似乎来了几位不速之客，请多留意。”';
  checkedIn = true;  flow.send({ type: 'DIALOGUE' }); renderUI();
 } else if (id === 'door') {
  if (!checkedIn) { notify('需要先向接待员领取房卡。'); return; }
  world.setDoorOpen(true); gardenUnlocked = true;   renderUI();
 } else {
  if (supplies) { notify('旅行补给已经领取。'); return; }
  supplies = true; renderUI();
 }
}
async function nextObjective() {
 if (mode() !== 'exploring') return;
 if (!checkedIn) return interact('reception');
 if (!supplies) return interact('supply');
 if (!gardenUnlocked) { const expected = activeNavigation + 1; await interact('door'); if (activeNavigation !== expected || !gardenUnlocked) return; }
 if (mode() === 'exploring') await exploreMove({ x: cleared ? 31 : 26.1667, z: cleared ? 14 : 16.8333 });
}
async function beginEncounter() {
 if (mode() !== 'exploring' || cleared) return;
 activeNavigation++; stopMovements(); clearPreview(); following = false;
 const epoch=playEpoch;
 flow.send({ type: 'ENCOUNTER' }); renderUI();
 const occupied: Point[] = ENEMY_SPAWNS.map(p=>({...p}));
 // Exploration companions can pass one another; combat begins with legal separated positions.
 for (const id of partyIds) {
  const here = actors.getPosition(id);
  if (!occupied.some(p => distance(p,here) < .94)) { occupied.push(here); continue; }
  const candidates = [1,1.5,2,2.5].flatMap(radius => Array.from({length:12},(_,i)=>({x:here.x+Math.cos(i*Math.PI/6)*radius,z:here.z+Math.sin(i*Math.PI/6)*radius})));
  const target = candidates.find(p=>world.navigation.isWalkable(p) && occupied.every(q=>distance(p,q)>=.94) && !!world.navigation.findPath(here,p));
  if (target) { await walk(id,world.navigation.findPath(here,target)!,4); if(epoch!==playEpoch)return; occupied.push(actors.getPosition(id)); }
  else occupied.push(here);
 }
 if(epoch!==playEpoch)return;
 battle = createBattle(partyIds.map(id => actors.getPosition(id)));
 checkpoint = structuredClone(battle);
 for (const u of battle.units.filter(u => u.team === 'enemy')) actors.add(u.id, u.role as ActorRole, u.position, 'enemy');
 selected = 'amiya'; intent = 'move'; hotbarTab='common'; 
 flow.send({ type: 'FORMATION_READY' }); cameraControl.setMode('battle'); syncActors();  renderUI();
}

function syncActors() {
 if (!battle) return;
 for (const u of battle.units) { actors.setPosition(u.id, u.position); actors.setHp(u.id, u.hp, u.maxHp); actors.setSelected(u.id, u.id === selected); if (u.hp <= 0) actors.setAnimation(u.id, 'death'); }
}
function selectUnit(id: string) {
 if (isBattle()) {
  if (intent === 'skill' && active()?.role === 'healer' && unit(id)?.team === 'party') { void command({ type: 'skill', unitId: active()!.id, targetId: id }); return; }
  const target = unit(id);
  if (target?.team === 'enemy') {
   const a = active(); if (mode() !== 'battle' || a?.team !== 'party') return;
   void command(intent === 'skill' ? { type: 'skill', unitId: a.id, targetId: id } : { type: 'attack', unitId: a.id, targetId: id }); return;
  }
  if (target) { selected = id; cameraControl.focus(target.position); if (active()?.id !== id) cameraControl.follow(false);  }
 } else if (mode() === 'exploring') { activeNavigation++; stopMovements(); clearPreview(); selected = id; followTrail.length = 0; followTrail.push(actors.getPosition(id)); }
 for (const who of partyIds) actors.setSelected(who, who === selected); renderUI();
}
async function animateEvents(events: BattleEvent[]) {
 for (const e of events) {
  if (e.type === 'move' && e.unitId && e.path) { showPath(e.path); await walk(e.unitId, e.path, actionSpeed === 99 ? 10000 : 5.5 * actionSpeed); clearPreview(); }
  if (e.type === 'attack' || e.type === 'skill' || e.type === 'opportunity') {
   if (e.unitId) actors.setAnimation(e.unitId, e.type === 'skill' ? 'skill' : 'attack');
   if (e.unitId && e.targetId) { const from = actors.getPosition(e.unitId), to = actors.getPosition(e.targetId); actors.setFacing(e.unitId, { x: to.x - from.x, z: to.z - from.z }); }
   if (actionSpeed !== 99) await new Promise(resolve => setTimeout(resolve, 180 / actionSpeed));
  }
  if ((e.type === 'damage' || e.type === 'heal') && e.targetId) { pulse(actors.getPosition(e.targetId), e.type === 'heal' ? '#9be2b3' : '#eab083'); actors.setAnimation(e.targetId, 'hurt'); }
  if (e.type === 'death' && e.unitId) actors.setAnimation(e.unitId, 'death');
 }
 if (actionSpeed !== 99 && events.some(e => e.type !== 'endTurn' && e.type !== 'turn')) await new Promise(resolve => setTimeout(resolve, 250 / actionSpeed));
 syncActors();
 if (battle) for (const u of battle.units) if (u.hp > 0) actors.setAnimation(u.id, 'idle');
}

function pulse(p: Point, color: string) {
 const ring = MeshBuilder.CreateTorus('action-pulse', { diameter: 2, thickness: .055, tessellation: 32 }, scene); ring.position.set(p.x, world.heightAt(p)+.3, p.z);
 const mat = new StandardMaterial('pulse-material', scene); mat.emissiveColor = Color3.FromHexString(color); mat.disableLighting = true; ring.material = mat; ring.isPickable = false;
 let age = 0; const obs = scene.onBeforeRenderObservable.add(() => { age += engine.getDeltaTime() / 1000; ring.scaling.setAll(1 + age * 3); ring.visibility = Math.max(0, 1 - age * 2); if (age > .5) { scene.onBeforeRenderObservable.remove(obs); ring.dispose(); mat.dispose(); } });
}
async function command(c: Command) {
 if (!battle || mode() !== 'battle' || help) return false;
 const result = rules.applyCommand(battle, c);
 if (!result.ok) { notify(result.reason ?? '该指令无法执行'); return false; }
 // Commit the complete rules result once; presentation cannot alter this state.
 const epoch=playEpoch;
 battle = result.state; flow.send({ type: 'PLAY' }); clearPreview(); renderUI();
 await animateEvents(result.events);
 if(epoch!==playEpoch)return false;
 flow.send({ type: 'DONE' });
 if (battle.outcome) {
  flow.send({ type: battle.outcome === 'victory' ? 'VICTORY' : 'DEFEAT' });
  renderUI(); return true;
 }
 const a = active(); if (a?.team === 'party') selected = a.id;
 intent = 'move'; syncActors();  renderUI();
 if (a?.team === 'enemy' && !aiRunning) void runEnemyTurns();
 return true;
}
async function runEnemyTurns() {
 if (aiRunning) return; aiRunning = true;
 try {
  let safety = 0;
  while (mode() === 'battle' && active()?.team === 'enemy' && battle && safety++ < 50) {
   await new Promise(resolve => setTimeout(resolve, actionSpeed === 99 ? 0 : 300 / actionSpeed));
   if (help || mode() !== 'battle') break;
   const c = chooseEnemyCommand(battle, rules); if (!c) break;
   if (!await command(c)) { const a = active(); if (a) await command({ type: 'endTurn', unitId: a.id }); }
  }
 } finally { aiRunning = false; }
}
function resetEncounter() {
 if (!checkpoint) return;
 stopMovements(); battle = structuredClone(checkpoint); cleared = false;
 for (const u of battle.units) { actors.add(u.id, roleFor(u), u.position, u.team); }
 selected = 'amiya'; intent = 'move'; hotbarTab='common';
 if (mode() === 'defeat') flow.send({ type: 'RETRY' });
 else { flow.send({ type: 'ENCOUNTER' }); flow.send({type:'FORMATION_READY'}); }
  syncActors(); renderUI();
}
function roleFor(u: Unit): ActorRole { return u.team === 'party' ? u.id as ActorRole : u.role as ActorRole; }
function continueExploration() {
 if (!battle) return;
 cleared = true;
 for (const u of battle.units.filter(u => u.team === 'enemy')) actors.remove(u.id);
 // Rest after an encounter belongs to the exploration controller, outside battle rules.
 const positions = partyIds.map((id, i) => { const here = actors.getPosition(id); if (world.navigation.isWalkable(here) && battle!.units.find(u => u.id === id)!.hp > 0) return here; return { x: 21.1667 + i * 1.5, z: 23.1673 }; });
 const rested = createBattle(positions);
 battle = null;
 partyIds.forEach((id, i) => { actors.setPosition(id, positions[i]); const u = rested.units.find(u => u.id === id)!; actors.setHp(id, u.hp, u.maxHp); actors.setAnimation(id, 'idle'); });
 selected = 'amiya'; following = true; followTrail.length = 0; followTrail.push(positions[0]); flow.send({ type: 'CONTINUE' }); cameraControl.setMode('explore');   renderUI();
}
function action(name: string) {
 if (name === 'reload') return location.reload();
 if (name === 'mapZoom' || name === 'mapOut') { mapZoom = Math.max(2, Math.min(5, mapZoom+(name==='mapZoom'?1:-1))); updateMinimap(); return; }
 if (name === 'inventory') { hotbarTab = hotbarTab==='items'?'common':'items'; renderUI(); return; }
 if (name === 'title') { playEpoch++; activeNavigation++; stopMovements(); help=false; flow.send({type:'TITLE'}); renderUI(); return; }
 if (name === 'help') { help = !help; renderUI(); if (!help && mode() === 'battle' && active()?.team === 'enemy') void runEnemyTurns(); return; }
 if (name === 'focus') { cameraControl.focus(focusPoint()); return; }
 if (name === 'speed') { actionSpeed = actionSpeed === 1 ? 3 : actionSpeed === 3 ? 99 : 1; renderUI(); return; }
 if (name === 'start') { playEpoch++; activeNavigation++; stopMovements(); if(battle)for(const u of battle.units.filter(u=>u.team==='enemy'))actors.remove(u.id); battle=null;checkpoint=null; checkedIn=false;supplies=false;cleared=false;gardenUnlocked=false; world.setDoorOpen(false); selected='amiya'; following=true;followTrail.length=0; const fresh=createBattle(PARTY_SPAWNS); partyIds.forEach((id,i)=>{actors.setPosition(id,PARTY_SPAWNS[i]);const u=fresh.units.find(u=>u.id===id)!;actors.setHp(id,u.hp,u.maxHp);actors.setAnimation(id,'idle');actors.setSelected(id,id===selected);}); help=false; hotbarTab='common'; flow.send({ type: 'START' }); cameraControl.setMode('explore'); cameraControl.focus(focusPoint()); renderUI(); return; }
 if (name === 'closeDialogue') { flow.send({ type: 'CLOSE' }); renderUI(); return; }
 if (name === 'next') { void nextObjective(); return; }
 if (name === 'retry' || name === 'replay') { help=false; hotbarTab='common'; cameraControl.setMode('battle'); resetEncounter(); return; }
 if (name === 'continue') { continueExploration(); return; }
 if (mode() !== 'battle' || active()?.team !== 'party' || help) return;
 if (name === 'move' || name === 'attack' || name === 'skill') {
  intent = name;
  if (name === 'skill' && active()?.role === 'tank') { void command({ type: 'skill', unitId: active()!.id }); return; }
   renderUI(); return;
 }
 if (['dash', 'disengage', 'rally', 'endTurn'].includes(name)) void command({ type: name as 'dash' | 'disengage' | 'rally' | 'endTurn', unitId: active()!.id });
}
ui.addEventListener('click', e => {
 const target = e.target as HTMLElement;
 const button = target.closest<HTMLElement>('[data-action],[data-unit],[data-interaction],[data-tab]'); if (!button) return;
 if (button.dataset.tab) { hotbarTab=button.dataset.tab as HotbarTab; renderUI(); }
 else if (button.dataset.action) action(button.dataset.action);
 else if (button.dataset.unit) selectUnit(button.dataset.unit);
 else if (button.dataset.interaction) void interact(button.dataset.interaction as Interaction['id']);
});
window.addEventListener('keydown', e => {
 if (e.key === 'Escape') { if (help) help = false; if (mode() === 'dialogue') flow.send({ type: 'CLOSE' }); if (mode() === 'exploring') { activeNavigation++; stopMovements(); } if (!help && mode() === 'battle' && active()?.team === 'enemy') void runEnemyTurns(); intent = 'move'; clearPreview(); renderUI(); }
 if (e.key.toLowerCase() === 'e' && nearest && mode() === 'exploring') void interact(nearest.id);
 if (e.key === '?' || e.key.toLowerCase() === 'h') action('help');
 if (['1', '2', '3'].includes(e.key)) selectUnit(partyIds[Number(e.key) - 1]);
 if (e.key === ' ' && mode() === 'battle' && active()?.team === 'party') { e.preventDefault(); action('endTurn'); }
});
canvas.addEventListener('contextmenu', e => e.preventDefault());

function pointerCommand(point: Point, targetId?: string): Command | null {
 const a = active(); if (!a || a.team !== 'party') return null;
 if (targetId) return intent === 'skill' ? { type: 'skill', unitId: a.id, targetId } : { type: 'attack', unitId: a.id, targetId };
 return intent === 'skill' ? { type: 'skill', unitId: a.id, to: point } : intent === 'attack' ? null : { type: 'move', unitId: a.id, to: point };
}
function hoverPreview(p: Point, id?: string) {
 if (!battle || mode() !== 'battle' || active()?.team !== 'party') return;
 const c = pointerCommand(p, id); if (!c) return;
 const preview = rules.previewCommand(battle, c);
 clearPreview();
 if (preview.path) showPath(preview.path, preview.ok);
 if (c.type === 'skill' && active()?.role === 'caster') { const center = c.to ?? unit(c.targetId ?? '')?.position; if (center) { areaRing.position.set(center.x, world.heightAt(center)+.16, center.z); areaRing.setEnabled(true); } }
 
}
function frame() {
 const dt = help ? 0 : Math.min(engine.getDeltaTime() / 1000, .05);
 actors.setCombatMode(isBattle());
 for (const [id, job] of [...movementJobs]) {
  let remaining = job.speed * dt;
  while (remaining > 0 && job.segment < job.path.length) {
   const here = actors.getPosition(id), next = job.path[job.segment], d = distance(here, next);
   actors.setFacing(id, { x: next.x - here.x, z: next.z - here.z });
   if (d <= remaining + .001) { actors.setPosition(id, next); remaining -= d; job.segment++; }
   else { actors.setPosition(id, { x: here.x + (next.x - here.x) / d * remaining, z: here.z + (next.z - here.z) / d * remaining }); remaining = 0; }
  }
  if (job.segment >= job.path.length) { movementJobs.delete(id); actors.setAnimation(id, 'idle'); job.resolve(true); }
 }
 followLeader(dt);
 const focus = focusPoint();
 if (!help) cameraControl.update(dt, { ...focus, y: world.heightAt(focus) + .8 });
 world.updateOcclusion(camera, focus);
 for (const id of isBattle() && battle ? battle.units.map(u => u.id) : partyIds) actors.setGroundHeight(id, world.heightAt(actors.getPosition(id)));
 actors.update(dt, camera);
 if (rangeRing) { const a = active(); rangeRing.setEnabled(isBattle() && !!a && a.hp > 0); if (a) { rangeRing.position.set(a.position.x, world.heightAt(a.position)+.1, a.position.z); rangeRing.scaling.setAll(a.range); } }
 if (effectTime > 0) effectTime -= dt;
 minimapTick += dt;
 if (minimapTick > .25) {
  minimapTick = 0; updateMinimap();
  if (mode() === 'exploring') { const near = INTERACTIONS.find(i => distance(focus, i) < i.radius + .8) ?? null; if (near?.id !== nearest?.id) { nearest = near; renderUI(); } }
 }
 if (mode() === 'exploring' && !cleared && checkedIn && supplies && gardenUnlocked && inRect(actors.getPosition(selected), ENCOUNTER_TRIGGER)) beginEncounter();
 scene.render();
}
async function boot() {
 renderUI();
 try {
  engine = new Engine(canvas, true, { stencil: true, preserveDrawingBuffer: false });
  engine.setHardwareScalingLevel(Math.max(1, window.devicePixelRatio / 1.5));
  scene = new Scene(engine);
  cameraControl = new CameraController(scene, canvas); camera = cameraControl.camera;
  cameraControl.setBounds(-12, 77, -15, 62, { minY: -2, maxY: 15, minRadius: 6, maxRadius: 105 });
  cameraControl.applyPreset({ alpha: -Math.PI/2 + .35, beta: .85, radius: 42, target: { x: 22,y:0,z:15 } }, true);
  world = new SourceHotelWorld(scene); await world.init(setLoading); rules = createBattleRules(world.navigation);
  setLoading('正在加载 Spine 干员与敌人…'); actors = new ActorRenderer(scene); await actors.init(setLoading); actors.setWorldScale(.4);
  partyIds.forEach((id, i) => actors.add(id, id as ActorRole, PARTY_SPAWNS[i], 'party'));
  const initialUnits = createBattle(PARTY_SPAWNS).units;
  partyIds.forEach(id => { const u = initialUnits.find(u => u.id === id)!; actors.setHp(id, u.hp, u.maxHp); });
  actors.setSelected(selected, true);
  const ringMat = new StandardMaterial('destination-material', scene); ringMat.emissiveColor = Color3.FromHexString('#e7c585'); ringMat.disableLighting = true;
  targetRing = MeshBuilder.CreateTorus('destination', { diameter: .8, thickness: .035, tessellation: 30 }, scene); targetRing.material = ringMat; targetRing.isPickable = false; targetRing.setEnabled(false);
  areaRing = MeshBuilder.CreateTorus('spell-area', { diameter: 6, thickness: .05, tessellation: 60 }, scene); areaRing.material = ringMat; areaRing.isPickable = false; areaRing.setEnabled(false);
  const rangeMat = new StandardMaterial('range-material', scene); rangeMat.emissiveColor = new Color3(.5, .66, .5); rangeMat.alpha = .18; rangeMat.disableLighting = true;
  rangeRing = MeshBuilder.CreateTorus('attack-range', { diameter: 2, thickness: .008, tessellation: 70 }, scene); rangeRing.material = rangeMat; rangeRing.isPickable = false; rangeRing.setEnabled(false);
  scene.onPointerObservable.add(info => {
   if (help || ['title', 'dialogue', 'victory', 'defeat', 'presenting','forming'].includes(mode())) return;
   const e = info.event as PointerEvent; if (info.type === PointerEventTypes.POINTERTAP && e.button !== 0) return;
   const pick = scene.pick(scene.pointerX, scene.pointerY, mesh => !!(mesh.metadata?.ground || mesh.metadata?.actorId || mesh.metadata?.interactionId));
   if (!pick?.hit || !pick.pickedPoint) return;
   const metadata = pick.pickedMesh?.metadata ?? {}; const p = { x: pick.pickedPoint.x, z: pick.pickedPoint.z };
   if (info.type === PointerEventTypes.POINTERMOVE) { if (performance.now() - lastHover < 100) return; lastHover = performance.now(); if (isBattle()) hoverPreview(p, metadata.actorId); return; }
   if (info.type !== PointerEventTypes.POINTERTAP) return;
   if (metadata.actorId) { selectUnit(metadata.actorId); return; }
   if (mode() === 'exploring') { if (metadata.interactionId) void interact(metadata.interactionId); else void exploreMove(p); }
   else if (mode() === 'battle') { const c = pointerCommand(p); if (c) void command(c); }
  });
  window.addEventListener('resize', () => engine.resize());
  // Read-only diagnostics are available only in development/e2e; no state mutation hooks.
  if (import.meta.env.DEV) Object.defineProperty(window, '__hotel', { value: { snapshot: () => ({ mode: mode(), battle: battle ? structuredClone(battle) : null, checkedIn, supplies, cleared, doorOpen: gardenUnlocked, positions: Object.fromEntries(partyIds.map(id => [id, actors.getPosition(id)])), navigationJobs: [...movementJobs].map(([id,job])=>({id,destination:job.path[job.path.length-1],segment:job.segment,blockedTime:job.blockedTime})), camera: { target: camera.target.asArray(), alpha:camera.alpha,beta:camera.beta,radius:camera.radius,following:cameraControl.isFollowing }, intent }), heightAt: (p:Point) => world.heightAt(p), project: (p: Point, y = .2) => { const v = Vector3.Project(new Vector3(p.x, y, p.z), Matrix.IdentityReadOnly, scene.getTransformMatrix(), camera.viewport.toGlobal(engine.getRenderWidth(), engine.getRenderHeight())); return { x: v.x * canvas.clientWidth / engine.getRenderWidth(), y: v.y * canvas.clientHeight / engine.getRenderHeight() }; }, preview: (c: Command) => battle ? rules.previewCommand(battle, c) : null } });
  flow.send({ type: 'READY' }); renderUI(); engine.runRenderLoop(frame);
 } catch (error) { console.error(error); flow.send({ type: 'FAIL' }); renderUI(); }
}
void boot();

