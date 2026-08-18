class_name InteractableBeacon
extends Interactable
## 示例可交互对象：交互后在两种颜色间切换（演示交互逻辑）。

@export var active_color := Color(1.0, 0.85, 0.3, 1.0)
@export var idle_color := Color(0.4, 0.45, 0.55, 1.0)

var _active := false


func _on_interact(_character: Node3D) -> void:
	_active = not _active
	var mesh := find_mesh()
	if mesh:
		var mat: StandardMaterial3D = mesh.material_override
		if mat == null:
			mat = StandardMaterial3D.new()
			mesh.material_override = mat
		if _active:
			mat.albedo_color = active_color
		else:
			mat.albedo_color = idle_color
