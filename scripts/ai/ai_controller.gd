class_name AiController
extends Node
## 简单 AI 控制器：驱动角色状态机做待机 / 漫游决策。
##
## 挂在场景任意位置，把要控制的 HD2DCharacter 拖到 target_path。

const CharacterState := preload("res://scripts/character/character_state.gd")
## 移动超时（秒）：角色持续移动超过此时长仍未完成（如被碰撞卡住）→ 强制停下重新决策。
const MOVE_TIMEOUT := 8.0

enum Behavior {
	IDLE,     # 仅待机（idle 小动作由角色状态机自行随机触发）
	WANDER,   # 随机漫游
}

@export var target_path: NodePath              # 要控制的角色（HD2DCharacter）节点路径
@export var behavior: Behavior = Behavior.WANDER
@export_range(0.5, 30.0) var wander_radius := 6.0   # 漫游半径
@export_range(0.0, 20.0) var idle_wait := 1.5       # 每次决策前的空闲等待（秒）

var _target: Variant = null                     # 运行时解析的目标角色（duck-typing 调用）
var _rng := RandomNumberGenerator.new()
var _idle_time := 0.0
var _move_time := 0.0


func _ready() -> void:
	_rng.randomize()
	_target = get_node_or_null(target_path)
	_idle_time = _rng.randf_range(0.0, idle_wait)


func _process(delta: float) -> void:
	if _target == null or not _target.has_method("get_state"):
		return
	var state: int = _target.get_state()
	# 移动超时保护：被卡住（碰撞/寻路异常）时强制停下并立即重新决策
	if state == CharacterState.Id.MOVE:
		_move_time += delta
		if _move_time >= MOVE_TIMEOUT:
			_move_time = 0.0
			if _target.has_method("stop_moving"):
				_target.stop_moving()
			_decide()
		return
	_move_time = 0.0
	# 角色忙（交互中）时不决策
	if state != CharacterState.Id.IDLE:
		return
	_idle_time += delta
	if _idle_time >= idle_wait:
		_idle_time = 0.0
		_decide()


## 决策：按 behavior 选择下一行为。
func _decide() -> void:
	match behavior:
		Behavior.IDLE:
			_target.set_state(CharacterState.Id.IDLE)
		Behavior.WANDER:
			_wander()


## 在漫游半径内随机选点移动。
func _wander() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var r := _rng.randf_range(wander_radius * 0.3, wander_radius)
	var offset := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
	_target.move_to(_target.global_position + offset)
