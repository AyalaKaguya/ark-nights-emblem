import { expect, test, type Locator, type Page } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import { snapshot, startJourney, travelToEncounter, waitForCameraSettled } from './helpers';

type Bounds = { x: number; y: number; width: number; height: number };
const LEGACY_REGIONS = '.objective, .hint, #hint, .toast, .status-note, .provenance, .help-grid, .log-panel, .caption';
const LEGACY_COPY = /旅途指南|查看操作说明|FIELD GUIDE|TRAVEL NOTES|COMBAT LOG|点击地面|点击金色交互|预览并执行移动|原型原创对话|原作导航范围|示意导览|独立 Web 原型|方舟原地图 \/ 原始模型与摆位/;

async function box(locator: Locator): Promise<Bounds> {
	await expect(locator).toBeVisible();
	const bounds = await locator.boundingBox();
	if (!bounds) throw new Error('Expected a visible UI region');
	return bounds;
}

function overlap(a: Bounds, b: Bounds): number {
	return Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x))
		* Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
}

async function assertImagesLoaded(page: Page): Promise<void> {
	await expect.poll(async () => page.locator('#ui img').evaluateAll(images => images.length), { timeout: 15_000 }).toBeGreaterThanOrEqual(4);
	await expect.poll(async () => page.locator('#ui img').evaluateAll(images => images.filter(image => {
		const img = image as HTMLImageElement;
		return !img.complete || img.naturalWidth === 0 || img.naturalHeight === 0;
	}).map(image => (image as HTMLImageElement).src)), { timeout: 15_000 }).toEqual([]);
	const sources = await page.locator('#ui img').evaluateAll(images => images.map(image => (image as HTMLImageElement).currentSrc));
	expect(sources.every(source => /^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?\//.test(source))).toBe(true);
	const avatars = page.locator('.party-rail .portrait-art img');
	await expect(avatars).toHaveCount(3);
	await expect(page.locator('.hotbar img')).not.toHaveCount(0);
	const operatorSources = await avatars.evaluateAll(images => images.map(image => (image as HTMLImageElement).currentSrc));
	expect(new Set(operatorSources).size).toBe(3);
	expect(operatorSources.every(source => source.includes('/ui/'))).toBe(true);
}

async function assertNoLegacyGuidance(page: Page): Promise<void> {
	await expect(page.locator(LEGACY_REGIONS)).toHaveCount(0);
	expect(await page.locator('#ui').innerText()).not.toMatch(LEGACY_COPY);
}

async function assertHudLayout(page: Page, battle: boolean): Promise<void> {
	const viewport = page.viewportSize()!;
	const regions: [string, Bounds][] = [
		['party', await box(page.locator('.party-rail'))],
		['hotbar', await box(page.locator('.hotbar'))],
		['minimap', await box(page.locator('.minimap'))],
	];
	if (battle) regions.push(['initiative', await box(page.locator('.turn-order'))]);
	for (const [name, bounds] of regions) {
		expect(bounds.width, `${name} width`).toBeGreaterThan(20);
		expect(bounds.height, `${name} height`).toBeGreaterThan(20);
		expect(bounds.x, `${name} left`).toBeGreaterThanOrEqual(-1);
		expect(bounds.y, `${name} top`).toBeGreaterThanOrEqual(-1);
		expect(bounds.x + bounds.width, `${name} right`).toBeLessThanOrEqual(viewport.width + 1);
		expect(bounds.y + bounds.height, `${name} bottom`).toBeLessThanOrEqual(viewport.height + 1);
	}
	for (let i = 0; i < regions.length; i++) for (let j = i + 1; j < regions.length; j++) {
		expect(overlap(regions[i][1], regions[j][1]), `${regions[i][0]} must not overlap ${regions[j][0]}`).toBeLessThanOrEqual(4);
	}
	const party = regions[0][1], hotbar = regions[1][1], minimap = regions[2][1];
	expect(party.x).toBeLessThan(viewport.width * .13);
	expect(party.height).toBeGreaterThan(party.width);
	expect(hotbar.y + hotbar.height).toBeGreaterThan(viewport.height * .8);
	expect(Math.abs(hotbar.x + hotbar.width / 2 - viewport.width / 2)).toBeLessThan(viewport.width * .13);
	expect(minimap.x + minimap.width).toBeGreaterThan(viewport.width * .85);
	expect(minimap.y).toBeLessThan(viewport.height * .12);
	const circle = await page.locator('.minimap-circle').evaluate(element => {
		const rect = element.getBoundingClientRect(), style = getComputedStyle(element);
		return { width: rect.width, height: rect.height, borderRadius: style.borderRadius };
	});
	expect(Math.abs(circle.width - circle.height)).toBeLessThan(2);
	expect(circle.borderRadius).toBe('50%');
	const portraits = await page.locator('.party-rail [data-unit]').evaluateAll(elements => elements.map(element => {
		const r = element.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height };
	}));
	expect(portraits).toHaveLength(3);
	for (let i = 1; i < portraits.length; i++) {
		expect(portraits[i].y).toBeGreaterThanOrEqual(portraits[i - 1].y + portraits[i - 1].height - 1);
		expect(Math.abs(portraits[i].x - portraits[0].x)).toBeLessThan(4);
	}
	if (battle) {
		await expect(page.locator('.turn-order img')).toHaveCount(7);
		expect(regions[3][1].y).toBeLessThan(viewport.height * .15);
	}
	const labelProblems = await page.locator('.hotbar button, .minimap button').evaluateAll(buttons => buttons.filter(button => !button.getAttribute('aria-label')?.trim()).map(button => button.outerHTML));
	expect(labelProblems).toEqual([]);
	const controls = await page.locator('.hotbar button').evaluateAll(buttons => buttons.filter(button => {
		const r = button.getBoundingClientRect(); return r.width > 0 && r.height > 0;
	}).map(button => {
		const r = button.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height, name: button.getAttribute('aria-label') };
	}));
	for (let i = 0; i < controls.length; i++) for (let j = i + 1; j < controls.length; j++) {
		expect(overlap(controls[i], controls[j]), `${controls[i].name} overlaps ${controls[j].name}`).toBeLessThanOrEqual(2);
	}
}

test('hotbar tabs, minimap zoom and pause menu work through visible controls', async ({ page }) => {
	await startJourney(page);
	const initial = await snapshot(page);
	await page.locator('[data-tab="items"]').click();
	await expect(page.locator('[data-tab="items"]')).toHaveAttribute('aria-pressed', 'true');
	await expect(page.locator('.item-grid')).toBeVisible();
	await page.locator('[data-tab="passive"]').click();
	await expect(page.locator('[data-tab="passive"]')).toHaveAttribute('aria-pressed', 'true');
	await expect(page.locator('.passive-grid')).toBeVisible();
	await page.locator('[data-tab="common"]').click();
	await expect(page.locator('.common-grid')).toBeVisible();
	await expect.poll(async () => Number(await page.locator('#ark-minimap').getAttribute('data-zoom'))).toBeGreaterThan(0);
	const zoom = Number(await page.locator('#ark-minimap').getAttribute('data-zoom'));
	await page.locator('[data-action="mapZoom"]').click();
	await expect.poll(async () => Number(await page.locator('#ark-minimap').getAttribute('data-zoom'))).toBeGreaterThan(zoom);
	await page.locator('[data-action="mapOut"]').click();
	await expect.poll(async () => Number(await page.locator('#ark-minimap').getAttribute('data-zoom'))).toBe(zoom);
	await page.keyboard.press('h');
	const menu = page.getByRole('dialog', { name: '暂停菜单' });
	await expect(menu).toBeVisible();
	await expect(menu.locator('button')).toHaveCount(3);
	await expect(menu.locator('[data-action="replay"]')).toBeDisabled();
	await menu.locator('[data-action="help"]').click();
	await expect(menu).not.toBeVisible();
	const afterControls = await snapshot(page);
	expect(afterControls.positions.amiya).toEqual(initial.positions.amiya);
	expect(afterControls.checkedIn).toBe(false);
	expect(afterControls.supplies).toBe(false);
	expect(afterControls.battle).toBeNull();
	await page.locator('[data-action="help"]').first().click();
	await menu.locator('[data-action="title"]').click();
	await expect(page.locator('[data-action="start"]')).toBeVisible();
	await page.locator('[data-action="start"]').click();
	await expect.poll(async () => (await snapshot(page)).mode).toBe('exploring');
	const restarted = await snapshot(page);
	expect(restarted.checkedIn).toBe(false);
	expect(restarted.supplies).toBe(false);
	expect(restarted.battle).toBeNull();
	expect(restarted.positions.amiya).toEqual(initial.positions.amiya);
	await expect(page.locator('[data-tab="common"]')).toHaveAttribute('aria-pressed', 'true');
	await assertNoLegacyGuidance(page);
});

for (const viewport of [{ width: 1600, height: 1000 }, { width: 1280, height: 720 }]) {
	test(`portrait rail, hotbar and round minimap fit ${viewport.width}x${viewport.height} without tutorial text`, async ({ page }, info) => {
		await page.setViewportSize(viewport);
		const errors: string[] = [];
		page.on('pageerror', error => errors.push(error.message));
		await startJourney(page);
		await waitForCameraSettled(page);
		await assertNoLegacyGuidance(page);
		await assertImagesLoaded(page);
		await assertHudLayout(page, false);
		if (info.project.name === 'edge') { await mkdir('screenshots/ui', { recursive: true }); await page.screenshot({ path: `screenshots/ui/explore-${viewport.width}x${viewport.height}.png` }); }
		await page.locator('[data-action="help"]').first().click();
		const pause = page.getByRole('dialog', { name: '暂停菜单' });
		await expect(pause).toBeVisible();
		expect(await pause.innerText()).not.toMatch(LEGACY_COPY);
		await expect(pause.locator('button')).toHaveCount(3);
		await page.keyboard.press('h');
		await expect(pause).not.toBeVisible();
		const before = await snapshot(page);
		expect(before.mode).toBe('exploring');
		await travelToEncounter(page);
		await waitForCameraSettled(page);
		await assertNoLegacyGuidance(page);
		await assertImagesLoaded(page);
		await assertHudLayout(page, true);
		if (info.project.name === 'edge') await page.screenshot({ path: `screenshots/ui/combat-${viewport.width}x${viewport.height}.png` });
		expect(errors).toEqual([]);
	});
}
