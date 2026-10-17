import { Color3 } from '@babylonjs/core/Maths/math.color';
import { Constants } from '@babylonjs/core/Engines/constants';
import { DynamicTexture } from '@babylonjs/core/Materials/Textures/dynamicTexture';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { CreatePlane } from '@babylonjs/core/Meshes/Builders/planeBuilder';
import { CreateTorus } from '@babylonjs/core/Meshes/Builders/torusBuilder';
import { ShaderMaterial } from '@babylonjs/core/Materials/shaderMaterial';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import { Texture } from '@babylonjs/core/Materials/Textures/texture';
import { Vector4 } from '@babylonjs/core/Maths/math.vector';
import type { Scene } from '@babylonjs/core/scene';
import type { Camera } from '@babylonjs/core/Cameras/camera';
import type { Point } from '../shared';

export type ActorRole = 'amiya' | 'hoshiguma' | 'ansel' | 'melee' | 'ranged';
export type ActorAnimation = 'idle' | 'move' | 'attack' | 'skill' | 'hurt' | 'death';
// The archived official Spine 3.8 distribution predates ES modules. Its API is
// isolated here; application rules and world/navigation do not depend on it.
type SpineObject = any;
type Model = { data: SpineObject; atlas: SpineObject; height: number; idle: string; move: string; action: string; death?: string; baseY: number; scale: number };
type Actor = { role: ActorRole; slot: number; root: Mesh; ring: Mesh; label: Mesh; labelTexture: DynamicTexture; labelMaterial: StandardMaterial; ringMaterial: StandardMaterial; skeleton: SpineObject; state: SpineObject; direction: Point; animation: ActorAnimation; elapsed: number; oneShotEnd: number; groundY: number; selected: boolean; hp: number; maxHp: number; team: 'party' | 'enemy' };

const CELL = 256;
const COLS = 4;
const ROWS = 2;
const WIDTH = CELL * COLS;
const HEIGHT = CELL * ROWS;
const FOOT_PIXELS = 14;
const BASE = import.meta.env.BASE_URL;
const MODEL_FILES: Record<ActorRole, string> = {
	amiya: 'build_char_002_amiya', hoshiguma: 'build_char_136_hsguma', ansel: 'build_char_212_ansel', melee: 'enemy_1002_nsabr', ranged: 'enemy_1003_ncbow',
};
const NAMES: Record<ActorRole, string> = { amiya: '阿米娅', hoshiguma: '星熊', ansel: '安赛尔', melee: '士兵', ranged: '弩手' };
const BODY_HEIGHT: Record<ActorRole, number> = { amiya: 2.55, hoshiguma: 2.8, ansel: 2.35, melee: 2.5, ranged: 2.3 };
let runtimePromise: Promise<SpineObject> | undefined;

async function loadRuntime(): Promise<SpineObject> {
	if (runtimePromise) return runtimePromise;
	runtimePromise = new Promise((resolve, reject) => {
		const script = document.createElement('script');
		script.src = `${BASE}vendor/spine-webgl-3.8.js`;
		script.onload = () => {
			const runtime = (window as Window & { spine?: SpineObject }).spine;
			if (runtime?.SkeletonBinary && runtime?.webgl?.SceneRenderer) resolve(runtime);
			else reject(new Error('Spine 3.8 运行时加载不完整'));
		};
		script.onerror = () => reject(new Error('无法加载本地 Spine 3.8 运行时'));
		document.head.appendChild(script);
	});
	return runtimePromise;
}

async function read(url: string): Promise<Response> {
	const response = await fetch(url);
	if (!response.ok) throw new Error(`角色资源加载失败 ${response.status}: ${url}`);
	return response;
}

async function loadImage(url: string): Promise<HTMLImageElement> {
	return new Promise((resolve, reject) => {
		const image = new Image();
		image.onload = () => resolve(image);
		image.onerror = () => reject(new Error(`无法加载角色纹理: ${url}`));
		image.src = url;
	});
}

/** World-space, animated Spine billboards with one shared offscreen WebGL atlas.
 * Movement and combat decisions are supplied by the game, never by this adapter.
 */
export class ActorRenderer {
	private actors = new Map<string, Actor>();
	private models = new Map<ActorRole, Model>();
	private spine!: SpineObject;
	private canvas!: HTMLCanvasElement;
	private gl!: WebGLRenderingContext;
	private renderer!: SpineObject;
	private texture!: DynamicTexture;
	private material!: ShaderMaterial;
	private dirty = true;
	private renderAccumulator = 0;
	private disposed = false;
	private worldScale = 1;
	private combatMode = false;

	constructor(private scene: Scene) {}

	async init(onProgress?: (label: string) => void): Promise<void> {
		onProgress?.('加载 Spine 3.8 动画运行时');
		this.spine = await loadRuntime();
		this.canvas = document.createElement('canvas');
		this.canvas.width = WIDTH;
		this.canvas.height = HEIGHT;
		const gl = this.canvas.getContext('webgl', { alpha: true, premultipliedAlpha: true, preserveDrawingBuffer: true, antialias: false, depth: false, stencil: false });
		if (!gl) throw new Error('当前浏览器无法创建 Spine WebGL 动画画布');
		this.gl = gl;
		this.renderer = new this.spine.webgl.SceneRenderer(this.canvas, gl, true);
		this.renderer.camera.position.set(WIDTH / 2, HEIGHT / 2, 0);
		this.renderer.camera.setViewport(WIDTH, HEIGHT);
		// No drawText/getContext calls are made on this DynamicTexture: its external
		// canvas already owns the one shared Spine WebGL context.
		this.texture = new DynamicTexture('spine-shared-atlas', this.canvas, this.scene, false, Texture.BILINEAR_SAMPLINGMODE);
		this.texture.hasAlpha = true;
		this.texture.gammaSpace = true;
		this.texture.wrapU = this.texture.wrapV = Texture.CLAMP_ADDRESSMODE;
		this.material = new ShaderMaterial('spine-world-unlit', this.scene, {
			vertexSource: 'precision highp float; attribute vec3 position; attribute vec2 uv; uniform mat4 worldViewProjection; varying vec2 vUV; void main(){ vUV=uv; gl_Position=worldViewProjection*vec4(position,1.0); }',
			fragmentSource: 'precision highp float; varying vec2 vUV; uniform sampler2D atlas; void main(){ vec4 pixel=texture2D(atlas,vUV); if(pixel.a<0.025) discard; gl_FragColor=pixel; }',
		}, { attributes: ['position', 'uv'], uniforms: ['worldViewProjection'], samplers: ['atlas'], needAlphaBlending: true, needAlphaTesting: true });
		this.material.setTexture('atlas', this.texture);
		this.material.backFaceCulling = false;
		this.material.alphaMode = Constants.ALPHA_COMBINE;
		this.material.forceDepthWrite = true;
		if (import.meta.env.DEV) Object.defineProperty(window, '__spineDiagnostics', { configurable: true, value: () => this.diagnostics() });
		await Promise.all((Object.keys(MODEL_FILES) as ActorRole[]).map(async role => {
			onProgress?.(`加载${NAMES[role]}真实 Spine 动画`);
			const name = MODEL_FILES[role];
			const folder = `${BASE}actors/${role}/`;
			const [atlasText, binary, image] = await Promise.all([
				read(`${folder}${name}.atlas`).then(response => response.text()),
				read(`${folder}${name}.skel`).then(response => response.arrayBuffer()),
				loadImage(`${folder}${name}.png`),
			]);
			const atlas = new this.spine.TextureAtlas(atlasText, () => new this.spine.webgl.GLTexture(gl, image, false));
			const data = new this.spine.SkeletonBinary(new this.spine.AtlasAttachmentLoader(atlas)).readSkeletonData(new Uint8Array(binary));
			if (!data.version.startsWith('3.8')) throw new Error(`${NAMES[role]}不是 Spine 3.8 资源`);
			const choose = (...names: string[]) => names.find(name => data.findAnimation(name)) ?? data.animations[0].name;
			const idle = choose('Relax', 'Idle', 'Default');
			const skeleton = new this.spine.Skeleton(data);
			const state = new this.spine.AnimationState(new this.spine.AnimationStateData(data));
			state.setAnimation(0, idle, true);
			state.update(0.1); state.apply(skeleton); skeleton.updateWorldTransform();
			const offset = new this.spine.Vector2(); const size = new this.spine.Vector2();
			skeleton.getBounds(offset, size, []);
			const scale = (CELL - 32) / size.y;
			this.models.set(role, { data, atlas, height: BODY_HEIGHT[role] * CELL / (CELL - 32), idle, move: choose('Move', 'Move_Loop', 'Run_Loop'), action: choose('Attack', 'Interact', 'Combat'), death: data.findAnimation('Die') ? 'Die' : undefined, baseY: offset.y, scale });
		}));
		onProgress?.('五种角色的真实 Spine 动画已就绪');
	}

	add(id: string, role: ActorRole, position: Point, team: 'party' | 'enemy'): void {
		this.remove(id);
		const model = this.models.get(role);
		if (!model) throw new Error('ActorRenderer.init() 必须先完成');
		const occupied = new Set([...this.actors.values()].map(actor => actor.slot));
		const slot = Array.from({ length: COLS * ROWS }, (_, i) => i).find(i => !occupied.has(i));
		if (slot === undefined) throw new Error('共享动画图集最多容纳八个角色');
		const col = slot % COLS; const row = Math.floor(slot / COLS);
		const crop = new Vector4((col * CELL + 1) / WIDTH, (row * CELL + 1) / HEIGHT, ((col + 1) * CELL - 1) / WIDTH, ((row + 1) * CELL - 1) / HEIGHT);
		const root = CreatePlane(`actor-${id}`, { width: model.height, height: model.height, sideOrientation: Mesh.DOUBLESIDE, frontUVs: crop, backUVs: crop }, this.scene);
		root.position.set(position.x, model.height * (0.5 - FOOT_PIXELS / CELL) + 0.04, position.z);
		root.material = this.material; root.isPickable = true; root.metadata = { actorId: id }; root.alphaIndex = team === 'party' ? 1 : 2;
		const ringMaterial = new StandardMaterial(`actor-ring-${id}`, this.scene);
		ringMaterial.disableLighting = true; ringMaterial.emissiveColor = team === 'party' ? new Color3(0.27, 0.83, 0.78) : new Color3(0.96, 0.36, 0.26); ringMaterial.alpha = 0.8;
		const ring = CreateTorus(`actor-foot-ring-${id}`, { diameter: role === 'hoshiguma' ? 1.55 : 1.25, thickness: 0.045, tessellation: 32 }, this.scene);
		ring.position.set(position.x, 0.06, position.z); ring.material = ringMaterial; ring.isPickable = true; ring.metadata = { actorId: id }; ring.visibility = 0.45;
		const labelTexture = new DynamicTexture(`actor-label-${id}`, { width: 256, height: 64 }, this.scene, false);
		labelTexture.hasAlpha = true;
		const labelMaterial = new StandardMaterial(`actor-label-material-${id}`, this.scene);
		labelMaterial.diffuseTexture = labelTexture; labelMaterial.useAlphaFromDiffuseTexture = true; labelMaterial.emissiveColor = Color3.White(); labelMaterial.disableLighting = true; labelMaterial.backFaceCulling = false;
		const label = CreatePlane(`actor-label-plane-${id}`, { width: 1.65, height: 0.12 }, this.scene);
		label.position.set(position.x, model.height + 0.3, position.z); label.material = labelMaterial; label.billboardMode = Mesh.BILLBOARDMODE_ALL; label.isPickable = false;
		const skeleton = new this.spine.Skeleton(model.data);
		const animationData = new this.spine.AnimationStateData(model.data); animationData.defaultMix = 0.13;
		const state = new this.spine.AnimationState(animationData); state.setAnimation(0, model.idle, true);
		this.actors.set(id, { role, slot, root, ring, label, labelTexture, labelMaterial, ringMaterial, skeleton, state, direction: { x: 1, z: 0 }, animation: 'idle', elapsed: 0, oneShotEnd: 0, groundY: 0, selected: false, hp: 1, maxHp: 1, team });
		this.applyWorldScale(this.actors.get(id)!);
		this.setHp(id, 1, 1); this.dirty = true;
	}

	setPosition(id: string, position: Point): void {
		const actor = this.actors.get(id); if (!actor) return;
		for (const mesh of [actor.root, actor.ring, actor.label]) { mesh.position.x = position.x; mesh.position.z = position.z; }
	}

	getPosition(id: string): Point { const root = this.actors.get(id)?.root; return root ? { x: root.position.x, z: root.position.z } : { x: 0, z: 0 }; }

	setWorldScale(scale: number): void {
		if (!Number.isFinite(scale) || scale <= 0) throw new Error('Actor world scale must be positive and finite');
		this.worldScale = scale;
		for (const actor of this.actors.values()) this.applyWorldScale(actor);
	}

	setGroundHeight(id: string, y: number): void {
		const actor = this.actors.get(id); if (!actor || !Number.isFinite(y)) return;
		actor.groundY = y; this.applyWorldScale(actor);
	}

	private applyWorldScale(actor: Actor): void {
		const scale = this.worldScale, height = this.models.get(actor.role)!.height;
		actor.root.scaling.set((actor.root.scaling.x < 0 ? -1 : 1) * scale, scale, scale);
		actor.root.position.y = actor.groundY + (height * (0.5 - FOOT_PIXELS / CELL) + 0.04) * scale;
		actor.ring.scaling.setAll(scale); actor.ring.position.y = actor.groundY + 0.06 * scale;
		actor.label.scaling.setAll(scale); actor.label.position.y = actor.groundY + (height + 0.3) * scale;
	}

	setAnimation(id: string, animation: ActorAnimation): void {
		const actor = this.actors.get(id); if (!actor || actor.animation === animation) return;
		const model = this.models.get(actor.role)!;
		actor.animation = animation; actor.elapsed = 0; actor.oneShotEnd = 0;
		const name = animation === 'move' ? model.move : animation === 'attack' || animation === 'skill' ? model.action : animation === 'death' ? model.death ?? model.idle : model.idle;
		const loop = animation === 'idle' || animation === 'move' || animation === 'hurt';
		const entry = actor.state.setAnimation(0, name, loop);
		if (!loop && animation !== 'death') actor.oneShotEnd = entry.animation.duration;
		this.dirty = true;
	}

	setFacing(id: string, direction: Point): void { const actor = this.actors.get(id); if (actor && Math.hypot(direction.x, direction.z) > 0.001) actor.direction = { ...direction }; }
	setSelected(id: string, selected: boolean): void {
		const actor = this.actors.get(id); if (!actor) return;
		actor.selected = selected; actor.ring.visibility = selected ? 1 : 0.35; this.updateBarVisibility(actor);
	}

	setCombatMode(enabled: boolean): void {
		this.combatMode = enabled;
		for (const actor of this.actors.values()) this.updateBarVisibility(actor);
	}

	private updateBarVisibility(actor: Actor): void {
		actor.label.isVisible = actor.hp > 0 && (actor.selected || actor.hp < actor.maxHp || this.combatMode && actor.team === 'enemy');
	}

	setHp(id: string, hp: number, maxHp: number): void {
		const actor = this.actors.get(id); if (!actor) return;
		actor.hp = Math.max(0, hp); actor.maxHp = maxHp;
		const context = actor.labelTexture.getContext() as CanvasRenderingContext2D;
		context.clearRect(0, 0, 256, 64);
		context.fillStyle = '#0a1816ed'; context.fillRect(2, 8, 252, 48);
		context.fillStyle = '#88764c'; context.fillRect(3, 9, 250, 46);
		context.fillStyle = '#172e28'; context.fillRect(7, 15, 242, 34);
		context.fillStyle = actor.team === 'party' ? '#88ac85' : '#a84935'; context.fillRect(7, 15, 242 * Math.max(0, Math.min(1, hp / Math.max(1, maxHp))), 34);
		context.fillStyle = '#d4c39144'; context.fillRect(7, 15, 242 * Math.max(0, Math.min(1, hp / Math.max(1, maxHp))), 5);
		actor.labelTexture.update();
		actor.ring.visibility = hp > 0 ? actor.selected ? 1 : 0.35 : 0.12;
		this.updateBarVisibility(actor);
	}

	remove(id: string): void {
		const actor = this.actors.get(id); if (!actor) return;
		for (const mesh of [actor.root, actor.ring, actor.label]) mesh.dispose();
		actor.ringMaterial.dispose(); actor.labelMaterial.dispose(); actor.labelTexture.dispose();
		this.actors.delete(id); this.dirty = true;
	}

	update(dt: number, camera: Camera): void {
		if (this.disposed || !this.renderer) return;
		const delta = Math.min(Math.max(dt, 0), 0.1);
		for (const [id, actor] of this.actors) {
			actor.elapsed += delta; actor.state.update(delta);
			if (actor.oneShotEnd > 0 && actor.elapsed >= actor.oneShotEnd) this.setAnimation(id, 'idle');
			// Vertical billboards preserve the foot position while the camera orbits.
			actor.root.rotation.y = Math.atan2(camera.position.x - actor.root.position.x, camera.position.z - actor.root.position.z) + Math.PI;
			const dx = camera.position.x - actor.root.position.x; const dz = camera.position.z - actor.root.position.z;
			const screenRight = actor.direction.x * dz - actor.direction.z * dx;
			actor.root.scaling.x = (screenRight < 0 ? -1 : 1) * this.worldScale;
			const pulse = actor.animation === 'hurt' ? Math.max(0, 1 - actor.elapsed * 4) : 0;
			actor.skeleton.color.set(1, 1 - pulse * 0.6, 1 - pulse * 0.6, actor.animation === 'death' ? Math.max(0.24, 1 - actor.elapsed * 0.45) : 1);
			const model = this.models.get(actor.role)!;
			actor.root.position.y = actor.groundY + (model.height * (0.5 - FOOT_PIXELS / CELL) + 0.04) * this.worldScale;
			// Building assets lack combat clips: their genuine Interact clip is used,
			// accompanied by a small presentation-only skill pulse (see sources).
			actor.root.scaling.y = this.worldScale * (actor.animation === 'skill' ? 1 + Math.sin(Math.min(1, actor.elapsed / 0.6) * Math.PI) * 0.07 : 1);
		}
		this.renderAccumulator += delta;
		if (!this.dirty && this.renderAccumulator < 1 / 30) return;
		this.renderAccumulator = 0; this.dirty = false;
		const gl = this.gl;
		gl.viewport(0, 0, WIDTH, HEIGHT); gl.disable(gl.SCISSOR_TEST); gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
		for (const actor of this.actors.values()) {
			const model = this.models.get(actor.role)!;
			const col = actor.slot % COLS; const row = Math.floor(actor.slot / COLS);
			actor.state.apply(actor.skeleton);
			actor.skeleton.scaleX = actor.skeleton.scaleY = model.scale;
			actor.skeleton.x = col * CELL + CELL / 2;
			actor.skeleton.y = row * CELL + FOOT_PIXELS - model.baseY * model.scale;
			actor.skeleton.updateWorldTransform();
			gl.enable(gl.SCISSOR_TEST); gl.scissor(col * CELL + 1, row * CELL + 1, CELL - 2, CELL - 2);
			this.renderer.begin(); this.renderer.drawSkeleton(actor.skeleton, true); this.renderer.end();
		}
		gl.disable(gl.SCISSOR_TEST);
		// Browser upload converts the premultiplied WebGL drawing buffer to straight
		// RGBA. The world material uses conventional alpha blending, not PMA twice.
		this.texture.update(true, false);
	}

	diagnostics(): Record<string, unknown> {
		const pixels = new Uint8Array(WIDTH * HEIGHT * 4);
		this.gl.readPixels(0, 0, WIDTH, HEIGHT, this.gl.RGBA, this.gl.UNSIGNED_BYTE, pixels);
		const alphaByCell = Array.from({ length: COLS * ROWS }, () => 0);
		for (let y = 0; y < HEIGHT; y++) for (let x = 0; x < WIDTH; x++) if (pixels[(y * WIDTH + x) * 4 + 3] > 0) alphaByCell[Math.floor(y / CELL) * COLS + Math.floor(x / CELL)]++;
		return { alphaByCell, textureReady: this.texture.isReady(), glError: this.gl.getError(), atlas: this.canvas.toDataURL(), actors: [...this.actors].map(([id, actor]) => ({ id, slot: actor.slot, animation: actor.animation, clip: actor.state.getCurrent(0)?.animation.name, bounds: actor.root.getBoundingInfo().boundingBox.extendSize.toString() })) };
	}

	dispose(): void {
		this.disposed = true;
		for (const id of [...this.actors.keys()]) this.remove(id);
		this.material?.dispose(); this.texture?.dispose(); this.renderer?.dispose();
		for (const model of this.models.values()) model.atlas.dispose();
		this.models.clear();
		this.gl?.getExtension('WEBGL_lose_context')?.loseContext();
	}
}
