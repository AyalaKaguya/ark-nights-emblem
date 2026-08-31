extends Node
## autoload GameState：全局模式、队伍、编队、存档与当前地图（跨场景持久）。
## 不声明 class_name（autoload 已生成同名单例）。
## 依赖方向：GameState 只持有 Resource 定义与纯运行时状态，不含表现逻辑。

const GameModeDef := preload("res://scripts/game/game_mode.gd")
const DataFactory := preload("res://scripts/game/data_factory.gd")
const UnitState := preload("res://scripts/game/unit_state.gd")
const SaveGame := preload("res://scripts/data/save_game.gd")
const OperatorData := preload("res://scripts/data/operator_data.gd")
const MapManifest := preload("res://scripts/data/map_manifest.gd")

signal mode_changed(previous: int, current: int)
signal party_changed
signal map_requested(manifest: MapManifest)
signal combat_resolved(result: String)

var mode: int = GameModeDef.Mode.CAMP
var roster: Array[OperatorData] = []
var party: Array[UnitState] = []
var current_map: MapManifest = null
var save: SaveGame = SaveGame.new()

## 战斗锁：进入 COMBAT_TURN 后置位，只有 resolve_combat 才能解除（禁止直接逃回实时 / 返营）。
var _combat_locked := false

## 撤退宽限时长（毫秒）：撤退后在此时间内不再触发遭遇，给玩家跑出警戒圈的机会。
const RETREAT_GRACE_MSEC := 5000

var _retreat_grace_until_msec := 0


func _ready() -> void:
	# 启动即准备新档（开始界面点击"开始"时再 new_game 注入数据）。
	pass


## 开始新游戏：构建默认编成与营地。
func new_game() -> void:
	roster = DataFactory.default_roster(true)
	party = build_party(DataFactory.default_active_ids())
	for u in party:
		u.inventory.add_item("item_medkit", 2)
	save.clear()
	save.active_ids = DataFactory.default_active_ids()
	mode = GameModeDef.Mode.CAMP
	_combat_locked = false
	_retreat_grace_until_msec = 0
	request_map(DataFactory.camp_manifest())


## 按 operator_id 列表构建出战队伍（新单位全状态）。
func build_party(active_ids: Array[String]) -> Array[UnitState]:
	var out: Array[UnitState] = []
	for id in active_ids:
		var op := find_operator(id)
		if op != null:
			var u := UnitState.new()
			u.bind_operator(op, _unit_id_for(op, out.size()))
			out.append(u)
	return out


func _unit_id_for(op: OperatorData, idx: int) -> String:
	return "%s_%d" % [op.operator_id, idx]


## 请求切换地图（营地 ↔ 箱庭）。不销毁 party 状态。
func request_map(manifest: MapManifest) -> void:
	current_map = manifest
	map_requested.emit(manifest)


func find_operator(id: String) -> OperatorData:
	for op in roster:
		if op.operator_id == id:
			return op
	return null


func get_unit(unit_id: String) -> UnitState:
	for u in party:
		if u.unit_id == unit_id:
			return u
	return null


func allies() -> Array[UnitState]:
	var out: Array[UnitState] = []
	for u in party:
		if u.faction() == "ally":
			out.append(u)
	return out


## ===================== 模式切换 =====================

func can_switch_to(new_mode: int) -> bool:
	if new_mode == mode:
		return true
	match new_mode:
		GameModeDef.Mode.COMBAT_TURN:
			return mode in [GameModeDef.Mode.REALTIME, GameModeDef.Mode.TACTICAL_TURN]
		GameModeDef.Mode.REALTIME:
			if _combat_locked:
				return false
			return mode in [GameModeDef.Mode.CAMP, GameModeDef.Mode.TACTICAL_TURN]
		GameModeDef.Mode.TACTICAL_TURN:
			return mode == GameModeDef.Mode.REALTIME
		GameModeDef.Mode.CAMP:
			if _combat_locked:
				return false
			return mode == GameModeDef.Mode.REALTIME
	return false


## 请求切换模式；非法切换返回 false 且不产生副作用。
func set_mode(new_mode: int) -> bool:
	if new_mode == mode:
		return true
	if not can_switch_to(new_mode):
		return false
	if new_mode == GameModeDef.Mode.COMBAT_TURN:
		_combat_locked = true
	var prev := mode
	mode = new_mode
	mode_changed.emit(prev, new_mode)
	return true


## 进入战斗（遭遇 / 主动攻击）。
func enter_combat() -> bool:
	return set_mode(GameModeDef.Mode.COMBAT_TURN)


## 结算战斗：唯一解除战斗锁的入口。胜利 / 撤退 → 回实时；失败 → 复活整队返营。
func resolve_combat(result: String) -> void:
	if mode != GameModeDef.Mode.COMBAT_TURN:
		return
	_combat_locked = false
	combat_resolved.emit(result)
	match result:
		"victory":
			_set_mode_internal(GameModeDef.Mode.REALTIME)
		"retreat":
			_arm_retreat_grace()
			_set_mode_internal(GameModeDef.Mode.REALTIME)
		"defeat":
			_set_mode_internal(GameModeDef.Mode.CAMP)
			revive_party()
			request_map(DataFactory.camp_manifest())


## 撤退宽限期内返回 true（遭遇触发检查用），防止撤退后立即被警戒范围重新拉入战斗。
func is_encounter_blocked() -> bool:
	return Time.get_ticks_msec() < _retreat_grace_until_msec


func _arm_retreat_grace() -> void:
	_retreat_grace_until_msec = Time.get_ticks_msec() + RETREAT_GRACE_MSEC


## 复活整队（战败返营时调用）：全员回满状态（HP / 体力 / 技力，清冷却与状态效果）。
func revive_party() -> void:
	for u in party:
		u.reset_to_full()
	party_changed.emit()


## 返营（安全入口）：战斗中禁止。
func request_return_camp() -> bool:
	if _combat_locked or mode != GameModeDef.Mode.REALTIME:
		return false
	_set_mode_internal(GameModeDef.Mode.CAMP)
	request_map(DataFactory.camp_manifest())
	return true


func _set_mode_internal(new_mode: int) -> void:
	var prev := mode
	mode = new_mode
	mode_changed.emit(prev, new_mode)


## ===================== 编队（仅营地） =====================

## 是否允许修改编队：仅在营地。
func can_edit_party() -> bool:
	return mode == GameModeDef.Mode.CAMP


## 替换队伍中 index 位置的干员（仅营地）。返回是否成功。
func replace_party_member(index: int, operator_id: String) -> bool:
	if not can_edit_party():
		return false
	if index < 0 or index >= party.size():
		return false
	var op := find_operator(operator_id)
	if op == null:
		return false
	# 已在队伍中且非自身 → 拒绝重复出战
	for u in party:
		if u.operator.operator_id == operator_id and party[index].operator.operator_id != operator_id:
			return false
	var u := UnitState.new()
	u.bind_operator(op, _unit_id_for(op, index))
	party[index] = u
	save.active_ids = _active_ids_from_party()
	party_changed.emit()
	return true


func _active_ids_from_party() -> Array[String]:
	var out: Array[String] = []
	for u in party:
		out.append(u.operator.operator_id)
	return out


## 按 id 列表重建出战队伍（仅营地）。复用同名单位的现有状态，新增单位全状态。
func set_party_ids(active_ids: Array[String]) -> bool:
	if not can_edit_party():
		return false
	if active_ids.size() > 2:
		return false
	var seen := {}
	var new_party: Array[UnitState] = []
	for id in active_ids:
		if seen.has(id):
			return false
		seen[id] = true
		var op := find_operator(id)
		if op == null:
			return false
		var existing := _find_unit_by_operator(id)
		if existing != null:
			new_party.append(existing)
		else:
			var u := UnitState.new()
			u.bind_operator(op, _unit_id_for(op, new_party.size()))
			new_party.append(u)
	party = new_party
	save.active_ids = active_ids
	party_changed.emit()
	return true


func _find_unit_by_operator(operator_id: String) -> UnitState:
	for u in party:
		if u.operator.operator_id == operator_id:
			return u
	return null


## ===================== 存档 =====================

func save_to(path: String) -> void:
	save.version = SaveGame.CURRENT_VERSION
	save.current_map_id = current_map.map_id if current_map else ""
	save.party = []
	for u in party:
		save.party.append(u.to_dict())
	save.active_ids = _active_ids_from_party()
	ResourceSaver.save(save, path)


func load_from(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var loaded: SaveGame = ResourceLoader.load(path) as SaveGame
	if loaded == null or not loaded.is_compatible():
		push_warning("GameState: 存档版本不兼容或为空")
		return false
	save = loaded
	roster = DataFactory.default_roster(true)
	party = []
	for d in save.party:
		var op := find_operator(str(d.get("operator_id", "")))
		if op == null:
			continue
		var u := UnitState.new()
		u.from_dict(d, op)
		party.append(u)
	current_map = DataFactory.camp_manifest() if save.current_map_id == "camp" else DataFactory.box_manifest()
	mode = GameModeDef.Mode.CAMP
	_combat_locked = false
	party_changed.emit()
	return true
