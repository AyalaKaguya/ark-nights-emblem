class_name CharacterStateMachine
extends RefCounted
## 角色状态机：以 Spine 动画为基准。
##
## 通过 Callable 与宿主角色解耦：宿主注入「播放动画」和「查询动画是否播完」
## 两个回调，状态机负责状态切换、动画映射与一次性动画回退。

const CharacterState := preload("res://scripts/character/character_state.gd")

## 状态改变信号（previous, current）
signal state_changed(previous: int, current: int)
## 一次性动画播放完成信号（completed_state）
signal one_shot_finished(state: int)

var _play_animation: Callable         # func(anim_name: String, loop: bool) -> void
var _is_animation_finished: Callable  # func() -> bool
var _current: int = CharacterState.Id.IDLE
var _return_state: int = CharacterState.Id.IDLE
var _idle_timer := 0.0
var _idle_next_trigger := 0.0

## IDLE 状态下随机播放 Interact 小动作（与交互对象无关）。
var idle_interact_enabled := true
var idle_interact_min := 4.0   # 随机触发的最短间隔（秒）
var idle_interact_max := 10.0  # 随机触发的最长间隔（秒）


func _init(play_animation: Callable, is_finished: Callable) -> void:
	_play_animation = play_animation
	_is_animation_finished = is_finished
	_idle_next_trigger = randf_range(idle_interact_min, idle_interact_max)


func get_state() -> int:
	return _current


## 强制播放当前状态的动画（用于初始化：当前已是 IDLE，绕过 set_state 的 next==current 短路）。
func start() -> void:
	_play_animation.call(_animation_for(_current), _is_looping(_current))


## 切换到指定状态。return_state 用于一次性状态：动画播完后回退到它（默认回退到进入前状态）。
func set_state(next: int, return_state: int = -1) -> void:
	if next == _current:
		return
	var prev := _current
	_current = next
	if CharacterState.ONE_SHOT.has(next):
		_return_state = return_state if return_state >= 0 else prev
	_play_animation.call(_animation_for(next), _is_looping(next))
	state_changed.emit(prev, next)


## 每帧调用：处理一次性动画播放完成的自动回退，以及 IDLE 状态随机触发 Interact 小动作。
func update(delta: float) -> void:
	# 一次性动画（Interact）播放完成 → 回退到进入前状态
	if CharacterState.ONE_SHOT.has(_current):
		if _is_animation_finished.call():
			var done := _current
			set_state(_return_state)
			one_shot_finished.emit(done)
		return
	# IDLE 状态：随机间隔播放 Interact 小动作（与交互对象无关）
	if _current == CharacterState.Id.IDLE and idle_interact_enabled:
		_idle_timer += delta
		if _idle_timer >= _idle_next_trigger:
			_idle_timer = 0.0
			_idle_next_trigger = randf_range(idle_interact_min, idle_interact_max)
			set_state(CharacterState.Id.INTERACT, CharacterState.Id.IDLE)


func _animation_for(state: int) -> String:
	return CharacterState.ANIMATIONS.get(state, "Relax")


func _is_looping(state: int) -> bool:
	return not CharacterState.ONE_SHOT.has(state)
