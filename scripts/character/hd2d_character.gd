class_name HD2DCharacter
extends Node3D
## HD2D 角色立牌：Spine 2D 骨骼渲染到 SubViewport 后贴到 3D billboard 上。
## 内建以 Spine 动画为基准的状态机（CharacterState / CharacterStateMachine）。

const CharacterState := preload("res://scripts/character/character_state.gd")
const CharacterStateMachine := preload("res://scripts/character/character_state_machine.gd")
const OUTLINE_SHADER := preload("res://scripts/shaders/outline.gdshader")
const ProjectedShadow := preload("res://scripts/effects/projected_shadow.gd")
const CollisionRids := preload("res://scripts/util/collision_rids.gd")
## 到达判定距离（米）。
const ARRIVE_DIST := 0.05
## 朝向收敛判定（度）。
const FACING_EPS_DEG := 0.25
## 接近目标此距离内直接对准方向（米），避免低速移动在最后阶段绕弧线/方向抖动。
const ALIGN_DIST := 1.0
## 角色碰撞箱默认半径（米）：body_radius 的默认值，也是角色间避让时对方无 _body_radius 方法的兜底。
const DEFAULT_BODY_RADIUS := 0.35
## 移动阶段：加速 → 巡航 → 减速（普通角色）或滑行（惯性角色）。
enum MovePhase { IDLE, ACCEL, CRUISE, DECEL, COAST }

## 角色当前 Spine 骨骼数据。注意：运行时切换骨骼必须调用 set_skeleton_data()，直接赋值不会更新 SpineSprite。
@export var skeleton_data: SpineSkeletonDataResource

@export_group("碰撞箱")
## 角色碰撞箱半径（米）：碰撞胶囊体、脚底指示器（indicator_match_body=true 时）与角色间避让共用此半径。
@export_range(0.1, 2.0, 0.05) var body_radius := DEFAULT_BODY_RADIUS

@export_group("立牌")
## 立牌中心相对脚底的高度（米）。
@export_range(0.0, 3.0, 0.05) var anchor_height := 1.2
## 立牌整体缩放系数（1.0 = 原始尺寸；发光层与投影阴影同步缩放）。
@export_range(0.1, 5.0, 0.05) var billboard_scale := 1.0
## 立牌竖直方向向镜头（相机）倾斜的最大角度（度）。
@export_range(0.0, 60.0, 1.0, "degrees") var max_tilt_deg := 15.0

@export_group("朝向")
## 角色当前逻辑朝向（度）。运行时由移动/面向逻辑驱动，也可手动设置。
@export_range(-180.0, 180.0, 1.0, "degrees") var facing_deg := 0.0
## 镜像翻转判定偏移（度）：阈值从正左侧再向右偏此角度才翻转，避免临界抖动。
@export_range(0.0, 90.0, 1.0, "degrees") var flip_bias_deg := 15.0

@export_group("脚底指示器")
## 脚底方向指示器是否可见。
@export var indicator_visible := true
## 脚底圆形指示器是否跟随碰撞箱半径（body_radius，表示角色体积）。
@export var indicator_match_body := true
## 手动指示器半径（米，indicator_match_body=false 时生效）。
@export_range(0.1, 5.0, 0.05) var indicator_radius := 0.5
## 指示器圆环宽度（米）。
@export_range(0.01, 1.0, 0.01) var indicator_ring_width := 0.08
## 指示器箭头张角（度），控制箭头的锐利程度。
@export_range(5.0, 80.0, 1.0, "degrees") var indicator_arrow_angle_deg := 30.0
## 指示器颜色（含透明度）。
@export var indicator_color := Color(0.95, 0.95, 0.95, 0.9)
## 指示器离地高度（米），避免与地面/投影阴影 z-fighting。
@export_range(0.0, 0.5, 0.005) var indicator_height := 0.02

@export_group("投影阴影")
## 投影阴影开关。
@export var shadow_enabled := true
## 投影阴影长度 = 立牌高度 × shadow_squash（越小越像正午，越大越像斜射拉长）。
@export_range(0.0, 1.0, 0.05) var shadow_squash := 0.5

@export_group("外发光")
## 外发光特效开关（仅在鼠标悬停时显现）。
@export var glow_enabled := true
## 外发光颜色。
@export var glow_color := Color(1.0, 0.84, 0.2, 1.0)
## 外发光半径（viewport 像素）。
@export_range(0.0, 80.0, 0.5) var glow_radius := 24.0
## 外发光强度。
@export_range(0.0, 8.0, 0.1) var glow_intensity := 2.0

@export_group("移动")
## 缓步速度（米/秒）：移动总距离 < crawl_dist 时采用。
@export_range(0.1, 10.0, 0.1) var crawl_speed := 0.8
## 走路速度（米/秒）：移动总距离在 [crawl_dist, walk_dist) 区间时采用。
@export_range(0.1, 20.0, 0.1) var walk_speed := 2.0
## 跑步速度（米/秒）：移动总距离 >= walk_dist 时采用。
@export_range(0.1, 30.0, 0.1) var run_speed := 5.0
## 缓步距离阈值（米）：移动总距离小于此值时采用缓步速度。
@export_range(0.5, 20.0, 0.5) var crawl_dist := 2.0
## 走路距离阈值（米）：移动总距离小于此值（且 >= crawl_dist）时采用走路速度，否则跑步。
@export_range(1.0, 50.0, 1.0) var walk_dist := 10.0
## 加速时间（秒）：开始移动时从 0 加速到档位速度的时间。
@export_range(0.05, 3.0, 0.05) var accel_time := 0.3
## 减速时间（秒）：普通角色接近终点时从当前速度减速到 0 的时间。
@export_range(0.05, 3.0, 0.05) var decel_time := 0.4
## 加速曲线（0→1 缓动，控制起步节奏；留空用 smoothstep）。
@export var accel_curve: Curve
## 减速曲线（0→1 缓动，控制收尾节奏；留空用 smoothstep）。
@export var decel_curve: Curve
## 惯性（秒）：到达终点后继续滑行的持续时间，滑行距离随速度增加。0=精确停下（普通角色），>0=滑行（轮椅/飞行角色）。
@export_range(0.0, 3.0, 0.05) var inertia := 0.0
## 移动方向转向速度（度/秒）：行进方向渐进旋转，避免突发大角度转向。
@export_range(10.0, 1080.0, 10.0, "degrees") var turn_speed := 480.0
## 视觉朝向转向速度（度/秒）：脚底箭头与立绘朝向的渐进旋转。
@export_range(10.0, 1440.0, 10.0, "degrees") var facing_speed := 720.0
## Move 动画正常播放（time_scale=1）对应的基准移动速度（米/秒）。
@export_range(0.5, 5.0, 0.1) var move_anim_reference_speed := 1.0
## 动画速度对移速的灵敏度：移速每偏离基准 1 米/秒，time_scale 增减此值。
@export_range(0.1, 1.0, 0.05) var move_anim_speed_sensitivity := 0.5

@export_group("状态面板")
## 角色标识名（仅用于识别/调试是哪个角色，不显示在状态面板）。
@export var identity_name := "角色"
## 侧面悬浮状态面板是否可见。
@export var show_status_panel := true
## 状态面板相对角色的水平偏移（米，相机右向）。
@export_range(0.0, 10.0, 0.1) var status_panel_side := 1.5
## 状态面板中心相对脚底的高度（米）。
@export_range(0.0, 10.0, 0.1) var status_panel_height := 2.2

@onready var viewport: SubViewport = $CharacterViewport
@onready var spine_sprite: SpineSprite = $CharacterViewport/SpineSprite
@onready var billboard: MeshInstance3D = $Billboard
@onready var glow_overlay: MeshInstance3D = $GlowOverlay
@onready var direction_indicator: MeshInstance3D = $DirectionIndicator

var _glow_mat: ShaderMaterial
var _glow_amount := 0.0   # 当前发光强度（平滑淡入淡出）
var _hovered := false      # 鼠标是否悬停在角色上
var _state_machine: CharacterStateMachine  # 状态机（动画驱动）
var _move_target := Vector3.ZERO
var _move_total_dist := 0.0            # 本次移动的总距离（米），用于决定三档速度
var _speed := 0.0                      # 当前实际移动速度（米/秒）
var _target_speed := 0.0               # 本次移动的档位目标速度（缓步/走路/跑步）
var _move_phase := MovePhase.IDLE      # 当前移动阶段
var _phase_t := 0.0                    # 加速/减速阶段进度 0~1
var _phase_start_speed := 0.0          # 减速/滑行起始速度
var _has_move_target := false
var _arrive_callback: Callable
var _path := PackedVector3Array()
var _path_index := 0
var _path_callback: Callable
var _move_dir := Vector3.FORWARD      # 当前实际移动方向（角速度受限渐进旋转）
var _facing_target_deg := 0.0          # 视觉朝向目标角度（度）
var _has_facing_target := false
var _status_panel_root: Node3D
var _status_panel_label: Label
var _status_panel_vp: SubViewport
var _cam_cache: Camera3D              # 相机引用缓存（避免每帧多次 get_camera_3d）
var _wall_rids_cache: Array[RID] = []  # occlusion_wall RID 缓存（墙体静态）
var _wall_rids_valid := false
var _hover_frame := 0                 # 悬停检测节流计数（每 4 帧检测一次）
var _last_status_text := ""           # 状态面板文本缓存（仅变化时更新 Label）


func _ready() -> void:
	if skeleton_data:
		spine_sprite.skeleton_data_res = skeleton_data
	add_to_group("character")
	_sync_collision_radius()
	_setup_body_material()
	_setup_glow()
	_build_indicator()
	_setup_projected_shadow()
	_setup_status_panel()
	direction_indicator.visible = indicator_visible
	_state_machine = CharacterStateMachine.new(
		Callable(self, "play_animation"),
		Callable(self, "is_animation_finished"),
	)
	_state_machine.state_changed.connect(_on_state_changed)
	_state_machine.one_shot_finished.connect(_on_one_shot_finished)
	_state_machine.start()


func _process(delta: float) -> void:
	_update_billboard()
	_update_hover()
	_update_glow(delta)
	_update_movement(delta)
	_update_turning(delta)
	_update_status_panel()
	_state_machine.update(delta)
	if direction_indicator:
		direction_indicator.rotation.y = deg_to_rad(facing_deg) + PI / 2.0
	_update_sprite_flip()


## 当箭头指向画面左侧时，把 Spine 立绘水平镜像（绕竖直轴翻转），使其面向与箭头一致。
func _update_sprite_flip() -> void:
	var cam := _get_cam()
	if cam == null:
		return
	var yaw := deg_to_rad(facing_deg) + PI / 2.0
	var facing := Vector3(cos(yaw), 0.0, -sin(yaw))               # 世界水平朝向
	var right := Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z)  # 相机水平右向
	# 阈值从 dot<0（正左侧）向右偏 flip_bias_deg：需要朝向更偏左才翻转，避免临界抖动
	spine_sprite.scale.x = -1.0 if facing.dot(right) < -sin(deg_to_rad(flip_bias_deg)) else 1.0


## 立牌水平朝向始终跟随相机（面对镜头），但竖直方向向镜头的倾斜限制在 max_tilt_deg 内。
## 同时更新本体与发光层（两者重叠、同朝向）。
func _update_billboard() -> void:
	var cam := _get_cam()
	if cam == null:
		return
	var origin := global_position
	# 相机水平右向（立牌右），保持与原实现一致的水平朝向
	var right := Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z)
	if right.length() < 0.001:
		right = Vector3(1.0, 0.0, 0.0)
	right = right.normalized()
	# 相机指向立牌的水平方向 + 仰角，用于计算立牌上方向的有限倾斜
	var to_cam := cam.global_position - origin
	var horiz := Vector3(to_cam.x, 0.0, to_cam.z)
	var horiz_len := horiz.length()
	var elev := atan2(to_cam.y, horiz_len)  # 相机相对立牌的仰角
	var tilt := clampf(elev, 0.0, deg_to_rad(max_tilt_deg))  # 只向后仰，最多 max_tilt_deg
	var up := Vector3.UP
	if horiz_len > 0.001:
		var toward := horiz / horiz_len
		up = (Vector3.UP * cos(tilt) + toward * sin(tilt)).normalized()
	var s := billboard_scale
	var basis := Basis(right, up, right.cross(up).normalized()).scaled(Vector3(s, s, s))
	billboard.global_basis = basis
	billboard.global_position = origin + up * anchor_height * s
	glow_overlay.global_basis = basis
	glow_overlay.global_position = origin + up * anchor_height * s


## 把 body_radius 同步到拾取碰撞胶囊体（半径单一来源：脚本属性）。
func _sync_collision_radius() -> void:
	var col := get_node_or_null("PickBody/CollisionShape3D")
	if col is CollisionShape3D:
		var shape := (col as CollisionShape3D).shape
		if shape is CapsuleShape3D:
			(shape as CapsuleShape3D).radius = body_radius


## 角色碰撞箱半径（米）：脚底指示器（indicator_match_body=true 时）与角色间避让共用。
func _body_radius() -> float:
	return body_radius


## 获取当前相机（缓存引用，避免每帧多次 get_camera_3d()）。
func _get_cam() -> Camera3D:
	if _cam_cache == null or not is_instance_valid(_cam_cache):
		_cam_cache = get_viewport().get_camera_3d()
	return _cam_cache


## 构建脚底方向指示器：圆环 + 等腰直角三角箭头（本地 +X 方向）。
## 圆环默认使用碰撞胶囊半径，直观表示角色体积。
func _build_indicator() -> void:
	if direction_indicator == null:
		return
	var verts := PackedVector3Array()
	var r_out := _body_radius() if indicator_match_body else indicator_radius
	var r_in := maxf(r_out - indicator_ring_width, 0.001)
	const SEGS := 64
	for i in SEGS:
		var a0 := TAU * i / SEGS
		var a1 := TAU * (i + 1) / SEGS
		verts.append(Vector3(cos(a0) * r_out, 0.0, -sin(a0) * r_out))
		verts.append(Vector3(cos(a0) * r_in, 0.0, -sin(a0) * r_in))
		verts.append(Vector3(cos(a1) * r_out, 0.0, -sin(a1) * r_out))
		verts.append(Vector3(cos(a1) * r_out, 0.0, -sin(a1) * r_out))
		verts.append(Vector3(cos(a0) * r_in, 0.0, -sin(a0) * r_in))
		verts.append(Vector3(cos(a1) * r_in, 0.0, -sin(a1) * r_in))
	var th := deg_to_rad(indicator_arrow_angle_deg)
	verts.append(Vector3(cos(th) * r_out, 0.0, sin(th) * r_out))
	verts.append(Vector3((cos(th) + sin(th)) * r_out, 0.0, 0.0))
	verts.append(Vector3(cos(th) * r_out, 0.0, -sin(th) * r_out))

	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	direction_indicator.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = indicator_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	direction_indicator.material_override = mat
	direction_indicator.position.y = indicator_height


## 投影阴影：把角色立绘沿阴影方向压扁、铺在脚底地面，得到与角色轮廓一致的投影阴影。
## 阴影跟随角色水平移动（父节点 origin 即脚底），长度 = 立牌高度 × shadow_squash。
func _setup_projected_shadow() -> void:
	if not shadow_enabled:
		return
	var size := Vector2(2.4, 2.4)
	if billboard.mesh is QuadMesh:
		size = (billboard.mesh as QuadMesh).size
	size *= billboard_scale
	var shadow := ProjectedShadow.new()
	shadow.name = "ProjectedShadow"
	add_child(shadow)
	shadow.setup(viewport.get_texture(), size)
	shadow.set_squash(shadow_squash)


## 设置角色逻辑朝向（度/弧度），或让箭头朝向某世界位置（自动投影水平面）。
func set_facing_deg(deg: float) -> void:
	facing_deg = deg


func set_facing_angle(rad: float) -> void:
	facing_deg = rad_to_deg(rad)


func set_facing_to(world_pos: Vector3) -> void:
	var dir := world_pos - global_position
	dir.y = 0.0
	if dir.length() > 0.001:
		facing_deg = rad_to_deg(atan2(-dir.z, dir.x) - PI / 2.0)


## 运行时切换 Spine 骨骼模型，并回到待机动画。
func set_skeleton_data(data: SpineSkeletonDataResource) -> void:
	skeleton_data = data
	if spine_sprite:
		spine_sprite.skeleton_data_res = data
		if _state_machine:
			_state_machine.set_state(CharacterState.Id.IDLE)
		else:
			play_animation(CharacterState.ANIMATIONS[CharacterState.Id.IDLE])


## 把 2D 视口渲染结果贴到 3D 立牌本体上（正常深度测试，被遮挡即隐藏）。
func _setup_body_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	billboard.material_override = mat


## 发光层：用 glow shader 铺在发光层 quad 上，depth_test_disabled 使其始终可见（穿透遮挡）。
func _setup_glow() -> void:
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = OUTLINE_SHADER
	_glow_mat.render_priority = 10  # 后于本体/遮挡物绘制
	_glow_mat.set_shader_parameter("albedo_tex", viewport.get_texture())
	_glow_mat.set_shader_parameter("texel_size", Vector2(1.0 / viewport.size.x, 1.0 / viewport.size.y))
	_glow_mat.set_shader_parameter("glow_color", glow_color)
	_glow_mat.set_shader_parameter("glow_radius", glow_radius)
	_glow_mat.set_shader_parameter("glow_intensity", glow_intensity)
	_glow_mat.set_shader_parameter("glow_amount", 0.0)
	glow_overlay.material_override = _glow_mat


## 鼠标悬停检测：从相机发射拾取射线，取第一个命中；只有命中角色自身（拾取体）才悬停。
## 射线排除 occlusion_wall 组，跨墙仍可悬停到角色。每 4 帧检测一次（射线开销减 75%）。
func _update_hover() -> void:
	_hover_frame += 1
	if _hover_frame % 4 != 0:
		return
	var cam := _get_cam()
	if cam == null:
		_hovered = false
		return
	var vp := get_viewport()
	var mouse := vp.get_mouse_position()
	if not Rect2(Vector2.ZERO, vp.get_visible_rect().size).has_point(mouse):
		_hovered = false
		return
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 2  # 仅 layer 2（角色拾取 Area3D），避免地面/墙抢走最近命中
	query.exclude = _get_wall_rids()  # 穿透 occlusion_wall，跨墙仍可悬停角色
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_hovered = false
		return
	_hovered = is_ancestor_of(hit.get("collider") as Node)


## occlusion_wall 组碰撞体 RID（首次使用收集后缓存；墙体静态，缓存有效）。
func _get_wall_rids() -> Array[RID]:
	if not _wall_rids_valid:
		_wall_rids_cache = CollisionRids.collect_group_rids(get_tree(), "occlusion_wall")
		_wall_rids_valid = true
	return _wall_rids_cache


## 平滑驱动发光强度：悬停且总开关开启 → 淡入；否则淡出。
func _update_glow(delta: float) -> void:
	var target := 1.0 if (_hovered and glow_enabled) else 0.0
	_glow_amount = move_toward(_glow_amount, target, delta * 8.0)
	if _glow_mat:
		_glow_mat.set_shader_parameter("glow_amount", _glow_amount)


## 显示/隐藏脚底方向指示器。
func set_indicator_visible(on: bool) -> void:
	indicator_visible = on
	if direction_indicator:
		direction_indicator.visible = on


## 开启/关闭外发光特效（总开关；仍只在鼠标悬停时显现）。
func set_glow_enabled(enabled: bool) -> void:
	glow_enabled = enabled


## 查询鼠标是否正悬停在角色上。
func is_hovered() -> bool:
	return _hovered


## 设置外发光颜色。
func set_glow_color(color: Color) -> void:
	glow_color = color
	if _glow_mat:
		_glow_mat.set_shader_parameter("glow_color", color)


## 播放 Spine 动画（loop 默认循环）。
func play_animation(anim_name: String, loop: bool = true) -> void:
	var state: SpineAnimationState = spine_sprite.get_animation_state()
	if state:
		state.set_animation(anim_name, loop)


## 设置 Spine 动画全局播放速度倍率。移动时用它让 Move 动画速度跟随实际移动速度，消除低速脚滑。
func _set_anim_time_scale(scale: float) -> void:
	var state: SpineAnimationState = spine_sprite.get_animation_state()
	if state:
		state.set_time_scale(scale)


## 让 Move 动画播放速度跟随实际移动速度（带基准修正：低速保底、高速快放）。
func _sync_move_anim_speed() -> void:
	var anim_scale := 1.0 - (move_anim_reference_speed - _speed) * move_anim_speed_sensitivity
	_set_anim_time_scale(clampf(anim_scale, 0.25, 3.0))


func play_move() -> void:
	set_state(CharacterState.Id.MOVE)


func play_idle() -> void:
	set_state(CharacterState.Id.IDLE)


## 查询当前 Spine 动画是否已播放完成（一次性动画回退判断）。
func is_animation_finished() -> bool:
	var state: SpineAnimationState = spine_sprite.get_animation_state()
	if state == null:
		return true
	var track := state.get_track(0)
	if track == null:
		return true
	var done: bool = track.is_complete()
	return done


## 切换到指定角色状态（动画由状态机自动播放）。
func set_state(next: int, return_state: int = -1) -> void:
	if _state_machine:
		_state_machine.set_state(next, return_state)


## 查询当前角色状态。
func get_state() -> int:
	if _state_machine:
		return _state_machine.get_state()
	return CharacterState.Id.IDLE


## 状态切换钩子（逻辑层可在此响应）。
func _on_state_changed(_previous: int, _current: int) -> void:
	pass


## 一次性动画播放完成钩子（Interact 小动作播完自动回退，无需额外逻辑）。
func _on_one_shot_finished(_state: int) -> void:
	pass


## 移动到目标点（保持当前地面高度），到达后回 IDLE 并可回调。
## 速度按移动总距离分三档：缓步（< crawl_dist）/ 走路（< walk_dist）/ 跑步（>= walk_dist）。
## 起步曲线加速、收尾曲线减速；惯性角色（inertia>0）到达后滑行一段再停。
func move_to(target: Vector3, arrive: Callable = Callable()) -> void:
	# 清空旧的导航路径，避免到达直行点后继续把旧路径走完（与 stop_moving 对称）。
	_path = PackedVector3Array()
	_path_callback = Callable()
	_move_target = target
	_move_target.y = global_position.y
	var to := _move_target - global_position
	to.y = 0.0
	_move_total_dist = to.length()
	_has_move_target = true
	_arrive_callback = arrive
	_move_dir = _dir_to(_move_target)
	_target_speed = _target_speed_for(_move_total_dist)
	_move_phase = MovePhase.ACCEL
	_phase_t = 0.0
	set_state(CharacterState.Id.MOVE)


## 停止移动并回到待机（立即停止，不滑行）。
func stop_moving() -> void:
	_has_move_target = false
	_speed = 0.0
	_move_phase = MovePhase.IDLE
	_set_anim_time_scale(1.0)
	_arrive_callback = Callable()
	_path = PackedVector3Array()
	_path_callback = Callable()
	_has_facing_target = false
	if _state_machine and _state_machine.get_state() == CharacterState.Id.MOVE:
		set_state(CharacterState.Id.IDLE)


## 沿导航路径逐点移动（由 PlayerController 寻路后调用）。
## 路径先做 Chaikin 细分平滑，拐角变圆滑；段间转向渐进。
## 速度按整条路径总长度分三档（缓步/走路/跑步），中间路径点平滑穿过不停顿。
func move_along_path(path: PackedVector3Array, arrive: Callable = Callable()) -> void:
	_path = smooth_path(path)
	_path_index = 0
	_path_callback = arrive
	_has_move_target = false
	_arrive_callback = Callable()
	_move_total_dist = _path_length(_path)
	if _advance_path_point():
		_move_dir = _dir_to(_move_target)
		_target_speed = _target_speed_for(_move_total_dist)
		_move_phase = MovePhase.ACCEL
		_phase_t = 0.0
		set_state(CharacterState.Id.MOVE)


## 推进到下一个路径点；路径走完返回 false 并触发回调。
func _advance_path_point() -> bool:
	while _path_index < _path.size():
		var p := _path[_path_index]
		p.y = global_position.y
		if p.distance_to(global_position) > ARRIVE_DIST:
			_move_target = p
			_has_move_target = true
			return true
		_path_index += 1
	_path = PackedVector3Array()
	var cb := _path_callback
	_path_callback = Callable()
	if cb.is_valid():
		cb.call()
	return false


## 移动逻辑：阶段状态机（加速 → 巡航 → 减速/滑行）。
## 起步曲线加速、收尾曲线减速；惯性角色到达后滑行。视觉朝向渐进跟随移动方向。
func _update_movement(delta: float) -> void:
	if not _has_move_target:
		return

	# 惯性滑行阶段：沿惯性方向继续飘，速度摩擦衰减到 0
	if _move_phase == MovePhase.COAST:
		var friction := _phase_start_speed / maxf(inertia, 0.001)
		_speed = maxf(_speed - friction * delta, 0.0)
		global_position += _slide_around_characters(_move_dir * (_speed * delta))
		_sync_move_anim_speed()
		if _speed <= 0.0:
			_speed = 0.0
			_finish_movement()
		return

	var to_target := _move_target - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var is_final_leg := _path.is_empty() or _path_index >= _path.size() - 1

	# 到达判定（移动前）
	if dist < ARRIVE_DIST:
		_on_reach_target()
		return

	# 推进阶段，更新速度
	match _move_phase:
		MovePhase.ACCEL:
			_phase_t += delta / maxf(accel_time, 0.001)
			if _phase_t >= 1.0:
				_phase_t = 1.0
				_speed = _target_speed
				_move_phase = MovePhase.CRUISE
			else:
				_speed = _target_speed * _sample_ease(accel_curve, _phase_t)
		MovePhase.CRUISE:
			_speed = _target_speed
			# 普通角色接近最终目标时提前减速；惯性角色不主动减速，靠滑行
			if is_final_leg and inertia <= 0.0 and dist <= _decel_distance(_speed):
				_move_phase = MovePhase.DECEL
				_phase_t = 0.0
				_phase_start_speed = _speed
		MovePhase.DECEL:
			_phase_t += delta / maxf(decel_time, 0.001)
			_speed = _phase_start_speed * (1.0 - _sample_ease(decel_curve, _phase_t))
			if _phase_t >= 1.0:
				_on_reach_target()
				return

	# 移动
	var step := _speed * delta
	if step > dist:
		step = dist
	if dist <= ALIGN_DIST:
		_move_dir = to_target.normalized()
	else:
		# 移动方向朝目标方向渐进旋转（角速度受限），避免突发大角度折向
		_move_dir = _steer_dir(_move_dir, to_target.normalized(), turn_speed, delta)
	# 角色间碰撞：移动向量经水平圆滑动避让，防止互相穿过
	var move_vec := _slide_around_characters(_move_dir * step)
	global_position += move_vec
	# 视觉朝向跟随移动方向渐进旋转（到达后继续转到最终朝向）
	_set_facing_target_dir(_move_dir)
	_sync_move_anim_speed()


## 到达目标后的处理：最终目标精确到位，中间路径点平滑通过（不瞬移，避免密集路径点间的跳变卡顿）。
func _on_reach_target() -> void:
	if _path.size() > 0:
		# 推进交给 _advance_path_point（内部会跳过已到达点），避免重复自增造成跳点。
		if _advance_path_point():
			_move_dir = _dir_to(_move_target)
			return  # 中间路径点：不瞬移，平滑通过
		# 路径走完（_advance_path_point 已触发 _path_callback）→ 最终目标，精确到位
		global_position = _move_target
		if inertia > 0.0:
			_move_phase = MovePhase.COAST
			_phase_start_speed = _speed
			return
		_finish_movement()
		return
	# move_to 到达 → 最终目标，精确到位
	global_position = _move_target
	if inertia > 0.0:
		_move_phase = MovePhase.COAST
		_phase_start_speed = _speed
		return
	_finish_movement()


## 移动彻底结束：清零状态、恢复动画速度、回到 IDLE 并触发回调。
func _finish_movement() -> void:
	_speed = 0.0
	_has_move_target = false
	_move_phase = MovePhase.IDLE
	_set_anim_time_scale(1.0)
	var cb := _arrive_callback
	_arrive_callback = Callable()
	set_state(CharacterState.Id.IDLE)
	if cb.is_valid():
		cb.call()


## 角色间碰撞绕行（水平 2D 圆-圆）：目标位置进入对方体积时，径向钳到圆边缘，
## 并把被削减的径向量转为切向偏移 → 角色沿对方边缘滑开绕行，而非原地卡住。
## 恰好接触时（距离=半径和）双方都能切向错开，不再互相锁定。远离方向不受影响。
func _slide_around_characters(move_vec: Vector3) -> Vector3:
	if move_vec.length() < 0.0001:
		return move_vec
	var self_r := _body_radius()
	var f2 := Vector2(global_position.x, global_position.z)
	var mv2 := Vector2(move_vec.x, move_vec.z)
	var t2 := f2 + mv2  # 本帧目标位置
	var step_len := mv2.length()
	for other in get_tree().get_nodes_in_group("character"):
		if other == self or not (other is Node3D):
			continue
		var opos: Vector3 = (other as Node3D).global_position
		var other_r := DEFAULT_BODY_RADIUS
		if other.has_method("_body_radius"):
			other_r = other._body_radius()
		var o2 := Vector2(opos.x, opos.z)
		var d := t2 - o2
		var dist := d.length()
		var min_d := self_r + other_r
		if dist < 0.001:
			# 目标与对方完全重合：沿移动方向推到接触点（更自然）
			if mv2.length() < 0.0001:
				t2 = o2 + Vector2(min_d, 0.0)
			else:
				t2 = o2 + mv2.normalized() * min_d
		elif dist < min_d:
			# 径向钳到圆边缘，削减量转切向（绕行）：clamped + 切向*penetration
			var normal := d / dist
			var clamped := o2 + normal * min_d
			var pen := min_d - dist
			var tangent := Vector2(-normal.y, normal.x)
			if tangent.dot(mv2) < 0.0:
				tangent = -tangent  # 取与移动方向同侧的切线（绕行方向）
			t2 = clamped + tangent * minf(pen, step_len)
	return Vector3(t2.x - f2.x, move_vec.y, t2.y - f2.y)


## 角速度受限的方向转向：把 cur 方向朝 target 方向最多旋转 deg_per_sec*delta 度。
func _steer_dir(cur: Vector3, target: Vector3, deg_per_sec: float, delta: float) -> Vector3:
	if cur.length() < 0.001:
		return target.normalized()
	var cur_angle := atan2(-cur.z, cur.x) - PI / 2.0
	var tgt_angle := atan2(-target.z, target.x) - PI / 2.0
	var diff := wrapf(tgt_angle - cur_angle, -PI, PI)
	var max_step := deg_to_rad(deg_per_sec) * delta
	var new_angle := tgt_angle if absf(diff) <= max_step else cur_angle + signf(diff) * max_step
	return Vector3(cos(new_angle + PI / 2.0), 0.0, -sin(new_angle + PI / 2.0))


## 计算从当前位置到 world_pos 的水平单位方向（退化时用当前朝向兜底）。
func _dir_to(world_pos: Vector3) -> Vector3:
	var d := world_pos - global_position
	d.y = 0.0
	if d.length() < 0.001:
		return _facing_dir()
	return d.normalized()


## 当前视觉朝向对应的水平单位方向。
func _facing_dir() -> Vector3:
	var yaw := deg_to_rad(facing_deg) + PI / 2.0
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## 记录渐进转向的目标角度（由 _update_turning 每帧平滑逼近）。
func _set_facing_target_dir(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.001:
		return
	_facing_target_deg = rad_to_deg(atan2(-flat.z, flat.x) - PI / 2.0)
	_has_facing_target = true


## 三档目标速度：按移动总距离分档（缓步/走路/跑步）。
func _target_speed_for(dist: float) -> float:
	if dist < crawl_dist:
		return crawl_speed
	if dist < walk_dist:
		return walk_speed
	return run_speed


## 曲线采样：优先用导出曲线，留空用 smoothstep 缓动（0→1）。
func _sample_ease(curve: Curve, t: float) -> float:
	if curve:
		return curve.sample(clampf(t, 0.0, 1.0))
	return t * t * (3.0 - 2.0 * t)  # smoothstep


## 减速距离：以当前速度按减速曲线降到 0 所需的前进距离（smoothstep 平均速度 0.5）。
func _decel_distance(speed: float) -> float:
	return speed * decel_time * 0.5


## 计算路径的水平总长度（米），用于按总距离决定移动速度。
func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(path.size() - 1):
		var dx := path[i + 1].x - path[i].x
		var dz := path[i + 1].z - path[i].z
		total += sqrt(dx * dx + dz * dz)
	return total


## 每帧把 facing_deg 以 facing_speed 向目标角度渐进旋转（走最短弧，跨 ±180° 环绕）。
func _update_turning(delta: float) -> void:
	if not _has_facing_target:
		return
	var cur := facing_deg
	var tgt := _wrap_deg(_facing_target_deg, cur)
	var diff := absf(tgt - cur)
	if diff <= FACING_EPS_DEG:
		facing_deg = tgt
		_has_facing_target = false
		return
	facing_deg = move_toward(cur, tgt, facing_speed * delta)


## 把 angle_deg 平移到以 reference_deg 为中心、差值在 ±180° 内的等效角度。
func _wrap_deg(angle_deg: float, reference_deg: float) -> float:
	var diff := fmod(angle_deg - reference_deg + 540.0, 360.0) - 180.0
	return reference_deg + diff


## Chaikin 细分平滑：把折线拐角切圆（保持首尾点），迭代 iterations 次。
## 静态方法，供外部（PlayerController 路径可视化）复用同一平滑结果。
static func smooth_path(path: PackedVector3Array, iterations: int = 2) -> PackedVector3Array:
	var pts := path
	for _i in range(iterations):
		if pts.size() < 3:
			break
		var out := PackedVector3Array()
		out.append(pts[0])
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			out.append(a.lerp(b, 0.25))
			out.append(a.lerp(b, 0.75))
		out.append(pts[pts.size() - 1])
		pts = out
	return pts


## ===================== 侧面悬浮状态面板（3D 空间，非 UI） =====================

## 构建跟随角色的悬浮半透明面板（SubViewport 渲染文本 → QuadMesh billboard）。
func _setup_status_panel() -> void:
	_status_panel_root = Node3D.new()
	_status_panel_root.name = "StatusPanel3D"
	add_child(_status_panel_root)

	_status_panel_vp = SubViewport.new()
	_status_panel_vp.transparent_bg = true
	_status_panel_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_status_panel_vp.size = Vector2i(256, 128)
	_status_panel_root.add_child(_status_panel_vp)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.10, 0.62)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_panel_vp.add_child(bg)

	_status_panel_label = Label.new()
	_status_panel_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_panel_label.add_theme_font_size_override("font_size", 24)
	_status_panel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_panel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_panel_vp.add_child(_status_panel_label)

	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.8, 0.9)
	quad.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _status_panel_vp.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	quad.material_override = mat
	_status_panel_root.add_child(quad)


## 每帧更新面板：面向相机、位于角色侧面高处、刷新状态文本。
func _update_status_panel() -> void:
	if _status_panel_root == null:
		return
	_status_panel_root.visible = show_status_panel
	if not show_status_panel:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_status_panel_root.global_basis = cam.global_basis
	_status_panel_root.global_position = global_position \
		+ cam.global_basis * Vector3(status_panel_side, status_panel_height, 0.0)
	if _status_panel_label:
		var text := _build_status_text()
		if text != _last_status_text:
			_last_status_text = text
			_status_panel_label.text = text


## 面板文本：仅当前状态（identity_name 仅用于识别角色，不显示在此）。
func _build_status_text() -> String:
	return CharacterState.NAMES.get(get_state(), "?")


## 切换面板显隐（PlayerController 的 F1 调用）。
func toggle_status_panel() -> void:
	set_status_panel_visible(not show_status_panel)


## 设置面板显隐。
func set_status_panel_visible(on: bool) -> void:
	show_status_panel = on
