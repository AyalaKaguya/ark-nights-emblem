import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { SourceNavigation, type SourceNavData } from './source-navigation';
import type { Point } from '../shared';

function testFloor(): SourceNavData {
	const positions: number[] = [], indices: number[] = [];
	for (let z = 0; z < 10; z++) for (let x = 0; x < 16; x++) {
		if (x >= 6 && x < 10 && z >= 3 && z < 7) continue;
		const id = positions.length / 3;
		positions.push(x, x * 0.08, z, x, x * 0.08, z + 1, x + 1, (x + 1) * 0.08, z + 1, x + 1, (x + 1) * 0.08, z);
		indices.push(id, id + 1, id + 2, id, id + 2, id + 3);
	}
	return { positions, indices };
}
const original = JSON.parse(readFileSync(new URL('../../public/maps/hotel/scene.json', import.meta.url), 'utf8')).navigation[0] as SourceNavData;
const source = new SourceNavigation(original);
const fixture = new SourceNavigation(testFloor(), { door: { x: 3, z: 5, width: 0.2, depth: 10 }, difficulty: [{ x: 12, z: 5, width: 2, depth: 4 }], solids: [{ x: 8, z: 5, width: 4, depth: 4 }] });
beforeAll(async () => { await source.init(); await fixture.init(); }, 30_000);
afterAll(() => { source.dispose(); fixture.dispose(); });

function checkPath(navigation: SourceNavigation, path: Point[] | null): asserts path is Point[] {
	expect(path).not.toBeNull(); if (!path) throw new Error('No route');
	for (let i = 0; i < path.length; i++) {
		expect(navigation.isWalkable(path[i])).toBe(true);
		if (!i) continue;
		const a = path[i - 1], b = path[i], count = Math.max(1, Math.ceil(Math.hypot(a.x - b.x, a.z - b.z) / 0.08));
		for (let j = 0; j <= count; j++) expect(navigation.isWalkable({ x: a.x + (b.x - a.x) * j / count, z: a.z + (b.z - a.z) * j / count })).toBe(true);
	}
}

describe('original source navigation', () => {
	it('rebuilds the exported 966 vertex source and keeps original heights', () => {
		expect(original.positions.length / 3).toBe(966);
		const samples: Point[] = [];
		for (let i = 0; i < original.indices.length; i += 30) {
			const ids = original.indices.slice(i, i + 3).map(id => id * 3);
			const p = { x: ids.reduce((sum, id) => sum + original.positions[id], 0) / 3, z: ids.reduce((sum, id) => sum + original.positions[id + 2], 0) / 3 };
			if (source.isWalkable(p)) samples.push(p);
		}
		expect(samples.length).toBeGreaterThan(40);
		for (const p of samples) expect(Number.isFinite(source.heightAt(p))).toBe(true);
		expect(source.isWalkable({ x: -100, z: -100 })).toBe(false);
		const first = samples[0];
		const routes = samples.slice(1).map(point => source.findPath(first, point)).filter(Boolean);
		expect(routes.length).toBeGreaterThan(10);
		for (const route of routes.slice(0, 8)) checkPath(source, route);
	});
	it('interpolates an elevated floor rather than flattening actors to zero', () => {
		expect(fixture.heightAt({ x: 12.25, z: 8 })).toBeCloseTo(0.98, 5);
	});
	it('preserves source holes, route boundaries and explicit sight occluders', () => {
		fixture.setDoorOpen(true);
		expect(fixture.isWalkable({ x: 8, z: 5 })).toBe(false);
		const path = fixture.findPath({ x: 4, z: 5 }, { x: 12, z: 5 });
		checkPath(fixture, path);
		expect(fixture.pathCost(path)).toBeGreaterThan(8.5);
		expect(fixture.lineOfSight({ x: 4, z: 5 }, { x: 12, z: 5 })).toBe(false);
	});
	it('adds only the optional virtual door and restores paths on opening', () => {
		fixture.setDoorOpen(false);
		expect(fixture.findPath({ x: 1, z: 2 }, { x: 5, z: 2 })).toBeNull();
		fixture.setDoorOpen(true);
		checkPath(fixture, fixture.findPath({ x: 1, z: 2 }, { x: 5, z: 2 }));
	});
	it('routes around occupied actors without ignoring nearby actors as the mover', () => {
		fixture.setDoorOpen(true);
		const blocker = { x: 3, z: 2, radius: 0.35 };
		const path = fixture.findPath({ x: 1, z: 2 }, { x: 5, z: 2 }, [blocker]);
		checkPath(fixture, path);
		expect(path.some(p => Math.abs(p.z - 2) > 0.6)).toBe(true);
		expect(fixture.findPath({ x: 1, z: 2 }, blocker, [blocker])).toBeNull();
		expect(fixture.findPath({ x: 1, z: 2 }, { x: 5, z: 2 }, [{ x: 1.1, z: 2, radius: 0.35 }])).toBeNull();
	});
	it('charges the configured difficult zone twice', () => {
		expect(fixture.pathCost([{ x: 12, z: 4 }, { x: 12, z: 6 }])).toBeCloseTo(4, 5);
		expect(fixture.pathCost([{ x: 14, z: 4 }, { x: 14, z: 6 }])).toBeCloseTo(2, 5);
	});
	it('computes a source-map route with live unit avoidance within the interactive budget', () => {
		const pairs = [
			[{ x: 6, z: 1 }, { x: 25, z: 0 }],
			[{ x: 25, z: 0 }, { x: 30.8, z: 21 }],
			[{ x: 30.8, z: 21 }, { x: 37.4, z: 12 }],
			[{ x: 6, z: 1 }, { x: 23, z: 8 }],
		] as [Point, Point][];
		const results = pairs.map(([from, to]) => {
			const time = performance.now(), path = source.findPath(from, to, [{ x: 15, z: 1, radius: 0.35 }]);
			return { from, to, path, ms: performance.now() - time };
		});
		console.log('Source path timings', results.map(({ from, to, path, ms }) => ({ from, to, points: path?.length ?? null, ms: Number(ms.toFixed(2)) })));
		expect(results.filter(result => result.path).length).toBeGreaterThanOrEqual(2);
		for (const result of results) if (result.path) { checkPath(source, result.path); expect(result.ms).toBeLessThan(60); }
	});
	it('admits the original southern arrival and keeps the northern route connected', () => {
		for (const p of [{ x: 21, z: 23 }, { x: 20, z: 24 }, { x: 22, z: 24 }]) expect(source.isWalkable(p)).toBe(true);
		checkPath(source, source.findPath({ x: 21, z: 23 }, { x: 23, z: 8 }));
		expect(source.heightAt({ x: 21, z: 23 })).toBeCloseTo(-0.01, 2);
	});
});
