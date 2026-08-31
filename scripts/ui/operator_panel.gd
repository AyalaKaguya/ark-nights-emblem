class_name OperatorPanel
extends CanvasLayer
## 干员页（与编队页分离）：干员列表 → 干员详情 层级。
## 快捷键 O 唤起；点击左侧列表项在右侧显示该干员的属性 / 技能详情。

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const OperatorData := preload("res://scripts/data/operator_data.gd")

signal closed

var _root: Control
var _list: VBoxContainer
var _detail: VBoxContainer
var _detail_name: Label
var _detail_stats: Label
var _detail_skills: VBoxContainer
var _roster: Array = []
var _selected := -1


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)

	var panel := UiKit.panel(UiKit.COLOR_BG, 12)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-400, -260)
	panel.size = Vector2(800, 520)
	_root.add_child(panel)

	var title := UiKit.label("干员详情", 20)
	title.position = Vector2(20, 16)
	panel.add_child(title)

	var close := UiKit.button("关闭 (O)", 14)
	close.position = Vector2(700, 16)
	close.size = Vector2(84, 28)
	close.pressed.connect(func(): closed.emit(); visible = false)
	panel.add_child(close)

	var list_title := UiKit.label("干员列表", 15, Color(0.7, 0.74, 0.84))
	list_title.position = Vector2(20, 60)
	panel.add_child(list_title)
	_list = VBoxContainer.new()
	_list.position = Vector2(20, 88)
	_list.size = Vector2(260, 410)
	_list.add_theme_constant_override("separation", 6)
	panel.add_child(_list)

	var detail_title := UiKit.label("详情", 15, Color(0.7, 0.74, 0.84))
	detail_title.position = Vector2(300, 60)
	panel.add_child(detail_title)
	_detail = VBoxContainer.new()
	_detail.position = Vector2(300, 88)
	_detail.size = Vector2(480, 410)
	_detail.add_theme_constant_override("separation", 8)
	panel.add_child(_detail)

	_detail_name = UiKit.label("—", 18)
	_detail.add_child(_detail_name)
	_detail_stats = UiKit.label("", 14)
	_detail.add_child(_detail_stats)
	_detail.add_child(UiKit.label("技能", 15, Color(0.7, 0.74, 0.84)))
	_detail_skills = VBoxContainer.new()
	_detail_skills.add_theme_constant_override("separation", 4)
	_detail.add_child(_detail_skills)

	visible = false


func open(roster: Array) -> void:
	_roster = roster
	visible = true
	_selected = 0 if not roster.is_empty() else -1
	_refresh_list()
	_refresh_detail()


func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for i in _roster.size():
		var op: OperatorData = _roster[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(250, 52)
		btn.modulate = Color(1.4, 1.4, 0.7) if i == _selected else Color.WHITE
		btn.pressed.connect(_select.bind(i))
		_list.add_child(btn)
		var avatar := UiKit.avatar(op.indicator_color, op.display_name.substr(0, 1), 36)
		avatar.position = Vector2(6, 8)
		btn.add_child(avatar)
		var l := UiKit.label("%s (%s)" % [op.display_name, op.archetype], 14)
		l.position = Vector2(52, 16)
		btn.add_child(l)


func _select(i: int) -> void:
	_selected = i
	_refresh_list()
	_refresh_detail()


func _refresh_detail() -> void:
	if _selected < 0 or _selected >= _roster.size():
		return
	var op: OperatorData = _roster[_selected]
	_detail_name.text = "%s — %s" % [op.display_name, op.archetype]
	_detail_stats.text = "生命 %d   攻击 %d   防御 %d   法抗 %d\n攻速 %.1fs   体力上限 %.0f   技力上限 %d" % [
		op.max_hp, op.atk, op.defense, op.res, op.attack_interval, op.max_stamina, op.max_sp]
	for c in _detail_skills.get_children():
		c.queue_free()
	if op.basic_attack:
		_detail_skills.add_child(UiKit.label("普攻：%s" % op.basic_attack.tooltip_text(), 13))
	for s in op.skills:
		_detail_skills.add_child(UiKit.label("%s" % s.tooltip_text(), 13))
