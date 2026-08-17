class_name OcclusionShatter
extends Node3D
## 遮挡破碎虚化：检测相机与目标之间的遮挡物，用破碎虚化 shader 让其“看穿”。
##
## 用法：把本节点挂到 Camera3D 下（子节点），并把需要“保持可见”的目标
## （物品 / 角色 / 实体）加入 `target_group`。测试时把场上的角色加入该 group 即可。
##
## 特性：
## - 球体 + 喇叭口：以角色为中心的球体（半径 `radius`），从球体朝向镜头张开一个
##   锥形“喇叭口”；喇叭口内命中中间遮挡物即虚化，不计算具体遮挡形状。
## - 仅视觉层：shader 只溶解片元、不写深度，不参与碰撞/交互、不改变光影计算。
## - 淡入淡出：遮挡出现/消失时 amount/fade 平滑过渡，遮挡物材质在恢复后自动还原。

const SHATTER_SHADER := preload("res://scripts/shaders/occlusion_shatter.gdshader")
const _center_height := 1.2  # 球心高度（角色身体中部）

@export var target_group := "occlusion_target"  # 需要保持可见的目标组
@export_range(0.1, 20.0) var radius := 1.2      # 角色周围球体半径（米），向镜头张开喇叭口
@export_range(0.0, 5.0) var core_radius := 0.8  # 完全透明的洞半径（主轴周围）
@export_range(0.1, 20.0) var falloff := 1.0     # 洞边缘平滑过渡带宽度
@export_range(0.1, 60.0) var fade_speed := 8.0  # 虚化淡入淡出速度
@export var wall_group := "occlusion_wall"      # 墙体组：破碎溶解（洞型看穿）
@export var ground_group := "ground"            # 地面组，永不虚化
@export var ignore_group := ""                  # 额外忽略组

var _camera: Camera3D
var _fades := {}        # MeshInstance3D -> float（当前虚化度 0~1）
var _infos := {}        # MeshInstance3D -> Dictionary（kind/origin/dir 虚化信息）
var _originals := {}    # MeshInstance3D -> Material（原始 material_override，恢复用）
var _shadow_dupes := {} # MeshInstance3D -> MeshInstance3D（只投阴影副本，保证看穿后阴影完整）
var _shadow_states := {} # MeshInstance3D -> int（原始 cast_shadow 设置，恢复用）
var _last_active := {}  # 上一次扫描结果（隔帧复用）
var _scan_counter := 0  # 扫描节流计数


func _ready() -> void:
	_camera = get_parent() as Camera3D
	if _camera == null:
		push_warning("OcclusionShatter 应作为 Camera3D 的子节点挂载")
		set_process(false)


func _process(delta: float) -> void:
	# 每 3 帧扫描一次物理射线（淡入淡出由 fade 动画平滑，中间帧复用上次结果）
	_scan_counter += 1
	var active := _last_active
	if _scan_counter % 3 == 1:
		active = _collect_active_meshes()
		_last_active = active
	_update_fades(active, delta)


## 收集当前应虚化的所有网格：对每个目标做视线射线检测
func _collect_active_meshes() -> Dictionary:
	var result := {}
	var space := get_world_3d().direct_space_state
	for target in get_tree().get_nodes_in_group(target_group):
		if target is Node3D:
			_collect_for_target(space, target as Node3D, result)
	return result


## 相机 → 目标身体多个采样点的视线射线：命中墙体（wall_group）→ 收集其网格打洞看穿。
## 非墙体模型不参与处理（保持原样）。
func _collect_for_target(space: PhysicsDirectSpaceState3D, target: Node3D, result: Dictionary) -> void:
	var cam_pos := _camera.global_position
	var excludes: Array[RID] = []
	_collect_target_rids(target, excludes)
	var points := _sample_points(target)
	var hits := {}  # MeshInstance3D -> true
	for point in points:
		var query := PhysicsRayQueryParameters3D.create(cam_pos, point)
		query.exclude = excludes
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider := hit.get("collider") as Node
		if not (collider is Node3D):
			continue
		if _in_group_recursive(collider, ground_group):
			continue
		if ignore_group != "" and _in_group_recursive(collider, ignore_group):
			continue
		if target.is_ancestor_of(collider):
			continue  # 排除目标自身（及其碰撞箱/网格）
		if not _in_group_recursive(collider, wall_group):
			continue  # 非墙体模型不参与
		var mesh := _find_mesh_instance(collider)
		if mesh != null:
			hits[mesh] = true
	if hits.is_empty():
		return
	var center := _target_center(target)
	var dir := _camera.global_position - center
	if dir.length() > 0.001:
		dir = dir.normalized()
	for mesh in hits:
		result[mesh] = {
			"origin": center,
			"dir": dir,
		}


## 检查节点自身或任意祖先是否在指定组中（碰撞体组常标在父/子节点上）
func _in_group_recursive(node: Node, group: String) -> bool:
	var cur: Node = node
	while cur != null:
		if cur.is_in_group(group):
			return true
		cur = cur.get_parent()
	return false


## 角色为中心的球体 → 朝向镜头的喇叭口采样。
## 从相机向球体截面圆盘（球心 + 内/外圈）发射射线，射线束形成锥形喇叭口。
func _sample_points(target: Node3D) -> Array[Vector3]:
	var center := _target_center(target)
	var points: Array[Vector3] = [center]                    # 主轴射线
	var dir := (_camera.global_position - center).normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.999:
		up = Vector3.FORWARD  # 相机几乎正上/正下时退避，避免 looking_at 退化
	var cam_basis := Basis.looking_at(dir, up)               # 截面圆盘垂直于视线
	for ring in [1.0, 0.5]:   # 外圈 + 内圈，构成喇叭口截面
		for i in 8:            # 方位角 8 等分
			var a := TAU * i / 8.0
			var off := cam_basis * Vector3(cos(a) * radius * ring, sin(a) * radius * ring, 0.0)
			points.append(center + off)
	return points


## 角色球心（身体中部，喇叭口起点）
func _target_center(target: Node3D) -> Vector3:
	return target.global_position + Vector3.UP * _center_height


## 收集目标子树的所有碰撞体 RID，用于射线排除（避免射线命中目标自身）
func _collect_target_rids(node: Node, rids: Array[RID]) -> void:
	if node is CollisionObject3D:
		var rid := (node as CollisionObject3D).get_rid()
		if rid.is_valid():
			rids.append(rid)
	for child in node.get_children():
		_collect_target_rids(child, rids)


## 让遮挡物 fade 逼近目标值（1=应虚化，0=已离开），归零时还原材质。
## keys() 返回快照数组，迭代中直接 erase 字典项是安全的。
func _update_fades(active: Dictionary, delta: float) -> void:
	for mesh in active.keys():
		_infos[mesh] = active[mesh]  # 虚化信息以最新为准（kind/轴可能切换）
		_fades[mesh] = _fades.get(mesh, 0.0)
	for mesh in _fades.keys():
		_sync_shadow_dupe(mesh)  # 若墙移动，副本跟随
		var t := move_toward(_fades[mesh], 1.0 if active.has(mesh) else 0.0, fade_speed * delta)
		if t <= 0.0:
			_clear_override(mesh)
			_fades.erase(mesh)
			_infos.erase(mesh)
		else:
			_fades[mesh] = t
			_apply_override(mesh, t, _infos[mesh])


## 施加（或复用）墙体洞型看穿 shader：fade 淡入淡出，同时用只投阴影副本保住阴影。
func _apply_override(mesh: MeshInstance3D, t: float, info: Dictionary) -> void:
	var mat := mesh.material_override as ShaderMaterial
	if mat == null or mat.shader != SHATTER_SHADER:
		_ensure_shadow_dupe(mesh)  # 墙半透明会破坏阴影，需只投阴影副本
		if not _originals.has(mesh):
			_originals[mesh] = mesh.material_override
		var src := _source_material(mesh)
		var tex := _albedo_texture_of(src)
		mat = ShaderMaterial.new()
		mat.shader = SHATTER_SHADER
		mat.set_shader_parameter("albedo_color", _albedo_color_of(src))
		mat.set_shader_parameter("roughness", _roughness_of(src))
		mat.set_shader_parameter("metallic", _metallic_of(src))
		if tex != null:
			mat.set_shader_parameter("albedo_tex", tex)
		mesh.material_override = mat
	mat.set_shader_parameter("fade", t)
	mat.set_shader_parameter("axis_origin", info.get("origin", Vector3.ZERO))
	mat.set_shader_parameter("axis_dir", info.get("dir", Vector3.FORWARD))
	mat.set_shader_parameter("core_radius", core_radius)
	mat.set_shader_parameter("falloff", falloff)


## 移除虚化，恢复遮挡物原始材质和阴影投射
func _clear_override(mesh: MeshInstance3D) -> void:
	_clear_shadow_dupe(mesh)
	if _originals.has(mesh):
		mesh.material_override = _originals[mesh]
		_originals.erase(mesh)
	else:
		mesh.material_override = null


## 创建只投阴影的副本（用原始不透明材质），保证看穿后墙的阴影完整不受影响。
## 原 mesh 关闭阴影投射，阴影完全由副本负责 → 阴影与看穿 alpha 无关。
func _ensure_shadow_dupe(mesh: MeshInstance3D) -> void:
	if _shadow_dupes.has(mesh):
		return
	_shadow_states[mesh] = mesh.cast_shadow
	var dupe := MeshInstance3D.new()
	dupe.name = mesh.name + "_ShadowOnly"
	dupe.mesh = mesh.mesh
	dupe.material_override = _source_material(mesh)  # 原始不透明材质
	dupe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	mesh.get_parent().add_child(dupe)
	dupe.global_transform = mesh.global_transform
	_shadow_dupes[mesh] = dupe
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 同步副本 transform（若遮挡物移动）
func _sync_shadow_dupe(mesh: MeshInstance3D) -> void:
	if _shadow_dupes.has(mesh):
		var dupe: MeshInstance3D = _shadow_dupes[mesh]
		if is_instance_valid(dupe):
			dupe.global_transform = mesh.global_transform


## 移除只投阴影的副本，恢复原 mesh 的阴影设置
func _clear_shadow_dupe(mesh: MeshInstance3D) -> void:
	if _shadow_dupes.has(mesh):
		var dupe: MeshInstance3D = _shadow_dupes[mesh]
		_shadow_dupes.erase(mesh)
		if is_instance_valid(dupe):
			dupe.queue_free()
	if _shadow_states.has(mesh):
		mesh.cast_shadow = _shadow_states[mesh]
		_shadow_states.erase(mesh)


## 遮挡物当前实际渲染用的材质（优先 material_override，其次 mesh 表面材质）
func _source_material(mesh: MeshInstance3D) -> Material:
	if mesh.material_override != null:
		return mesh.material_override
	if mesh.mesh != null and mesh.mesh.material != null:
		return mesh.mesh.material
	return null


func _albedo_color_of(mat: Material) -> Color:
	if mat is StandardMaterial3D:
		return mat.albedo_color
	if mat is ShaderMaterial:
		var c: Variant = mat.get_shader_parameter("albedo_color")
		if c is Color:
			return c
	return Color.WHITE


func _albedo_texture_of(mat: Material) -> Texture2D:
	if mat is StandardMaterial3D:
		return mat.albedo_texture
	if mat is ShaderMaterial:
		var tex: Variant = mat.get_shader_parameter("albedo_tex")
		if tex is Texture2D:
			return tex
	return null


## 继承原材质粗糙度（保持光照一致，避免虚化后色彩变化）
func _roughness_of(mat: Material) -> float:
	if mat is StandardMaterial3D:
		return mat.roughness
	return 1.0


## 继承原材质金属度（保持光照一致，避免虚化后色彩变化）
func _metallic_of(mat: Material) -> float:
	if mat is StandardMaterial3D:
		return mat.metallic
	return 0.0


## 从碰撞体节点向上/向下寻找可渲染的 MeshInstance3D
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	var found := _find_mesh_in_subtree(node)
	if found != null:
		return found
	var parent := node.get_parent()
	if parent != null and parent != self:
		return _find_mesh_in_subtree(parent)
	return null


func _find_mesh_in_subtree(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var m := _find_mesh_in_subtree(child)
		if m != null:
			return m
	return null
