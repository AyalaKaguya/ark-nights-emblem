class_name ActionPipeline
extends RefCounted
## 统一动作管线：动作定义 → 目标校验 → 资源校验 → 原子扣费 → 效果结算。
## 纯规则层，不触发任何动画 / VFX（结算事件由表现层消费）。
##
## context: { "units": Array[UnitState], "bounds": Rect2 }

const EffectResolver := preload("res://scripts/game/effect_resolver.gd")
const UnitState := preload("res://scripts/game/unit_state.gd")
const SkillData := preload("res://scripts/data/skill_data.gd")
const ItemData := preload("res://scripts/data/item_data.gd")


class ActionDef:
	var kind := ""              # "move" / "attack" / "skill" / "item"
	var actor: UnitState
	var target_pos := Vector2.ZERO
	var targets: Array = []     # Array[UnitState]
	var skill: SkillData
	var item: ItemData
	var distance_m := 0.0       # 移动距离（validate 填充）


class Result:
	var ok := false
	var reason := ""
	var stamina_cost := 0.0
	var sp_cost := 0
	var events: Array = []
	var distance_m := 0.0


## 校验：不产生任何扣费 / 状态变化。返回 Result（ok=false 时 reason 说明原因）。
static func validate(action: ActionDef, context: Dictionary) -> Result:
	var r := Result.new()
	if action == null or action.actor == null:
		r.reason = "无动作主体"
		return r
	var actor := action.actor
	if not actor.alive:
		r.reason = "单位已阵亡"
		return r
	match action.kind:
		"move":
			_validate_move(action, context, r)
		"attack":
			if not _validate_offensive(action, actor.operator.basic_attack, actor.operator.basic_attack, context, r, false):
				pass
		"skill":
			_validate_offensive(action, action.skill, action.skill, context, r, true)
		"item":
			_validate_item(action, context, r)
		_:
			r.reason = "未知动作类型 '%s'" % action.kind
	return r


## 执行：校验通过后原子扣费 + 结算。失败校验不产生任何扣费。
static func execute(action: ActionDef, context: Dictionary) -> Result:
	var r := validate(action, context)
	if not r.ok:
		return r
	var actor := action.actor
	match action.kind:
		"move":
			if not actor.deduct(r.stamina_cost, 0):
				r.ok = false
				r.reason = "体力不足"
				return r
			actor.pos = action.target_pos
			actor.emit_changed()
			r.events.append({"kind": "move", "actor": actor, "pos": action.target_pos, "distance_m": r.distance_m})
		"attack":
			_finish_offensive(actor, actor.operator.basic_attack, action.targets, r)
		"skill":
			_finish_offensive(actor, action.skill, action.targets, r)
		"item":
			if not actor.deduct(r.stamina_cost, r.sp_cost):
				r.ok = false
				r.reason = "资源不足"
				return r
			if not actor.inventory.remove_item(action.item.item_id, 1):
				r.ok = false
				r.reason = "道具数量不足"
				return r
			actor.acted_this_turn = true
			r.events.append_array(EffectResolver.resolve(actor, action.targets, action.item.effect_id, action.item.effect_params))
			r.events.append({"kind": "item", "actor": actor, "item": action.item, "targets": action.targets})
	return r


## ===================== 移动 =====================

static func _validate_move(action: ActionDef, context: Dictionary, r: Result) -> void:
	var actor := action.actor
	var bounds := _bounds(context)
	var target := action.target_pos
	if target.x < bounds.position.x or target.x > bounds.end.x or target.y < bounds.position.y or target.y > bounds.end.y:
		r.reason = "目标超出地图边界"
		return
	var d := Vector2(target - actor.pos).length()
	var move_budget := actor.stamina / maxf(actor.operator.move_stamina_per_meter, 0.0001)
	if d > move_budget + 0.0001:
		r.reason = "目标超出移动范围（体力不足）"
		return
	if _overlaps_other(actor, target, context):
		r.reason = "目标位置被其他单位占据"
		return
	var cost := d * actor.operator.move_stamina_per_meter
	if not actor.can_afford(cost, 0):
		r.reason = "体力不足"
		return
	r.ok = true
	r.distance_m = d
	r.stamina_cost = cost


## ===================== 普攻 / 技能 =====================

static func _validate_offensive(action: ActionDef, skill: SkillData, _basic: SkillData, context: Dictionary, r: Result, is_skill: bool) -> bool:
	if skill == null:
		r.reason = "未配置普攻" if not is_skill else "未指定技能"
		return false
	if action.actor.acted_this_turn:
		r.reason = "本回合已执行过动作"
		return false
	if is_skill and action.skill == null:
		r.reason = "未指定技能"
		return false
	if action.actor.is_on_cooldown(skill):
		r.reason = "技能冷却中"
		return false
	if not action.actor.can_afford(skill.stamina_cost, skill.sp_cost):
		r.reason = "资源不足（需体力%.1f/技力%d）" % [skill.stamina_cost, skill.sp_cost]
		return false
	# 目标校验
	var targets := _filter_targets(action, skill, context)
	if targets.is_empty():
		r.reason = "无有效目标"
		return false
	action.targets = targets
	r.ok = true
	r.stamina_cost = skill.stamina_cost
	r.sp_cost = skill.sp_cost
	return true


static func _finish_offensive(actor: UnitState, skill: SkillData, targets: Array, r: Result) -> void:
	if not actor.deduct(r.stamina_cost, r.sp_cost):
		r.ok = false
		r.reason = "资源不足"
		return
	actor.acted_this_turn = true
	actor.start_cooldown(skill)
	r.events.append({"kind": "action_cast", "actor": actor, "skill": skill, "targets": targets})
	r.events.append_array(EffectResolver.resolve(actor, targets, skill.effect_id, skill.effect_params))


## 按目标方式从 context 中选取 / 校验目标。
static func _filter_targets(action: ActionDef, skill: SkillData, context: Dictionary) -> Array:
	var actor := action.actor
	var out: Array = []
	match skill.target_mode:
		SkillData.TargetMode.SELF:
			if actor.alive:
				out.append(actor)
		SkillData.TargetMode.SINGLE_ENEMY, SkillData.TargetMode.SINGLE_ALLY:
			if action.targets.size() > 0:
				var t = action.targets[0]
				if t is UnitState and (t as UnitState).alive:
					if _target_allowed(actor, t, skill.target_mode) and _in_range(actor, t, skill.range_m):
						out.append(t)
		SkillData.TargetMode.ALL_ENEMY, SkillData.TargetMode.ALL_ALLY:
			for u in _units(context):
				if u.alive and _target_allowed(actor, u, skill.target_mode) and _in_range(actor, u, skill.range_m):
					out.append(u)
		SkillData.TargetMode.POINT_AOE:
			# 点目标：以目标点为中心，effect_radius 内全部敌人。
			var center: Vector2 = action.target_pos
			var radius := skill.effect_radius_m
			for u in _units(context):
				if u.alive and u.faction() != actor.faction():
					if Vector2(u.pos - center).length() <= radius + 0.0001:
						out.append(u)
	return out


static func _target_allowed(actor: UnitState, target: UnitState, mode: int) -> bool:
	match mode:
		SkillData.TargetMode.SINGLE_ENEMY, SkillData.TargetMode.ALL_ENEMY, SkillData.TargetMode.POINT_AOE:
			return actor.is_enemy_of(target)
		SkillData.TargetMode.SINGLE_ALLY, SkillData.TargetMode.ALL_ALLY:
			return not actor.is_enemy_of(target)
	return true


static func _in_range(actor: UnitState, target: UnitState, range_m: float) -> bool:
	return Vector2(actor.pos - target.pos).length() <= range_m + 0.0001


## ===================== 道具 =====================

static func _validate_item(action: ActionDef, context: Dictionary, r: Result) -> void:
	var actor := action.actor
	if action.item == null:
		r.reason = "未指定道具"
		return
	if actor.acted_this_turn:
		r.reason = "本回合已执行过动作"
		return
	if not actor.inventory.has(action.item.item_id):
		r.reason = "道具数量不足"
		return
	if not actor.can_afford(action.item.stamina_cost, action.item.sp_cost):
		r.reason = "资源不足"
		return
	# 目标默认自身，或由调用方指定（须为友方且在范围内）。
	var targets := []
	if action.targets.size() > 0:
		for t in action.targets:
			if t is UnitState and (t as UnitState).alive and not actor.is_enemy_of(t):
				targets.append(t)
	if targets.is_empty():
		targets.append(actor)
	action.targets = targets
	r.ok = true
	r.stamina_cost = action.item.stamina_cost
	r.sp_cost = action.item.sp_cost


## ===================== 上下文工具 =====================

static func _units(context: Dictionary) -> Array:
	return context.get("units", [])


static func _bounds(context: Dictionary) -> Rect2:
	var b: Rect2 = context.get("bounds", Rect2(0, 0, 0, 0))
	if b.size.x <= 0 or b.size.y <= 0:
		return Rect2(-24, -24, 48, 48)
	return b


## 目标点是否落入其他存活单位的体积内（连续圆判定；排除 actor 自身）。
static func _overlaps_other(actor: UnitState, target: Vector2, context: Dictionary) -> bool:
	for u in _units(context):
		var other := u as UnitState
		if other == null or other == actor or not other.alive:
			continue
		var min_d := actor.operator.body_radius + other.operator.body_radius
		if Vector2(other.pos - target).length() < min_d:
			return true
	return false
