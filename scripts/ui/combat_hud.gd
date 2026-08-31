class_name CombatHud
extends CanvasLayer
## BG3 式战斗 HUD：底部三个相邻独立面板（角色 / 动作槽网格 / 回合控制），整体水平居中。
## 动作槽 12 列 × 2 行（默认，可扩到 4 行），操作栏高度随行数变化。
## 模式显隐：即时制显示"战术微操+返营"，战术微操显示"结束战术"，回合制显示"结束回合+撤退"。

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const UnitState := preload("res://scripts/game/unit_state.gd")
const UnitActor := preload("res://scripts/game/unit_actor.gd")
const StatusEffectData := preload("res://scripts/data/status_effect_data.gd")
const GameModeDef := preload("res://scripts/game/game_mode.gd")

signal slot_pressed(index: int)
signal end_turn_pressed
signal retreat_pressed
signal return_camp_pressed
signal tactical_pressed
signal end_tactical_pressed
signal depart_pressed
signal toggle_action_bar_pressed
signal slot_rebound(slot_index: int, action_key: String)

const REBIND_ATTACK := 0
const REBIND_SKILL_BASE := 100
const REBIND_ITEM := 200
const REBIND_CLEAR := 300

const CHAR_W := 170.0
const ACTION_W := 330.0
const TURN_W := 170.0
const PANEL_FIXED_H := 132.0
const ACTION_H_2ROW := 86.0
const ACTION_H_4ROW := 138.0
const BOTTOM_MARGIN := 16.0
const SLOT_SIZE := 24.0

var _char_panel: Panel
var _action_panel: Panel
var _turn_panel: Panel

var _avatar: Panel
var _avatar_initial: Label
var _name_label: Label
var _archetype_label: Label
var _hp_bar: ProgressBar
var _sp_bar: ProgressBar
var _stats_label: Label
var _stamina_pips: HBoxContainer
var _status_row: HBoxContainer

var _slots: Array[Button] = []
var _slot_rows: Array[HBoxContainer] = []
var _show_all_rows := false
var _active_slot := -1

var _current_unit: UnitState
var _edit_mode := false
var _edit_btn: Button
var _layout_btn: Button
var _popup: PopupMenu
var _rebind_target := -1

var _mode_label: Label
var _turn_label: Label
var _end_turn_btn: Button
var _retreat_btn: Button
var _return_camp_btn: Button
var _tactical_btn: Button
var _end_tactical_btn: Button
var _depart_btn: Button

var _quest_label: Label
var _minimap: Panel
var _minimap_dots: Dictionary = {}


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_char_panel(root)
	_build_action_panel(root)
	_build_turn_panel(root)
	_build_top_right(root)
	_layout_panels()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := _key_to_slot_index(event.keycode)
		if idx >= 0 and idx < _slots.size() and not _slots[idx].disabled:
			_on_slot(idx)
			get_viewport().set_input_as_handled()


func _key_to_slot_index(keycode: Key) -> int:
	match keycode:
		KEY_1, KEY_KP_1: return 0
		KEY_2, KEY_KP_2: return 1
		KEY_3, KEY_KP_3: return 2
		KEY_4, KEY_KP_4: return 3
		KEY_5, KEY_KP_5: return 4
		KEY_6, KEY_KP_6: return 5
		KEY_7, KEY_KP_7: return 6
		KEY_8, KEY_KP_8: return 7
	return -1


## ===================== 三栏布局（整体居中 + 操作栏高度随行数变化） =====================

func _layout_panels() -> void:
	var total := CHAR_W + ACTION_W + TURN_W
	var half := total / 2.0
	var action_h := ACTION_H_4ROW if _show_all_rows else ACTION_H_2ROW
	UiKit.place(_char_panel, Vector4(0.5, 1, 0.5, 1), Vector4(-half, -PANEL_FIXED_H - BOTTOM_MARGIN, -half + CHAR_W, -BOTTOM_MARGIN))
	UiKit.place(_action_panel, Vector4(0.5, 1, 0.5, 1), Vector4(-half + CHAR_W, -action_h - BOTTOM_MARGIN, -half + CHAR_W + ACTION_W, -BOTTOM_MARGIN))
	UiKit.place(_turn_panel, Vector4(0.5, 1, 0.5, 1), Vector4(-half + CHAR_W + ACTION_W, -PANEL_FIXED_H - BOTTOM_MARGIN, -half + total, -BOTTOM_MARGIN))


func _build_char_panel(root: Control) -> void:
	_char_panel = UiKit.panel(UiKit.COLOR_BG, 10)
	_char_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_char_panel)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 2)
	_char_panel.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	_avatar = UiKit.avatar(Color(0.4, 0.4, 0.4), "?", 40)
	top.add_child(_avatar)
	_avatar_initial = _avatar.get_child(0) as Label
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	top.add_child(names)
	_name_label = UiKit.label("—", 14)
	names.add_child(_name_label)
	_archetype_label = UiKit.label("", 11, Color(0.7, 0.74, 0.84))
	names.add_child(_archetype_label)

	_hp_bar = UiKit.hbar(UiKit.COLOR_HP, Color(0.1, 0.1, 0.14, 0.9), 11)
	v.add_child(_hp_bar)
	_sp_bar = UiKit.hbar(UiKit.COLOR_SP, Color(0.1, 0.1, 0.14, 0.9), 8)
	v.add_child(_sp_bar)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 4)
	v.add_child(bottom)
	bottom.add_child(UiKit.label("体", 10, UiKit.COLOR_STAMINA))
	_stamina_pips = HBoxContainer.new()
	_stamina_pips.add_theme_constant_override("separation", 1)
	bottom.add_child(_stamina_pips)
	for i in 6:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(9, 9)
		pip.color = UiKit.COLOR_STAMINA
		_stamina_pips.add_child(pip)
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 2)
	bottom.add_child(_status_row)

	_stats_label = UiKit.label("HP — · SP —", 10, Color(0.82, 0.86, 0.94))
	v.add_child(_stats_label)


func _build_action_panel(root: Control) -> void:
	_action_panel = UiKit.panel(UiKit.COLOR_BG, 10)
	_action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_action_panel)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 2)
	_action_panel.add_child(v)

	var tools := HBoxContainer.new()
	tools.alignment = BoxContainer.ALIGNMENT_END
	tools.add_theme_constant_override("separation", 2)
	v.add_child(tools)
	_layout_btn = _small_symbol_button("⇅", "切换 2×12 / 4×12")
	_layout_btn.pressed.connect(toggle_action_bar_layout)
	tools.add_child(_layout_btn)
	_edit_btn = _small_symbol_button("✎", "编辑绑定")
	_edit_btn.pressed.connect(_toggle_edit_mode)
	tools.add_child(_edit_btn)

	for r in UnitState.SLOT_ROWS_MAX:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(row)
		_slot_rows.append(row)
		if r >= 2:
			row.visible = false

	_popup = PopupMenu.new()
	_popup.id_pressed.connect(_on_popup_id)
	_action_panel.add_child(_popup)

	for i in UnitState.SLOT_COUNT_MAX:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		btn.add_theme_font_size_override("font_size", 9)
		btn.text = ""
		btn.pressed.connect(_on_slot.bind(i))
		_slots.append(btn)
		_slot_rows[i / UnitState.SLOT_COLUMNS].add_child(btn)


func _small_symbol_button(symbol: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = symbol
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(20, 18)
	b.add_theme_font_size_override("font_size", 11)
	return b


func _build_turn_panel(root: Control) -> void:
	_turn_panel = UiKit.panel(UiKit.COLOR_BG, 10)
	_turn_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_turn_panel)

	_mode_label = UiKit.label("REALTIME", 11, UiKit.COLOR_STAMINA)
	_mode_label.position = Vector2(10, 8)
	_turn_panel.add_child(_mode_label)

	_turn_label = UiKit.label("", 11)
	_turn_label.position = Vector2(10, 26)
	_turn_panel.add_child(_turn_label)

	_end_turn_btn = UiKit.button("结束回合", 13)
	_end_turn_btn.position = Vector2(10, 44)
	_end_turn_btn.size = Vector2(150, 24)
	_end_turn_btn.pressed.connect(func(): end_turn_pressed.emit())
	_turn_panel.add_child(_end_turn_btn)

	_tactical_btn = UiKit.button("战术微操", 13)
	_tactical_btn.position = Vector2(10, 44)
	_tactical_btn.size = Vector2(150, 24)
	_tactical_btn.tooltip_text = "进入回合制微操（T）"
	_tactical_btn.pressed.connect(func(): tactical_pressed.emit())
	_turn_panel.add_child(_tactical_btn)

	_end_tactical_btn = UiKit.button("结束战术", 13)
	_end_tactical_btn.position = Vector2(10, 44)
	_end_tactical_btn.size = Vector2(150, 24)
	_end_tactical_btn.tooltip_text = "返回即时制（T）"
	_end_tactical_btn.pressed.connect(func(): end_tactical_pressed.emit())
	_turn_panel.add_child(_end_tactical_btn)

	_depart_btn = UiKit.button("出发", 13)
	_depart_btn.position = Vector2(10, 44)
	_depart_btn.size = Vector2(150, 24)
	_depart_btn.tooltip_text = "进入箱庭地图"
	_depart_btn.pressed.connect(func(): depart_pressed.emit())
	_turn_panel.add_child(_depart_btn)

	_retreat_btn = UiKit.button("撤退", 12)
	_retreat_btn.position = Vector2(10, 72)
	_retreat_btn.size = Vector2(150, 22)
	_retreat_btn.pressed.connect(func(): retreat_pressed.emit())
	_turn_panel.add_child(_retreat_btn)

	_return_camp_btn = UiKit.button("返营", 12)
	_return_camp_btn.position = Vector2(10, 72)
	_return_camp_btn.size = Vector2(150, 22)
	_return_camp_btn.tooltip_text = "战斗中不可返营"
	_return_camp_btn.pressed.connect(func(): return_camp_pressed.emit())
	_turn_panel.add_child(_return_camp_btn)


## ===================== 右上：小地图 + 任务 =====================

func _build_top_right(root: Control) -> void:
	var panel := UiKit.panel(UiKit.COLOR_BG, 10)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	UiKit.place(panel, Vector4(1, 0, 1, 0), Vector4(-176, 16, -16, 216))

	_minimap = UiKit.panel(Color(0.08, 0.09, 0.14, 0.9), 6)
	_minimap.position = Vector2(10, 10)
	_minimap.size = Vector2(140, 140)
	panel.add_child(_minimap)

	_quest_label = UiKit.label("任务", 12)
	_quest_label.position = Vector2(10, 158)
	_quest_label.size = Vector2(140, 36)
	_quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_quest_label)


## ===================== 槽位 =====================

func _on_slot(index: int) -> void:
	if _edit_mode:
		_open_rebind_popup(index)
	else:
		slot_pressed.emit(index)


func set_slots(names: Array[String]) -> void:
	for i in _slots.size():
		var text := names[i] if i < names.size() else ""
		_slots[i].text = text
		_slots[i].disabled = text == ""
		_slots[i].tooltip_text = text if text != "" else "（空槽）"


func set_active_slot(index: int) -> void:
	_active_slot = index
	for i in _slots.size():
		_slots[i].modulate = Color(1.2, 1.2, 0.6) if i == index else Color.WHITE


## 切换 2×12 / 4×12：操作栏高度随之变化。
func toggle_action_bar_layout() -> void:
	_show_all_rows = not _show_all_rows
	for r in _slot_rows.size():
		if r >= 2:
			_slot_rows[r].visible = _show_all_rows
	_layout_panels()
	toggle_action_bar_pressed.emit()


## ===================== 动作槽重绑定 =====================

func _toggle_edit_mode() -> void:
	_edit_mode = not _edit_mode
	_edit_btn.text = "✓" if _edit_mode else "✎"
	_edit_btn.tooltip_text = "完成绑定" if _edit_mode else "编辑绑定"
	for i in _slots.size():
		_slots[i].modulate = Color(1.0, 0.9, 0.5) if (_edit_mode and _slots[i].text != "") else Color.WHITE


func _open_rebind_popup(index: int) -> void:
	if _popup == null or _current_unit == null:
		return
	_rebind_target = index
	_popup.clear()
	_popup.add_item("普攻", REBIND_ATTACK)
	for i in _current_unit.operator.skills.size():
		_popup.add_item(_current_unit.operator.skills[i].display_name, REBIND_SKILL_BASE + i)
	_popup.add_item("道具", REBIND_ITEM)
	_popup.add_item("（清空）", REBIND_CLEAR)
	_popup.position = Vector2i(_slots[index].get_global_rect().position)
	_popup.popup()


func _on_popup_id(id: int) -> void:
	if _rebind_target < 0:
		return
	var key := ""
	if id == REBIND_ATTACK:
		key = "attack"
	elif id == REBIND_ITEM:
		key = "item"
	elif id == REBIND_CLEAR:
		key = ""
	elif id >= REBIND_SKILL_BASE:
		key = "skill:%d" % (id - REBIND_SKILL_BASE)
	slot_rebound.emit(_rebind_target, key)
	_rebind_target = -1


## ===================== 更新接口 =====================

func set_mode_text(text: String) -> void:
	_mode_label.text = text


func set_turn_text(text: String) -> void:
	_turn_label.text = text


func set_quest(text: String) -> void:
	_quest_label.text = text


## 按模式切换回合面板显隐（CAMP 显示出发；REALTIME 显示战术微操+返营；TACTICAL 显示结束战术；COMBAT 显示结束回合+撤退）。
func set_mode_ui(mode: int) -> void:
	var combat := mode == GameModeDef.Mode.COMBAT_TURN
	var tactical := mode == GameModeDef.Mode.TACTICAL_TURN
	var realtime := mode == GameModeDef.Mode.REALTIME
	var camp := mode == GameModeDef.Mode.CAMP
	_end_turn_btn.visible = combat
	_retreat_btn.visible = combat
	_turn_label.visible = combat
	_tactical_btn.visible = realtime
	_end_tactical_btn.visible = tactical
	_return_camp_btn.visible = realtime
	_depart_btn.visible = camp


## 更新当前单位面板。
func set_current_unit(u: UnitState) -> void:
	if u == null or u.operator == null:
		return
	_current_unit = u
	var initial := u.operator.display_name.substr(0, 1)
	var sb := _avatar.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = u.operator.indicator_color
	if _avatar_initial != null:
		_avatar_initial.text = initial
	_name_label.text = u.operator.display_name
	_archetype_label.text = u.operator.archetype
	_hp_bar.max_value = u.effective_max_hp()
	_hp_bar.value = u.hp
	_sp_bar.max_value = u.operator.max_sp
	_sp_bar.value = u.sp
	_stats_label.text = "HP %d/%d · SP %d/%d" % [int(ceil(u.hp)), int(u.effective_max_hp()), u.sp, u.operator.max_sp]
	_set_stamina_pips(u.stamina, u.operator.max_stamina)
	_set_status_icons(u.statuses)


func _set_stamina_pips(value: float, maximum: float) -> void:
	for i in _stamina_pips.get_child_count():
		var pip := _stamina_pips.get_child(i) as ColorRect
		pip.color = UiKit.COLOR_STAMINA if float(i) < value else Color(0.2, 0.2, 0.22, 1.0)


func _set_status_icons(statuses: Array) -> void:
	for c in _status_row.get_children():
		c.queue_free()
	for s in statuses:
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(10, 10)
		icon.color = Color(0.9, 0.3, 0.3) if (s as StatusEffectData).is_debuff else Color(0.4, 0.85, 0.5)
		icon.tooltip_text = (s as StatusEffectData).display_name
		_status_row.add_child(icon)


func update_minimap(allies: Array, enemies: Array, bounds: Rect2) -> void:
	for dot in _minimap_dots.values():
		if is_instance_valid(dot):
			dot.queue_free()
	_minimap_dots.clear()
	for a in allies:
		_add_minimap_dot(a, Color(0.4, 0.8, 1.0), bounds)
	for e in enemies:
		_add_minimap_dot(e, Color(1.0, 0.35, 0.35), bounds)


func _add_minimap_dot(actor: UnitActor, color: Color, bounds: Rect2) -> void:
	if actor == null:
		return
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(6, 6)
	dot.color = color
	var norm := (Vector2(actor.global_position.x, actor.global_position.z) - bounds.position) / bounds.size
	dot.position = Vector2(norm.x * 128.0, norm.y * 128.0)
	_minimap.add_child(dot)
	_minimap_dots[actor.get_instance_id()] = dot
