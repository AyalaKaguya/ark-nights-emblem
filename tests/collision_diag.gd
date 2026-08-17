extends SceneTree
## 临时诊断：验证脚底指示器半径=碰撞胶囊半径 + 角色间碰撞滑动/推开/不穿透。
## 需渲染循环，用非 headless 运行：godot --path . --script res://tests/collision_diag.gd
## 结果写 res://tests/collision_out.txt

const HD2DCharacter := preload("res://scripts/character/hd2d_character.gd")

var _fails := 0
var _log := ""


func _check(cond: bool, label: String) -> void:
	if cond:
		_log += "PASS: " + label + "\n"
	else:
		_fails += 1
		_log += "FAIL: " + label + "\n"


func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) < eps


func _write_result() -> void:
	var f := FileAccess.open("res://tests/collision_out.txt", FileAccess.WRITE)
	if f:
		f.store_string(_log + "RESULT: " + ("ALL PASS" if _fails == 0 else "%d FAILS" % _fails))
		f.close()


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene: Node = load("res://node_3d.tscn").instantiate()
	root.add_child(scene)
	# 等几帧让 _ready / add_to_group 生效
	for _i in range(5):
		await process_frame
	# 停用 AI 漫游，避免干扰碰撞测试
	var ai := scene.get_node_or_null("AiController")
	if ai:
		ai.set_process(false)
	# 停用 PlayerController 的输入（无窗口输入，无碍）
	var chars := get_nodes_in_group("character")
	_log += "group 角色数量: %d\n" % chars.size()
	for c in chars:
		_log += "  角色: %s (parent=%s)\n" % [c.name, c.get_parent().name if c.get_parent() else "null"]
	_check(chars.size() == 2, "场景有 2 个角色")
	if chars.size() < 2:
		_write_result()
		quit(1)
		return
	var a: Node3D = chars[0] as Node3D
	var b: Node3D = chars[1] as Node3D

	# 1. 碰撞半径读取
	var ra: float = a._body_radius()
	var rb: float = b._body_radius()
	_check(_approx(ra, 0.35), "角色A 碰撞半径=0.35 (%.3f)" % ra)
	_check(_approx(rb, 0.35), "角色B 碰撞半径=0.35 (%.3f)" % rb)

	# 2. 指示器圆环半径 = 碰撞半径（圆环第一段顶点半径即 r_out；箭头尖端会超出）
	var mesh: ArrayMesh = a.get_node("DirectionIndicator").mesh
	var surf := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = surf[Mesh.ARRAY_VERTEX]
	var ring_r: float = Vector2(verts[0].x, verts[0].z).length()
	_check(_approx(ring_r, ra, 0.01), "指示器圆环半径=碰撞半径 (%.3f)" % ring_r)
	# 圆环所有顶点（前 64*6 个）半径都在 [r_in, r_out] 内
	var all_in_ring := true
	for i in range(64 * 6):
		var rr: float = Vector2(verts[i].x, verts[i].z).length()
		if rr > ra + 0.01:
			all_in_ring = false
	_check(all_in_ring, "圆环主体顶点半径均 ≤ 碰撞半径")

	# 3. 碰撞钳制纯函数
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(1, 0, 0)
	var mv: Vector3 = a._slide_around_characters(Vector3(0.5, 0, 0))
	_check(_approx(mv.x, 0.3, 0.001), "径向移动被钳到接触距离 0.3 (%.3f)" % mv.x)
	var mv2: Vector3 = a._slide_around_characters(Vector3(0, 0, 0.5))
	_check(_approx(mv2.z, 0.5, 0.001), "切向移动不受影响 (%.3f)" % mv2.z)
	# 重叠：A 在 (0.5,0,0)（重叠 0.2），移动后目标被钳到接触点 (0.3,0)
	a.global_position = Vector3(0.5, 0, 0)
	var mv3: Vector3 = a._slide_around_characters(Vector3(0.05, 0, 0))
	_check(_approx(mv3.x, -0.2, 0.001), "重叠目标被钳到接触点 (位移 -0.2) (%.3f)" % mv3.x)
	# 远离方向不受影响
	var mv4: Vector3 = a._slide_around_characters(Vector3(-0.5, 0, 0))
	_check(_approx(mv4.x, -0.5, 0.001), "远离方向不被限制 (%.3f)" % mv4.x)
	# 完全重合：沿移动方向推到接触距离（径向 0.7；切向分量来自绕行补偿）
	a.global_position = Vector3(1, 0, 0)
	b.global_position = Vector3(1, 0, 0)
	var mv5: Vector3 = a._slide_around_characters(Vector3(0.05, 0, 0))
	_check(_approx(mv5.x, 0.7, 0.001), "完全重合沿移动方向推到 0.7 (%.3f)" % mv5.x)

	# 接触时切向错开：A (0,0) 与 B (0.7,0) 恰好接触，A 前进会被 B 挡 → 应产生切向绕行
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(0.7, 0, 0)
	var mv6: Vector3 = a._slide_around_characters(Vector3(0.06, 0, 0))
	_check(absf(mv6.z) > 0.03, "恰好接触时产生切向绕行 (z=%.3f)" % mv6.z)
	_check(mv6.x <= 0.0, "恰好接触时不再径向推进 (x=%.3f)" % mv6.x)

	# 4. 端到端绕行：A 从 (-3,0,0) 走向 (3,0,0)，B 静止在 (1,0,0)，A 应自行绕过而非卡住
	a.global_position = Vector3(-3, 0, 0)
	b.global_position = Vector3(1, 0, 0)
	a.move_to(Vector3(3, 0, 0))
	var max_abs_z := 0.0
	var min_sep := 99.0
	for i in range(12):
		await create_timer(0.5).timeout
		var sep_i: float = Vector2(a.global_position.x - 1.0, a.global_position.z).length()
		max_abs_z = maxf(max_abs_z, absf(a.global_position.z))
		min_sep = minf(min_sep, sep_i)
		_log += "  t=%.1f A=(%.2f, %.2f) sep=%.3f\n" % [(i + 1) * 0.5, a.global_position.x, a.global_position.z, sep_i]
	_check(min_sep >= 0.65, "全程与 B 间距 ≥0.65（未穿透）(min=%.3f)" % min_sep)
	_check(max_abs_z > 0.2, "A 产生切向绕行偏移 (max|z|=%.3f)" % max_abs_z)
	_check(a.global_position.distance_to(Vector3(3, 0, 0)) < 0.3, "A 绕过 B 后到达目标 (%.2f)" % a.global_position.distance_to(Vector3(3, 0, 0)))

	_write_result()
	quit(1 if _fails > 0 else 0)
