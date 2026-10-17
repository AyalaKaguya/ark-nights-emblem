import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { SourceGeometrySight, sourceIsArchitecture, type SourceGeometryInstance } from './source-geometry';

const instance: SourceGeometryInstance = { id: 'wall', name: 'S_outworld_building1', active: true, bounds: { min: [-2, 0, -1], max: [2, 4, 1] }, ranges: [{ chunkId: 'wall', indexStart: 0, indexCount: 6 }] };
// A wall at x=0 whose actual triangles cover only z>0, despite a larger AABB.
const chunk = { id: 'wall', positions: new Float32Array([0, 0, 0, 0, 4, 0, 0, 4, 1, 0, 0, 1]), indices: new Uint32Array([0, 1, 2, 0, 2, 3]) };
const sight = new SourceGeometrySight([chunk], [instance]);

describe('original geometry line of sight', () => {
	it('blocks actual architecture triangles from either direction', () => {
		expect(sight.blocked({ x: -1, y: 0.7, z: 0.5 }, { x: 1, y: 0.7, z: 0.5 })).toBe(true);
		expect(sight.blocked({ x: 1, y: 0.7, z: 0.5 }, { x: -1, y: 0.7, z: 0.5 })).toBe(true);
	});
	it('does not turn the entire bounds into a solid or obstruct above a low wall', () => {
		expect(sight.blocked({ x: -1, y: 0.7, z: -0.5 }, { x: 1, y: 0.7, z: -0.5 })).toBe(false);
		expect(sight.blocked({ x: -1, y: 4.5, z: 0.5 }, { x: 1, y: 4.5, z: 0.5 })).toBe(false);
	});
	it('keeps duplicated/layered ground, water and decorations out of sight solids', () => {
		for (const name of ['S_outworld_halfground_1', 'S_playground_low20', 'S_outworld_water_3', 'S_outworld_Roofgrass2']) expect(sourceIsArchitecture({ ...instance, name })).toBe(false);
		expect([...sight.maskFor(chunk)]).toEqual([1, 1, 1, 1]);
	});
	it('uses original runtime instance triangle ranges without treating bounds as walls', () => {
		const data = JSON.parse(readFileSync(new URL('../../public/maps/hotel/scene-runtime.json', import.meta.url), 'utf8'));
		const binary = readFileSync(new URL('../../public/maps/hotel/geometry.bin', import.meta.url));
		const buffer = binary.buffer.slice(binary.byteOffset, binary.byteOffset + binary.byteLength);
		const chunks = data.meshes.map((mesh: { id: string; positions: { offset: number; length: number }; indices: { offset: number; length: number } }) => ({ id: mesh.id, positions: new Float32Array(buffer, mesh.positions.offset, mesh.positions.length), indices: new Uint32Array(buffer, mesh.indices.offset, mesh.indices.length) }));
		const actual = new SourceGeometrySight(chunks, data.instances);
		expect(actual.architecture.length).toBeGreaterThan(200);
		expect(actual.architecture.some(instance => /halfground|playground|water|flow/i.test(instance.name))).toBe(false);
		const started = performance.now();
		for (let i = 0; i < 20; i++) actual.blocked({ x: 21, y: .7, z: 23 }, { x: 26 + i % 3, y: .7, z: 15 });
		expect((performance.now() - started) / 20).toBeLessThan(15);
		// Pick an actual upright source triangle and cross its interior at normal.
		let checked = false;
		for (const instance of actual.architecture) {
			if (checked) break;
			for (const range of instance.ranges) {
				const source = chunks.find((chunk: { id: string }) => chunk.id === range.chunkId)!;
				for (let i = range.indexStart; i < range.indexStart + range.indexCount; i += 3) {
					const [a, b, c] = [source.indices[i] * 3, source.indices[i + 1] * 3, source.indices[i + 2] * 3], p = source.positions;
					const e1 = [p[b] - p[a], p[b + 1] - p[a + 1], p[b + 2] - p[a + 2]], e2 = [p[c] - p[a], p[c + 1] - p[a + 1], p[c + 2] - p[a + 2]];
					const normal = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
					const length = Math.hypot(...normal); if (length < .1 || Math.abs(normal[1]) > length * .25) continue;
					const center = [(p[a] + p[b] + p[c]) / 3, (p[a + 1] + p[b + 1] + p[c + 1]) / 3, (p[a + 2] + p[b + 2] + p[c + 2]) / 3];
					const from = { x: center[0] - normal[0] / length * .1, y: center[1] - normal[1] / length * .1, z: center[2] - normal[2] / length * .1 };
					const to = { x: center[0] + normal[0] / length * .1, y: center[1] + normal[1] / length * .1, z: center[2] + normal[2] / length * .1 };
					expect(actual.blocked(from, to)).toBe(true); checked = true; break;
				}
				if (checked) break;
			}
		}
		expect(checked).toBe(true);
	});
});
