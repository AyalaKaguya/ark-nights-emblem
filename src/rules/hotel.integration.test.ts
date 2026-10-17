import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { distance } from '../shared';
import type { Point } from '../shared';
import { SourceNavigation, type SourceNavData } from '../world/source-navigation';
import { BODY_RADIUS, chooseEnemyCommand, createBattle, createBattleRules, currentUnit } from './index';
import type { BattleRules, BattleState, Command, Unit } from './index';

const COURTYARD_PARTY: Point[] = [{ x: 24, z: 17.5 }, { x: 23, z: 18.5 }, { x: 25, z: 18.5 }];
const sourceNav = JSON.parse(readFileSync(new URL('../../public/maps/hotel/scene.json', import.meta.url), 'utf8')).navigation[0] as SourceNavData;
const get = (state: BattleState, id: string): Unit => state.units.find(unit => unit.id === id)!;

interface RunStats {
	commands: number;
	enemyMoves: number;
	enemyAttacks: number;
	enemyPasses: number;
	maxEnemyDecisionMs: number;
	totalEnemyDecisionMs: number;
	maxCommandsPerTurn: number;
	elapsedMs: number;
}

/** A conservative player policy uses only public preview/apply APIs, never rewrites state. */
function friendlyCommand(state: BattleState, rules: BattleRules): Command {
	const actor = currentUnit(state)!;
	const legal = (command: Command): boolean => rules.previewCommand(state, command).ok;
	const enemies = state.units.filter(unit => unit.team === 'enemy' && unit.hp > 0)
		.sort((a, b) => distance(actor.position, a.position) - distance(actor.position, b.position));
	if (actor.hp <= actor.maxHp - 6) {
		const rally: Command = { type: 'rally', unitId: actor.id };
		if (legal(rally)) return rally;
	}
	if (actor.role === 'healer') {
		const injured = state.units.filter(unit => unit.team === 'party' && unit.hp > 0 && unit.maxHp - unit.hp >= 14)
			.sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp);
		for (const target of injured) {
			const command: Command = { type: 'skill', unitId: actor.id, targetId: target.id };
			if (legal(command)) return command;
		}
	}
	if (actor.role === 'caster') {
		const choices = enemies.map(enemy => ({ command: { type: 'skill', unitId: actor.id, targetId: enemy.id } as Command,
			preview: rules.previewCommand(state, { type: 'skill', unitId: actor.id, targetId: enemy.id }) }))
			.filter(choice => choice.preview.ok).sort((a, b) => (b.preview.targetIds?.length ?? 0) - (a.preview.targetIds?.length ?? 0));
		if (choices.length) return choices[0].command;
	}
	for (const target of enemies) {
		const command: Command = { type: 'attack', unitId: actor.id, targetId: target.id };
		if (legal(command)) return command;
	}
	if (actor.budget.action > 0 && actor.budget.movement > 0.1) {
		// The same public tactical approach policy works for either team after a read-only team projection.
		const projected: BattleState = { ...state, units: state.units.map(unit => ({ ...unit, team: unit.team === 'party' ? 'enemy' : 'party' })) };
		const approach = chooseEnemyCommand(projected, rules);
		if (approach?.type === 'move' && legal(approach)) return approach;
	}
	return { type: 'endTurn', unitId: actor.id };
}

function assertStateGeometry(state: BattleState, navigation: SourceNavigation): void {
	const living = state.units.filter(unit => unit.hp > 0);
	for (const unit of living) {
		expect(navigation.isWalkable(unit.position), `${unit.id} must remain on the Recast surface`).toBe(true);
		expect(unit.budget.movement).toBeGreaterThanOrEqual(0);
		expect(unit.budget.action).toBeGreaterThanOrEqual(0);
		expect(unit.budget.bonus).toBeGreaterThanOrEqual(0);
		expect(unit.budget.reaction).toBeGreaterThanOrEqual(0);
	}
	for (let i = 0; i < living.length; i++) for (let j = i + 1; j < living.length; j++) {
		expect(distance(living[i].position, living[j].position), `${living[i].id}/${living[j].id} overlap`).toBeGreaterThanOrEqual(BODY_RADIUS * 2 - 0.00001);
	}
}

function play(navigation: SourceNavigation, passOnly: boolean): { state: BattleState; stats: RunStats } {
	const rules = createBattleRules(navigation);
	let state = createBattle(COURTYARD_PARTY);
	const started = performance.now();
	const stats: RunStats = { commands: 0, enemyMoves: 0, enemyAttacks: 0, enemyPasses: 0,
		maxEnemyDecisionMs: 0, totalEnemyDecisionMs: 0, maxCommandsPerTurn: 0, elapsedMs: 0 };
	let previousTurn = '', commandsThisTurn = 0;
	assertStateGeometry(state, navigation);
	while (!state.outcome && state.round <= 35 && stats.commands < 700) {
		const actor = currentUnit(state)!;
		const turn = `${state.round}/${actor.id}`;
		if (turn !== previousTurn) { previousTurn = turn; commandsThisTurn = 0; }
		stats.maxCommandsPerTurn = Math.max(stats.maxCommandsPerTurn, ++commandsThisTurn);
		expect(commandsThisTurn, `${turn} must not loop`).toBeLessThanOrEqual(12);
		let command: Command;
		if (actor.team === 'enemy') {
			const decisionStart = performance.now();
			command = chooseEnemyCommand(state, rules)!;
			const time = performance.now() - decisionStart;
			stats.maxEnemyDecisionMs = Math.max(stats.maxEnemyDecisionMs, time);
			stats.totalEnemyDecisionMs += time;
			if (command.type === 'move') stats.enemyMoves++;
			if (command.type === 'attack') stats.enemyAttacks++;
			if (command.type === 'endTurn') stats.enemyPasses++;
		} else command = passOnly ? { type: 'endTurn', unitId: actor.id } : friendlyCommand(state, rules);
		const preview = rules.previewCommand(state, command);
		expect(preview.ok, `${actor.id} ${command.type}: ${preview.reason ?? ''}`).toBe(true);
		const before = JSON.stringify(state);
		const result = rules.applyCommand(state, command);
		expect(result.ok, result.reason).toBe(true);
		expect(JSON.stringify(state)).toBe(before);
		state = result.state;
		stats.commands++;
		assertStateGeometry(state, navigation);
	}
	stats.elapsedMs = performance.now() - started;
	return { state, stats };
}

describe('original source Recast hotel navigation and battle integration', () => {
	let navigation: SourceNavigation;
	beforeAll(async () => {
		navigation = new SourceNavigation(sourceNav);
		await navigation.init();
		navigation.setDoorOpen(true);
	}, 30_000);
	afterAll(() => navigation?.dispose());

	it('wins with a legal friendly policy from the courtyard encounter trigger', () => {
		const result = play(navigation, false);
		console.info('hotel legal-party policy', { ...result.stats, round: result.state.round, outcome: result.state.outcome,
			partyHP: result.state.units.filter(unit => unit.team === 'party').map(unit => [unit.id, unit.hp]) });
		expect(result.state.outcome).toBe('victory');
		expect(result.state.round).toBeLessThanOrEqual(35);
		expect(result.stats.enemyAttacks).toBeGreaterThan(0);
	}, 60_000);

	it('repeatedly passing loses: enemies navigate, attack and finish the battle', () => {
		const result = play(navigation, true);
		console.info('hotel pass-only policy', { ...result.stats, round: result.state.round, outcome: result.state.outcome });
		expect(result.state.outcome).toBe('defeat');
		expect(result.stats.enemyMoves).toBeGreaterThan(0);
		expect(result.stats.enemyAttacks).toBeGreaterThan(0);
		expect(get(result.state, 'amiya').hp).toBe(0);
		expect(get(result.state, 'hoshiguma').hp).toBe(0);
		expect(get(result.state, 'ansel').hp).toBe(0);
	}, 60_000);
});
