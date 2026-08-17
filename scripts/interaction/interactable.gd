class_name Interactable
extends Node3D
## 可交互对象基类：加入 interactable 组，角色可走到旁边触发 interact()。
## 支持被「选中」：选中后发光常亮（emission + 场景 glow），配合 PlayerController 使用。
##
## 子类重写 _on_interact() 实现具体交互逻辑。

## 交互触发信号（参数为触发交互的角色）
signal interacted(character: Node3D)
## 选中状态改变信号
signal selection_changed(selected: bool)

## 交互提示文本（供 UI 或调试显示）
@export var prompt_text := "交互"
## 选中高亮颜色
@export var highlight_color := Color(1.0, 0.84, 0.2, 1.0)
## 选中高亮发光强度（emission energy，配合场景 glow 产生光晕）
@export var highlight_energy := 4.0
## 拾取检测半径（自动创建的 Area3D 碰撞体）
@export var pick_radius := 0.6

var _selected := false
var _highlight_mat: StandardMaterial3D
var _prev_override: Material = null


func _ready() -> void:
	add_to_group("interactable")
	_ensure_pick_area()


## 执行交互：发出信号并调用子类钩子。
func interact(character: Node3D) -> void:
	interacted.emit(character)
	_on_interact(character)


## 子类重写：具体交互逻辑。
func _on_interact(_character: Node3D) -> void:
	pass


## 设置/取消选中（选中后发光常亮）。
func set_selected(on: bool) -> void:
	if _selected == on:
		return
	_selected = on
	_apply_highlight(on)
	selection_changed.emit(on)


## 是否处于选中状态。
func is_selected() -> bool:
	return _selected


## 查找第一个 MeshInstance3D 子节点（供子类做视觉反馈 / 高亮）。
func find_mesh() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D:
			return child
	return null


## 自动创建拾取碰撞体（Area3D，layer 3），供鼠标射线选中。
func _ensure_pick_area() -> void:
	if get_node_or_null("PickArea") != null:
		return
	var area := Area3D.new()
	area.name = "PickArea"
	area.collision_layer = 4   # layer 3（拾取专用）
	area.collision_mask = 0
	add_child(area)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = pick_radius
	shape.shape = sphere
	area.add_child(shape)


## 选中高亮：复制当前材质并增强 emission；取消时恢复原 material_override。
func _apply_highlight(on: bool) -> void:
	var mesh := find_mesh()
	if mesh == null:
		return
	if on:
		_prev_override = mesh.material_override
		if _highlight_mat == null:
			_highlight_mat = _build_highlight_material(mesh)
		mesh.material_override = _highlight_mat
	else:
		mesh.material_override = _prev_override
		_prev_override = null


## 基于当前生效材质构建高亮材质（保留原外观，仅加 emission 发光）。
func _build_highlight_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	var base: Material = mesh.material_override if mesh.material_override != null else mesh.mesh.material
	var mat: StandardMaterial3D
	if base is StandardMaterial3D:
		mat = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = highlight_color
	mat.emission_energy_multiplier = highlight_energy
	return mat
