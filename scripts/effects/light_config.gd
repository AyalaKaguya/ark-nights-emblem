extends Node
## 场景主光参数中心（autoload 单例 LightConfig）。
## HD-2D 立牌与投影阴影不参与真实 3D 光照，需要每帧读取主 DirectionalLight3D 的方向
## 与仰角，让投影阴影跟随太阳方向与高度、立牌明暗与场景一致。
##
## 不声明 class_name：autoload 注册时 project.godot 已生成同名全局单例，脚本再声明会触发
## "Class hides an autoload singleton" 解析错误。
## 用法：LightConfig.sample(); var d := LightConfig.light_direction; var e := LightConfig.light_elevation

var light_color := Color(1.0, 0.98, 0.92)
var light_energy := 1.0
## 指向光源的世界方向（归一化）。DirectionalLight3D 沿本地 -Z 照射，故光源在 +Z 方向。
var light_direction := Vector3.UP
## 光源仰角（弧度）：0=地平线，PI/2=正上方。用于计算投影阴影长度。
var light_elevation := PI * 0.25

var _light: DirectionalLight3D
var _resolved := false


func _ready() -> void:
	_resolve()


## 找到主光并读取其参数。按 group "main_light" 检索；找不到则保持默认暖白光 + 斜上方。
func _resolve() -> void:
	_resolved = true
	if _light != null and is_instance_valid(_light):
		_read(_light)
		return
	_light = null
	if get_tree() == null:
		return
	for n in get_tree().get_nodes_in_group("main_light"):
		if n is DirectionalLight3D:
			_light = n
			_read(n)
			return


func _read(l: DirectionalLight3D) -> void:
	light_color = l.light_color
	light_energy = l.light_energy
	# DirectionalLight3D 沿本地 -Z 照射，指向光源的方向是 +Z（global_basis.z）。
	var to_light := l.global_basis.z.normalized()
	light_direction = to_light
	light_elevation = asin(clampf(to_light.y, -1.0, 1.0))


## 供立牌/阴影每帧调用：确保已解析；光存在则刷新（运行时可能被替换/移除），
## 光失效时尝试重新解析一次。
func sample() -> void:
	if not _resolved:
		_resolve()
		return
	if _light != null and is_instance_valid(_light):
		_read(_light)
	else:
		_resolved = false
		_resolve()
