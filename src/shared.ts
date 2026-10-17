export interface Point { x: number; z: number }
export interface CircleBlocker extends Point { radius: number; id?: string }
export interface Rect { x: number; z: number; width: number; depth: number }
export interface Navigation {
	findPath(from: Point, to: Point, blockers?: CircleBlocker[]): Point[] | null;
	pathCost(path: Point[]): number;
	lineOfSight(from: Point, to: Point): boolean;
	isWalkable(point: Point): boolean;
	setDoorOpen(open: boolean): void;
	readonly doorOpen: boolean;
}
export interface Interaction extends Point {
	id: 'reception' | 'door' | 'supply';
	label: string;
	radius: number;
}
export const PARTY_SPAWNS: Point[] = [{ x: 21.1667, z: 23.1673 }, { x: 19.1667, z: 23.8346 }, { x: 23.1667, z: 23.1673 }];
export const ENEMY_SPAWNS: Point[] = [{ x: 26.1667, z: 16.8333 }, { x: 29.1667, z: 15.5 }, { x: 29.1667, z: 11.1667 }, { x: 30.5, z: 10.5 }];
export const ENCOUNTER_TRIGGER: Rect = { x: 25.7, z: 16.5, width: 2.5, depth: 4 };
/** Prototype wet-stone cost beside the original western spring; not official terrain metadata. */
export const DIFFICULT_TERRAIN: Rect[] = [{ x: 8.8, z: 20, width: 1.2, depth: 5 }];
export const INTERACTIONS: Interaction[] = [
	{ id: 'reception', label: '接待员', x: 22.1667, z: 16.8333, radius: 2.3 },
	{ id: 'door', label: '庭院通行点', x: 24.8333, z: 16.8333, radius: 2.3 },
	{ id: 'supply', label: '旅行补给', x: 29.1667, z: 19.8317, radius: 2.3 },
];
export const distance = (a: Point, b: Point): number => Math.hypot(a.x - b.x, a.z - b.z);
export const inRect = (p: Point, r: Rect): boolean => Math.abs(p.x - r.x) <= r.width / 2 && Math.abs(p.z - r.z) <= r.depth / 2;
