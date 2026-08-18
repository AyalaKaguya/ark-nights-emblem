class_name ProjectedShadow
extends MeshInstance3D
## 投影阴影：把角色立绘（SubViewport 输出的含 alpha 纹理）沿阴影方向压扁、铺在脚底地面，
## 得到与角色轮廓一致的“投影”阴影（区别于圆形晕影）。父节点 origin 即脚底。
##
## 用法：
##   var shadow := ProjectedShadow.new()
##   add_child(shadow)
##   shadow.setup(viewport.get_texture(), Vector2(2.4, 2.4))  # 纹理 + 立牌尺寸（宽、高，米）
##   shadow.set_squash(0.5)                                    # 阴影长度 = 立牌高度 × squash

@export var shadow_color := Color(0.0, 0.0, 0.0, 0.5)   # 阴影颜色（RGBA）
@export var squash := 0.5                                # 阴影长度 = 立牌高度 × squash
@export var ground_offset := 0.015                       # 贴地微调，避免与地形/指示环 z-fighting
@export var shadow_dir := Vector3(0.5, 0.0, -0.5)        # 阴影延伸的水平方向（自动归一化）

var _mat: ShaderMaterial
var _tex: Texture2D
var _billboard_size := Vector2(2.4, 2.4)   # 立牌尺寸（宽、高，米）


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 阴影自身不参与 3D 投影
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://scripts/shaders/projected_shadow.gdshader")
	_mat.render_priority = -10         # 先于角色立牌/发光层等半透明绘制，避免排序抖动
	material_override = _mat
	_rebuild()


## 绑定角色立绘纹理与立牌尺寸（宽、高，米）。
func setup(tex: Texture2D, billboard_size: Vector2) -> void:
	_tex = tex
	_billboard_size = billboard_size
	if _mat:
		_rebuild()


## 重算方向、底片尺寸与位置（squash / shadow_dir / 立牌尺寸变化时调用）。
## 底片局部：X 轴=宽度(perp)，Y 轴=长度(shadow_dir)，Z 轴=上；UV.y=0 是局部 -Y（脚底）。
func _rebuild() -> void:
	var d := Vector3(shadow_dir.x, 0.0, shadow_dir.z)
	if d.length() < 0.001:
		d = Vector3(0.5, 0.0, -0.5)
	d = d.normalized()
	shadow_dir = d
	var p := Vector3(-d.z, 0.0, d.x)   # 与 d 垂直的水平单位向量
	var length := _billboard_size.y * maxf(squash, 0.01)
	var qm := QuadMesh.new()
	qm.size = Vector2(_billboard_size.x, length)
	mesh = qm
	# 底片法线朝上（平躺），宽度沿 p、长度沿 d；脚底（局部 -Y）对准父节点 origin。
	basis = Basis(p, d, p.cross(d))
	position = d * (length * 0.5) + Vector3.UP * ground_offset
	_apply_params()


func _apply_params() -> void:
	if _mat == null:
		return
	if _tex:
		_mat.set_shader_parameter("albedo_tex", _tex)
	_mat.set_shader_parameter("shadow_color", shadow_color)


## 设置压扁系数（阴影长度 / 立牌高度）。
func set_squash(s: float) -> void:
	squash = clampf(s, 0.0, 1.0)
	_rebuild()


## 设置阴影颜色与不透明度。
func set_shadow_color(c: Color) -> void:
	shadow_color = c
	_apply_params()
