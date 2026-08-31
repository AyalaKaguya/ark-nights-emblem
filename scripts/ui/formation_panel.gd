class_name FormationPanel
extends CanvasLayer
## 营地编队设施面板：增删 / 更换出战队员。仅在营地可用（由 GameState 门控）。

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const OperatorData := preload("res://scripts/data/operator_data.gd")

signal ids_changed(new_ids: Array[String])
signal closed

var _root: Control
var _roster_col: VBoxContainer
var _party_col: VBoxContainer
var _roster: Array = []
var _ids: Array[String] = []


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
	panel.position = Vector2(-360, -240)
	panel.size = Vector2(720, 480)
	_root.add_child(panel)

	var title := UiKit.label("编队（仅营地可用）", 20)
	title.position = Vector2(20, 16)
	panel.add_child(title)

	var close := UiKit.button("关闭", 14)
	close.position = Vector2(620, 16)
	close.size = Vector2(80, 28)
	close.pressed.connect(func(): closed.emit(); visible = false)
	panel.add_child(close)

	var roster_title := UiKit.label("可用干员", 16)
	roster_title.position = Vector2(20, 60)
	panel.add_child(roster_title)
	_roster_col = VBoxContainer.new()
	_roster_col.position = Vector2(20, 88)
	_roster_col.size = Vector2(330, 360)
	_roster_col.add_theme_constant_override("separation", 8)
	panel.add_child(_roster_col)

	var party_title := UiKit.label("出战队伍", 16)
	party_title.position = Vector2(380, 60)
	panel.add_child(party_title)
	_party_col = VBoxContainer.new()
	_party_col.position = Vector2(380, 88)
	_party_col.size = Vector2(320, 360)
	_party_col.add_theme_constant_override("separation", 8)
	panel.add_child(_party_col)

	visible = false


func open(roster: Array, active_ids: Array[String]) -> void:
	_roster = roster
	_ids = active_ids.duplicate()
	visible = true
	_refresh()


func _refresh() -> void:
	for c in _roster_col.get_children():
		c.queue_free()
	for c in _party_col.get_children():
		c.queue_free()
	for op in _roster:
		var in_party: bool = _ids.has(op.operator_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_roster_col.add_child(row)
		row.add_child(UiKit.avatar(op.indicator_color, op.display_name.substr(0, 1), 36))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		col.add_child(UiKit.label("%s (%s)" % [op.display_name, op.archetype], 14))
		col.add_child(UiKit.label("HP%d ATK%d DEF%d RES%d" % [op.max_hp, op.atk, op.defense, op.res], 11, Color(0.7, 0.7, 0.76)))
		var btn := UiKit.button("已上阵" if in_party else "上阵", 13)
		btn.disabled = in_party or _ids.size() >= 2
		btn.pressed.connect(_add.bind(op.operator_id))
		row.add_child(btn)

	for i in 2:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_party_col.add_child(row)
		if i < _ids.size():
			var op := _find_op(_ids[i])
			row.add_child(UiKit.avatar(op.indicator_color if op else Color.GRAY, op.display_name.substr(0, 1) if op else "?", 36))
			row.add_child(UiKit.label(op.display_name if op else "?", 14))
			var rm := UiKit.button("移除", 13)
			rm.pressed.connect(_remove.bind(i))
			row.add_child(rm)
		else:
			row.add_child(UiKit.label("（空位）", 14, Color(0.5, 0.5, 0.56)))


func _add(operator_id: String) -> void:
	if _ids.size() >= 2 or _ids.has(operator_id):
		return
	_ids.append(operator_id)
	ids_changed.emit(_ids.duplicate())
	_refresh()


func _remove(index: int) -> void:
	if index < _ids.size():
		_ids.remove_at(index)
		ids_changed.emit(_ids.duplicate())
		_refresh()


func _find_op(id: String) -> OperatorData:
	for op in _roster:
		if op.operator_id == id:
			return op
	return null
