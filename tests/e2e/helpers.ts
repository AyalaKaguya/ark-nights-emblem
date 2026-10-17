import { expect, type Page } from '@playwright/test';
import type { Point } from '../../src/shared';
import type { BattleState, Command, Preview, Unit } from '../../src/rules';

export interface HotelSnapshot {
	mode: string;
	battle: BattleState | null;
	checkedIn: boolean;
	supplies: boolean;
	cleared: boolean;
	doorOpen: boolean;
	positions: Record<string, Point>;
	camera: { target: number[]; alpha: number; beta: number; radius: number; following: boolean };
	intent: 'move' | 'attack' | 'skill';
}
interface HotelDiagnostics {
	snapshot(): HotelSnapshot;
	project(point: Point, y?: number): { x: number; y: number };
	heightAt(point: Point): number;
	preview(command: Command): Preview | null;
}
declare global { interface Window { __hotel?: HotelDiagnostics } }

/** Diagnostics are read-only. All game-state changes below are real mouse/key UI events. */
export const snapshot = (page: Page): Promise<HotelSnapshot> => page.evaluate(() => {
	if (!window.__hotel) throw new Error('Development diagnostics are not ready');
	return window.__hotel.snapshot();
});
export const preview = (page: Page, command: Command): Promise<Preview | null> => page.evaluate(c => window.__hotel?.preview(c) ?? null, command);
export const activeUnit = (state: HotelSnapshot): Unit | undefined => state.battle?.units.find(unit => unit.id === state.battle?.order[state.battle.turnIndex]);
export const partyCard = (page: Page, id: string) => page.locator(`.party-rail [data-unit="${id}"]`).first();

export async function waitForMode(page: Page, modes: string | string[], timeout = 30_000): Promise<HotelSnapshot> {
	const allowed = Array.isArray(modes) ? modes : [modes];
	await expect.poll(async () => allowed.includes((await snapshot(page)).mode), { timeout }).toBe(true);
	return snapshot(page);
}

export async function openHotel(page: Page): Promise<void> {
	await page.goto('/');
	await page.waitForFunction(() => !!window.__hotel, { timeout: 60_000 });
	await waitForMode(page, 'title');
	await expect(page.locator('[data-action="start"]')).toBeVisible();
}

export async function startJourney(page: Page): Promise<void> {
	await openHotel(page);
	await page.locator('[data-action="start"]').click();
	await waitForMode(page, 'exploring');
}

export async function travelToEncounter(page: Page): Promise<BattleState> {
	await startJourney(page);
	await page.locator('[data-action="next"]').click();
	await waitForMode(page, 'dialogue');
	expect((await snapshot(page)).checkedIn).toBe(true);
	await expect(page.locator('[data-action="closeDialogue"]')).toBeVisible();
	await page.locator('[data-action="closeDialogue"]').click();
	await waitForMode(page, 'exploring');
	await page.locator('[data-action="next"]').click();
	await expect.poll(async () => (await snapshot(page)).supplies, { timeout: 30_000 }).toBe(true);
	await page.locator('[data-action="next"]').click();
	await expect.poll(async () => (await snapshot(page)).doorOpen, { timeout: 30_000 }).toBe(true);
	const state = await waitForMode(page, 'battle', 45_000);
	expect(state.battle).not.toBeNull();
	expect(state.battle!.units.filter(unit => unit.team === 'enemy')).toHaveLength(4);
	return state.battle!;
}

async function screenPoint(page: Page, point: Point, y: number): Promise<{ x: number; y: number }> {
	const projected = await page.evaluate(({ point, y }) => {
		const diagnostics = window.__hotel!;
		return diagnostics.project(point, diagnostics.heightAt(point) + y);
	}, { point, y });
	const bounds = await page.locator('#renderCanvas').boundingBox();
	if (!bounds) throw new Error('Render canvas is not visible');
	return { x: bounds.x + projected.x, y: bounds.y + projected.y };
}

/** A moving follow camera cannot be targeted using an earlier projected pixel. */
export async function waitForCameraSettled(page: Page): Promise<void> {
	let last: number[] | null = null;
	let stable = 0;
	await expect.poll(async () => {
		const camera = (await snapshot(page)).camera;
		const values = [...camera.target, camera.alpha, camera.beta, camera.radius];
		const delta = last ? Math.max(...values.map((value, index) => Math.abs(value - last![index]))) : Infinity;
		last = values;
		stable = delta < .015 ? stable + 1 : 0;
		return stable;
	}, { timeout: 6000, intervals: [100] }).toBeGreaterThanOrEqual(3);
}

export async function clickWorld(page: Page, point: Point, y = .05): Promise<void> {
	await waitForCameraSettled(page);
	let projected = await screenPoint(page, point, y);
	const viewport = page.viewportSize()!;
	// Camera changes use the visible canvas exactly like a player does.
	if (projected.x < 300 || projected.x > viewport.width - 320 || projected.y < 120 || projected.y > viewport.height - 190) {
		await page.locator('[data-action="focus"]').first().click();
		const canvas = await page.locator('#renderCanvas').boundingBox();
		if (canvas) { await page.mouse.move(canvas.x + canvas.width / 2, canvas.y + canvas.height / 2); await page.mouse.wheel(0, 450); }
		await waitForCameraSettled(page);
		projected = await screenPoint(page, point, y);
	}
	expect(Number.isFinite(projected.x) && Number.isFinite(projected.y)).toBe(true);
	expect(projected.x).toBeGreaterThan(0);
	expect(projected.x).toBeLessThan(viewport.width);
	expect(projected.y).toBeGreaterThan(0);
	expect(projected.y).toBeLessThan(viewport.height);
	await page.mouse.click(projected.x, projected.y);
}

function gameplaySignature(state: HotelSnapshot): string { return JSON.stringify([state.mode, state.battle]); }

export async function performBattleCommand(page: Page, command: Command): Promise<void> {
	const before = await snapshot(page);
	expect(before.mode).toBe('battle');
	expect((await preview(page, command))?.ok).toBe(true);
	if (command.type === 'move') {
		await page.locator('[data-action="move"]').click();
		await clickWorld(page, command.to);
	} else if (command.type === 'attack' || command.type === 'skill') {
		await page.locator(`[data-action="${command.type}"]`).click();
		const actor = activeUnit(before)!;
		if (command.type === 'skill' && actor.role === 'tank') { /* The skill button is its complete UI action. */ }
		else if (command.targetId) {
			const target = before.battle!.units.find(unit => unit.id === command.targetId)!;
			if (target.team === 'party') await partyCard(page, target.id).click();
			// Source-map actors are scaled to .4; click their visible torso rather than above the billboard.
			else await clickWorld(page, target.position, .4);
		} else if (command.type === 'skill' && command.to) await clickWorld(page, command.to);
	} else await page.locator(`[data-action="${command.type}"]`).click();
	await expect.poll(async () => gameplaySignature(await snapshot(page)), { timeout: 12_000 }).not.toBe(gameplaySignature(before));
	await waitForMode(page, ['battle', 'victory', 'defeat'], 45_000);
}

export async function skipPresentation(page: Page): Promise<void> {
	const speed = page.locator('[data-action="speed"]');
	const speedLabel = async () => (await speed.getAttribute('aria-label')) ?? (await speed.textContent()) ?? '';
	for (let i = 0; i < 3 && !(await speedLabel()).includes('跳过'); i++) await speed.click();
	await expect.poll(speedLabel).toContain('跳过');
}

export async function waitForPlayerTurn(page: Page): Promise<HotelSnapshot> {
	await expect.poll(async () => {
		const state = await snapshot(page);
		return ['victory', 'defeat'].includes(state.mode) || state.mode === 'battle' && activeUnit(state)?.team === 'party';
	}, { timeout: 45_000 }).toBe(true);
	return snapshot(page);
}

const pointDistance = (a: Point, b: Point) => Math.hypot(a.x - b.x, a.z - b.z);

export async function chooseLegalPlayerCommand(page: Page, state: HotelSnapshot): Promise<Command> {
	const actor = activeUnit(state)!;
	const units = state.battle!.units;
	const enemies = units.filter(unit => unit.team === 'enemy' && unit.hp > 0)
		.sort((a, b) => pointDistance(actor.position, a.position) - pointDistance(actor.position, b.position));
	if (actor.hp <= actor.maxHp - 6) {
		const rally: Command = { type: 'rally', unitId: actor.id };
		if ((await preview(page, rally))?.ok) return rally;
	}
	if (actor.role === 'healer') for (const ally of units.filter(unit => unit.team === 'party' && unit.hp > 0 && unit.maxHp - unit.hp >= 14)) {
		const heal: Command = { type: 'skill', unitId: actor.id, targetId: ally.id };
		if ((await preview(page, heal))?.ok) return heal;
	}
	if (actor.role === 'caster') {
		let best: { command: Command; count: number } | null = null;
		for (const enemy of enemies) {
			const command: Command = { type: 'skill', unitId: actor.id, targetId: enemy.id };
			const result = await preview(page, command);
			if (result?.ok && (!best || (result.targetIds?.length ?? 0) > best.count)) best = { command, count: result.targetIds?.length ?? 0 };
		}
		if (best) return best.command;
	}
	for (const enemy of enemies) {
		const attack: Command = { type: 'attack', unitId: actor.id, targetId: enemy.id };
		if ((await preview(page, attack))?.ok) return attack;
	}
	if (actor.budget.action > 0 && actor.budget.movement > .2) {
		let best: { command: Command; score: number } | null = null;
		for (const enemy of enemies) {
			const d = pointDistance(actor.position, enemy.position);
			const dx = (enemy.position.x - actor.position.x) / Math.max(.001, d), dz = (enemy.position.z - actor.position.z) / Math.max(.001, d);
			for (const length of [Math.min(actor.budget.movement, Math.max(1, d - Math.max(.95, actor.range - .2))), actor.budget.movement * .65, 2]) {
				for (const angle of [0, Math.PI / 6, -Math.PI / 6, Math.PI / 2, -Math.PI / 2]) {
					const to = { x: actor.position.x + (dx * Math.cos(angle) - dz * Math.sin(angle)) * length,
						z: actor.position.z + (dx * Math.sin(angle) + dz * Math.cos(angle)) * length };
					const command: Command = { type: 'move', unitId: actor.id, to };
					// A user cannot click a ground point hidden by their own selection/body plane.
					if (pointDistance(to, actor.position) < .95) continue;
					const result = await preview(page, command);
					const remaining = pointDistance(to, enemy.position);
					const score = d - remaining - (result?.cost ?? 0) * .02;
					if (result?.ok && score > .5 && (!best || score > best.score)) best = { command, score };
				}
			}
		}
		if (best) return best.command;
	}
	return { type: 'endTurn', unitId: actor.id };
}
