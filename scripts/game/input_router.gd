extends Node
## autoload InputRouter：InputMap 动作注册中心 + 语义化输入路由。
## 避免各系统硬编码按键互相冲突：UI 只订阅语义信号，动作 → 语义的映射集中在本文档。
## （相机 WASD/QE、玩家左右键仍沿用既有实现，但通过 GameState.mode 由模式控制器门控。）

signal interact
signal toggle_inventory
signal toggle_operator
signal toggle_tactical
signal end_turn
signal retreat
signal cancel
signal confirm
signal cycle_unit

## 动作名常量（与 InputMap 一致）。
const ACTION_INTERACT := "ui_interact"
const ACTION_TOGGLE_INVENTORY := "ui_toggle_inventory"
const ACTION_TOGGLE_OPERATOR := "ui_toggle_operator"
const ACTION_TOGGLE_TACTICAL := "ui_toggle_tactical"
const ACTION_END_TURN := "ui_end_turn"
const ACTION_RETREAT := "ui_retreat"
const ACTION_CANCEL := "ui_cancel"
const ACTION_CONFIRM := "ui_confirm"
const ACTION_CYCLE_UNIT := "ui_cycle_unit"


func _ready() -> void:
	_build_input_map()


## 幂等注册 InputMap 动作（运行期构建，避免手写 project.godot 序列化风险）。
func _build_input_map() -> void:
	_add_key_action(ACTION_INTERACT, KEY_F)
	_add_key_action(ACTION_TOGGLE_INVENTORY, KEY_TAB)
	_add_key_action(ACTION_TOGGLE_OPERATOR, KEY_O)
	_add_key_action(ACTION_TOGGLE_TACTICAL, KEY_T)
	_add_key_action(ACTION_END_TURN, KEY_ENTER)
	_add_key_action(ACTION_RETREAT, KEY_R)
	_add_key_action(ACTION_CANCEL, KEY_ESCAPE)
	_add_key_action(ACTION_CONFIRM, KEY_SPACE)
	_add_key_action(ACTION_CYCLE_UNIT, KEY_COMMA)


func _add_key_action(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	# 幂等：已存在该键则跳过
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.physical_keycode == keycode:
			return
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_INTERACT):
		interact.emit()
	elif event.is_action_pressed(ACTION_TOGGLE_INVENTORY):
		toggle_inventory.emit()
	elif event.is_action_pressed(ACTION_TOGGLE_OPERATOR):
		toggle_operator.emit()
	elif event.is_action_pressed(ACTION_TOGGLE_TACTICAL):
		toggle_tactical.emit()
	elif event.is_action_pressed(ACTION_END_TURN):
		end_turn.emit()
	elif event.is_action_pressed(ACTION_RETREAT):
		retreat.emit()
	elif event.is_action_pressed(ACTION_CANCEL):
		cancel.emit()
	elif event.is_action_pressed(ACTION_CONFIRM):
		confirm.emit()
	elif event.is_action_pressed(ACTION_CYCLE_UNIT):
		cycle_unit.emit()


## 当前模式是否允许"实时探索类"输入（相机始终可用，玩家移动/交互仅在非战斗模式）。
static func realtime_input_enabled(mode: int) -> bool:
	const GameModeDef := preload("res://scripts/game/game_mode.gd")
	return mode != GameModeDef.Mode.COMBAT_TURN
