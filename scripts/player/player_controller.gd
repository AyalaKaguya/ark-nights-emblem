class_name PlayerController
extends Node
## 玩家控制器：左键选中可交互对象（发光常亮）、右键寻路移动、F1 切换所有角色状态面板。
##
## 挂到主场景，引用角色与导航区域。

const CharacterState := preload("res://scripts/character/character_state.gd")
const HD2DCharacter := preload("res://scripts/character/hd2d_character.gd")
const CollisionRids := preload("res://scripts/util/collision_rids.gd")

@export var character_path: NodePath          # 手动控制的 HD2DCharacter 角色节点
@export var navigation_region_path: NodePath  # NavigationRegion3D 导航区域
## 导航地面半宽（米，地面为 nav_half_extent*2 的方形）。
@export var nav_half_extent := 12.0
## 导航网格 cell 尺寸（米，越小越精细，墙边保留的通道越贴近墙壁）。
@export var nav_cell_size := 0.5
## 障碍物边距（米，角色绕行时与障碍物的安全距离；越小路径越贴墙）。
@export var nav_margin := 0.2
## 导航 agent 半径（米）。
@export var nav_agent_radius := 0.4
## 寻路点最大坡度（度）：只接受法线与竖直方向夹角不超过该值的表面（上表面/平地面），
## 点击墙面等陡峭表面时忽略，避免把目标设到墙壁上。
@export_range(0.0, 89.0, 1.0, "degrees") var max_nav_slope_deg := 45.0
## 寻路障碍物分组（专用于寻路，与遮挡虚化的 occlusion_wall 无关）。
@export var nav_obstacle_group := "nav_obstacle"

var _character: HD2DCharacter = null
var _navigation_region: NavigationRegion3D
var _selected: Node3D = null
var _path_line: MeshInstance3D
var _path_target: MeshInstance3D
var _has_path := false
var _path_height := 0.06


func _ready() -> void:
	_character = get_node_or_null(character_path) as HD2DCharacter
	_navigation_region = get_node_or_null(navigation_region_path) as NavigationRegion3D
	_setup_path_visual()
	# 延迟到场景就绪后构建导航网格（烘焙在 headless 下不可用，改用手动 cell 网格）
	call_deferred("_build_navigation")


func _process(_delta: float) -> void:
	_update_path_visual()


## 创建导航路径可视化：路径线（LINE_STRIP）+ 落点标记（平放圆环）。
func _setup_path_visual() -> void:
	var mat := _make_path_material()
	_path_line = MeshInstance3D.new()
	_path_line.name = "PathLine"
	_path_line.material_override = mat
	add_child(_path_line)
	_path_line.visible = false
	_path_target = MeshInstance3D.new()
	_path_target.name = "PathTarget"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.30
	torus.outer_radius = 0.40
	_path_target.mesh = torus
	_path_target.material_override = mat
	add_child(_path_target)
	_path_target.visible = false


func _make_path_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.2, 1.0, 0.9, 0.85)
	m.emission_enabled = true
	m.emission = Color(0.2, 1.0, 0.9)
	m.emission_energy_multiplier = 1.5
	m.disable_receive_shadows = true
	return m


## 显示路径线与落点标记。
func _show_path(points: PackedVector3Array, target: Vector3) -> void:
	_draw_path_line(points)
	_path_target.global_position = target + Vector3.UP * _path_height
	_path_target.visible = true
	_has_path = true


## 每帧：角色不再移动（到达/中断）时隐藏路径可视化。
func _update_path_visual() -> void:
	if not _has_path:
		return
	var moving: bool = _character != null \
		and _character.get_state() == CharacterState.Id.MOVE
	if not moving:
		_hide_path()


func _hide_path() -> void:
	_has_path = false
	if _path_line:
		_path_line.visible = false
	if _path_target:
		_path_target.visible = false


## 用 LINE_STRIP 重建路径折线（抬升避免与地面 z-fighting）。
func _draw_path_line(points: PackedVector3Array) -> void:
	if points.size() < 2:
		_path_line.visible = false
		return
	var verts := PackedVector3Array()
	for p in points:
		verts.append(p + Vector3.UP * _path_height)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	_path_line.mesh = mesh
	_path_line.visible = true


## 手动构建导航网格：把地面划分为 cell，障碍物（nav_obstacle 组）占据的 cell 跳过。
func _build_navigation() -> void:
	if _navigation_region == null:
		return
	var nm: NavigationMesh = _navigation_region.navigation_mesh
	if nm == null:
		nm = NavigationMesh.new()
		_navigation_region.navigation_mesh = nm
	nm.clear()
	nm.agent_radius = nav_agent_radius
	nm.cell_size = nav_cell_size
	var obstacles := _collect_obstacle_rects()
	var verts := PackedVector3Array()
	var polys: Array[PackedInt32Array] = []
	var n := int(nav_half_extent * 2.0 / nav_cell_size)
	for ix in range(n):
		for iz in range(n):
			var x0 := -nav_half_extent + ix * nav_cell_size
			var z0 := -nav_half_extent + iz * nav_cell_size
			var rect := Rect2(x0, z0, nav_cell_size, nav_cell_size)
			var blocked := false
			for o in obstacles:
				if o.grow(nav_margin).intersects(rect):
					blocked = true
					break
			if blocked:
				continue
			var base := verts.size()
			verts.append(Vector3(x0, 0.0, z0))
			verts.append(Vector3(x0, 0.0, z0 + nav_cell_size))
			verts.append(Vector3(x0 + nav_cell_size, 0.0, z0 + nav_cell_size))
			verts.append(Vector3(x0 + nav_cell_size, 0.0, z0))
			polys.append(PackedInt32Array([base, base + 1, base + 2, base + 3]))
	nm.set_vertices(verts)
	for p in polys:
		nm.add_polygon(p)
	nm.emit_changed()
	_navigation_region.set_navigation_mesh(nm)


## 从寻路障碍分组（nav_obstacle）收集障碍物的 XZ 平面 AABB。
func _collect_obstacle_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for node in get_tree().get_nodes_in_group(nav_obstacle_group):
		if node is Node3D:
			var rect := _node_aabb_xz(node as Node3D)
			if rect.size.x > 0.01 and rect.size.y > 0.01:
				result.append(rect)
	return result


## 计算节点（含其子 CollisionShape3D BoxShape）在 XZ 平面的包围矩形。
func _node_aabb_xz(node: Node3D) -> Rect2:
	var center := node.global_position
	var half_ext := Vector2(0.5, 0.5)
	for child in node.get_children():
		if child is CollisionShape3D:
			var shape := (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				var s := (shape as BoxShape3D).size
				half_ext = Vector2(s.x * 0.5, s.z * 0.5)
	return Rect2(center.x - half_ext.x, center.z - half_ext.y, half_ext.x * 2.0, half_ext.y * 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_try_select()
			MOUSE_BUTTON_RIGHT:
				_try_navigate()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_toggle_status_panels()


## 鼠标射线检测：mask 为碰撞层掩码，areas 控制检测 Area 还是 Body。
func _raycast(mask: int, areas: bool, exclude_wall: bool = false) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var vp := get_viewport()
	var mouse := vp.get_mouse_position()
	if not Rect2(Vector2.ZERO, vp.get_visible_rect().size).has_point(mouse):
		return {}
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	query.collide_with_areas = areas
	query.collide_with_bodies = not areas
	if exclude_wall:
		query.exclude = CollisionRids.collect_group_rids(get_tree(), "occlusion_wall")
	return get_viewport().get_world_3d().direct_space_state.intersect_ray(query)


## 左键：命中可交互对象拾取体 → 选中；否则取消选中。
func _try_select() -> void:
	var hit := _raycast(4, true)  # layer 3（可交互拾取 Area3D）
	if hit.is_empty():
		_set_selected(null)
		return
	var collider := hit.get("collider") as Node
	_set_selected(_find_interactable(collider))


## 沿祖先链找 interactable 组节点。
func _find_interactable(node: Node) -> Node3D:
	var n := node
	while n != null:
		if n.is_in_group("interactable"):
			return n as Node3D
		n = n.get_parent()
	return null


## 切换当前选中对象，并同步其发光状态。
func _set_selected(obj: Node3D) -> void:
	if _selected == obj:
		return
	if _selected != null and _selected.has_method("set_selected"):
		_selected.set_selected(false)
	_selected = obj
	if _selected != null and _selected.has_method("set_selected"):
		_selected.set_selected(true)


## 右键：命中地面则寻路移动过去（射线穿透 occlusion_wall 选点）。
## 只接受法线接近竖直的表面（上表面/平地面），墙面等陡坡点击被忽略。
func _try_navigate() -> void:
	if _character == null:
		return
	var hit := _raycast(1, false, true)  # layer 1，穿透 occlusion_wall 选地面
	if hit.is_empty():
		return
	# 斜率限制：normal.y = cos(坡度角)，低于阈值说明命中墙面/陡坡 → 忽略
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if normal.y < cos(deg_to_rad(max_nav_slope_deg)):
		return
	var point: Vector3 = hit.get("position")
	_navigate_to(point)


## 通过导航网格寻路；无导航或路径失败则直线移动兜底。成功后显示路径可视化。
func _navigate_to(point: Vector3) -> void:
	if _navigation_region == null:
		_character.move_to(point)
		_show_path(PackedVector3Array([_character.global_position, point]), point)
		return
	var map: RID = _navigation_region.get_navigation_map()
	var from := NavigationServer3D.map_get_closest_point(map, _character.global_position)
	var to := NavigationServer3D.map_get_closest_point(map, point)
	var path := NavigationServer3D.map_get_path(map, from, to, true, 1)
	if path.is_empty():
		_character.move_to(point)
		_show_path(PackedVector3Array([from, to]), point)
	else:
		# 与角色内部 move_along_path 相同的 Chaikin 细分，保证可视化线路与轨迹一致
		var smooth := HD2DCharacter.smooth_path(path)
		_character.move_along_path(smooth)
		_show_path(smooth, point)


## 当前选中对象（供查询）。
func get_selected() -> Node3D:
	return _selected


## 切换所有角色的侧面状态面板显隐（F1）。
func _toggle_status_panels() -> void:
	for node in get_tree().get_nodes_in_group("character"):
		if node.has_method("toggle_status_panel"):
			node.toggle_status_panel()
