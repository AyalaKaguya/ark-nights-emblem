class_name InventoryPanel
extends CanvasLayer
## 独立角色背包面板（Tab 唤起）：左侧竖排队员头像 + 无文字蓝 HP / 绿技力条；
## 右侧按 物品 / 属性 / 技能 / 装备 切换。每名角色独立背包。

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const UnitState := preload("res://scripts/game/unit_state.gd")
const DataFactory := preload("res://scripts/game/data_factory.gd")
const ItemData := preload("res://scripts/data/item_data.gd")

signal use_item_requested(unit_id: String, item_id: String)
signal closed

var _root: Control
var _left_col: VBoxContainer
var _content: VBoxContainer
var _tab_label: Label
var _party: Array = []
var _selected := 0
var _tab := 0  # 0 物品 / 1 属性 / 2 技能 / 3 装备


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
	panel.position = Vector2(-420, -280)
	panel.size = Vector2(840, 560)
	_root.add_child(panel)

	var title := UiKit.label("角色背包", 22)
	title.position = Vector2(20, 16)
	panel.add_child(title)

	var close := UiKit.button("关闭 (Tab)", 14)
	close.position = Vector2(740, 16)
	close.size = Vector2(84, 28)
	close.pressed.connect(func(): closed.emit(); visible = false)
	panel.add_child(close)

	_left_col = VBoxContainer.new()
	_left_col.position = Vector2(20, 60)
	_left_col.size = Vector2(160, 480)
	_left_col.add_theme_constant_override("separation", 10)
	panel.add_child(_left_col)

	# 右侧内容区
	var right := VBoxContainer.new()
	right.position = Vector2(200, 60)
	right.size = Vector2(620, 480)
	right.add_theme_constant_override("separation", 8)
	panel.add_child(right)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	right.add_child(tabs)
	var tab_names := ["物品", "属性", "技能", "装备"]
	for i in tab_names.size():
		var b := UiKit.button(tab_names[i], 15)
		b.pressed.connect(_set_tab.bind(i))
		tabs.add_child(b)

	_tab_label = UiKit.label("", 16)
	right.add_child(_tab_label)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
	right.add_child(_content)

	visible = false


func open(party: Array) -> void:
	_party = party
	visible = true
	_selected = mini(_selected, maxi(party.size() - 1, 0))
	_refresh()


func _set_tab(t: int) -> void:
	_tab = t
	_refresh_content()


func _refresh() -> void:
	for c in _left_col.get_children():
		c.queue_free()
	for i in _party.size():
		var u: UnitState = _party[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 64)
		btn.modulate = Color(1.4, 1.4, 0.7) if i == _selected else Color.WHITE
		btn.pressed.connect(_select.bind(i))
		_left_col.add_child(btn)

		var avatar := UiKit.avatar(u.operator.indicator_color, u.operator.display_name.substr(0, 1), 44)
		avatar.position = Vector2(6, 10)
		btn.add_child(avatar)

		# 无文字蓝色 HP 条
		var hp := UiKit.hbar(UiKit.COLOR_HP, Color(0.1, 0.1, 0.14), 8)
		hp.max_value = u.effective_max_hp()
		hp.value = u.hp
		hp.position = Vector2(60, 16)
		hp.size = Vector2(84, 8)
		btn.add_child(hp)

		# 无文字绿色技力条
		var sp := UiKit.hbar(UiKit.COLOR_SP, Color(0.1, 0.1, 0.14), 6)
		sp.max_value = u.operator.max_sp
		sp.value = u.sp
		sp.position = Vector2(60, 30)
		sp.size = Vector2(84, 6)
		btn.add_child(sp)
	_refresh_content()


func _select(i: int) -> void:
	_selected = i
	_refresh()


func _refresh_content() -> void:
	for c in _content.get_children():
		c.queue_free()
	if _party.is_empty() or _selected >= _party.size():
		return
	var u: UnitState = _party[_selected]
	match _tab:
		0:
			_tab_label.text = "物品 — %s" % u.operator.display_name
			if u.inventory.is_empty():
				_content.add_child(UiKit.label("（空）", 14, Color(0.6, 0.6, 0.66)))
			else:
				for item_id in u.inventory.items().keys():
					var item = _find_item(item_id)
					var row := HBoxContainer.new()
					row.add_theme_constant_override("separation", 10)
					_content.add_child(row)
					var count := u.inventory.count(item_id)
					row.add_child(UiKit.label("%s ×%d" % [item.display_name if item else item_id, count], 15))
					if item != null:
						var use := UiKit.button("使用", 13)
						use.pressed.connect(_on_use_item.bind(u.unit_id, item_id))
						row.add_child(use)
		1:
			_tab_label.text = "属性 — %s" % u.operator.display_name
			_content.add_child(UiKit.label("生命 %d/%d" % [int(ceil(u.hp)), int(u.effective_max_hp())], 15))
			_content.add_child(UiKit.label("攻击 %d   防御 %d   法抗 %d" % [int(u.effective_atk()), int(u.effective_def()), int(u.effective_res())], 15))
			_content.add_child(UiKit.label("体力 %.1f/%d   技力 %d/%d" % [u.stamina, int(u.operator.max_stamina), u.sp, u.operator.max_sp], 15))
			_content.add_child(UiKit.label("职业 %s   攻速 %.1fs" % [u.operator.archetype, u.operator.attack_interval], 15))
		2:
			_tab_label.text = "技能 — %s" % u.operator.display_name
			if u.operator.basic_attack:
				_content.add_child(UiKit.label(u.operator.basic_attack.tooltip_text(), 14))
			for s in u.operator.skills:
				var cd := int(u.skill_cooldowns.get(s.skill_id, 0))
				var suffix := "（冷却 %d 回合）" % cd if cd > 0 else ""
				_content.add_child(UiKit.label(s.tooltip_text() + suffix, 14))
		3:
			_tab_label.text = "装备 — %s" % u.operator.display_name
			if u.equipment.is_empty():
				_content.add_child(UiKit.label("（未装备）", 14, Color(0.6, 0.6, 0.66)))
			else:
				for e in u.equipment:
					_content.add_child(UiKit.label(e.display_name, 15))


func _on_use_item(unit_id: String, item_id: String) -> void:
	use_item_requested.emit(unit_id, item_id)


func _find_item(item_id: String) -> ItemData:
	for it in DataFactory.default_items():
		if it.item_id == item_id:
			return it
	return null
