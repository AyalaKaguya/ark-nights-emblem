import { describe, expect, it } from 'vitest';
import type { CircleBlocker, Navigation, Point } from '../shared';
import {
	BODY_RADIUS, MOVEMENT_PER_TURN, chooseEnemyCommand, createBattle, createBattleRules,
	currentUnit, damageAmount,
} from './index';
import type { BattleState, Command, Unit } from './index';

/** A predictable geometry oracle keeps tests independent of Babylon and browser rendering. */
class MockNavigation implements Navigation {
	doorOpen = true;
	multiplier = 1;
	blocked = false;
	visible = true;
	route: Point[] | null | undefined;
	lastBlockers: CircleBlocker[] = [];
	findPath(from: Point, to: Point, blockers: CircleBlocker[] = []): Point[] | null {
		this.lastBlockers = blockers;
		if (this.route !== undefined) return this.route;
		return this.blocked ? null : [{ ...from }, { ...to }];
	}
	pathCost(path: Point[]): number {
		return path.slice(1).reduce((sum, point, i) => sum + Math.hypot(point.x - path[i].x, point.z - path[i].z), 0) * this.multiplier;
	}
	lineOfSight(): boolean { return this.visible && this.doorOpen; }
	isWalkable(point: Point): boolean { return !this.blocked && Math.abs(point.x) <= 50 && Math.abs(point.z) <= 50; }
	setDoorOpen(open: boolean): void { this.doorOpen = open; }
}

const get = (state: BattleState, id: string): Unit => state.units.find(unit => unit.id === id)!;
const last = <T>(values: T[]): T => values[values.length - 1];
const active = (state: BattleState, id = 'amiya'): void => { state.turnIndex = state.order.indexOf(id); };
function setup(): { state: BattleState; nav: MockNavigation; rules: ReturnType<typeof createBattleRules> } {
	const state = createBattle([{ x: 0, z: 0 }, { x: -20, z: 0 }, { x: 20, z: 0 }]);
	get(state, 'enemy-melee-1').position = { x: 0, z: -6 };
	get(state, 'enemy-melee-2').position = { x: 4, z: -6 };
	get(state, 'enemy-ranged-1').position = { x: -5, z: -15 };
	get(state, 'enemy-ranged-2').position = { x: 5, z: -15 };
	const nav = new MockNavigation();
	return { state, nav, rules: createBattleRules(nav) };
}

function deepFreeze<T>(value: T): T {
	if (value && typeof value === 'object') {
		Object.freeze(value);
		for (const item of Object.values(value)) deepFreeze(item);
	}
	return value;
}

describe('battle creation and independent turn budgets', () => {
	it('creates three named operators, four enemies and fixed descending initiative', () => {
		const state = createBattle([{ x: 1, z: 2 }]);
		expect(state.units.filter(unit => unit.team === 'party').map(unit => unit.name)).toEqual(['阿米娅', '星熊', '安赛尔']);
		expect(state.units.filter(unit => unit.team === 'enemy')).toHaveLength(4);
		expect(state.order.slice(0, 3)).toEqual(['amiya', 'ansel', 'hoshiguma']);
		expect(state.order.slice(3)).toEqual(['enemy-melee-1', 'enemy-melee-2', 'enemy-ranged-1', 'enemy-ranged-2']);
		expect(currentUnit(state)?.id).toBe('amiya');
		for (const unit of state.units) expect(unit.budget).toEqual({ movement: 9, action: 1, bonus: 1, reaction: 1 });
	});

	it('copies spawn positions and state before changing them', () => {
		const spawn = { x: 0, z: 0 };
		const state = createBattle([spawn]);
		get(state, 'amiya').position.x = 8;
		expect(spawn.x).toBe(0);
	});

	it('resets only the next living unit and retains other units reaction use', () => {
		const { state, rules } = setup();
		get(state, 'ansel').budget = { movement: 2, action: 0, bonus: 0, reaction: 0 };
		get(state, 'enemy-melee-1').budget.reaction = 0;
		const result = rules.applyCommand(state, { type: 'endTurn', unitId: 'amiya' });
		expect(currentUnit(result.state)?.id).toBe('ansel');
		expect(get(result.state, 'ansel').budget).toEqual({ movement: 9, action: 1, bonus: 1, reaction: 1 });
		expect(get(result.state, 'enemy-melee-1').budget.reaction).toBe(0);
	});

	it('skips dead units and wraps rounds without giving them turns', () => {
		const { state, rules } = setup();
		get(state, 'ansel').hp = 0;
		let result = rules.applyCommand(state, { type: 'endTurn', unitId: 'amiya' });
		expect(currentUnit(result.state)?.id).toBe('hoshiguma');
		active(result.state, 'enemy-ranged-2');
		result = rules.applyCommand(result.state, { type: 'endTurn', unitId: 'enemy-ranged-2' });
		expect(result.state.round).toBe(2);
		expect(currentUnit(result.state)?.id).toBe('amiya');
	});
});

describe('continuous navigation, costs and occupancy', () => {
	it('uses path length instead of straight distance and keeps both API calls pure', () => {
		const { state, nav, rules } = setup();
		nav.route = [{ x: 0, z: 0 }, { x: 0, z: 3 }, { x: 4, z: 3 }];
		const before = JSON.stringify(state);
		deepFreeze(state);
		const command: Command = { type: 'move', unitId: 'amiya', to: { x: 4, z: 3 } };
		expect(rules.previewCommand(state, command).cost).toBe(7);
		const result = rules.applyCommand(state, command);
		expect(result.ok).toBe(true);
		expect(get(result.state, 'amiya').budget.movement).toBe(2);
		expect(get(result.state, 'amiya').position).toEqual({ x: 4, z: 3 });
		expect(JSON.stringify(state)).toBe(before);
		expect(nav.lastBlockers).toHaveLength(6);
		expect(nav.lastBlockers[0].radius).toBe(BODY_RADIUS);
	});

	it('charges difficult terrain and rejects over-budget movement with no state changes', () => {
		const { state, nav, rules } = setup();
		nav.multiplier = 2;
		const move: Command = { type: 'move', unitId: 'amiya', to: { x: 4, z: 0 } };
		expect(rules.previewCommand(state, move).cost).toBe(8);
		const result = rules.applyCommand(state, move);
		expect(get(result.state, 'amiya').budget.movement).toBe(1);
		const failed = rules.applyCommand(state, { ...move, to: { x: 5, z: 0 } });
		expect(failed.ok).toBe(false);
		expect(failed.state).toEqual(state);
		expect(failed.events).toEqual([]);
	});

	it('rejects occupied destinations and sparse paths that cross circular bodies', () => {
		const { state, rules } = setup();
		get(state, 'ansel').position = { x: 2, z: 0 };
		expect(rules.previewCommand(state, { type: 'move', unitId: 'amiya', to: { x: 2.2, z: 0 } }).ok).toBe(false);
		expect(rules.previewCommand(state, { type: 'move', unitId: 'amiya', to: { x: 4, z: 0 } }).ok).toBe(false);
		get(state, 'ansel').hp = 0;
		expect(rules.previewCommand(state, { type: 'move', unitId: 'amiya', to: { x: 4, z: 0 } }).ok).toBe(true);
	});

	it('rejects no route, incomplete routes, invalid numbers and non-walkable points', () => {
		const { state, nav, rules } = setup();
		const move: Command = { type: 'move', unitId: 'amiya', to: { x: 4, z: 0 } };
		nav.route = null;
		expect(rules.previewCommand(state, move).ok).toBe(false);
		nav.route = [{ x: 0, z: 0 }, { x: 2, z: 0 }];
		expect(rules.previewCommand(state, move).ok).toBe(false);
		nav.route = undefined;
		expect(rules.previewCommand(state, { ...move, to: { x: NaN, z: 0 } }).ok).toBe(false);
		nav.blocked = true;
		expect(rules.previewCommand(state, move).ok).toBe(false);
	});

	it('can split movement around one major action without spending bonus or reaction', () => {
		const { state, rules } = setup();
		let next = rules.applyCommand(state, { type: 'move', unitId: 'amiya', to: { x: 1, z: 0 } }).state;
		next = rules.applyCommand(next, { type: 'attack', unitId: 'amiya', targetId: 'enemy-melee-1' }).state;
		next = rules.applyCommand(next, { type: 'move', unitId: 'amiya', to: { x: 2, z: 0 } }).state;
		expect(get(next, 'amiya').budget).toEqual({ movement: 7, action: 0, bonus: 1, reaction: 1 });
		expect(rules.previewCommand(next, { type: 'attack', unitId: 'amiya', targetId: 'enemy-melee-1' }).ok).toBe(false);
	});
});

describe('opportunity reactions along the actual path', () => {
	function reactionSetup() {
		const test = setup();
		get(test.state, 'enemy-melee-1').position = { x: 0, z: 1.2 };
		return test;
	}

	it('reacts on exiting a melee circle and cannot react twice before its own turn', () => {
		const { state, rules } = reactionSetup();
		const first = rules.applyCommand(state, { type: 'move', unitId: 'amiya', to: { x: -2, z: 0 } });
		expect(first.events.filter(event => event.type === 'opportunity')).toHaveLength(1);
		expect(first.events.map(event => event.type)).toEqual(['move', 'opportunity', 'damage', 'move', 'movementComplete']);
		const segments = first.events.filter(event => event.type === 'move');
		expect(segments).toHaveLength(2);
		expect(last(segments[0].path!)).toEqual(segments[1].path![0]);
		expect(last(segments[0].path!).x).toBeCloseTo(-Math.sqrt(1.8 ** 2 - 1.2 ** 2));
		expect(first.events.find(event => event.type === 'movementComplete')!.amount).toBeCloseTo(2);
		expect(get(first.state, 'amiya').hp).toBe(45);
		expect(get(first.state, 'enemy-melee-1').budget.reaction).toBe(0);
		const back = rules.applyCommand(first.state, { type: 'move', unitId: 'amiya', to: { x: 0, z: 0 } });
		const again = rules.applyCommand(back.state, { type: 'move', unitId: 'amiya', to: { x: -2, z: 0 } });
		expect(again.events.some(event => event.type === 'opportunity')).toBe(false);
		expect(get(again.state, 'amiya').hp).toBe(45);
		active(again.state, 'hoshiguma');
		const enemyTurn = rules.applyCommand(again.state, { type: 'endTurn', unitId: 'hoshiguma' });
		expect(currentUnit(enemyTurn.state)?.id).toBe('enemy-melee-1');
		expect(get(enemyTurn.state, 'enemy-melee-1').budget.reaction).toBe(1);
	});

	it('detects an enter-and-exit crossing inside one long segment', () => {
		const { state, rules } = reactionSetup();
		get(state, 'amiya').position = { x: -3, z: 0 };
		const result = rules.applyCommand(state, { type: 'move', unitId: 'amiya', to: { x: 3, z: 0 } });
		expect(result.ok).toBe(true);
		expect(result.events.filter(event => event.type === 'opportunity')).toHaveLength(1);
	});

	it('does not react on entry, ranged threats or through walls', () => {
		const { state, nav, rules } = reactionSetup();
		get(state, 'amiya').position = { x: -3, z: 0 };
		const entering = rules.applyCommand(state, { type: 'move', unitId: 'amiya', to: { x: 0, z: 0 } });
		expect(entering.events.some(event => event.type === 'opportunity')).toBe(false);
		nav.visible = false;
		const obscured = rules.applyCommand(entering.state, { type: 'move', unitId: 'amiya', to: { x: -2, z: 0 } });
		expect(obscured.events.some(event => event.type === 'opportunity')).toBe(false);
		nav.visible = true;
		get(state, 'enemy-melee-1').range = 10;
		get(state, 'amiya').position = { x: 0, z: 0 };
		const ranged = rules.applyCommand(state, { type: 'move', unitId: 'amiya', to: { x: -2, z: 0 } });
		expect(ranged.events.some(event => event.type === 'opportunity')).toBe(false);
	});

	it('dash adds movement but provokes; disengage spends the major action and prevents reactions', () => {
		const { state, rules } = reactionSetup();
		const dash = rules.applyCommand(state, { type: 'dash', unitId: 'amiya' });
		expect(get(dash.state, 'amiya').budget.movement).toBe(MOVEMENT_PER_TURN * 2);
		expect(get(dash.state, 'amiya').budget.action).toBe(0);
		expect(rules.applyCommand(dash.state, { type: 'move', unitId: 'amiya', to: { x: -2, z: 0 } }).events.some(event => event.type === 'opportunity')).toBe(true);
		const disengage = rules.applyCommand(state, { type: 'disengage', unitId: 'amiya' });
		expect(get(disengage.state, 'amiya').budget.action).toBe(0);
		const move = rules.applyCommand(disengage.state, { type: 'move', unitId: 'amiya', to: { x: -2, z: 0 } });
		expect(move.events.some(event => event.type === 'opportunity')).toBe(false);
		expect(get(move.state, 'enemy-melee-1').budget.reaction).toBe(1);
	});

	it('death truncates movement at the reaction point and immediately advances to a living unit', () => {
		const { state, rules } = reactionSetup();
		get(state, 'amiya').hp = 1;
		const result = rules.applyCommand(state, { type: 'move', unitId: 'amiya', to: { x: -4, z: 0 } });
		expect(get(result.state, 'amiya').hp).toBe(0);
		expect(get(result.state, 'amiya').position.x).toBeCloseTo(-Math.sqrt(1.8 ** 2 - 1.2 ** 2));
		expect(get(result.state, 'amiya').budget.movement).toBeCloseTo(9 - Math.sqrt(1.8 ** 2 - 1.2 ** 2));
		expect(currentUnit(result.state)?.id).toBe('ansel');
		expect(result.events.filter(event => event.type === 'opportunity')).toHaveLength(1);
		expect(result.events.map(event => event.type)).toEqual(['move', 'opportunity', 'damage', 'death', 'movementComplete', 'turn']);
		const moves = result.events.filter(event => event.type === 'move');
		expect(moves).toHaveLength(1);
		expect(last(moves[0].path!)).toEqual(get(result.state, 'amiya').position);
		expect(result.events.find(event => event.type === 'movementComplete')!.amount).toBeCloseTo(moves[0].amount!);
		expect(get(result.state, 'amiya').budget.reaction).toBe(1);
	});

	it('emits successive path fragments before each reaction and charges their total once', () => {
		const { state, nav, rules } = reactionSetup();
		get(state, 'enemy-melee-2').position = { x: 1, z: 1.2 };
		nav.multiplier = 2;
		const result = rules.applyCommand(state, { type: 'move', unitId: 'amiya', to: { x: 4, z: 0 } });
		expect(result.ok).toBe(true);
		expect(result.events.map(event => event.type)).toEqual(['move', 'opportunity', 'damage', 'move', 'opportunity', 'damage', 'move', 'movementComplete']);
		const moves = result.events.filter(event => event.type === 'move');
		expect(moves).toHaveLength(3);
		expect(last(moves[0].path!)).toEqual(moves[1].path![0]);
		expect(last(moves[1].path!)).toEqual(moves[2].path![0]);
		const summary = result.events.find(event => event.type === 'movementComplete')!;
		expect(moves.reduce((sum, event) => sum + event.amount!, 0)).toBeCloseTo(summary.amount!);
		expect(summary.amount).toBeCloseTo(8);
		expect(get(result.state, 'amiya').budget.movement).toBeCloseTo(1);
		expect(get(result.state, 'amiya').position).toEqual({ x: 4, z: 0 });
	});

	it('stops later reactions after a fatal reaction and resolves defeat immediately', () => {
		const { state, rules } = reactionSetup();
		get(state, 'ansel').hp = 0;
		get(state, 'hoshiguma').hp = 0;
		get(state, 'amiya').hp = 1;
		get(state, 'enemy-melee-2').position = { x: -1, z: 1.2 };
		const result = rules.applyCommand(state, { type: 'move', unitId: 'amiya', to: { x: -4, z: 0 } });
		expect(result.state.outcome).toBe('defeat');
		expect(currentUnit(result.state)).toBeNull();
		expect(result.events.filter(event => event.type === 'opportunity')).toHaveLength(1);
		expect(get(result.state, 'enemy-melee-2').budget.reaction).toBe(1);
	});
});

describe('operator skills, action limits and formulas', () => {
	it('keeps Arknights-style physical and arts damage deterministic', () => {
		const { state } = setup();
		const target = get(state, 'hoshiguma');
		expect(damageAmount(2, 'physical', target)).toBe(1);
		expect(damageAmount(20, 'physical', target)).toBe(13);
		target.resistance = 25;
		expect(damageAmount(18, 'arts', target)).toBe(14);
		target.resistance = 100;
		expect(damageAmount(18, 'arts', target)).toBe(1);
	});

	it('Amiya AOE damages several visible enemies, excludes allies and spends one major action', () => {
		const { state, rules } = setup();
		get(state, 'enemy-melee-2').position = { x: 2, z: -6 };
		get(state, 'ansel').position = { x: 1, z: -6 };
		const command: Command = { type: 'skill', unitId: 'amiya', targetId: 'enemy-melee-1' };
		expect(rules.previewCommand(state, command).targetIds).toEqual(['enemy-melee-1', 'enemy-melee-2']);
		const result = rules.applyCommand(state, command);
		expect(get(result.state, 'enemy-melee-1').hp).toBe(12);
		expect(get(result.state, 'enemy-melee-2').hp).toBe(10);
		expect(get(result.state, 'ansel').hp).toBe(52);
		expect(get(result.state, 'amiya').budget.action).toBe(0);
		expect(rules.previewCommand(result.state, command).ok).toBe(false);
	});

	it('Hoshiguma guarding halves incoming damage until her own next turn', () => {
		const { state, rules } = setup();
		active(state, 'hoshiguma');
		const result = rules.applyCommand(state, { type: 'skill', unitId: 'hoshiguma' });
		expect(get(result.state, 'hoshiguma').guarding).toBe(true);
		expect(damageAmount(19, 'physical', get(result.state, 'hoshiguma'))).toBe(6);
		get(result.state, 'amiya').hp = 0;
		get(result.state, 'ansel').hp = 0;
		active(result.state, 'enemy-ranged-2');
		const next = rules.applyCommand(result.state, { type: 'endTurn', unitId: 'enemy-ranged-2' });
		expect(currentUnit(next.state)?.id).toBe('hoshiguma');
		expect(get(next.state, 'hoshiguma').guarding).toBe(false);
	});

	it('Ansel heals a living ally up to maximum HP and requires range and visibility', () => {
		const { state, nav, rules } = setup();
		active(state, 'ansel');
		get(state, 'ansel').position = { x: 3, z: 0 };
		get(state, 'amiya').hp = 50;
		const command: Command = { type: 'skill', unitId: 'ansel', targetId: 'amiya' };
		expect(rules.previewCommand(state, command).amount).toBe(4);
		const result = rules.applyCommand(state, command);
		expect(get(result.state, 'amiya').hp).toBe(54);
		expect(result.events.find(event => event.type === 'heal')?.amount).toBe(4);
		nav.visible = false;
		expect(rules.previewCommand(state, command).ok).toBe(false);
		nav.visible = true;
		get(state, 'ansel').position.x = 20;
		expect(rules.previewCommand(state, command).ok).toBe(false);
	});

	it('rally spends only bonus, restores six and never refreshes across turns', () => {
		const { state, rules } = setup();
		get(state, 'amiya').hp = 30;
		const result = rules.applyCommand(state, { type: 'rally', unitId: 'amiya' });
		expect(get(result.state, 'amiya').hp).toBe(36);
		expect(get(result.state, 'amiya').budget).toEqual({ movement: 9, action: 1, bonus: 0, reaction: 1 });
		expect(rules.previewCommand(result.state, { type: 'rally', unitId: 'amiya' }).ok).toBe(false);
		active(result.state, 'enemy-ranged-2');
		const next = rules.applyCommand(result.state, { type: 'endTurn', unitId: 'enemy-ranged-2' });
		expect(get(next.state, 'amiya').budget.bonus).toBe(1);
		expect(rules.previewCommand(next.state, { type: 'rally', unitId: 'amiya' }).ok).toBe(false);
	});

	it('resolves victory at the fatal hit and disallows every later command', () => {
		const { state, rules } = setup();
		state.units.filter(unit => unit.team === 'enemy').forEach(unit => { unit.hp = 0; });
		get(state, 'enemy-melee-1').hp = 1;
		const result = rules.applyCommand(state, { type: 'attack', unitId: 'amiya', targetId: 'enemy-melee-1' });
		expect(result.state.outcome).toBe('victory');
		expect(result.events.filter(event => event.type === 'battleEnd')).toHaveLength(1);
		expect(rules.previewCommand(result.state, { type: 'endTurn', unitId: 'amiya' }).ok).toBe(false);
	});
});

describe('invalid commands and tactical AI', () => {
	it('rejects wrong turns, missing/dead/allied targets, exhausted budgets and blocked sight', () => {
		const { state, nav, rules } = setup();
		const invalid: Command[] = [
			{ type: 'attack', unitId: 'ansel', targetId: 'enemy-melee-1' },
			{ type: 'attack', unitId: 'missing', targetId: 'enemy-melee-1' },
			{ type: 'attack', unitId: 'amiya', targetId: 'ansel' },
			{ type: 'attack', unitId: 'amiya', targetId: 'missing' },
			{ type: 'attack', unitId: 'amiya', targetId: 'enemy-ranged-1' },
			{ type: 'skill', unitId: 'amiya' },
			{ type: 'skill', unitId: 'amiya', to: { x: 30, z: 0 } },
			{ type: 'rally', unitId: 'amiya' },
			{ type: 'move', unitId: 'amiya', to: { x: 0, z: 0 } },
		];
		for (const command of invalid) {
			const result = rules.applyCommand(state, command);
			expect(result.ok).toBe(false);
			expect(result.state).toEqual(state);
			expect(result.events).toEqual([]);
		}
		get(state, 'enemy-melee-1').hp = 0;
		expect(rules.previewCommand(state, { type: 'attack', unitId: 'amiya', targetId: 'enemy-melee-1' }).ok).toBe(false);
		get(state, 'amiya').budget.action = 0;
		expect(rules.previewCommand(state, { type: 'dash', unitId: 'amiya' }).ok).toBe(false);
		expect(rules.previewCommand(state, { type: 'disengage', unitId: 'amiya' }).ok).toBe(false);
		get(state, 'amiya').budget.action = 1;
		get(state, 'enemy-melee-1').hp = 10;
		nav.setDoorOpen(false);
		expect(rules.previewCommand(state, { type: 'attack', unitId: 'amiya', targetId: 'enemy-melee-1' }).ok).toBe(false);
		expect(rules.previewCommand(state, { type: 'skill', unitId: 'amiya', targetId: 'enemy-melee-1' }).ok).toBe(false);
	});

	it('enemy chooses legal approach, attacks, then ends without overspending', () => {
		const { state, rules } = setup();
		active(state, 'enemy-melee-1');
		const first = chooseEnemyCommand(state, rules)!;
		expect(first.type).toBe('move');
		expect(rules.previewCommand(state, first).ok).toBe(true);
		const moved = rules.applyCommand(state, first).state;
		const second = chooseEnemyCommand(moved, rules)!;
		expect(second.type).toBe('attack');
		const attacked = rules.applyCommand(moved, second).state;
		expect(chooseEnemyCommand(attacked, rules)?.type).toBe('endTurn');
		expect(chooseEnemyCommand(createBattle([]), rules)).toBeNull();
	});

	it('blocked AI ends its turn instead of issuing illegal or looping commands', () => {
		const { state, nav, rules } = setup();
		active(state, 'enemy-ranged-1');
		nav.blocked = true;
		nav.visible = false;
		expect(chooseEnemyCommand(state, rules)?.type).toBe('endTurn');
	});

	it('a simple player policy can defeat the default enemy group within 30 rounds', () => {
		const { state: initial, rules } = setup();
		get(initial, 'hoshiguma').position = { x: -2, z: 0 };
		get(initial, 'ansel').position = { x: 2, z: 0 };
		let state = initial;
		let commands = 0;
		while (!state.outcome && state.round <= 30 && commands++ < 1500) {
			const actor = currentUnit(state)!;
			let command: Command | null = null;
			if (actor.team === 'enemy') command = chooseEnemyCommand(state, rules);
			else {
				if (actor.hp <= actor.maxHp - 6) {
					const rally: Command = { type: 'rally', unitId: actor.id };
					if (rules.previewCommand(state, rally).ok) command = rally;
				}
				const enemies = state.units.filter(unit => unit.team === 'enemy' && unit.hp > 0)
					.sort((a, b) => Math.hypot(a.position.x - actor.position.x, a.position.z - actor.position.z) - Math.hypot(b.position.x - actor.position.x, b.position.z - actor.position.z));
				if (!command && actor.role === 'healer') {
					for (const ally of state.units.filter(unit => unit.team === 'party' && unit.hp > 0 && unit.maxHp - unit.hp >= 10)) {
						const heal: Command = { type: 'skill', unitId: actor.id, targetId: ally.id };
						if (rules.previewCommand(state, heal).ok) { command = heal; break; }
					}
				}
				if (!command && actor.role === 'caster') for (const enemy of enemies) {
					const skill: Command = { type: 'skill', unitId: actor.id, targetId: enemy.id };
					if (rules.previewCommand(state, skill).ok) { command = skill; break; }
				}
				if (!command) for (const enemy of enemies) {
					const attack: Command = { type: 'attack', unitId: actor.id, targetId: enemy.id };
					if (rules.previewCommand(state, attack).ok) { command = attack; break; }
				}
				if (!command && actor.budget.action > 0 && actor.budget.movement > 0.1) {
					// Reuse the legal approach policy with a team inversion, never changing the game state.
					const inverted: BattleState = { ...state, units: state.units.map(unit => ({ ...unit, team: unit.team === 'party' ? 'enemy' : 'party' })) };
					command = chooseEnemyCommand(inverted, rules);
				}
			}
			command ??= { type: 'endTurn', unitId: actor.id };
			const result = rules.applyCommand(state, command);
			expect(result.ok).toBe(true);
			state = result.state;
		}
		expect(state.outcome).toBe('victory');
		expect(state.round).toBeLessThanOrEqual(30);
	});
});
