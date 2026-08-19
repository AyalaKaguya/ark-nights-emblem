class_name ProjectedShadow
extends MeshInstance3D
## 投影阴影：一块"只投射阴影、不渲染到主画面"的隐形立牌板，按角色立绘的 alpha 轮廓裁剪，
## 交给 Godot 原生阴影贴图（shadow map）投射出与角色轮廓一致的真实阴影。
##
## 由引擎阴影系统处理，天然正确：会投射到地面/墙体/家具等任意接收阴影的几何（爬上墙）、
## 墙背面（光照不到处）无阴影、与其它阴影是并集（重叠不变深）。
##
## 板始终面向主光（法线 = 指向光源），形状随立绘 alpha 逐帧更新。父节点 origin 即脚底。
## 阴影软硬/暗度由 DirectionalLight3D.shadow_blur 与 WorldEnvironment 环境光决定。

var _tex: Texture2D
var _billboard_size := Vector2(2.4, 2.4)   # 立牌尺寸（宽、高，米）
var _last_light_dir := Vector3.UP


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY  # 只投阴影，不可见

	# 阴影板材质：alpha 裁剪（按立绘 alpha），阴影贴图按此裁剪出角色轮廓
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # 双面，避免板背对光源时阴影消失
	mat.disable_receive_shadows = true
	material_override = mat

	var qm := QuadMesh.new()
	qm.size = Vector2(_billboard_size.x, _billboard_size.y)
	mesh = qm

	_update_from_light()


func _process(_delta: float) -> void:
	_update_from_light()


## 绑定角色立绘纹理与立牌尺寸（宽、高，米）。
func setup(tex: Texture2D, billboard_size: Vector2) -> void:
	_tex = tex
	_billboard_size = billboard_size
	var m := material_override as StandardMaterial3D
	if m:
		m.albedo_texture = tex
	var qm := mesh as QuadMesh
	if qm:
		qm.size = Vector2(billboard_size.x, billboard_size.y)
	_update_from_light()


## 每帧读取主光；仅当光源方向变化时重算板的朝向/位置。
func _update_from_light() -> void:
	LightConfig.sample()
	var to_light := LightConfig.light_direction
	if to_light.is_equal_approx(_last_light_dir):
		return
	_last_light_dir = to_light
	_apply_light(to_light)


## 把板面向主光，并让板的"高"方向随光倾斜（从光源看仍呈角色轮廓）。
func _apply_light(to_light: Vector3) -> void:
	var ly := clampf(to_light.y, 0.0, 1.0)   # sin(仰角)
	var hx := -to_light.x
	var hz := -to_light.z
	var k := sqrt(hx * hx + hz * hz)          # cos(仰角)
	var S: Vector3
	if k < 0.0001:
		S = Vector3(0.0, 0.0, -1.0)           # 光近垂直：随便取一个水平方向兜底
		k = 0.0001
	else:
		S = Vector3(hx / k, 0.0, hz / k)      # 背离光源的水平方向
	var P := Vector3(-S.z, 0.0, S.x)          # 水平垂直（宽方向）
	# 高方向取“朝上偏”（to_light×P）：QuadMesh 的 V 是翻转的（V=0 在 +Y），取反让立绘头顶朝上。
	var Y := to_light.cross(P)
	var H := _billboard_size.y
	# 板局部：X=宽(U)，Y=高(V)，Z=法线（指向光源）
	basis = Basis(P, Y, to_light)
	# 板中心对齐角色竖直中点（= up * H/2 = ly*H/2*to_light + k*H/2*Y）
	position = to_light * (ly * H * 0.5) + Y * (k * H * 0.5)
