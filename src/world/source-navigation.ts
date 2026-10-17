import { init as initRecast, NavMesh, NavMeshQuery } from 'recast-navigation';
import { generateSoloNavMesh } from 'recast-navigation/generators';
import type { CircleBlocker, Navigation, Point, Rect } from '../shared';

export interface SourceNavData { positions: number[]; indices: number[] }
export interface SourceNavigationSettings {
	door?: Rect;
	difficulty?: Rect[];
	/** Only explicit upright physical occluders. Does not alter source walkability. */
	solids?: Rect[];
}
type Surface = Point & { y: number; ref: number; nx: number; nz: number };
type Triangle = { ax: number; ay: number; az: number; bx: number; by: number; bz: number; cx: number; cy: number; cz: number; denom: number };
const CELL = 0.5;
const BUCKET = 2;
const ACTOR_RADIUS = 0.45;
const CLEARANCE = 0.012;
const DIRECTIONS = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]] as const;
const dist = (a: Point, b: Point): number => Math.hypot(a.x - b.x, a.z - b.z);
const within = (p: Point, r: Rect, pad = 0): boolean => Math.abs(p.x - r.x) < r.width / 2 + pad && Math.abs(p.z - r.z) < r.depth / 2 + pad;
function intersects(a: Point, b: Point, r: Rect, pad = 0): boolean {
	let lo = 0, hi = 1;
	for (const axis of ['x', 'z'] as const) {
		const d = b[axis] - a[axis], half = (axis === 'x' ? r.width : r.depth) / 2 + pad;
		if (Math.abs(d) < 1e-9) { if (a[axis] < r[axis] - half || a[axis] > r[axis] + half) return false; continue; }
		const t1 = (r[axis] - half - a[axis]) / d, t2 = (r[axis] + half - a[axis]) / d;
		lo = Math.max(lo, Math.min(t1, t2)); hi = Math.min(hi, Math.max(t1, t2));
		if (lo > hi) return false;
	}
	return true;
}
function circleDistance(a: Point, b: Point, c: Point): number {
	const dx = b.x - a.x, dz = b.z - a.z;
	const t = Math.max(0, Math.min(1, ((c.x - a.x) * dx + (c.z - a.z) * dz) / (dx * dx + dz * dz || 1)));
	return Math.hypot(a.x + t * dx - c.x, a.z + t * dz - c.z);
}
class Heap {
	private values: { id: number; f: number }[] = [];
	get length(): number { return this.values.length; }
	push(id: number, f: number): void {
		let i = this.values.length; const entry = { id, f }; this.values.push(entry);
		while (i) { const p = (i - 1) >> 1; if (this.values[p].f <= f) break; this.values[i] = this.values[p]; i = p; }
		this.values[i] = entry;
	}
	pop(): number {
		const first = this.values[0], last = this.values.pop()!;
		if (this.values.length) {
			let i = 0;
			while (i * 2 + 1 < this.values.length) {
				let child = i * 2 + 1;
				if (child + 1 < this.values.length && this.values[child + 1].f < this.values[child].f) child++;
				if (this.values[child].f >= last.f) break;
				this.values[i] = this.values[child]; i = child;
			}
			this.values[i] = last;
		}
		return first.id;
	}
}

/** Recast rebuilt exclusively from the original walkable triangles. Their
 * existing edge clearance is preserved: walkableRadius is zero, not eroded a
 * second time. An exact source footprint guards voxel edge expansion. A cached
 * 0.5 m graph overlays virtual gates and 0.35 m actor-to-actor clearance.
 */
export class SourceNavigation implements Navigation {
	doorOpen: boolean;
	private navMesh?: NavMesh;
	private query?: NavMeshQuery;
	private triangles: Triangle[] = [];
	private buckets = new Map<string, number[]>();
	private minX = Infinity;
	private maxX = -Infinity;
	private minZ = Infinity;
	private maxZ = -Infinity;
	private minY = Infinity;
	private maxY = -Infinity;
	private width = 0;
	private depth = 0;
	private nodes: (Surface | undefined)[] = [];
	private edges = new Uint8Array(0);
	private edgeCosts = new Float32Array(0);

	constructor(private source: SourceNavData, private settings: SourceNavigationSettings = {}) {
		this.doorOpen = !settings.door;
		if (!source.positions.length || source.positions.length % 3 || source.indices.length % 3) throw new Error('Invalid source navigation triangle arrays');
		for (let i = 0; i < source.positions.length; i += 3) {
			const [x, y, z] = source.positions.slice(i, i + 3);
			if (![x, y, z].every(Number.isFinite)) throw new Error('Source navigation contains non-finite vertices');
			this.minX = Math.min(this.minX, x); this.maxX = Math.max(this.maxX, x);
			this.minY = Math.min(this.minY, y); this.maxY = Math.max(this.maxY, y);
			this.minZ = Math.min(this.minZ, z); this.maxZ = Math.max(this.maxZ, z);
		}
		for (let i = 0; i < source.indices.length; i += 3) {
			const indices = source.indices.slice(i, i + 3);
			if (indices.some(index => !Number.isInteger(index) || index < 0 || index * 3 + 2 >= source.positions.length)) throw new Error('Source navigation index is out of range');
			const [a, b, c] = indices.map(index => index * 3), p = source.positions;
			const denom = (p[b + 2] - p[c + 2]) * (p[a] - p[c]) + (p[c] - p[b]) * (p[a + 2] - p[c + 2]);
			if (Math.abs(denom) < 1e-8) continue;
			const triangle = { ax: p[a], ay: p[a + 1], az: p[a + 2], bx: p[b], by: p[b + 1], bz: p[b + 2], cx: p[c], cy: p[c + 1], cz: p[c + 2], denom };
			const id = this.triangles.push(triangle) - 1;
			for (let z = Math.floor(Math.min(triangle.az, triangle.bz, triangle.cz) / BUCKET); z <= Math.floor(Math.max(triangle.az, triangle.bz, triangle.cz) / BUCKET); z++) {
				for (let x = Math.floor(Math.min(triangle.ax, triangle.bx, triangle.cx) / BUCKET); x <= Math.floor(Math.max(triangle.ax, triangle.bx, triangle.cx) / BUCKET); x++) {
					const key = `${x},${z}`; const bucket = this.buckets.get(key) ?? []; bucket.push(id); this.buckets.set(key, bucket);
				}
			}
		}
	}

	async init(): Promise<void> {
		if (this.query) return;
		await initRecast();
		const positions = this.source.positions, indices: number[] = [];
		// Exported Unity meshes can contain mixed winding; Recast expects upwards
		// facing walkable triangles. This changes indices only, never their footprint.
		for (let i = 0; i < this.source.indices.length; i += 3) {
			const [a, b, c] = this.source.indices.slice(i, i + 3), A = a * 3, B = b * 3, C = c * 3;
			const normalY = (positions[B + 2] - positions[A + 2]) * (positions[C] - positions[A]) - (positions[B] - positions[A]) * (positions[C + 2] - positions[A + 2]);
			indices.push(a, normalY >= 0 ? b : c, normalY >= 0 ? c : b);
		}
		const generated = generateSoloNavMesh(positions, indices, {
			cs: 0.1, ch: 0.05, walkableSlopeAngle: 60, walkableHeight: 16, walkableClimb: 6, walkableRadius: 0,
			minRegionArea: 0, mergeRegionArea: 4, maxEdgeLen: 120, maxSimplificationError: 0.35,
			detailSampleDist: 3, detailSampleMaxError: 0.5,
		});
		if (!generated.success) throw new Error(`Original map Recast generation failed: ${generated.error}`);
		this.navMesh = generated.navMesh; this.query = new NavMeshQuery(generated.navMesh, { maxNodes: 8192 });
		this.query.defaultQueryHalfExtents = { x: 0.2, y: 0.6, z: 0.2 };
		this.width = Math.floor((this.maxX - this.minX) / CELL + 1e-4) + 1;
		this.depth = Math.floor((this.maxZ - this.minZ) / CELL + 1e-4) + 1;
		this.nodes = new Array(this.width * this.depth);
		this.edges = new Uint8Array(this.nodes.length); this.edgeCosts = new Float32Array(this.nodes.length * 8);
		for (let i = 0; i < this.nodes.length; i++) this.nodes[i] = this.surface({ x: this.minX + i % this.width * CELL, z: this.minZ + Math.floor(i / this.width) * CELL });
		for (let i = 0; i < this.nodes.length; i++) {
			const a = this.nodes[i]; if (!a) continue;
			for (let d = 0; d < 8; d++) {
				const id = this.neighbor(i, d), b = id < 0 ? undefined : this.nodes[id];
				if (b && this.staticSegment(a, b)) { this.edges[i] |= 1 << d; this.edgeCosts[i * 8 + d] = this.pathCost([a, b]); }
			}
		}
	}

	private sourceHeight(point: Point): number | undefined {
		let height: number | undefined;
		for (const id of this.buckets.get(`${Math.floor(point.x / BUCKET)},${Math.floor(point.z / BUCKET)}`) ?? []) {
			const t = this.triangles[id];
			const u = ((t.bz - t.cz) * (point.x - t.cx) + (t.cx - t.bx) * (point.z - t.cz)) / t.denom;
			const v = ((t.cz - t.az) * (point.x - t.cx) + (t.ax - t.cx) * (point.z - t.cz)) / t.denom;
			if (u < -1e-5 || v < -1e-5 || u + v > 1.00001) continue;
			const y = u * t.ay + v * t.by + (1 - u - v) * t.cy;
			if (height === undefined || y > height) height = y;
		}
		return height;
	}

	heightAt(point: Point): number {
		const height = this.sourceHeight(point); if (height !== undefined) return height;
		const near = this.query?.findClosestPoint({ x: point.x, y: (this.minY + this.maxY) / 2, z: point.z }, { halfExtents: { x: 1, y: this.maxY - this.minY + 1, z: 1 } });
		return near?.success ? near.point.y : 0;
	}

	private surface(point: Point): Surface | undefined {
		if (!this.query || !Number.isFinite(point.x) || !Number.isFinite(point.z)) return undefined;
		const height = this.sourceHeight(point); if (height === undefined) return undefined;
		const near = this.query.findClosestPoint({ x: point.x, y: height, z: point.z });
		if (!near.success || !near.polyRef || Math.hypot(near.point.x - point.x, near.point.z - point.z) > 0.11 || Math.abs(near.point.y - height) > 0.36) return undefined;
		return { x: point.x, z: point.z, y: height, ref: near.polyRef, nx: near.point.x, nz: near.point.z };
	}

	private neighbor(id: number, direction: number): number {
		const [dx, dz] = DIRECTIONS[direction], x = id % this.width + dx, z = Math.floor(id / this.width) + dz;
		return x < 0 || z < 0 || x >= this.width || z >= this.depth ? -1 : z * this.width + x;
	}

	private staticSegment(a: Surface, b: Surface): boolean {
		const count = Math.max(1, Math.ceil(dist(a, b) / 0.16));
		let previousHeight = a.y;
		for (let i = 1; i <= count; i++) {
			const height = this.sourceHeight({ x: a.x + (b.x - a.x) * i / count, z: a.z + (b.z - a.z) * i / count });
			if (height === undefined || Math.abs(height - previousHeight) > 0.43) return false;
			previousHeight = height;
		}
		const ray = this.query!.raycast(a.ref, { x: a.nx, y: a.y + 0.05, z: a.nz }, { x: b.nx, y: b.y + 0.05, z: b.nz });
		if (!ray.success || ray.t < 0.999) return false;
		// The high-level WASM raycast currently allocates no visited-poly buffer
		// (maxPath=0); t is still valid. Height continuity was checked above.
		const endHeight = this.query!.getPolyHeight(ray.path.length ? ray.path[ray.path.length - 1] : b.ref, { x: b.nx, y: b.y, z: b.nz });
		return endHeight.success && Math.abs(endHeight.height - b.y) <= 0.36;
	}

	setDoorOpen(open: boolean): void { this.doorOpen = open; }
	isWalkable(point: Point): boolean { return !!this.surface(point) && (!this.settings.door || this.doorOpen || !within(point, this.settings.door, ACTOR_RADIUS)); }
	lineOfSight(a: Point, b: Point): boolean {
		return !(this.settings.solids ?? []).some(rect => intersects(a, b, rect)) && (!this.settings.door || this.doorOpen || !intersects(a, b, this.settings.door));
	}

	private dynamicPoint(point: Point, blockers: CircleBlocker[]): boolean {
		return (!this.settings.door || this.doorOpen || !within(point, this.settings.door, ACTOR_RADIUS + CLEARANCE)) && !blockers.some(circle => dist(point, circle) < circle.radius + ACTOR_RADIUS + CLEARANCE);
	}
	private dynamicSegment(a: Point, b: Point, blockers: CircleBlocker[]): boolean {
		return (!this.settings.door || this.doorOpen || !intersects(a, b, this.settings.door, ACTOR_RADIUS + CLEARANCE)) && !blockers.some(circle => circleDistance(a, b, circle) < circle.radius + ACTOR_RADIUS + CLEARANCE);
	}
	private nearNodes(point: Surface, free: Uint8Array, blockers: CircleBlocker[]): number[] {
		const x = Math.round((point.x - this.minX) / CELL), z = Math.round((point.z - this.minZ) / CELL);
		const candidates: { id: number; distance: number }[] = [];
		for (let dz = -3; dz <= 3; dz++) for (let dx = -3; dx <= 3; dx++) {
			if (x + dx < 0 || z + dz < 0 || x + dx >= this.width || z + dz >= this.depth) continue;
			const id = (z + dz) * this.width + x + dx, node = this.nodes[id];
			if (!free[id] || !node || !this.dynamicSegment(point, node, blockers) || !this.staticSegment(point, node)) continue;
			candidates.push({ id, distance: dist(point, node) });
		}
		return candidates.sort((a, b) => a.distance - b.distance).slice(0, 8).map(candidate => candidate.id);
	}

	findPath(from: Point, to: Point, blockers: CircleBlocker[] = []): Point[] | null {
		const a = this.surface(from), b = this.surface(to); if (!a || !b) return null;
		// A mover's own circle is ignored only at its exact centre. Nearby actors
		// remain real blockers, including overlapping formation members.
		const dynamic = blockers.filter(circle => Number.isFinite(circle.radius) && circle.radius >= 0 && dist(circle, from) > 0.025);
		if (!this.dynamicPoint(a, dynamic) || !this.dynamicPoint(b, dynamic)) return null;
		if (dist(a, b) < 0.02) return [{ ...from }, { ...to }];
		if (!(this.settings.difficulty?.length) && this.dynamicSegment(a, b, dynamic) && this.staticSegment(a, b)) return [{ ...from }, { ...to }];
		const base = this.query!.computePath({ x: a.nx, y: a.y, z: a.nz }, { x: b.nx, y: b.y, z: b.nz }, { maxPathPolys: 2048, maxStraightPathPoints: 1024 });
		if (!base.success || !base.path.length || dist(base.path[base.path.length - 1], to) > 0.2) return null;
		const free = new Uint8Array(this.nodes.length);
		for (let i = 0; i < this.nodes.length; i++) free[i] = this.nodes[i] && this.dynamicPoint(this.nodes[i]!, dynamic) ? 1 : 0;
		const starts = this.nearNodes(a, free, dynamic), ends = new Set(this.nearNodes(b, free, dynamic));
		if (!starts.length || !ends.size) return null;
		const costs = new Float64Array(this.nodes.length); costs.fill(Infinity);
		const parents = new Int32Array(this.nodes.length); parents.fill(-1);
		const closed = new Uint8Array(this.nodes.length), heap = new Heap();
		for (const id of starts) { costs[id] = this.pathCost([a, this.nodes[id]!]); heap.push(id, costs[id] + dist(this.nodes[id]!, b)); }
		let finish = -1;
		while (heap.length) {
			const id = heap.pop(); if (closed[id]) continue; closed[id] = 1;
			if (ends.has(id)) { finish = id; break; }
			const point = this.nodes[id]!;
			for (let d = 0; d < 8; d++) {
				if (!(this.edges[id] & 1 << d)) continue;
				const next = this.neighbor(id, d); if (next < 0 || closed[next] || !free[next]) continue;
				const target = this.nodes[next]!; if (!this.dynamicSegment(point, target, dynamic)) continue;
				const cost = costs[id] + this.edgeCosts[id * 8 + d];
				if (cost < costs[next]) { costs[next] = cost; parents[next] = id; heap.push(next, cost + dist(target, b)); }
			}
		}
		if (finish < 0) return null;
		const path: Surface[] = [b];
		for (let id = finish; id >= 0; id = parents[id]) path.push(this.nodes[id]!);
		path.push(a); path.reverse();
		const output: Point[] = [{ ...from }];
		for (let i = 0; i < path.length - 1;) {
			let j = Math.min(path.length - 1, i + 24);
			while (j > i + 1 && (!this.dynamicSegment(path[i], path[j], dynamic) || !this.staticSegment(path[i], path[j]) || this.pathCost([path[i], path[j]]) > this.pathCost(path.slice(i, j + 1)) + 0.03)) j--;
			output.push({ x: path[j].x, z: path[j].z }); i = j;
		}
		return output;
	}

	pathCost(path: Point[]): number {
		let cost = 0;
		for (let i = 1; i < path.length; i++) {
			const a = path[i - 1], b = path[i], length = dist(a, b), samples = Math.max(1, Math.ceil(length / 0.12));
			for (let j = 0; j < samples; j++) {
				const p = { x: a.x + (b.x - a.x) * (j + 0.5) / samples, z: a.z + (b.z - a.z) * (j + 0.5) / samples };
				cost += length / samples * ((this.settings.difficulty ?? []).some(rect => within(p, rect)) ? 2 : 1);
			}
		}
		return cost;
	}

	dispose(): void { this.query?.destroy(); this.navMesh?.destroy(); this.query = undefined; this.navMesh = undefined; this.nodes = []; this.edges = new Uint8Array(0); }
}
