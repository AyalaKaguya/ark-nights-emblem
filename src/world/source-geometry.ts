export interface SourceVector3 { x: number; y: number; z: number }
export interface SourceGeometryChunk { id: string; positions: ArrayLike<number>; indices: ArrayLike<number> }
export interface SourceGeometryInstance {
	id: string;
	name: string;
	active: boolean;
	bounds: { min: number[]; max: number[] };
	ranges: { chunkId: string; indexStart: number; indexCount: number }[];
}

/** Architectural names only; terrain holes and layered grounds are never walls. */
export function sourceIsArchitecture(instance: SourceGeometryInstance): boolean {
	return instance.active && /(?:buildings?|wall(?:corner)?|entrance|tower)/i.test(instance.name) &&
		!/(?:halfground|playground|background|water|flow|spring|flower|grass)/i.test(instance.name) &&
		instance.bounds.max[1] - instance.bounds.min[1] > 0.4;
}

function segmentBox(a: SourceVector3, b: SourceVector3, bounds: SourceGeometryInstance['bounds']): boolean {
	let min = 0, max = 1;
	for (const [axis, index] of [['x', 0], ['y', 1], ['z', 2]] as const) {
		const delta = b[axis] - a[axis];
		if (Math.abs(delta) < 1e-9) { if (a[axis] < bounds.min[index] || a[axis] > bounds.max[index]) return false; continue; }
		const t0 = (bounds.min[index] - a[axis]) / delta, t1 = (bounds.max[index] - a[axis]) / delta;
		min = Math.max(min, Math.min(t0, t1)); max = Math.min(max, Math.max(t0, t1));
		if (min > max) return false;
	}
	return true;
}

/** Two-sided Möller-Trumbore finite ray. Endpoint touches are deliberately
 * excluded so standing beside a wall doesn't obstruct one's own eye position.
 */
export function sourceSegmentTriangle(a: SourceVector3, b: SourceVector3, positions: ArrayLike<number>, ia: number, ib: number, ic: number): boolean {
	const ax = positions[ia], ay = positions[ia + 1], az = positions[ia + 2];
	const e1x = positions[ib] - ax, e1y = positions[ib + 1] - ay, e1z = positions[ib + 2] - az;
	const e2x = positions[ic] - ax, e2y = positions[ic + 1] - ay, e2z = positions[ic + 2] - az;
	const dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z;
	const px = dy * e2z - dz * e2y, py = dz * e2x - dx * e2z, pz = dx * e2y - dy * e2x;
	const det = e1x * px + e1y * py + e1z * pz;
	if (Math.abs(det) < 1e-9) return false;
	const inverse = 1 / det, tx = a.x - ax, ty = a.y - ay, tz = a.z - az;
	const u = (tx * px + ty * py + tz * pz) * inverse;
	if (u < -1e-6 || u > 1.000001) return false;
	const qx = ty * e1z - tz * e1y, qy = tz * e1x - tx * e1z, qz = tx * e1y - ty * e1x;
	const v = (dx * qx + dy * qy + dz * qz) * inverse;
	if (v < -1e-6 || u + v > 1.000001) return false;
	const t = (e2x * qx + e2y * qy + e2z * qz) * inverse;
	return t > 0.003 && t < 0.997;
}

/** Uses each original renderer's world-space merged triangle ranges. Bounds are
 * a broad phase only: windows, empty courtyards and archways within bounds remain
 * unobstructed unless an actual triangle intersects the 3D ray.
 */
export class SourceGeometrySight {
	readonly architecture: SourceGeometryInstance[];
	private chunks = new Map<string, SourceGeometryChunk>();
	constructor(chunks: SourceGeometryChunk[], instances: SourceGeometryInstance[]) {
		for (const chunk of chunks) this.chunks.set(chunk.id, chunk);
		this.architecture = instances.filter(sourceIsArchitecture);
	}
	blocked(from: SourceVector3, to: SourceVector3): boolean {
		for (const instance of this.architecture) {
			if (!segmentBox(from, to, instance.bounds)) continue;
			for (const range of instance.ranges) {
				const chunk = this.chunks.get(range.chunkId); if (!chunk) continue;
				const end = Math.min(chunk.indices.length, range.indexStart + range.indexCount);
				for (let i = range.indexStart; i + 2 < end; i += 3) {
					if (sourceSegmentTriangle(from, to, chunk.positions, chunk.indices[i] * 3, chunk.indices[i + 1] * 3, chunk.indices[i + 2] * 3)) return true;
				}
			}
		}
		return false;
	}
	/** Vertex mask limits the camera cutaway to source architecture only. */
	maskFor(chunk: SourceGeometryChunk): Float32Array {
		const mask = new Float32Array(chunk.positions.length / 3);
		for (const instance of this.architecture) for (const range of instance.ranges) {
			if (range.chunkId !== chunk.id) continue;
			for (let i = range.indexStart; i < Math.min(chunk.indices.length, range.indexStart + range.indexCount); i++) mask[chunk.indices[i]] = 1;
		}
		return mask;
	}
}
