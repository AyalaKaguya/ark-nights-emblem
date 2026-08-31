class_name TurnManager
extends RefCounted
## 回合管理器：先手队列（友方→敌方）、回合开始恢复（体力 +4 封顶、技力回复、冷却/状态推进）、
## 胜利 / 失败 / 撤退判定。纯规则层。

const UnitState := preload("res://scripts/game/unit_state.gd")

signal round_started(round_number: int)
signal turn_started(unit: UnitState, events: Array)
signal turn_ended(unit: UnitState)
signal battle_finished(result: String)

var allies: Array = []     # Array[UnitState]
var enemies: Array = []    # Array[UnitState]
var order: Array = []      # 本轮顺序
var round_number := 0
var active_unit: UnitState = null
var active := false

var _idx := 0


func start_battle(ally_list: Array, enemy_list: Array) -> void:
	allies = ally_list.duplicate()
	enemies = enemy_list.duplicate()
	round_number = 0
	active = true
	_start_round()


func is_active() -> bool:
	return active


## 结束当前单位的回合，进入下一单位。
func end_turn() -> void:
	if not active:
		return
	if active_unit != null:
		turn_ended.emit(active_unit)
		active_unit = null
	_next()


## 撤退：作为独立战斗行为结算（由表现层在玩家回合调用）。
func retreat() -> void:
	if not active:
		return
	active = false
	battle_finished.emit("retreat")


## 立即结束战斗（外部强制，如加载 / 重置）。
func force_finish(result: String) -> void:
	if not active:
		return
	active = false
	battle_finished.emit(result)


func _start_round() -> void:
	round_number += 1
	order = []
	for u in allies:
		order.append(u)
	for u in enemies:
		order.append(u)
	_idx = 0
	round_started.emit(round_number)
	_next()


func _next() -> void:
	if not active:
		return
	if _check_end():
		return
	while _idx < order.size():
		var u: UnitState = order[_idx]
		_idx += 1
		if not u.alive:
			continue
		active_unit = u
		var events := u.recover_turn_start()
		if _check_end():
			return
		if not u.alive:
			# 回合开始被自身 dot 击杀且战斗未结束：跳过其回合，顺延到下一单位
			active_unit = null
			continue
		turn_started.emit(u, events)
		return
	_start_round()


func _check_end() -> bool:
	if not active:
		return true
	if _all_dead(enemies):
		active = false
		battle_finished.emit("victory")
		return true
	if _all_dead(allies):
		active = false
		battle_finished.emit("defeat")
		return true
	return false


func _all_dead(list: Array) -> bool:
	if list.is_empty():
		return false
	for u in list:
		if (u as UnitState).alive:
			return false
	return true


## 当前是否是玩家（友方）单位在行动。
func is_player_turn() -> bool:
	return active_unit != null and active_unit.faction() == "ally"
