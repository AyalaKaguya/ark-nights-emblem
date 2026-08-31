class_name UnitState
extends RefCounted
## 纯运行时状态：一名单位（干员 / 敌人）的 HP、技力、体力、位置、状态效果、冷却与背包。
## 不含任何 Node / 表现逻辑；表现层（UnitActor）订阅 changed 刷新。

const OperatorData := preload("res://scripts/data/operator_data.gd")
const SkillData := preload("res://scripts/data/skill_data.gd")
const EquipmentData := preload("res://scripts/data/equipment_data.gd")
const StatusEffectData := preload("res://scripts/data/status_effect_data.gd")
const Inventory := preload("res://scripts/game/inventory.gd")
const ItemData := preload("res://scripts/data/item_data.gd")

signal changed

## 动作槽网格：12 列，默认 2 行（24 槽），最多 4 行（48 槽）。
const SLOT_COLUMNS := 12
const SLOT_ROWS_MAX := 4
const SLOT_COUNT_MAX := SLOT_COLUMNS * SLOT_ROWS_MAX

var operator: OperatorData
var unit_id := ""
var hp := 0.0
var sp := 0
var stamina := 0.0
## 权威世界坐标（米，XZ 平面）。
var pos := Vector2.ZERO
var alive := true
var statuses: Array[StatusEffectData] = []
var status_durations := {}       # status_id -> 剩余回合数
var skill_cooldowns := {}        # skill_id -> 剩余回合数
var inventory := Inventory.new()
var equipment: Array[EquipmentData] = []
var acted_this_turn := false     # 本回合是否已执行过"动作"（移动不受限，普攻/技能/道具受限）
## 动作槽绑定（48 项）："attack" / "skill:N"（N=operator.skills 索引）/ "item" / ""（空槽）。
var slot_bindings: Array[String] = []

var _dbg_tag := ""


func _init(op: OperatorData = null, id: String = "") -> void:
	operator = op
	unit_id = id
	_dbg_tag = op.operator_id if op else id


func bind_operator(op: OperatorData, id: String = "") -> void:
	operator = op
	unit_id = id if id != "" else op.operator_id
	_dbg_tag = op.operator_id
	reset_to_full()


func reset_to_full() -> void:
	if operator == null:
		return
	hp = float(operator.max_hp)
	sp = 0
	stamina = float(operator.max_stamina)
	pos = Vector2.ZERO
	alive = true
	statuses = []
	status_durations = {}
	skill_cooldowns = {}
	acted_this_turn = false
	slot_bindings = default_slot_bindings()
	emit_changed()


## 默认动作槽绑定：槽 0 普攻、槽 1-3 技能、槽 4 道具，其余空。
func default_slot_bindings() -> Array[String]:
	var b: Array[String] = []
	b.resize(SLOT_COUNT_MAX)
	b.fill("")
	b[0] = "attack"
	var i := 1
	for idx in operator.skills.size():
		if i >= 4:
			break
		b[i] = "skill:%d" % idx
		i += 1
	b[4] = "item"
	return b


## 解析槽位绑定为动作描述：{ "kind": "attack"/"skill"/"item", "skill": SkillData, "item": ItemData } 或空字典。
func resolve_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= slot_bindings.size():
		return {}
	var key := slot_bindings[slot_index]
	if key == "attack":
		return {"kind": "attack", "skill": operator.basic_attack}
	if key.begins_with("skill:"):
		var idx := int(key.get_slice(":", 1))
		if idx >= 0 and idx < operator.skills.size():
			return {"kind": "skill", "skill": operator.skills[idx]}
	if key == "item":
		var it := first_item()
		if it != null:
			return {"kind": "item", "item": it}
	return {}


## 背包中的第一件道具（道具槽使用）。
func first_item() -> ItemData:
	for item_id in inventory.items().keys():
		if inventory.count(item_id) > 0:
			return _find_item_data(item_id)
	return null


func _find_item_data(item_id: String) -> ItemData:
	const DataFactory := preload("res://scripts/game/data_factory.gd")
	for it in DataFactory.default_items():
		if it.item_id == item_id:
			return it
	return null


## 该槽位是否有可执行动作。
func slot_has_action(slot_index: int) -> bool:
	return not resolve_slot(slot_index).is_empty()


## 槽位显示名。
func slot_display_name(slot_index: int) -> String:
	var d := resolve_slot(slot_index)
	if d.is_empty():
		return ""
	match d["kind"]:
		"attack":
			return "普攻"
		"skill":
			return (d["skill"] as SkillData).display_name
		"item":
			return (d["item"] as ItemData).display_name
	return ""


func emit_changed() -> void:
	changed.emit()


## ===================== 有效属性（含装备与状态修正） =====================

func effective_max_hp() -> float:
	var v := float(operator.max_hp)
	for e in equipment:
		v += e.max_hp_bonus
	return maxf(v, 1.0)


func effective_atk() -> float:
	var v := float(operator.atk)
	for e in equipment:
		v += e.atk_bonus
	var mult := 0.0
	for s in statuses:
		mult += s.atk_modifier
	return maxf(v * (1.0 + mult), 0.0)


func effective_def() -> float:
	var v := float(operator.defense)
	for e in equipment:
		v += e.def_bonus
	var mult := 0.0
	for s in statuses:
		mult += s.def_modifier
	return maxf(v * (1.0 + mult), 0.0)


func effective_res() -> float:
	var v := float(operator.res)
	for e in equipment:
		v += e.res_bonus
	var mult := 0.0
	for s in statuses:
		mult += s.res_modifier
	return clampf(v * (1.0 + mult), 0.0, 100.0)


## ===================== 资源 =====================

func can_afford(stamina_cost: float, sp_cost: int) -> bool:
	return stamina >= stamina_cost - 0.0001 and sp >= sp_cost


## 原子扣费：不足时不扣任何资源，返回 false。
func deduct(stamina_cost: float, sp_cost: int) -> bool:
	if not can_afford(stamina_cost, sp_cost):
		return false
	stamina -= stamina_cost
	sp -= sp_cost
	emit_changed()
	return true


## 回复（封顶）。
func recover_stamina(amount: float) -> float:
	var before := stamina
	stamina = minf(stamina + amount, float(operator.max_stamina))
	emit_changed()
	return stamina - before


func recover_sp(amount: int) -> int:
	var before := sp
	sp = mini(sp + amount, int(operator.max_sp))
	emit_changed()
	return sp - before


## 自身回合开始：体力 +4（封顶 6）、技力 + 每回合回复、推进冷却与状态。
## 返回本回合的结算事件（dot 伤害等），供表现层播放。
func recover_turn_start() -> Array:
	var events := []
	recover_stamina(operator.stamina_recover_per_turn)
	recover_sp(operator.sp_regen_per_turn)
	# 每回合固定技力回复之外，按技能恢复条件补充（ON_TURN_START）
	if operator.basic_attack and operator.basic_attack.restore_condition == SkillData.RestoreCondition.ON_TURN_START:
		recover_sp(operator.basic_attack.restore_amount)
	for s in operator.skills:
		if s.restore_condition == SkillData.RestoreCondition.ON_TURN_START:
			recover_sp(s.restore_amount)
	acted_this_turn = false
	events.append_array(tick_statuses())
	tick_cooldowns()
	return events


## 推进冷却：所有技能剩余冷却 -1。
func tick_cooldowns() -> void:
	for k in skill_cooldowns.keys():
		skill_cooldowns[k] = int(skill_cooldowns[k]) - 1
		if skill_cooldowns[k] <= 0:
			skill_cooldowns.erase(k)


func start_cooldown(skill: SkillData) -> void:
	if skill.cooldown > 0:
		skill_cooldowns[skill.skill_id] = skill.cooldown


func is_on_cooldown(skill: SkillData) -> bool:
	return int(skill_cooldowns.get(skill.skill_id, 0)) > 0


## ===================== 生命 =====================

## 造成伤害，返回是否死亡。
func apply_damage(amount: float) -> bool:
	hp = maxf(hp - amount, 0.0)
	if hp <= 0.0 and alive:
		alive = false
		hp = 0.0
	emit_changed()
	return not alive


func heal(amount: float) -> float:
	if not alive:
		return 0.0  # 死亡单位不可治疗（复活须走显式复活流程）
	var before := hp
	hp = minf(hp + amount, effective_max_hp())
	emit_changed()
	return hp - before


## ===================== 状态效果 =====================

func apply_status(data: StatusEffectData) -> void:
	if data == null:
		return
	# 同名状态不叠层：已存在时只刷新持续时间，防止 buff 无限刷层
	for s in statuses:
		if s.status_id == data.status_id:
			status_durations[data.status_id] = data.duration_turns
			emit_changed()
			return
	statuses.append(data)
	status_durations[data.status_id] = data.duration_turns
	emit_changed()


## 清除全部减益（净化），返回移除的数量。
func remove_debuffs() -> int:
	var removed := 0
	for s in statuses.duplicate():
		if s.is_debuff:
			statuses.erase(s)
			status_durations.erase(s.status_id)
			removed += 1
	if removed > 0:
		emit_changed()
	return removed


## 回合结算：dot 伤害，扣减持续时间并清理过期状态。返回事件数组。
func tick_statuses() -> Array:
	var events := []
	var expired := []
	for s in statuses:
		if s.dot_per_turn > 0:
			var died := apply_damage(float(s.dot_per_turn))
			events.append({"kind": "dot", "target": self, "amount": float(s.dot_per_turn)})
			if died:
				events.append({"kind": "death", "target": self})
		var dur := int(status_durations.get(s.status_id, 0))
		if dur > 0:
			dur -= 1
			if dur <= 0:
				status_durations.erase(s.status_id)
				expired.append(s)
			else:
				status_durations[s.status_id] = dur
	for s in expired:
		statuses.erase(s)
	emit_changed()
	return events


func has_status(status_id: String) -> bool:
	return status_durations.has(status_id)


## ===================== 序列化 =====================

func to_dict() -> Dictionary:
	var status_ids := []
	for s in statuses:
		status_ids.append(s.status_id)
	return {
		"unit_id": unit_id,
		"operator_id": operator.operator_id if operator else "",
		"hp": hp,
		"sp": sp,
		"stamina": stamina,
		"x": pos.x,
		"y": pos.y,
		"alive": alive,
		"inventory": inventory.to_dict(),
		"statuses": status_ids,
		"cooldowns": skill_cooldowns.duplicate(),
		"slot_bindings": slot_bindings.duplicate(),
	}


## 从字典还原（operator 通过 id 查表注入）。
func from_dict(d: Dictionary, operator: OperatorData) -> void:
	bind_operator(operator, str(d.get("unit_id", operator.operator_id)))
	hp = float(d.get("hp", effective_max_hp()))
	sp = int(d.get("sp", 0))
	stamina = float(d.get("stamina", operator.max_stamina))
	pos = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	alive = bool(d.get("alive", true))
	inventory.from_dict(d.get("inventory", {}))
	# 状态效果与冷却按 id 重建（状态效果数据从 operator 表中恢复需外部注入，这里仅还原冷却）
	skill_cooldowns = {}
	var cds: Dictionary = d.get("cooldowns", {})
	for k in cds:
		skill_cooldowns[k] = int(cds[k])
	# 动作槽绑定
	var binds: Array = d.get("slot_bindings", [])
	if binds.size() == SLOT_COUNT_MAX:
		slot_bindings = binds.duplicate()
	else:
		slot_bindings = default_slot_bindings()
	emit_changed()


func faction() -> String:
	return operator.faction if operator else "ally"


func is_enemy_of(other: UnitState) -> bool:
	return faction() != other.faction()


func world_position() -> Vector3:
	return Vector3(pos.x, 0.0, pos.y)
