class_name RpgCamera
extends Camera3D
## TRPG 风格轨道相机：WASD 移焦点、Q/E 环绕（带惯性）、中键 PAN、滚轮推拉、镜头震动。

## 焦点小球（轨道目标）节点路径
@export var focus_path: NodePath
## 焦点小球，运行时从 focus_path 解析（非 Node3D 节点会被视为无效）
@onready var focus: Node3D = (get_node_or_null(focus_path) as Node3D) if focus_path != NodePath() else null

@export_range(2.0, 40.0) var min_distance := 4.0
@export_range(2.0, 40.0) var max_distance := 14.0
@export_range(5.0, 45.0) var min_pitch := 12.0    # 近距离水平视角
@export_range(5.0, 45.0) var max_pitch := 45.0    # 远距离俯视视角
@export_range(0.0, 45.0) var pitch_min := 0.0     # 俯仰角全局下限
@export_range(15.0, 180.0) var yaw_speed := 60.0  # 环绕速度（度/秒）
@export_range(0.5, 20.0) var focus_speed := 5.0   # 焦点移动速度
@export_range(0.0, 2.0) var focus_height := 0.5
@export var ground_group := "ground"
@export_range(0.5, 20.0) var float_trigger_height := 2.0  # 下方超过此高度无地面 → 进入浮空
@export_range(1.0, 30.0) var height_follow_speed := 10.0  # 高度跟随平滑速度
@export var float_visual_hint := true   # 浮空时视点小球变橙色提示（false 关闭）
@export_range(0.05, 1.0) var zoom_anim_duration := 0.25
@export_range(1.0, 30.0) var focus_accel := 8.0     # 焦点加速度（越大越快达到满速；松手滑行也越快停）
@export_range(1.0, 20.0) var orbit_damping := 5.0    # 环绕惯性衰减
@export_range(0.05, 2.0) var pan_sensitivity := 0.3  # 中键 PAN 灵敏度（度/像素）
@export_range(0.0, 2.0) var shake_amplitude := 0.5
@export_range(0.5, 10.0) var shake_decay := 2.5

## 球面轨道参数（唯一事实来源，位置都由它们推导）
var _distance := 8.0
var _yaw := 45.0
var _pitch := 35.0

var _orbit_dir := 0            # -1 逆时针(Q) / 0 停 / +1 顺时针(E)
var _orbit_vel := 0.0          # 环绕角速度（带惯性）
var _focus_vel := Vector3.ZERO # 焦点速度向量（带惯性）
var _pan_active := false       # 中键 PAN 是否按住
var _shake_trauma := 0.0       # 震动强度 0~1
var _floating := false         # 浮空状态：锁定当前高度，不再吸附地面
var _zoom_tween: Tween         # 滚轮推拉动画（内置 Tween，替代原手动状态机）

var _focus_sphere: MeshInstance3D   # 视点小球（变色提示用）
var _float_hint_mat: StandardMaterial3D
const _float_hint_color := Color(1.0, 0.55, 0.2, 0.95)  # 浮空提示色：橙色
const _look_height := 0.6      # 注视点/碰撞检测高度（角色胸部）
const _orbit_accel := 6.0      # 环绕加速速率


func _ready() -> void:
	if focus == null:
		push_warning("RpgCamera: focus 未设置，请把透明小球节点拖到 focus 属性")
		return
	_rebuild_orbit_from_camera()  # 从场景摆放位置初始化，避免跳变
	_apply_camera_position()
	_setup_float_hint()


## 准备浮空变色提示：定位视点小球并创建提示材质（用 override，不动原材质）
func _setup_float_hint() -> void:
	if not float_visual_hint:
		return
	var s := focus.get_node_or_null("FocusSphere")
	if s is MeshInstance3D:
		_focus_sphere = s
		_float_hint_mat = StandardMaterial3D.new()
		_float_hint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_float_hint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_float_hint_mat.disable_receive_shadows = true
		_float_hint_mat.albedo_color = _float_hint_color


## 公共查询接口：小球当前是否处于浮空模式
func is_floating() -> bool:
	return _floating


## 浮空提示开关（运行时可切换）
func set_float_hint_visible(hint_on: bool) -> void:
	if _focus_sphere == null:
		return
	if hint_on:
		_focus_sphere.material_override = _float_hint_mat
	else:
		_focus_sphere.material_override = null


func _unhandled_input(event: InputEvent) -> void:
	if focus == null:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and not event.echo:
		_handle_key(event)


func _process(delta: float) -> void:
	if focus == null:
		return
	_update_focus_move(delta)  # WASD 焦点移动（渲染帧驱动，无颗粒感）
	_update_orbit_yaw(delta)   # QE 环绕独立更新（PAN 激活时惯性已清零）
	_apply_camera_position()   # 轨道位置每帧应用（推拉动画由 Tween 驱动 _distance/_pitch）
	_apply_shake(delta)


## WASD 焦点移动：速度向量平滑逼近目标方向，松手后惯性滑行；镜头越远越快
func _update_focus_move(delta: float) -> void:
	var target_vel := _get_wasd_dir() * focus_speed * _zoom_scale()
	_focus_vel = _focus_vel.lerp(target_vel, _exp_damp(delta, focus_accel))
	if _focus_vel.length() > 0.01:
		_move_focus(_focus_vel * delta, delta)
	else:
		_focus_vel = Vector3.ZERO


## 距离缩放系数：最近处=1，最远处=max_distance/min_distance，镜头越远移动/缩放越快
func _zoom_scale() -> float:
	return _distance / min_distance


## 环绕角速度：按住逼近满速，松手指数衰减；角度直接积分，天然平滑无段落感
func _update_orbit_yaw(delta: float) -> void:
	if _orbit_dir != 0:
		_orbit_vel = lerpf(_orbit_vel, _orbit_dir * yaw_speed, _exp_damp(delta, _orbit_accel))
	else:
		_orbit_vel *= exp(-delta * orbit_damping)
	if absf(_orbit_vel) > 0.01:
		_yaw = wrapf(_yaw + _orbit_vel * delta, -180.0, 180.0)


## 帧率无关的指数阻尼系数（rate 越大收敛越快）
static func _exp_damp(delta: float, rate: float) -> float:
	return 1.0 - exp(-delta * rate)


# ===================== 输入 =====================

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_set_pan(event.pressed)
		return
	if not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP: _start_zoom(_distance - _zoom_scale())
		MOUSE_BUTTON_WHEEL_DOWN: _start_zoom(_distance + _zoom_scale())


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_Q: _orbit_dir = -1 if event.pressed else 0
		KEY_E: _orbit_dir = 1 if event.pressed else 0


## 中键按下/松开：进入 PAN 时清掉 QE 惯性，避免与拖拽争抢 yaw
func _set_pan(active: bool) -> void:
	_pan_active = active
	if active:
		_orbit_dir = 0
		_orbit_vel = 0.0


## 中键拖拽：横移环绕（yaw）、纵移俯仰（pitch）
func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _pan_active:
		return
	_yaw = wrapf(_yaw - event.relative.x * pan_sensitivity, -180.0, 180.0)
	_pitch = clampf(_pitch + event.relative.y * pan_sensitivity, pitch_min, max_pitch)
	# 相机位置由 _process 每帧平滑跟随


## 基于相机朝向获取 WASD 水平方向（视野平面投影；对角输入由 normalized 归一化）
func _get_wasd_dir() -> Vector3:
	var cam_basis := global_transform.basis
	var fwd := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
	var right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
	var x := 0.0
	var y := 0.0
	if Input.is_physical_key_pressed(KEY_D): x += 1.0
	if Input.is_physical_key_pressed(KEY_A): x -= 1.0
	if Input.is_physical_key_pressed(KEY_W): y += 1.0
	if Input.is_physical_key_pressed(KEY_S): y -= 1.0
	return (fwd * y + right * x).normalized()


# ===================== 推拉动画（smoothstep 缓动插值 distance + pitch） =====================

## 启动推拉动画：distance 与 pitch 联动平滑（smoothstep 缓动），yaw 由 QE 独立积分。
## 用内置 Tween 驱动 _distance/_pitch；相机位置由 _process 每帧统一应用。
func _start_zoom(target_dist: float) -> void:
	if _zoom_tween != null:
		_zoom_tween.kill()
	var from_dist := _distance
	var from_pitch := _pitch
	var to_dist := clampf(target_dist, min_distance, max_distance)
	var to_pitch := _pitch_for_distance(to_dist)
	_zoom_tween = create_tween()
	_zoom_tween.tween_method(
		func(t: float) -> void:
			var s := smoothstep(0.0, 1.0, t)
			_distance = lerpf(from_dist, to_dist, s)
			_pitch = lerpf(from_pitch, to_pitch, s),
		0.0, 1.0, zoom_anim_duration)


## 立即设置距离并联动俯仰角（无动画；公共接口）
func set_distance(value: float) -> void:
	_distance = clampf(value, min_distance, max_distance)
	_pitch = _pitch_for_distance(_distance)
	_apply_camera_position()


## 距离 → 俯仰角联动（近水平，远俯视）
func _pitch_for_distance(dist: float) -> float:
	return lerpf(min_pitch, max_pitch, inverse_lerp(min_distance, max_distance, dist))


# ===================== 移动焦点小球 =====================

## 移动焦点：水平由惯性驱动（已在 _update_focus_move 平滑），垂直高度平滑跟随地面。
## 浮空规则：脚下地面在 float_trigger_height 以内则吸附地面；一旦超距/无地面则进入浮空，
## 锁定当前高度不再吸附，直到镜头位置被重置（_rebuild_orbit_from_camera / reset_focus_ground()）。
func _move_focus(offset: Vector3, delta: float) -> void:
	var target := focus.global_position + offset
	var target_y := _resolve_focus_height(target, focus.global_position.y)
	focus.global_position = Vector3(
		target.x,
		lerpf(focus.global_position.y, target_y, _exp_damp(delta, height_follow_speed)),
		target.z)
	_apply_camera_position()


## 目标高度：脚下有近地面 → 吸附；无地面/超距 → 浮空（锁定高度）。
## 浮空中若脚下重新出现近地面 → 自动解除浮空。
func _resolve_focus_height(target: Vector3, current_y: float) -> float:
	var ground_y := _ground_height_at(target)
	var airborne := is_inf(ground_y) or current_y - ground_y > float_trigger_height
	if _floating:
		if airborne:
			return current_y          # 仍无地面/太远：保持浮空
		_exit_floating()              # 下方有地面且足够近 → 自动解除
	elif airborne:
		_enter_floating()             # 下方超距/无地面 → 进入浮空
		return current_y
	return ground_y + focus_height    # 有地面 → 吸附


func _enter_floating() -> void:
	_floating = true
	set_float_hint_visible(true)


func _exit_floating() -> void:
	_floating = false
	set_float_hint_visible(false)


## 解除浮空状态，恢复地面吸附（公共接口：外部重置镜头位置时调用）
func reset_focus_ground() -> void:
	if _floating:
		_exit_floating()


# ===================== 轨道应用（位置推导） =====================

## 目标轨道位置：完全由 focus + (distance/yaw/pitch) 决定，不被遮挡顶高
func _compute_target_position() -> Vector3:
	var yaw_r := deg_to_rad(_yaw)
	var pitch_r := deg_to_rad(_pitch)
	var dir := Vector3(sin(yaw_r), 0.0, cos(yaw_r))
	return focus.global_position + dir * (_distance * cos(pitch_r)) \
		+ Vector3(0.0, _distance * sin(pitch_r), 0.0)


## 立即按轨道参数设置相机位置
func _apply_camera_position() -> void:
	if focus == null:
		return
	global_position = _compute_target_position()
	_look_at_focus()


## 注视焦点上方（角色胸部高度）
func _look_at_focus() -> void:
	look_at(focus.global_position + Vector3(0.0, _look_height, 0.0), Vector3.UP)


# ===================== 镜头震动 =====================

## 公共接口：add_shake(0.4)，trauma 叠加取上限
func add_shake(amount: float) -> void:
	_shake_trauma = clampf(_shake_trauma + amount, 0.0, 1.0)


## 每帧衰减并叠加随机偏移（幅度 = trauma²）
func _apply_shake(delta: float) -> void:
	if _shake_trauma <= 0.0:
		return
	_shake_trauma = maxf(_shake_trauma - shake_decay * delta, 0.0)
	var amp := _shake_trauma * _shake_trauma * shake_amplitude
	global_position += Vector3(
		randf_range(-1.0, 1.0) * amp,
		randf_range(-1.0, 1.0) * amp,
		randf_range(-1.0, 1.0) * amp)


# ===================== 轨道重建 / 工具 =====================

## 从相机实际位置反推轨道参数（模式切换不跳变）；同时重置镜头位置 → 解除浮空状态
func _rebuild_orbit_from_camera() -> void:
	if _floating:
		_exit_floating()
	var rel := global_position - focus.global_position
	var rel_len := rel.length()
	if rel_len < 0.001:
		return
	_distance = clampf(rel_len, min_distance, max_distance)
	_pitch = clampf(rad_to_deg(asin(clampf(rel.y / rel_len, -1.0, 1.0))), pitch_min, max_pitch)
	_yaw = wrapf(rad_to_deg(atan2(rel.x, rel.z)), -180.0, 180.0)


## 水平位置的地面高度（向下射线）：只认 ground 组的物体，墙体/有顶物一律跳过；无地面返回 -INF
func _ground_height_at(pos: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(pos.x, 100.0, pos.z), Vector3(pos.x, -100.0, pos.z))
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var space := get_world_3d().direct_space_state
	for i in 64:  # 上限保护：最多穿透 64 层，绝不死循环
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider := hit.get("collider") as Node
		if collider != null and _in_group_recursive(collider, ground_group):
			return (hit.get("position") as Vector3).y
		# 用 hit 自身的 rid 排除（保证与命中对象一致），继续向下找地面
		query.exclude.append(hit.get("rid"))
	return -INF  # 无地面


## 沿祖先链检查节点是否在组内（子碰撞体挂在父节点组上的情况）
static func _in_group_recursive(node: Node, group: String) -> bool:
	var cur: Node = node
	while cur != null:
		if cur.is_in_group(group):
			return true
		cur = cur.get_parent()
	return false
