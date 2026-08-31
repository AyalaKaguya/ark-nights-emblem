class_name UiKit
extends RefCounted
## UI 构建小工具：集中创建 Label / Button / Panel / 进度条 / 样式盒，保证配色与字体一致。

const COLOR_HP := Color(0.29, 0.53, 0.93)        # 科技蓝（HP）
const COLOR_SP := Color(0.48, 0.85, 0.6)         # 生命绿（技力）
const COLOR_STAMINA := Color(1.0, 0.84, 0.2)     # 琥珀金（体力）
const COLOR_BG := Color(0.04, 0.04, 0.08, 0.9)   # 宇宙黑
const COLOR_TEXT := Color(0.92, 0.94, 1.0)


static func label(text: String, font_size: int = 16, color: Color = COLOR_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, font_size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	return b


## 深色圆角样式盒（Panel / PanelContainer 通用）。
static func panel_stylebox(bg: Color, corner_radius: int = 8, border_color: Color = Color(1, 1, 1, 0.14)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(corner_radius)
	sb.set_border_width_all(1)
	sb.border_color = border_color
	sb.set_content_margin_all(8)
	return sb


static func panel(bg: Color, corner_radius: int = 8, border_color: Color = Color(1, 1, 1, 0.12)) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", panel_stylebox(bg, corner_radius, border_color))
	return p


## 横向进度条（HP / SP / 体力）。fill/bg 传入颜色。
static func hbar(fill_color: Color, bg_color: Color = Color(0.1, 0.1, 0.14, 0.9), height: int = 14) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## 圆形头像占位（无立绘图片时用色块 + 首字）。
static func avatar(color: Color, initial: String, size: float) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(size / 2.0))
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.4)
	p.add_theme_stylebox_override("panel", sb)
	var l := label(initial, int(size * 0.5), Color(1, 1, 1))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(l)
	return p


## 用显式 anchor + offset 定位一个 Control（anchor 与 offset 均为 Vector4：left/top/right/bottom）。
static func place(c: Control, anchor: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchor.x
	c.anchor_top = anchor.y
	c.anchor_right = anchor.z
	c.anchor_bottom = anchor.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w
