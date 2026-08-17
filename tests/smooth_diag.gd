extends SceneTree
## 临时诊断：验证 HD2DCharacter.smooth_path 的 Chaikin 细分行为。

const HD2DCharacter := preload("res://scripts/character/hd2d_character.gd")
const PlayerController := preload("res://scripts/player/player_controller.gd")

var _fails := 0
var _log := ""


func _check(cond: bool, label: String) -> void:
	if cond:
		_log += "PASS: " + label + "\n"
	else:
		_fails += 1
		_log += "FAIL: " + label + "\n"


func _write_result() -> void:
	var f := FileAccess.open("res://tests/diag_out.txt", FileAccess.WRITE)
	if f:
		f.store_string(_log + "RESULT: " + ("ALL PASS" if _fails == 0 else "%d FAILS" % _fails))
		f.close()


func _initialize() -> void:
	# 直角折线：3 点
	var path := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1),
	])
	var smooth := HD2DCharacter.smooth_path(path, 2)
	_check(smooth.size() > path.size(), "细分后点数增加 (%d > %d)" % [smooth.size(), path.size()])
	_check(smooth[0] == path[0], "首点保持")
	_check(smooth[smooth.size() - 1] == path[path.size() - 1], "尾点保持")
	# 中间点应贴近内角（拐角被切圆）
	var corner := Vector3(1, 0, 0)
	var min_dist := 1e9
	for p in smooth:
		min_dist = minf(min_dist, p.distance_to(corner))
	_check(min_dist > 0.05, "拐角点被切开 (min_dist=%.3f)" % min_dist)
	# 平滑后相邻点间距应小于原始 1.0（更密）
	var max_gap := 0.0
	for i in range(smooth.size() - 1):
		max_gap = maxf(max_gap, smooth[i].distance_to(smooth[i + 1]))
	_check(max_gap < 1.0, "平滑后点距更密 (max_gap=%.3f)" % max_gap)

	# 单点/两点路径不崩溃
	_check(HD2DCharacter.smooth_path(PackedVector3Array([Vector3.ZERO])).size() == 1, "单点路径不崩溃")
	_check(HD2DCharacter.smooth_path(PackedVector3Array([Vector3.ZERO, Vector3.ONE])).size() == 2, "两点路径不崩溃")

	# ===== 距离相关速度曲线 =====
	var ch := HD2DCharacter.new()
	ch.min_move_speed = 1.5
	ch.max_move_speed = 5.0
	ch.speed_ramp_dist = 8.0
	ch.speed_curve = null
	_check(is_equal_approx(ch._current_speed(0.0), 1.5), "距离0 → 最慢速度 1.5")
	_check(is_equal_approx(ch._current_speed(8.0), 5.0), "距离ramp → 最快速度 5.0")
	var mid := ch._current_speed(4.0)
	_check(mid > 1.5 and mid < 5.0, "中间距离速度在范围内 (%.3f)" % mid)
	var prev := 0.0
	var mono := true
	for i in range(11):
		var s := ch._current_speed(i * 0.8)
		if i > 0 and s < prev - 1e-6:
			mono = false
		prev = s
	_check(mono, "速度随距离单调递增")
	# 自定义 Curve 生效：采样 t=0.5 的值被用作比例
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 1.0))
	ch.speed_curve = curve
	var curved := ch._current_speed(4.0)  # t=0.5 → k≈0.5 附近
	_check(curved >= 1.5 and curved <= 5.0, "自定义曲线采样有效 (%.3f)" % curved)

	# ===== 导航网格精细化 + 斜率限制 =====
	var pc := PlayerController.new()
	_check(is_equal_approx(pc.nav_cell_size, 0.5), "cell 尺寸默认 0.5（更贴墙）")
	_check(is_equal_approx(pc.nav_margin, 0.2), "障碍物边距默认 0.2（更贴墙）")
	_check(is_equal_approx(pc.max_nav_slope_deg, 45.0), "最大坡度默认 45°")
	var th := cos(deg_to_rad(pc.max_nav_slope_deg))
	_check(is_equal_approx(th, cos(deg_to_rad(45.0))), "45° 阈值 ≈ 0.7071 (%.4f)" % th)
	_check(1.0 >= th, "平地上表面（normal.y=1）可设定")
	_check(0.0 < th, "垂直墙面（normal.y=0）被拒绝")
	# 中等坡度：30° 坡面在 45° 阈值内可接受
	_check(cos(deg_to_rad(30.0)) >= th, "30° 坡面可接受")
	# 陡坡：60° 超过阈值被拒绝
	_check(cos(deg_to_rad(60.0)) < th, "60° 陡坡被拒绝")

	print("RESULT: ", "ALL PASS" if _fails == 0 else "%d FAILS" % _fails)
	_write_result()
	quit(1 if _fails > 0 else 0)
