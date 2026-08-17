extends SceneTree
## 临时诊断：分析角色 SubViewport 渲染纹理，定位头顶黑线。
## 运行：godot --path . --script res://tests/capture_analysis.gd
## 结果写入 res://tests/capture_out.txt（--script 模式 print 缓冲丢失）。

var _log := ""


func _check(cond: bool, label: String) -> void:
	_log += ("PASS: " if cond else "FAIL: ") + label + "\n"


func _write_result() -> void:
	var f := FileAccess.open("res://tests/capture_out.txt", FileAccess.WRITE)
	if f:
		f.store_string(_log)
		f.close()


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene: Node = load("res://node_3d.tscn").instantiate()
	root.add_child(scene)
	for _i in range(12):
		await process_frame

	for ch in get_nodes_in_group("character"):
		var name: String = ch.get("character_name")
		var vp: SubViewport = ch.get_node_or_null("CharacterViewport")
		if vp == null:
			continue
		_log += "== %s viewport=%dx%d ==\n" % [name, vp.size.x, vp.size.y]
		var img: Image = vp.get_texture().get_image()
		if img == null:
			_log += "  image is null\n"
			continue
		var w := img.get_width()
		var h := img.get_height()
		_log += "  texture %dx%d\n" % [w, h]
		# 找 alpha > 10 的 bounding box（立绘实际占用区域）
		var min_x := w
		var min_y := h
		var max_x := -1
		var max_y := -1
		var non_transparent := 0
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				var a: float = img.get_pixel(x, y).a
				if a > 0.04:
					non_transparent += 1
					min_x = mini(min_x, x)
					min_y = mini(min_y, y)
					max_x = maxi(max_x, x)
					max_y = maxi(max_y, y)
		_log += "  alpha>0.04 采样点: %d, bbox: x[%d..%d] y[%d..%d]\n" % [non_transparent, min_x, max_x, min_y, max_y]
		# 立绘是否贴到视口边缘（被裁切）
		_check(min_y > 2, "%s 立绘顶部未贴视口顶边（min_y=%d, 被裁=%s）" % [name, min_y, str(min_y <= 2)])
		_check(min_x > 2 and max_x < w - 2, "%s 立绘左右未贴边（x[%d..%d] vs 视口 %d）" % [name, min_x, max_x, w])
		# 立绘顶部一行（头顶上方 1~3 像素）是否突然变黑
		if min_y >= 4:
			var edge := ""
			for yy in range(maxi(0, min_y - 3), min_y + 2):
				var px := img.get_pixel((min_x + max_x) / 2, yy)
				edge += "  y=%d rgba(%.2f,%.2f,%.2f,%.2f)\n" % [yy, px.r, px.g, px.b, px.a]
			_log += "  头顶中心列采样:\n" + edge

	_write_result()
	quit(0)
