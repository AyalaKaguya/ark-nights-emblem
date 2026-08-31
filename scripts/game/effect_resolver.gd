class_name EffectResolver
extends RefCounted
## 效果结算：把 effect_id + 参数应用到目标，返回结算事件数组（供表现层播放动画/VFX/飘字）。
## 属于"规则层"，不含任何场景表现。

const UnitState := preload("res://scripts/game/unit_state.gd")
const SkillData := preload("res://scripts/data/skill_data.gd")
const StatusEffectData := preload("res://scripts/data/status_effect_data.gd")
const DamageFormula := preload("res://scripts/game/damage_formula.gd")

## 结算并返回事件数组。events 项：{ kind, actor, target, amount, ... }。
static func resolve(actor: UnitState, targets: Array, effect_id: String, params: Dictionary) -> Array:
	var events := []
	match effect_id:
		"damage":
			events.append_array(_damage(actor, targets, params))
		"heal":
			events.append_array(_heal(actor, targets, params))
		"cleanse":
			events.append_array(_cleanse(actor, targets))
		"apply_status":
			events.append_array(_apply_status(actor, targets, params))
		"noop":
			events.append({"kind": "noop", "actor": actor})
		_:
			push_warning("EffectResolver: 未知效果 id '%s'，按 noop 处理" % effect_id)
			events.append({"kind": "noop", "actor": actor})
	return events


static func _damage(actor: UnitState, targets: Array, params: Dictionary) -> Array:
	var events := []
	var atk_mult: float = params.get("atk_mult", 1.0)
	var flat: float = params.get("flat_damage", 0.0)
	var damage_type: String = params.get("damage_type", "physical")
	var atk := actor.effective_atk()
	for t in targets:
		if t is UnitState and (t as UnitState).alive:
			var amount := DamageFormula.compute(atk * atk_mult + flat, t, damage_type)
			var died: bool = (t as UnitState).apply_damage(amount)
			events.append({"kind": "damage", "actor": actor, "target": t, "amount": amount, "damage_type": damage_type})
			# 命中技力回复（ON_HIT）
			_restore_on_hit(actor)
			if died:
				events.append({"kind": "death", "actor": actor, "target": t})
				_restore_on_kill(actor)
	return events


static func _heal(actor: UnitState, targets: Array, params: Dictionary) -> Array:
	var events := []
	var flat: float = params.get("amount", 0.0)
	var hp_mult: float = params.get("max_hp_mult", 0.0)
	for t in targets:
		if t is UnitState and (t as UnitState).alive:
			var amount := flat + (t as UnitState).effective_max_hp() * hp_mult
			(t as UnitState).heal(amount)
			events.append({"kind": "heal", "actor": actor, "target": t, "amount": amount})
	return events


static func _apply_status(actor: UnitState, targets: Array, params: Dictionary) -> Array:
	var events := []
	var status: StatusEffectData = params.get("status", null)
	if status == null:
		return events
	for t in targets:
		if t is UnitState and (t as UnitState).alive:
			(t as UnitState).apply_status(status)
			events.append({"kind": "status", "actor": actor, "target": t, "status": status})
	return events


## 净化：移除目标身上的全部减益，返回结算事件。
static func _cleanse(actor: UnitState, targets: Array) -> Array:
	var events := []
	for t in targets:
		if t is UnitState and (t as UnitState).alive:
			var u := t as UnitState
			var removed := u.remove_debuffs()
			if removed > 0:
				events.append({"kind": "cleanse", "actor": actor, "target": u, "removed": removed})
	return events


static func _restore_on_hit(actor: UnitState) -> void:
	_check_restore(actor, SkillData.RestoreCondition.ON_HIT)


static func _restore_on_kill(actor: UnitState) -> void:
	_check_restore(actor, SkillData.RestoreCondition.ON_KILL)


static func _check_restore(actor: UnitState, cond: int) -> void:
	if actor == null or actor.operator == null:
		return
	if actor.operator.basic_attack and actor.operator.basic_attack.restore_condition == cond:
		actor.recover_sp(actor.operator.basic_attack.restore_amount)
	for s in actor.operator.skills:
		if s.restore_condition == cond:
			actor.recover_sp(s.restore_amount)
