import { ENEMY_SPAWNS, PARTY_SPAWNS, distance } from '../shared';
import type { CircleBlocker, Navigation, Point } from '../shared';

export type Team = 'party' | 'enemy';
export type Role = 'caster' | 'tank' | 'healer' | 'melee' | 'ranged';
export type DamageType = 'physical' | 'arts';
export interface Budget { movement: number; action: number; bonus: number; reaction: number }
export interface Unit {
	id: string; name: string; team: Team; role: Role; position: Point;
	hp: number; maxHp: number; attack: number; defense: number; resistance: number;
	speed: number; range: number; damageType: DamageType; budget: Budget;
	guarding: boolean; disengaged: boolean; rallyUsed?: boolean;
}
export interface BattleState {
	units: Unit[]; order: string[]; turnIndex: number; round: number;
	outcome: null | 'victory' | 'defeat';
}
export type Command =
	| { type: 'move'; unitId: string; to: Point }
	| { type: 'attack'; unitId: string; targetId: string }
	| { type: 'skill'; unitId: string; targetId?: string; to?: Point }
	| { type: 'dash' | 'disengage' | 'endTurn' | 'rally'; unitId: string };
export interface Preview {
	ok: boolean; reason?: string; path?: Point[]; cost?: number; targetIds?: string[]; amount?: number;
}
export interface BattleEvent {
	type: string; unitId?: string; targetId?: string; path?: Point[]; amount?: number; text?: string;
}
export interface Apply { state: BattleState; events: BattleEvent[]; ok: boolean; reason?: string }
export interface BattleRules {
	previewCommand(state: BattleState, command: Command): Preview;
	applyCommand(state: BattleState, command: Command): Apply;
}

export const MOVEMENT_PER_TURN = 9;
export const BODY_RADIUS = 0.45;
export const OPPORTUNITY_RANGE = 1.8;
export const SKILL_INFO = {
	caster: { name: '术式爆发', description: '主要动作：10 米内半径 3 米法术爆发，对敌人造成 24 点基础法术伤害。', range: 10, radius: 3, amount: 24 },
	tank: { name: '护卫姿态', description: '主要动作：进入护卫姿态，所受伤害减半，持续至自己的下个回合。', range: 0, radius: 0, amount: 0 },
	healer: { name: '急救术式', description: '主要动作：治疗 8 米内一个存活友方 22 点生命。', range: 8, radius: 0, amount: 22 },
} as const;
const EPSILON = 0.00001;
const freshBudget = (): Budget => ({ movement: MOVEMENT_PER_TURN, action: 1, bonus: 1, reaction: 1 });
const copyPoint = (point: Point): Point => ({ x: point.x, z: point.z });
const finitePoint = (point: Point | undefined): point is Point => !!point && Number.isFinite(point.x) && Number.isFinite(point.z);
const cloneState = (state: BattleState): BattleState => ({
	...state, order: [...state.order],
	units: state.units.map(unit => ({ ...unit, position: copyPoint(unit.position), budget: { ...unit.budget } })),
});
const rejected = (reason: string): Preview => ({ ok: false, reason });
const findUnit = (state: BattleState, id: string): Unit | undefined => state.units.find(unit => unit.id === id);

export function currentUnit(state: BattleState): Unit | null {
	if (state.outcome) return null;
	const unit = findUnit(state, state.order[state.turnIndex]);
	return unit && unit.hp > 0 ? unit : null;
}

export function createBattle(partyPositions: Point[]): BattleState {
	const units: Unit[] = [
		makeUnit('amiya', '阿米娅', 'party', 'caster', partyPositions[0] ?? PARTY_SPAWNS[0], 54, 18, 3, 20, 18, 10, 'arts'),
		makeUnit('hoshiguma', '星熊', 'party', 'tank', partyPositions[1] ?? PARTY_SPAWNS[1], 90, 18, 7, 10, 12, 1.8, 'physical'),
		makeUnit('ansel', '安赛尔', 'party', 'healer', partyPositions[2] ?? PARTY_SPAWNS[2], 52, 12, 2, 10, 15, 10, 'arts'),
		makeUnit('enemy-melee-1', '持盾侦察兵', 'enemy', 'melee', ENEMY_SPAWNS[0], 36, 12, 3, 0, 10, 1.8, 'physical'),
		makeUnit('enemy-melee-2', '近战侦察兵', 'enemy', 'melee', ENEMY_SPAWNS[1], 34, 12, 2, 0, 10, 1.8, 'physical'),
		makeUnit('enemy-ranged-1', '弩手', 'enemy', 'ranged', ENEMY_SPAWNS[2], 30, 9, 1, 10, 8, 10, 'physical'),
		makeUnit('enemy-ranged-2', '术士', 'enemy', 'ranged', ENEMY_SPAWNS[3], 28, 10, 1, 15, 8, 10, 'arts'),
	];
	return { units, order: [...units].sort((a, b) => b.speed - a.speed || a.id.localeCompare(b.id)).map(unit => unit.id), turnIndex: 0, round: 1, outcome: null };
}

function makeUnit(id: string, name: string, team: Team, role: Role, position: Point, hp: number,
	attack: number, defense: number, resistance: number, speed: number, range: number, damageType: DamageType): Unit {
	return { id, name, team, role, position: copyPoint(position), hp, maxHp: hp, attack, defense, resistance,
		speed, range, damageType, budget: freshBudget(), guarding: false, disengaged: false, rallyUsed: false };
}

/** No randomness: given the same state, command and navigation, the result is identical. */
export function createBattleRules(navigation: Navigation): BattleRules {
	function previewCommand(state: BattleState, command: Command): Preview {
		if (state.outcome) return rejected('战斗已经结束');
		const actor = findUnit(state, command.unitId);
		if (!actor || actor.hp <= 0) return rejected('行动单位不存在或已倒下');
		if (currentUnit(state)?.id !== actor.id) return rejected('尚未轮到该单位行动');
		switch (command.type) {
			case 'endTurn': return { ok: true };
			case 'move': return previewMove(state, actor, command.to, navigation);
			case 'attack': {
				if (actor.budget.action < 1) return rejected('主要动作已经用完');
				const target = findUnit(state, command.targetId);
				if (!target || target.hp <= 0 || target.team === actor.team) return rejected('攻击需要存活敌方目标');
				if (distance(actor.position, target.position) > actor.range + EPSILON) return rejected('目标超出攻击距离');
				if (!navigation.lineOfSight(actor.position, target.position)) return rejected('目标被墙体或关闭的门遮挡');
				return { ok: true, targetIds: [target.id], amount: damageAmount(actor.attack, actor.damageType, target) };
			}
			case 'skill': return previewSkill(state, actor, command, navigation);
			case 'dash':
				return actor.budget.action >= 1 ? { ok: true, amount: MOVEMENT_PER_TURN } : rejected('疾走需要一个主要动作');
			case 'disengage':
				return actor.budget.action >= 1 ? { ok: true } : rejected('撤离需要一个主要动作');
			case 'rally':
				if (actor.rallyUsed) return rejected('振作每场战斗只能使用一次');
				if (actor.budget.bonus < 1) return rejected('附赠动作已经用完');
				if (actor.hp >= actor.maxHp) return rejected('生命已满');
				return { ok: true, targetIds: [actor.id], amount: Math.min(6, actor.maxHp - actor.hp) };
			default: return rejected('未知指令');
		}
	}

	function applyCommand(input: BattleState, command: Command): Apply {
		const preview = previewCommand(input, command);
		if (!preview.ok) return { state: cloneState(input), events: [], ok: false, reason: preview.reason };
		const state = cloneState(input);
		const actor = findUnit(state, command.unitId)!;
		const events: BattleEvent[] = [];
		switch (command.type) {
			case 'move': executeMove(state, actor, preview.path!, navigation, events); break;
			case 'attack': {
				actor.budget.action -= 1;
				const target = findUnit(state, command.targetId)!;
				events.push({ type: 'attack', unitId: actor.id, targetId: target.id, text: `${actor.name} 发动普攻` });
				dealDamage(actor, target, actor.attack, actor.damageType, events);
				break;
			}
			case 'skill': {
				actor.budget.action -= 1;
				events.push({ type: 'skill', unitId: actor.id, text: `${actor.name} 使用${skillName(actor)}` });
				if (actor.role === 'tank') actor.guarding = true;
				else for (const id of preview.targetIds ?? []) {
					const target = findUnit(state, id)!;
					if (actor.role === 'healer') heal(actor, target, SKILL_INFO.healer.amount, events);
					else dealDamage(actor, target, SKILL_INFO.caster.amount, 'arts', events);
				}
				break;
			}
			case 'dash':
				actor.budget.action -= 1;
				actor.budget.movement += MOVEMENT_PER_TURN;
				events.push({ type: 'dash', unitId: actor.id, amount: MOVEMENT_PER_TURN, text: `${actor.name} 疾走：移动额度 +9 米` });
				break;
			case 'disengage':
				actor.budget.action -= 1;
				actor.disengaged = true;
				events.push({ type: 'disengage', unitId: actor.id, text: `${actor.name} 撤离：本回合移动不触发机会攻击` });
				break;
			case 'rally':
				actor.budget.bonus -= 1;
				actor.rallyUsed = true;
				heal(actor, actor, 6, events);
				break;
			case 'endTurn':
				events.push({ type: 'endTurn', unitId: actor.id, text: `${actor.name} 结束回合` });
				break;
		}
		updateOutcome(state, events);
		if (!state.outcome && (command.type === 'endTurn' || actor.hp <= 0)) advanceTurn(state, events);
		return { state, events, ok: true };
	}
	return { previewCommand, applyCommand };
}

function previewMove(state: BattleState, actor: Unit, target: Point, navigation: Navigation): Preview {
	if (!finitePoint(target)) return rejected('移动坐标无效');
	if (!navigation.isWalkable(target)) return rejected('目标不可通行');
	if (distance(actor.position, target) <= EPSILON) return rejected('已经在目标位置');
	if (actor.budget.movement <= EPSILON) return rejected('移动额度已经用完');
	const blockers: CircleBlocker[] = state.units.filter(unit => unit.hp > 0 && unit.id !== actor.id)
		.map(unit => ({ ...unit.position, radius: BODY_RADIUS, id: unit.id }));
	if (blockers.some(blocker => distance(target, blocker) < BODY_RADIUS * 2 - EPSILON)) return rejected('目标被其他单位占据');
	const route = navigation.findPath(actor.position, target, blockers);
	if (!route || route.length < 2 || route.some(point => !finitePoint(point))) return rejected('找不到可通行路径');
	if (distance(route[0], actor.position) > 0.05 || distance(route[route.length - 1], target) > 0.05) return rejected('路径无法到达指定位置');
	// Occupancy is checked for the whole segment, even when navigation returns a sparse path.
	for (let i = 1; i < route.length; i++) {
		if (blockers.some(blocker => segmentDistance(blocker, route[i - 1], route[i]) < BODY_RADIUS * 2 - EPSILON)) {
			return rejected('路径被其他单位占据');
		}
	}
	const cost = navigation.pathCost(route);
	if (!Number.isFinite(cost) || cost < 0) return rejected('路径费用无效');
	if (cost > actor.budget.movement + EPSILON) return rejected(`移动需要 ${cost.toFixed(1)} 米，剩余 ${actor.budget.movement.toFixed(1)} 米`);
	return { ok: true, path: route.map(copyPoint), cost };
}

function previewSkill(state: BattleState, actor: Unit, command: Extract<Command, { type: 'skill' }>, navigation: Navigation): Preview {
	if (actor.budget.action < 1) return rejected('主要动作已经用完');
	if (actor.role === 'tank') return { ok: true, targetIds: [actor.id] };
	if (actor.role === 'healer') {
		const target = findUnit(state, command.targetId ?? actor.id);
		if (!target || target.hp <= 0 || target.team !== actor.team) return rejected('治疗需要存活友方目标');
		if (target.hp >= target.maxHp) return rejected('目标生命已满');
		if (distance(actor.position, target.position) > SKILL_INFO.healer.range + EPSILON) return rejected('目标超出治疗距离');
		if (!navigation.lineOfSight(actor.position, target.position)) return rejected('治疗目标被遮挡');
		return { ok: true, targetIds: [target.id], amount: Math.min(SKILL_INFO.healer.amount, target.maxHp - target.hp) };
	}
	if (actor.role !== 'caster') return rejected('该单位没有可用技能');
	const center = command.to ?? findUnit(state, command.targetId ?? '')?.position;
	if (!finitePoint(center)) return rejected('术式需要一个目标点或目标单位');
	if (!navigation.isWalkable(center)) return rejected('术式落点不可通行');
	if (distance(actor.position, center) > SKILL_INFO.caster.range + EPSILON) return rejected('术式落点超出 10 米');
	if (!navigation.lineOfSight(actor.position, center)) return rejected('术式落点被墙体或关闭的门遮挡');
	const targets = state.units.filter(unit => unit.hp > 0 && unit.team !== actor.team
		&& distance(center, unit.position) <= SKILL_INFO.caster.radius + EPSILON
		&& navigation.lineOfSight(center, unit.position));
	if (!targets.length) return rejected('术式范围内没有可见敌人');
	return { ok: true, targetIds: targets.map(unit => unit.id), amount: SKILL_INFO.caster.amount };
}

const skillName = (unit: Unit): string => unit.role === 'tank' ? SKILL_INFO.tank.name
	: unit.role === 'healer' ? SKILL_INFO.healer.name : SKILL_INFO.caster.name;

export function damageAmount(attack: number, kind: DamageType, target: Unit): number {
	const raw = kind === 'arts' ? Math.max(1, Math.round(attack * (1 - Math.min(100, Math.max(0, target.resistance)) / 100)))
		: Math.max(1, attack - target.defense);
	return target.guarding ? Math.max(raw > 0 ? 1 : 0, Math.floor(raw / 2)) : raw;
}

function dealDamage(actor: Unit, target: Unit, attack: number, kind: DamageType, events: BattleEvent[]): void {
	const amount = Math.min(target.hp, damageAmount(attack, kind, target));
	target.hp = Math.max(0, target.hp - amount);
	events.push({ type: 'damage', unitId: actor.id, targetId: target.id, amount, text: `${target.name} 受到 ${amount} 点${kind === 'arts' ? '法术' : '物理'}伤害` });
	if (target.hp <= 0) events.push({ type: 'death', unitId: target.id, text: `${target.name} 倒下` });
}

function heal(actor: Unit, target: Unit, amount: number, events: BattleEvent[]): void {
	const restored = Math.min(amount, target.maxHp - target.hp);
	target.hp += restored;
	events.push({ type: 'heal', unitId: actor.id, targetId: target.id, amount: restored, text: `${target.name} 恢复 ${restored} 点生命` });
}

function updateOutcome(state: BattleState, events: BattleEvent[]): void {
	if (state.outcome) return;
	if (!state.units.some(unit => unit.team === 'party' && unit.hp > 0)) state.outcome = 'defeat';
	else if (!state.units.some(unit => unit.team === 'enemy' && unit.hp > 0)) state.outcome = 'victory';
	if (state.outcome) events.push({ type: 'battleEnd', text: state.outcome === 'victory' ? '遭遇战胜利' : '小队全员倒下' });
}

function advanceTurn(state: BattleState, events: BattleEvent[]): void {
	for (let checked = 0; checked < state.order.length; checked++) {
		state.turnIndex++;
		if (state.turnIndex >= state.order.length) { state.turnIndex = 0; state.round++; }
		const actor = findUnit(state, state.order[state.turnIndex]);
		if (!actor || actor.hp <= 0) continue;
		actor.budget = freshBudget();
		actor.guarding = false;
		actor.disengaged = false;
		events.push({ type: 'turn', unitId: actor.id, text: `第 ${state.round} 轮 · ${actor.name}` });
		return;
	}
}

function pointAlong(from: Point, to: Point, t: number): Point {
	return { x: from.x + (to.x - from.x) * t, z: from.z + (to.z - from.z) * t };
}

function segmentDistance(point: Point, from: Point, to: Point): number {
	const dx = to.x - from.x, dz = to.z - from.z;
	const lengthSquared = dx * dx + dz * dz;
	const t = lengthSquared ? Math.max(0, Math.min(1, ((point.x - from.x) * dx + (point.z - from.z) * dz) / lengthSquared)) : 0;
	return distance(point, pointAlong(from, to, t));
}

/** Exact exit parameter: detects crossing a melee circle even inside a long path segment. */
function circleExit(from: Point, to: Point, center: Point, radius: number): number | null {
	const dx = to.x - from.x, dz = to.z - from.z;
	const fx = from.x - center.x, fz = from.z - center.z;
	const a = dx * dx + dz * dz;
	if (a <= EPSILON * EPSILON) return null;
	const b = 2 * (fx * dx + fz * dz), c = fx * fx + fz * fz - radius * radius;
	const discriminant = b * b - 4 * a * c;
	if (discriminant <= EPSILON * EPSILON) return null;
	const exit = (-b + Math.sqrt(discriminant)) / (2 * a);
	if (exit < -EPSILON || exit >= 1 - EPSILON) return null;
	// A point already outside and moving farther away must not provoke a reaction.
	const before = pointAlong(from, to, Math.max(0, exit - 0.0001));
	if (distance(before, center) > radius + EPSILON) return null;
	return Math.max(0, exit);
}

function executeMove(state: BattleState, actor: Unit, path: Point[], navigation: Navigation, events: BattleEvent[]): void {
	const travelled: Point[] = [copyPoint(path[0])];
	let segment: Point[] = [copyPoint(path[0])];
	const arrive = (point: Point): void => {
		actor.position = copyPoint(point);
		if (distance(travelled[travelled.length - 1], point) <= EPSILON) return;
		travelled.push(copyPoint(point));
		segment.push(copyPoint(point));
	};
	const emitSegment = (): void => {
		if (segment.length < 2) return;
		// A presentation consumes each move exactly here, before the following reaction.
		events.push({ type: 'move', unitId: actor.id, path: segment, amount: navigation.pathCost(segment) });
		segment = [copyPoint(segment[segment.length - 1])];
	};
	for (let i = 1; i < path.length && actor.hp > 0; i++) {
		const from = path[i - 1], to = path[i];
		const reactions: { enemy: Unit; t: number }[] = [];
		if (!actor.disengaged) for (const enemy of state.units) {
			if (enemy.hp <= 0 || enemy.team === actor.team || enemy.budget.reaction < 1 || enemy.range > OPPORTUNITY_RANGE + EPSILON) continue;
			const t = circleExit(from, to, enemy.position, OPPORTUNITY_RANGE);
			if (t !== null && navigation.lineOfSight(enemy.position, pointAlong(from, to, Math.max(0, t - 0.0001)))) reactions.push({ enemy, t });
		}
		reactions.sort((a, b) => a.t - b.t || a.enemy.id.localeCompare(b.enemy.id));
		for (const reaction of reactions) {
			arrive(pointAlong(from, to, reaction.t));
			emitSegment();
			reaction.enemy.budget.reaction -= 1;
			events.push({ type: 'opportunity', unitId: reaction.enemy.id, targetId: actor.id, text: `${reaction.enemy.name} 使用反应：机会攻击` });
			dealDamage(reaction.enemy, actor, reaction.enemy.attack, reaction.enemy.damageType, events);
			if (actor.hp <= 0) break;
		}
		if (actor.hp > 0) arrive(to);
	}
	emitSegment();
	const cost = navigation.pathCost(travelled);
	actor.budget.movement = Math.max(0, actor.budget.movement - cost);
	// Summary only: clients must not animate this complete path a second time.
	events.push({ type: 'movementComplete', unitId: actor.id, path: travelled, amount: cost, text: `${actor.name} 移动 ${cost.toFixed(1)} 米` });
}

/** Returns one legal command at a time; callers repeat until an endTurn command is applied. */
export function chooseEnemyCommand(state: BattleState, rules: BattleRules): Command | null {
	const actor = currentUnit(state);
	if (!actor || actor.team !== 'enemy') return null;
	const endTurn: Command = { type: 'endTurn', unitId: actor.id };
	if (actor.budget.action < 1) return endTurn;
	const targets = state.units.filter(unit => unit.team !== actor.team && unit.hp > 0)
		.sort((a, b) => distance(actor.position, a.position) - distance(actor.position, b.position) || a.hp - b.hp);
	for (const target of targets) {
		const attack: Command = { type: 'attack', unitId: actor.id, targetId: target.id };
		if (rules.previewCommand(state, attack).ok) return attack;
	}
	if (actor.budget.movement <= 0.1 || targets.length === 0) return endTurn;
	let best: { command: Command; score: number } | null = null;
	for (const target of targets) {
		const startDistance = distance(actor.position, target.position);
		const dx = (target.position.x - actor.position.x) / Math.max(startDistance, EPSILON);
		const dz = (target.position.z - actor.position.z) / Math.max(startDistance, EPSILON);
		// Candidate fan follows the nearest foe while allowing obstacle detours and ranged firing positions.
		for (const length of [Math.min(actor.budget.movement, Math.max(0.1, startDistance - Math.max(BODY_RADIUS * 2 + 0.05, actor.range - 0.2))), actor.budget.movement, actor.budget.movement * 0.5, 1]) {
			for (const angle of [0, Math.PI / 6, -Math.PI / 6, Math.PI / 2, -Math.PI / 2]) {
				const to = { x: actor.position.x + (dx * Math.cos(angle) - dz * Math.sin(angle)) * length,
					z: actor.position.z + (dx * Math.sin(angle) + dz * Math.cos(angle)) * length };
				const command: Command = { type: 'move', unitId: actor.id, to };
				const preview = rules.previewCommand(state, command);
				if (!preview.ok) continue;
				const simulated = cloneState(state);
				findUnit(simulated, actor.id)!.position = to;
				const canAttack = rules.previewCommand(simulated, { type: 'attack', unitId: actor.id, targetId: target.id }).ok;
				const remainingDistance = distance(to, target.position);
				const score = (canAttack ? 100 : 0) + startDistance - remainingDistance - (preview.cost ?? 0) * 0.02;
				if (score > 0.05 && (!best || score > best.score)) best = { command, score };
			}
		}
	}
	return best?.command ?? endTurn;
}
