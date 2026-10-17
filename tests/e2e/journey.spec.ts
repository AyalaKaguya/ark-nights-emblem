import { expect, test } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import {
	activeUnit, chooseLegalPlayerCommand, partyCard, performBattleCommand, skipPresentation, snapshot,
	startJourney, travelToEncounter, waitForCameraSettled, waitForMode, waitForPlayerTurn,
} from './helpers';

test.afterEach(async ({ page }, info) => {
	if (info.status !== info.expectedStatus) {
		try { await info.attach('read-only-game-snapshot', { body: JSON.stringify(await snapshot(page), null, 2), contentType: 'application/json' }); }
		catch { /* A failed load may not expose diagnostics yet. */ }
	}
});

test('complete journey through reception, supplies, gate, legal combat and continued exploration', async ({ page }, info) => {
	const errors: string[] = [];
	page.on('pageerror', error => errors.push(error.message));
	await travelToEncounter(page);
	await skipPresentation(page);
	if (info.project.name === 'edge') { await mkdir('screenshots', { recursive: true }); await page.screenshot({ path: 'screenshots/combat.png' }); }
	for (let count = 0; count < 90; count++) {
		const state = await waitForPlayerTurn(page);
		if (state.mode === 'victory' || state.mode === 'defeat') break;
		expect(state.battle!.round).toBeLessThanOrEqual(30);
		const command = await chooseLegalPlayerCommand(page, state);
		await performBattleCommand(page, command);
	}
	await waitForMode(page, 'victory');
	await expect(page.getByRole('heading', { name: '庭院重归宁静' })).toBeVisible();
	if (info.project.name === 'edge') await page.screenshot({ path: 'screenshots/victory.png' });
	await page.locator('[data-action="continue"]').click();
	const rested = await waitForMode(page, 'exploring');
	expect(rested.cleared).toBe(true);
	expect(rested.battle).toBeNull();
	if (info.project.name === 'edge') await page.screenshot({ path: 'screenshots/exploration.png' });
	await page.locator('[data-action="help"]').first().click();
	await expect(page.getByRole('dialog', { name: '暂停菜单' }).locator('[data-action="replay"]')).toBeEnabled();
	await page.keyboard.press('h');
	expect(errors).toEqual([]);
});

test('passing every player turn leads to defeat and Retry restores the encounter checkpoint', async ({ page }) => {
	const original = await travelToEncounter(page);
	await skipPresentation(page);
	for (let count = 0; count < 100; count++) {
		const state = await waitForPlayerTurn(page);
		if (state.mode === 'victory' || state.mode === 'defeat') break;
		await performBattleCommand(page, { type: 'endTurn', unitId: activeUnit(state)!.id });
	}
	const defeated = await waitForMode(page, 'defeat');
	expect(defeated.battle!.units.filter(unit => unit.team === 'party').every(unit => unit.hp === 0)).toBe(true);
	await page.locator('[data-action="retry"]').click();
	const restarted = await waitForMode(page, 'battle');
	expect(restarted.battle).toEqual(original);
	await expect(page.locator('[data-action="endTurn"]')).toBeEnabled();
});

test('changing the selected operator cancels a pending reception trip without awarding a remote interaction', async ({ page }) => {
	await startJourney(page);
	const initial = await snapshot(page);
	await page.locator('[data-action="next"]').click();
	await expect.poll(async () => {
		const state = await snapshot(page), a = state.positions.amiya, b = initial.positions.amiya;
		return Math.hypot(a.x - b.x, a.z - b.z) > .2;
	}).toBe(true);
	await partyCard(page, 'hoshiguma').click();
	await page.waitForTimeout(800);
	const cancelled = await snapshot(page);
	expect(cancelled.mode).toBe('exploring');
	expect(cancelled.checkedIn).toBe(false);
	expect(cancelled.supplies).toBe(false);
});

test('Escape stops an exploration route and leaves all objectives unclaimed', async ({ page }) => {
	await startJourney(page);
	await page.locator('[data-action="next"]').click();
	await page.waitForTimeout(400);
	await page.keyboard.press('Escape');
	const stopped = await snapshot(page);
	await page.waitForTimeout(750);
	const later = await snapshot(page);
	expect(later.mode).toBe('exploring');
	expect(later.checkedIn).toBe(false);
	expect(later.positions.amiya.x).toBeCloseTo(stopped.positions.amiya.x, 3);
	expect(later.positions.amiya.z).toBeCloseTo(stopped.positions.amiya.z, 3);
});

test('pause menu opened during enemy activity resumes to a playable player turn after closing', async ({ page }) => {
	await travelToEncounter(page);
	// 3× keeps a visible enemy delay while ensuring the old 50-attempt guard would exhaust while paused.
	await page.locator('[data-action="speed"]').click();
	for (let count = 0; count < 3; count++) {
		const state = await waitForPlayerTurn(page);
		await page.locator('[data-action="endTurn"]').click();
		if (activeUnit(state)?.id === 'hoshiguma') break;
		await waitForMode(page, ['battle', 'defeat']);
	}
	await page.keyboard.press('h');
	await expect(page.getByRole('dialog', { name: '暂停菜单' })).toBeVisible();
	await page.waitForTimeout(6500);
	await page.keyboard.press('h');
	await expect(page.getByRole('dialog', { name: '暂停菜单' })).not.toBeVisible();
	const resumed = await waitForPlayerTurn(page);
	expect(resumed.mode).toBe('battle');
	await expect(page.locator('[data-action="endTurn"]')).toBeEnabled();
});

test('camera pans, refocuses, zooms and orbits through real keyboard and mouse controls', async ({ page }) => {
	await startJourney(page);
	await waitForCameraSettled(page);
	const canvas = await page.locator('#renderCanvas').boundingBox();
	if (!canvas) throw new Error('Canvas must be visible');
	const center = { x: canvas.x + canvas.width / 2, y: canvas.y + canvas.height / 2 };
	await page.mouse.move(center.x, center.y);
	// A right-click focuses the canvas without issuing a gameplay move.
	await page.mouse.click(center.x, center.y, { button: 'right' });
	const initial = await snapshot(page);
	await page.keyboard.down('w');
	await page.waitForTimeout(500);
	await page.keyboard.up('w');
	await waitForCameraSettled(page);
	const panned = await snapshot(page);
	expect(panned.camera.following).toBe(false);
	expect(Math.hypot(panned.camera.target[0] - initial.camera.target[0], panned.camera.target[2] - initial.camera.target[2])).toBeGreaterThan(.8);
	await page.keyboard.press('f');
	await waitForCameraSettled(page);
	const focused = await snapshot(page);
	expect(focused.camera.following).toBe(true);
	expect(focused.camera.target[0]).toBeCloseTo(focused.positions.amiya.x, 1);
	expect(focused.camera.target[2]).toBeCloseTo(focused.positions.amiya.z, 1);
	await page.mouse.wheel(0, -250);
	await waitForCameraSettled(page);
	const zoomed = await snapshot(page);
	expect(zoomed.camera.radius).toBeLessThan(focused.camera.radius - 1);
	await page.mouse.down({ button: 'right' });
	await page.mouse.move(center.x + 120, center.y + 70, { steps: 12 });
	await page.mouse.up({ button: 'right' });
	await waitForCameraSettled(page);
	const orbited = await snapshot(page);
	expect(Math.abs(orbited.camera.alpha - zoomed.camera.alpha)).toBeGreaterThan(.25);
	expect(Math.abs(orbited.camera.beta - zoomed.camera.beta)).toBeGreaterThan(.1);
	expect(orbited.positions).toEqual(initial.positions);
});
