class_name StartScreen
extends CanvasLayer
## 开始界面：标题 + 开始按钮。点击后开始新游戏并进入营地。

const UiKit := preload("res://scripts/ui/ui_kit.gd")

signal start_pressed

var _root: Control


func _ready() -> void:
	layer = 30
	add_to_group("start_screen")
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var title := UiKit.label("ArkNight Emblem", 44, Color(0.98, 0.94, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.position = Vector2(-260, -160)
	title.size = Vector2(520, 60)
	_root.add_child(title)

	var subtitle := UiKit.label("HD-2D 战术 RPG 原型 · 非商业垂直切片", 16, Color(0.6, 0.66, 0.78))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	subtitle.position = Vector2(-260, -100)
	subtitle.size = Vector2(520, 30)
	_root.add_child(subtitle)

	var start := UiKit.button("开始游戏", 22)
	start.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	start.position = Vector2(-120, 40)
	start.size = Vector2(240, 52)
	start.pressed.connect(func(): start_pressed.emit())
	_root.add_child(start)


func show_screen() -> void:
	visible = true
