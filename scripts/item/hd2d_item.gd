class_name HD2DItem
extends Interactable
## 静态物品立牌：2D 物品贴图渲染进 SubViewport 后贴到 3D billboard 上。
## 仿照 HD2DCharacter 的 HD-2D 立牌管线，但移除移动/状态机/方向指示器/状态面板，
## 保留并复用的部分：
##   - 面向相机的 billboard（竖直方向向镜头有限倾斜，max_tilt_deg 限制）
##   - 投影阴影（按贴图 alpha 裁剪、只投阴影，交给引擎阴影系统；跟随主光）
##   - 悬停 / 选中时的外发光（outline 着色器，穿透遮挡）
##   - Interactable 交互能力（自动拾取区 + 选中发光 + interact() 钩子）
##
## 用法：在 SceneTree 放一个 HD2DItem，给 item_texture 赋一张带透明背景的物品 PNG，
##   用 display_size / sprite_scale / sprite_offset 把立绘贴满 billboard 即可。
##   需要交互逻辑时重写 _on_interact(character)。

const OUTLINE_SHADER := preload("res://scripts/shaders/outline.gdshader")
const ProjectedShadow := preload("res://scripts/effects/projected_shadow.gd")
const RpgCamera := preload("res://scripts/camera/rpg_camera.gd")

@export_group("物品贴图")
## 物品 2D 立绘（建议 PNG，带透明背景）。渲染进 SubViewport 后贴到 billboard。
@export var item_texture: Texture2D
## 立绘在视口内的缩放（贴满 / 缩小用）。
@export_range(0.1, 8.0, 0.05) var sprite_scale := 1.0
## 立绘相对视口中心的像素偏移（微调构图，配合 sprite_scale 居中）。
@export var sprite_offset := Vector2.ZERO

@export_group("立牌")
## billboard 显示尺寸（米）：宽、高。投影阴影同步采用此尺寸。
@export var display_size := Vector2(1.0, 1.2)
## 立牌中心相对脚底（节点原点）的高度（米）。
@export_range(0.0, 3.0, 0.05) var anchor_height := 0.6
## 立牌整体缩放系数（1.0 = 原始尺寸；投影阴影同步缩放）。
@export_range(0.1, 5.0, 0.05) var billboard_scale := 1.0
## 立牌竖直方向向镜头倾斜的最大角度（度）。
@export_range(0.0, 60.0, 1.0, "degrees") var max_tilt_deg := 15.0

@export_group("交互")
## 是否作为可交互对象（关闭后移出 interactable 组并删除拾取区，变为纯装饰立牌）。
@export var interaction_enabled := true

@export_group("投影阴影")
## 投影阴影开关（隐形阴影板：按立绘 alpha 裁剪、只投阴影，交给引擎阴影系统处理）。
@export var shadow_enabled := true

@export_group("外发光")
## 外发光特效开关（仅在鼠标悬停或选中时显现）。
@export var glow_enabled := true
## 外发光颜色。
@export var glow_color := Color(1.0, 0.84, 0.2, 1.0)
## 外发光半径（viewport 像素）。
@export_range(0.0, 80.0, 0.5) var glow_radius := 24.0
## 外发光强度。
@export_range(0.0, 8.0, 0.1) var glow_intensity := 2.0

@onready var viewport: SubViewport = $ItemViewport
@onready var sprite: Sprite2D = $ItemViewport/Sprite2D
@onready var billboard: MeshInstance3D = $Billboard
@onready var glow_overlay: MeshInstance3D = $GlowOverlay

var _glow_mat: ShaderMaterial
var _glow_amount := 0.0          # 当前发光强度（平滑淡入淡出）
var _hovered := false            # 鼠标是否悬停在物品上
var _selected_glow := false      # 选中态是否要求常亮发光
var _cam_cache: Camera3D         # 相机引用缓存（避免每帧多次 get_camera_3d）
var _hover_frame := 0            # 悬停检测节流计数（每 4 帧检测一次）


func _ready() -> void:
	super._ready()
	if not interaction_enabled:
		remove_from_group("interactable")
		var pa := get_node_or_null("PickArea")
		if pa:
			pa.queue_free()
	_setup_sprite()
	_setup_body_material()
	_setup_glow()
	_setup_projected_shadow()


func _process(delta: float) -> void:
	_update_billboard()
	_update_hover()
	_update_glow(delta)


## 把 2D 立绘放进 SubViewport（居中 + 缩放 + 偏移），让渲染结果贴到 billboard。
func _setup_sprite() -> void:
	if item_texture:
		sprite.texture = item_texture
	sprite.scale = Vector2(sprite_scale, sprite_scale)
	sprite.position = viewport.size * 0.5 + sprite_offset
	sprite.centered = true


## 把 2D 视口渲染结果贴到 3D 立牌本体上（正常深度测试，被遮挡即隐藏）。
## 与 HD2DCharacter._setup_body_material 保持一致：StandardMaterial3D + UNSHADED + ALPHA。
## （若要受光梯度明暗，可换成 scripts/shaders/sprite_lighting.gdshader，此处保持与角色一致。）
func _setup_body_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var qm := QuadMesh.new()
	qm.size = display_size
	billboard.mesh = qm
	billboard.material_override = mat
	billboard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 发光层：用 glow（outline）着色器铺在发光层 quad 上，depth_test_disabled 使其始终可见（穿透遮挡）。
func _setup_glow() -> void:
	var qm := QuadMesh.new()
	qm.size = display_size
	glow_overlay.mesh = qm
	glow_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


## 投影阴影：按立绘 alpha 裁剪的隐形板（SHADOWS_ONLY）投射真实阴影，交给 Godot 阴影贴图。
func _setup_projected_shadow() -> void:
	if not shadow_enabled:
		return
	var size := display_size * billboard_scale
	var shadow := ProjectedShadow.new()
	shadow.name = "ProjectedShadow"
	add_child(shadow)
	shadow.setup(viewport.get_texture(), size)


## 立牌水平朝向始终跟随相机（面对镜头），但竖直方向向镜头的倾斜限制在 max_tilt_deg 内。
## 同时更新本体与发光层（两者重叠、同朝向）。
func _update_billboard() -> void:
	var cam := _get_cam()
	if cam == null:
		return
	var origin := global_position
	# 相机水平右向（立牌右），保持与角色立牌一致的水平朝向
	var right := Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z)
	if right.length() < 0.001:
		right = Vector3(1.0, 0.0, 0.0)
	right = right.normalized()
	# 相机指向立牌的水平方向 + 仰角，用于计算立牌上方向的有限倾斜
	var to_cam := cam.global_position - origin
	var horiz := Vector3(to_cam.x, 0.0, to_cam.z)
	var horiz_len := horiz.length()
	var elev := atan2(to_cam.y, horiz_len)  # 相机相对立牌的仰角（近似等于相机俯仰角）
	# 低视角保持竖直，镜头抬高后逐渐向后仰，到相机最高俯仰角时达到 max_tilt_deg。
	# 映射区间直接取自 RpgCamera 的 min_pitch/max_pitch，自动跟随相机配置。
	var zero_deg := 12.0
	var full_deg := 45.0
	if cam is RpgCamera:
		zero_deg = (cam as RpgCamera).min_pitch
		full_deg = (cam as RpgCamera).max_pitch
	var t := clampf(inverse_lerp(zero_deg, full_deg, rad_to_deg(elev)), 0.0, 1.0)
	var tilt := deg_to_rad(lerpf(0.0, max_tilt_deg, t))
	var up := Vector3.UP
	if horiz_len > 0.001:
		var toward := horiz / horiz_len
		up = (Vector3.UP * cos(tilt) - toward * sin(tilt)).normalized()
	var s := billboard_scale
	var basis := Basis(right, up, right.cross(up).normalized()).scaled(Vector3(s, s, s))
	billboard.global_basis = basis
	billboard.global_position = origin + up * anchor_height * s
	glow_overlay.global_basis = basis
	glow_overlay.global_position = origin + up * anchor_height * s


## 获取当前相机（缓存引用，避免每帧多次 get_camera_3d()）。
func _get_cam() -> Camera3D:
	if _cam_cache == null or not is_instance_valid(_cam_cache):
		_cam_cache = get_viewport().get_camera_3d()
	return _cam_cache


## 鼠标悬停检测：从相机发射拾取射线，命中 Interactable 的 PickArea（layer 4）即悬停。
## 每 4 帧检测一次（射线开销减 75%）。
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
	query.collision_mask = 4  # Interactable 的 PickArea 在 layer 4（拾取专用）
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_hovered = false
		return
	_hovered = is_ancestor_of(hit.get("collider") as Node)


## 平滑驱动发光强度：悬停且总开关开启，或处于选中态 → 淡入；否则淡出。
func _update_glow(delta: float) -> void:
	var target := 1.0 if ((_hovered and glow_enabled) or _selected_glow) else 0.0
	_glow_amount = move_toward(_glow_amount, target, delta * 8.0)
	if _glow_mat:
		_glow_mat.set_shader_parameter("glow_amount", _glow_amount)


## 重写选中高亮：立牌本体是 unshaded 着色器 billboard，emission 不生效，
## 故改用外发光层（glow overlay）表达选中态，与悬停发光共用同一管线。
func _apply_highlight(on: bool) -> void:
	_selected_glow = on


## 查询鼠标是否正悬停在物品上。
func is_hovered() -> bool:
	return _hovered
