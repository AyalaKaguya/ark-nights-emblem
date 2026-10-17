import { Scene } from '@babylonjs/core/scene';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import { ShaderMaterial } from '@babylonjs/core/Materials/shaderMaterial';
import { Texture } from '@babylonjs/core/Materials/Textures/texture';
import { Color3, Color4 } from '@babylonjs/core/Maths/math.color';
import { CreatePlane } from '@babylonjs/core/Meshes/Builders/planeBuilder';
import { CreateTorus } from '@babylonjs/core/Meshes/Builders/torusBuilder';
import { CreateCylinder } from '@babylonjs/core/Meshes/Builders/cylinderBuilder';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import { Matrix, Vector2, Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { Camera } from '@babylonjs/core/Cameras/camera';
import { INTERACTIONS, DIFFICULT_TERRAIN, type Navigation, type Point } from '../shared';
import { SourceNavigation } from './source-navigation';
import { SourceGeometrySight, type SourceGeometryInstance } from './source-geometry';

type SourceMesh = { id: string; name: string; materialId: string; lightmapIndex: number; active: boolean; positions: Float32Array; normals: Float32Array; uv: Float32Array; uv2: Float32Array; indices: Uint32Array; colors: Float32Array };
type SourceMaterial = { id: string; name: string; textures: Record<string, string>; floats: Record<string, number>; colors: Record<string, { r: number; g: number; b: number; a: number }> };
type SourceInstance = SourceGeometryInstance;
export interface SourceMapData {
	meshes: SourceMesh[]; materials: SourceMaterial[]; instances: SourceInstance[];
	navigation: { positions: number[]; indices: number[]; bounds: { min: number[]; max: number[] } }[];
	lightmaps: { index: number; path: string; decodedPath?: string }[];
	regions: Record<string, { min: number[]; max: number[] }>;
}

/** Original client meshes and UVs, with baked material/lightmap adaptation for WebGL. */
export class SourceHotelWorld {
	navigation!: Navigation & { heightAt(point: Point): number };
	data!: SourceMapData;
	private meshes: Mesh[] = [];
	private materials: (ShaderMaterial | StandardMaterial)[] = [];
	private textures = new Map<string, Texture>();
	/** Local camera cutaway; collision and source meshes always remain intact. */
	viewOcclusionToggle = true;
	private sight!: SourceGeometrySight;
	private sourceMaterials: ShaderMaterial[] = [];
	private markers: { mesh: Mesh; groundY: number; bob: boolean; phase: number }[] = [];
	private steam: { mesh: Mesh; origin: Vector3; phase: number; speed: number }[] = [];
	private steamMaterial?: ShaderMaterial;
	private clock = 0;
	private waters = 0;
	private doorMarkerMaterial?: StandardMaterial;
	constructor(private scene: Scene) {}
	async init(progress?: (text: string) => void): Promise<void> {
		progress?.('加载方舟旅行小记原始地图、模型与贴图…');
		const response = await fetch(`${import.meta.env.BASE_URL}maps/hotel/scene-runtime.json`);
		if (!response.ok) throw new Error(`原地图加载失败：${response.status}`);
		const runtime = await response.json();
		const geometryResponse = await fetch(`${import.meta.env.BASE_URL}${runtime.geometry.file.replace(/^\//, '')}`);
		if (!geometryResponse.ok) throw new Error(`原地图几何加载失败：${geometryResponse.status}`);
		const buffer = await geometryResponse.arrayBuffer();
		for (const mesh of runtime.meshes) for (const attribute of ['positions', 'normals', 'uv', 'uv2', 'colors', 'indices']) {
			const field = mesh[attribute]; mesh[attribute] = field.kind === 'uint32' ? new Uint32Array(buffer, field.offset, field.length) : new Float32Array(buffer, field.offset, field.length);
		}
		this.data = runtime;
		this.sight = new SourceGeometrySight(this.data.meshes, this.data.instances);
		this.scene.clearColor = new Color4(.12, .20, .23, 1);
		for (const chunk of this.data.meshes) {
			if (!chunk.active) continue;
			const source = this.data.materials.find(m => m.id === chunk.materialId)!;
			const mesh = new Mesh(`original-${chunk.id}-${chunk.name}`, this.scene);
			const vertex = new VertexData(); vertex.positions = chunk.positions; vertex.normals = chunk.normals; vertex.uvs = chunk.uv; vertex.uvs2 = chunk.uv2; vertex.indices = chunk.indices; vertex.applyToMesh(mesh);
			const diffuse = source.textures._MainTex;
			const lightmap = this.data.lightmaps.find(l => l.index === chunk.lightmapIndex);
			// Only original pool-water materials: wooden/metal waterwheel geometry
			// is not classified as a fluid, and no new pool surfaces are generated.
			const water = /poolwater/i.test(source.name);
			const cutout = !water && (source.floats._Mode === 1 || /transparent/i.test(source.name));
			const material = new ShaderMaterial(`original-material-${chunk.id}`, this.scene, {
				vertexSource: `precision highp float;
attribute vec3 position; attribute vec2 uv; attribute vec2 uv2; attribute float viewMask;
uniform mat4 worldViewProjection;
varying vec2 vUV; varying vec2 vLM; varying vec3 vWorld; varying float vViewMask;
void main(){vUV=uv;vLM=uv2;vWorld=position;vViewMask=viewMask;gl_Position=worldViewProjection*vec4(position,1.0);}`,
				fragmentSource: `precision highp float;
varying vec2 vUV; varying vec2 vLM; varying vec3 vWorld; varying float vViewMask;
uniform sampler2D diffuse; uniform sampler2D lightmap; uniform sampler2D normalA; uniform sampler2D normalB;
uniform float hasDiffuse; uniform float hasLightmap; uniform float cutoff; uniform float alpha; uniform vec3 tint;
uniform float isWater; uniform float waterNormals; uniform float time; uniform float flowSpeed; uniform vec3 shallow;
uniform vec3 viewPosition; uniform vec3 focusPosition; uniform vec2 focusScreen; uniform float holeRadius; uniform float viewCutout;
void main(){
 vec4 c=vec4(1.0);if(hasDiffuse>0.5)c=texture2D(diffuse,vUV);if(c.a<cutoff)discard;
 if(viewCutout>0.5 && vViewMask>0.5){
  vec3 sight=focusPosition-viewPosition;float focusDistance=length(sight);
  float fragmentDistance=dot(vWorld-viewPosition,sight/max(focusDistance,0.001));
  if(fragmentDistance>0.3 && fragmentDistance<focusDistance-0.35){
   float d=length(gl_FragCoord.xy-focusScreen)/max(holeRadius,1.0);
   float reveal=1.0-smoothstep(0.63,1.0,d);
   float threshold=fract(sin(dot(floor(gl_FragCoord.xy),vec2(12.9898,78.233)))*43758.5453);
   if(threshold<reveal)discard;
  }
 }
 vec3 light=vec3(1.0);if(hasLightmap>0.5){vec4 lm=texture2D(lightmap,vLM);light=clamp(lm.rgb,vec3(0.20),vec3(1.5));}
 vec3 color=c.rgb*tint*light;
 if(isWater>0.5 && waterNormals>0.5){
  vec2 uv1=vUV*vec2(2.0,3.0)+vec2(-0.023,0.008)*time*flowSpeed;
  vec2 uv2=vUV*vec2(1.0,2.0)+vec2(0.009,-0.017)*time*flowSpeed;
  vec3 n1=texture2D(normalA,uv1).rgb*2.0-1.0;
  vec3 n2=texture2D(normalB,uv2).rgb*2.0-1.0;
  vec3 normal=normalize(vec3((n1.x+n2.x)*0.18,1.0,(n1.y+n2.y)*0.18));
  vec3 eye=normalize(viewPosition-vWorld);float fresnel=pow(1.0-max(dot(eye,normal),0.0),3.0);
  float ripple=clamp((n1.x+n2.y)*0.5,-1.0,1.0);
  color=mix(color,shallow,0.18+0.05*ripple)+vec3(0.12,0.18,0.18)*fresnel;
 }
 gl_FragColor=vec4(color,c.a*alpha);
}`,
			}, { attributes: ['position', 'uv', 'uv2', 'viewMask'], uniforms: ['worldViewProjection', 'hasDiffuse', 'hasLightmap', 'cutoff', 'alpha', 'tint', 'isWater', 'waterNormals', 'time', 'flowSpeed', 'shallow', 'viewPosition', 'focusPosition', 'focusScreen', 'holeRadius', 'viewCutout'], samplers: ['diffuse', 'lightmap', 'normalA', 'normalB'], needAlphaBlending: water, needAlphaTesting: cutout });
			mesh.setVerticesData('viewMask', this.sight.maskFor(chunk), false, 1);
			material.backFaceCulling = false;
			material.setFloat('hasDiffuse', diffuse ? 1 : 0); material.setFloat('hasLightmap', lightmap && !water ? 1 : 0); material.setFloat('cutoff', cutout ? Math.min(source.floats._Cutoff ?? .3, .4) : 0); material.setFloat('alpha', water ? source.floats._Alpha ?? .68 : 1);
			const color = water ? source.colors._WaterColor : source.colors._Color;
			material.setColor3('tint', color ? new Color3(color.r, color.g, color.b) : Color3.White());
			material.setFloat('isWater', water ? 1 : 0); material.setFloat('waterNormals', water && source.textures._NormalMap && source.textures._DetailNormal ? 1 : 0);
			material.setFloat('time', 0); material.setFloat('flowSpeed', source.floats._FlowSpeed ?? .3);
			material.setFloat('viewCutout', 0); material.setFloat('holeRadius', 1); material.setVector2('focusScreen', Vector2.Zero());
			material.setVector3('viewPosition', Vector3.Zero()); material.setVector3('focusPosition', Vector3.Zero());
			const shallow = source.colors._ShallowWaterColor; material.setColor3('shallow', shallow ? new Color3(shallow.r, shallow.g, shallow.b) : new Color3(.15,.62,.44));
			if (water) {
				this.waters++;
				if (source.textures._NormalMap) material.setTexture('normalA', this.texture(source.textures._NormalMap));
				if (source.textures._DetailNormal) material.setTexture('normalB', this.texture(source.textures._DetailNormal));
			}
			if (diffuse) material.setTexture('diffuse', this.texture(diffuse));
			if (lightmap) material.setTexture('lightmap', this.texture(lightmap.decodedPath ?? lightmap.path));
			mesh.material = material; mesh.isPickable = false; mesh.freezeWorldMatrix(); this.meshes.push(mesh); this.materials.push(material); this.sourceMaterials.push(material);
		}
		const nav = this.data.navigation[0];
		const surface = new Mesh('original-walk-surface', this.scene); const v = new VertexData(); v.positions = nav.positions; v.indices = nav.indices; v.normals = []; VertexData.ComputeNormals(nav.positions, nav.indices, v.normals as number[]); v.applyToMesh(surface);
		const hidden = new StandardMaterial('navigation-pick-material', this.scene); hidden.alpha = 0; hidden.backFaceCulling = false; surface.material = hidden; surface.visibility = .001; surface.metadata = { ground: true }; surface.isPickable = true; this.meshes.push(surface); this.materials.push(hidden);
		progress?.('从原作导航面重建可行走路线…');
		const navigation = new SourceNavigation(nav, { difficulty: DIFFICULT_TERRAIN }); await navigation.init(); this.navigation = navigation;
		const baseSight = navigation.lineOfSight.bind(navigation);
		navigation.lineOfSight = (from, to) => baseSight(from, to) && !this.sight.blocked({ x: from.x, y: navigation.heightAt(from) + .7, z: from.z }, { x: to.x, y: navigation.heightAt(to) + .7, z: to.z });
		this.createInteractions();
		await this.createSteam();
		await Promise.all([...this.textures.values()].map(t => t.isReady() ? Promise.resolve() : new Promise<void>((resolve, reject) => { const timeout = setTimeout(() => reject(new Error('原地图纹理加载超时')), 30_000); t.onLoadObservable.addOnce(() => { clearTimeout(timeout); resolve(); }); })));
	}

	private createInteractions(): void {
		for (let i = 0; i < INTERACTIONS.length; i++) {
			const interaction = INTERACTIONS[i], groundY = this.heightAt(interaction);
			const material = new StandardMaterial(`original-interaction-${interaction.id}`, this.scene);
			material.disableLighting = true; material.emissiveColor = new Color3(.96, .75, .29); material.alpha = .86; this.materials.push(material);
			if (interaction.id === 'door') this.doorMarkerMaterial = material;
			const ring = CreateTorus(`interaction-${interaction.id}-ring`, { diameter: 1.05, thickness: .045, tessellation: 32 }, this.scene);
			ring.position.set(interaction.x, groundY + .045, interaction.z); ring.material = material; ring.metadata = { interactionId: interaction.id }; this.meshes.push(ring); this.markers.push({ mesh: ring, groundY, bob: false, phase: i });
			const marker = CreateCylinder(`interaction-${interaction.id}-beacon`, { height: .27, diameterTop: 0, diameterBottom: .2, tessellation: 4 }, this.scene);
			marker.position.set(interaction.x, groundY + .6, interaction.z); marker.material = material; marker.metadata = { interactionId: interaction.id }; this.meshes.push(marker); this.markers.push({ mesh: marker, groundY, bob: true, phase: i });
		}
	}

	private async createSteam(): Promise<void> {
		const response = await fetch(`${import.meta.env.BASE_URL}maps/hotel/interest-points.json`);
		if (!response.ok) return;
		const points = await response.json() as { smokeEmitters?: { name: string; position: number[] }[] };
		const material = new ShaderMaterial('source-emitter-steam', this.scene, {
			vertexSource: 'precision highp float;attribute vec3 position;attribute vec2 uv;uniform mat4 worldViewProjection;varying vec2 vUV;void main(){vUV=uv;gl_Position=worldViewProjection*vec4(position,1.0);}',
			fragmentSource: 'precision highp float;varying vec2 vUV;uniform float time;void main(){vec2 p=vUV*2.0-1.0;float r=dot(p,p);float noise=0.75+0.25*sin(p.x*8.0+time*0.4)*sin(p.y*6.0-time*0.2);float a=pow(max(0.0,1.0-r),2.0)*noise*0.085;if(a<0.006)discard;gl_FragColor=vec4(0.83,0.92,0.91,a);}',
		}, { attributes: ['position', 'uv'], uniforms: ['worldViewProjection', 'time'], needAlphaBlending: true });
		material.backFaceCulling = false; material.setFloat('time', 0); this.steamMaterial = material; this.materials.push(material);
		for (const [i, emitter] of (points.smokeEmitters ?? []).entries()) {
			// Positions come directly from original smoke transform nodes. Two soft
			// lightweight puffs per emitter approximate the missing Unity particle FX.
			for (let j = 0; j < 2; j++) {
				const mesh = CreatePlane(`source-steam-${emitter.name}-${j}`, { size: 2.2 }, this.scene);
				const origin = Vector3.FromArray(emitter.position);
				mesh.position.copyFrom(origin); mesh.material = material; mesh.billboardMode = Mesh.BILLBOARDMODE_ALL; mesh.isPickable = false; mesh.alphaIndex = 10;
				this.meshes.push(mesh); this.steam.push({ mesh, origin, phase: (i * .37 + j * .5) % 1, speed: .09 + i % 3 * .012 });
			}
		}
	}
	private texture(path: string): Texture {
		if (this.textures.has(path)) return this.textures.get(path)!;
		const url = `${import.meta.env.BASE_URL}${path.replace(/^\//, '')}`;
		const texture = new Texture(url, this.scene, false, true, Texture.TRILINEAR_SAMPLINGMODE); texture.wrapU = texture.wrapV = Texture.WRAP_ADDRESSMODE; this.textures.set(path, texture); return texture;
	}
	heightAt(point: Point): number { return this.navigation.heightAt(point); }
	setDoorOpen(open: boolean): void { this.navigation.setDoorOpen(open); if (this.doorMarkerMaterial) this.doorMarkerMaterial.emissiveColor = open ? new Color3(.38, .81, .62) : new Color3(.96, .75, .29); }
	setViewOcclusion(enabled: boolean): void { this.viewOcclusionToggle = enabled; }
	updateOcclusion(camera: Camera, focus: Point): void {
		this.clock += Math.min(this.scene.getEngine().getDeltaTime() / 1000, .1);
		const engine = this.scene.getEngine(), width = engine.getRenderWidth(), height = engine.getRenderHeight();
		const focusPosition = new Vector3(focus.x, this.heightAt(focus) + .65, focus.z);
		const view = camera.globalPosition;
		const projected = Vector3.Project(focusPosition, Matrix.IdentityReadOnly, this.scene.getTransformMatrix(), camera.viewport.toGlobal(width, height));
		const radius = Math.max(35, Math.min(150, height * 1.2 / (2 * Math.tan(camera.fov / 2) * Math.max(2, Vector3.Distance(view, focusPosition)))));
		const enabled = this.viewOcclusionToggle && projected.z > 0 && projected.z < 1 ? 1 : 0;
		for (const material of this.sourceMaterials) {
			material.setFloat('time', this.clock); material.setFloat('viewCutout', enabled); material.setFloat('holeRadius', radius);
			material.setVector3('viewPosition', view); material.setVector3('focusPosition', focusPosition); material.setVector2('focusScreen', new Vector2(projected.x, height - projected.y));
		}
		for (const marker of this.markers) {
			if (marker.bob) { marker.mesh.position.y = marker.groundY + .6 + Math.sin(this.clock * 2.1 + marker.phase) * .07; marker.mesh.rotation.y = this.clock * .5; }
			else marker.mesh.scaling.setAll(1 + Math.sin(this.clock * 1.6 + marker.phase) * .035);
		}
		this.steamMaterial?.setFloat('time', this.clock);
		for (const puff of this.steam) {
			const t = (this.clock * puff.speed + puff.phase) % 1;
			puff.mesh.position.set(puff.origin.x + Math.sin(t * Math.PI) * .3, puff.origin.y + .3 + t * 2.7, puff.origin.z + t * .2);
			puff.mesh.scaling.setAll(.7 + t * .8); puff.mesh.visibility = Math.sin(t * Math.PI);
		}
	}
	diagnostics(): Record<string, unknown> { return { architectureInstances: this.sight.architecture.length, animatedOriginalWaterChunks: this.waters, sourceSteamPuffs: this.steam.length, interactionMeshes: this.markers.length, localCameraCutaway: this.viewOcclusionToggle }; }
	dispose(): void { for (const mesh of this.meshes) mesh.dispose(); for (const material of this.materials) material.dispose(); for (const texture of this.textures.values()) texture.dispose(); (this.navigation as SourceNavigation).dispose(); }
}
