class_name GameController
extends Node3D
## 游戏控制器：模式管理、地图加载、单位生成、实时探索与回合战斗编排、UI 接线。
## 只订阅状态、发送命令；战斗规则全部由 ActionPipeline / TurnManager 承担。

const RpgCamera := preload("res://scripts/camera/rpg_camera.gd")
const OcclusionShatter := preload("res://scripts/camera/occlusion_shatter.gd")
const PlayerController := preload("res://scripts/player/player_controller.gd")
const UnitActor := preload("res://scripts/game/unit_actor.gd")
const UnitState := preload("res://scripts/game/unit_state.gd")
const ActionPipeline := preload("res://scripts/game/action_pipeline.gd")
const TurnManager := preload("res://scripts/game/turn_manager.gd")
const DataFactory := preload("res://scripts/game/data_factory.gd")
const GameModeDef := preload("res://scripts/game/game_mode.gd")
const MapManifest := preload("res://scripts/data/map_manifest.gd")
const EncounterData := preload("res://scripts/data/encounter_data.gd")
const SkillData := preload("res://scripts/data/skill_data.gd")
const ItemData := preload("res://scripts/data/item_data.gd")
const CombatHud := preload("res://scripts/ui/combat_hud.gd")
const InventoryPanel := preload("res://scripts/ui/inventory_panel.gd")
const FormationPanel := preload("res://scripts/ui/formation_panel.gd")
const OperatorPanel := preload("res://scripts/ui/operator_panel.gd")
const StartScreen := preload("res://scripts/ui/start_screen.gd")

var _map_host: Node3D
var _camera_focus: Node3D
var _camera: Camera3D

var _units: Array = []            # Array[UnitActor]
var _ally_actors: Array = []
var _enemy_actors: Array = []

var _player_controller: Node
var _main_index := 0

var _hud: CombatHud
var _inventory: InventoryPanel
var _formation: FormationPanel
var _operator_panel: OperatorPanel
var _start_screen: StartScreen

var _turn_manager: TurnManager
var _active_actor: UnitActor = null
var _pending_slot := -1           # 0 普攻 / 1..3 技能 / 4 道具
var _move_budget := 0.0           # 当前主控单位移动半径（米）
var _move_overlay: MeshInstance3D
var _tactical_active := false


func _ready() -> void:
	_build_world()
	_build_ui()
	InputRouter.interact.connect(_on_interact)
	InputRouter.toggle_inventory.connect(_on_toggle_inventory)
	InputRouter.toggle_operator.connect(_on_toggle_operator)
	InputRouter.toggle_tactical.connect(_on_toggle_tactical)
	InputRouter.end_turn.connect(_on_end_turn)
	InputRouter.retreat.connect(_on_retreat)
	InputRouter.cycle_unit.connect(_on_cycle_unit)
	GameState.mode_changed.connect(_on_mode_changed)
	GameState.map_requested.connect(_on_map_requested)
	_start_screen.show_screen()
	# 自动开始：开始界面作为开场闪屏，约 1.2 秒后自动进入营地（按钮仍可手动点击）
	get_tree().create_timer(1.2).timeout.connect(_auto_start)


func _auto_start() -> void:
	if GameState.party.is_empty():
		_on_start()


## ===================== 世界 / 相机 / 光照 =====================

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.24, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.add_to_group("main_light")
	var lb := Basis(
		Vector3(0.86601907, -0.3535631, 0.3535593),
		Vector3(0.0, 0.70710295, 0.7071106),
		Vector3(-0.500011, -0.61237127, 0.61236465))
	light.transform = Transform3D(lb, Vector3(0, 5, 0))
	light.shadow_enabled = true
	add_child(light)

	_camera_focus = Node3D.new()
	_camera_focus.name = "CameraFocus"
	_camera_focus.position = Vector3(0, 0.5, 0)
	add_child(_camera_focus)

	_camera = RpgCamera.new()
	_camera.name = "Camera3D"
	_camera.focus_path = _camera_focus.get_path()
	# 预设一个良好的初始轨道位置，让 _ready 的 _rebuild_orbit_from_camera 反推出俯视角度
	_camera.position = Vector3(4.63, 5.09, 4.63)
	add_child(_camera)

	var occl := OcclusionShatter.new()
	occl.name = "OcclusionShatter"
	_camera.add_child(occl)

	_map_host = Node3D.new()
	_map_host.name = "MapHost"
	add_child(_map_host)


## ===================== UI =====================

func _build_ui() -> void:
	_hud = CombatHud.new()
	add_child(_hud)
	_hud.visible = false
	_hud.slot_pressed.connect(_on_slot_pressed)
	_hud.end_turn_pressed.connect(_on_end_turn)
	_hud.retreat_pressed.connect(_on_retreat)
	_hud.return_camp_pressed.connect(_on_return_camp)
	_hud.tactical_pressed.connect(_on_enter_tactical)
	_hud.end_tactical_pressed.connect(_on_end_tactical)
	_hud.depart_pressed.connect(_on_depart_button)
	_hud.slot_rebound.connect(_on_slot_rebound)
	_hud.toggle_action_bar_pressed.connect(func(): pass)

	_inventory = InventoryPanel.new()
	add_child(_inventory)
	_inventory.use_item_requested.connect(_on_inventory_use_item)

	_formation = FormationPanel.new()
	add_child(_formation)
	_formation.ids_changed.connect(_on_formation_ids_changed)

	_operator_panel = OperatorPanel.new()
	add_child(_operator_panel)

	_start_screen = StartScreen.new()
	add_child(_start_screen)
	_start_screen.start_pressed.connect(_on_start)


## ===================== 开始 / 地图加载 =====================

func _on_start() -> void:
	_start_screen.visible = false
	GameState.new_game()


func _on_map_requested(manifest: MapManifest) -> void:
	_clear_map()
	var scene := load(manifest.scene_path) as PackedScene
	if scene:
		_map_host.add_child(scene.instantiate())
	_spawn_party(manifest)
	if manifest.is_box_map and manifest.encounter:
		_spawn_enemies(manifest.encounter)
	_setup_realtime_controller()
	_wire_map_interactables(manifest)
	_hud.set_quest(_quest_for(manifest))
	_hud.update_minimap(_ally_actors, _enemy_actors, Rect2(-12, -12, 24, 24))
	_hud.visible = true
	_hud.set_mode_ui(GameState.mode)
	_update_mode_text()
	_snap_camera_to_main()
	_update_leader()


## 模式标签显示当前地图名 + 模式。
func _update_mode_text() -> void:
	var map_name := GameState.current_map.display_name if GameState.current_map else "—"
	_hud.set_mode_text("%s · %s" % [map_name, GameModeDef.name_of(GameState.mode)])


func _process(_delta: float) -> void:
	# 实时探索：遭遇警戒范围触发战斗
	if GameState.mode != GameModeDef.Mode.REALTIME:
		return
	if GameState.current_map == null or not GameState.current_map.is_box_map:
		return
	if GameState.current_map.encounter == null:
		return
	if GameState.is_encounter_blocked():
		return  # 撤退宽限期内不触发遭遇，让玩家跑出警戒圈
	var trigger := GameState.current_map.encounter.trigger_radius_m
	if _ally_actors.is_empty():
		return
	var main: UnitActor = _ally_actors[_main_index]
	for e in _enemy_actors:
		if Vector2(main.global_position.x - e.global_position.x, main.global_position.z - e.global_position.z).length() <= trigger:
			GameState.enter_combat()
			return


func _wire_map_interactables(manifest: MapManifest) -> void:
	var fac := get_tree().get_first_node_in_group("formation_facility")
	if fac and fac.has_signal("interacted") and not fac.interacted.is_connected(_on_formation_facility):
		fac.interacted.connect(_on_formation_facility)
	var depart := get_tree().get_first_node_in_group("depart")
	if depart and depart.has_signal("interacted") and not depart.interacted.is_connected(_on_depart):
		depart.interacted.connect(_on_depart)
	var exit := get_tree().get_first_node_in_group("safe_exit")
	if exit and exit.has_signal("interacted") and not exit.interacted.is_connected(_on_safe_exit):
		exit.interacted.connect(_on_safe_exit)


func _on_formation_facility(_character: Node3D) -> void:
	_formation.open(GameState.roster, _active_ids())


func _on_depart(_character: Node3D) -> void:
	_depart_to_box()


func _on_depart_button() -> void:
	_depart_to_box()


func _depart_to_box() -> void:
	GameState.set_mode(GameModeDef.Mode.REALTIME)
	GameState.request_map(DataFactory.box_manifest())


func _on_safe_exit(_character: Node3D) -> void:
	GameState.request_return_camp()


func _active_ids() -> Array[String]:
	var out: Array[String] = []
	for u in GameState.party:
		out.append(u.operator.operator_id)
	return out


func _clear_map() -> void:
	for c in _map_host.get_children():
		c.queue_free()
	_units.clear()
	_ally_actors.clear()
	_enemy_actors.clear()
	_clear_move_overlay()
	_active_actor = null
	_pending_slot = -1
	if _turn_manager != null:
		if _turn_manager.active:
			_turn_manager.force_finish("aborted")
		_turn_manager = null
	if _player_controller:
		_player_controller.queue_free()
		_player_controller = null


func _spawn_party(manifest: MapManifest) -> void:
	for i in GameState.party.size():
		var u: UnitState = GameState.party[i]
		var spawn := manifest.spawn_points[i] if i < manifest.spawn_points.size() else Vector2.ZERO
		u.pos = spawn
		var actor := UnitActor.new()
		actor.name = "Ally_" + u.unit_id
		_map_host.add_child(actor)
		actor.setup(u)
		_units.append(actor)
		_ally_actors.append(actor)


func _spawn_enemies(enc: EncounterData) -> void:
	for entry in enc.enemies:
		var u := UnitState.new()
		u.bind_operator(entry.operator, entry.operator.operator_id)
		u.pos = entry.pos
		var actor := UnitActor.new()
		actor.name = "Enemy_" + entry.operator.operator_id
		_map_host.add_child(actor)
		actor.setup(u)
		_units.append(actor)
		_enemy_actors.append(actor)


func _setup_realtime_controller() -> void:
	if _ally_actors.is_empty():
		return
	if _player_controller != null:
		_player_controller.queue_free()
		_player_controller = null
	var pc := PlayerController.new()
	pc.name = "PlayerController"
	# 必须在 add_child 之前设置路径：PlayerController._ready 依赖这些路径解析角色与导航区域
	pc.character_path = _ally_actors[_main_index].character.get_path()
	var nav := get_tree().get_first_node_in_group("navigation_region")
	pc.navigation_region_path = nav.get_path() if nav else NodePath()
	_map_host.add_child(pc)
	_player_controller = pc
	_apply_player_controller_active()


func _apply_player_controller_active() -> void:
	if _player_controller == null:
		return
	var active := GameState.mode in [GameModeDef.Mode.CAMP, GameModeDef.Mode.REALTIME]
	_player_controller.set_process_unhandled_input(active)
	_player_controller.set_process(active)


func _snap_camera_to_main() -> void:
	if _ally_actors.is_empty() or _camera_focus == null:
		return
	var a: UnitActor = _ally_actors[_main_index]
	_camera_focus.global_position = a.global_position + Vector3(0, 0.5, 0)
	if _camera:
		_camera.reset_focus_ground()


func _quest_for(manifest: MapManifest) -> String:
	if manifest.is_camp:
		return "当前：营地\n任务：点击『出发』进入箱庭地图，击败 2 名敌人。"
	return "当前：箱庭地图\n任务：接近并击败 2 名敌人，然后从安全入口返回营地。"


## ===================== 模式切换 =====================

func _on_mode_changed(_prev: int, cur: int) -> void:
	_hud.set_mode_ui(cur)
	_update_mode_text()
	_apply_player_controller_active()
	if cur == GameModeDef.Mode.COMBAT_TURN:
		_start_combat()
	elif cur == GameModeDef.Mode.REALTIME:
		_tactical_active = false
		_clear_move_overlay()
		_pending_slot = -1
	elif cur == GameModeDef.Mode.TACTICAL_TURN:
		_tactical_active = true
		_begin_move_selection(_ally_actors[_main_index])


func _on_toggle_tactical() -> void:
	if GameState.mode == GameModeDef.Mode.REALTIME:
		GameState.set_mode(GameModeDef.Mode.TACTICAL_TURN)
	elif GameState.mode == GameModeDef.Mode.TACTICAL_TURN:
		_recover_party_stamina()
		GameState.set_mode(GameModeDef.Mode.REALTIME)


func _on_enter_tactical() -> void:
	if GameState.mode == GameModeDef.Mode.REALTIME:
		GameState.set_mode(GameModeDef.Mode.TACTICAL_TURN)


func _on_end_tactical() -> void:
	if GameState.mode == GameModeDef.Mode.TACTICAL_TURN:
		_recover_party_stamina()
		GameState.set_mode(GameModeDef.Mode.REALTIME)


func _recover_party_stamina() -> void:
	for u in GameState.party:
		u.recover_turn_start()


## ===================== 战斗 =====================

func _start_combat() -> void:
	var allies := []
	for a in _ally_actors:
		allies.append(a.state)
	var enemies := []
	for e in _enemy_actors:
		enemies.append(e.state)
	_turn_manager = TurnManager.new()
	_turn_manager.turn_started.connect(_on_turn_started)
	_turn_manager.turn_ended.connect(_on_turn_ended)
	_turn_manager.battle_finished.connect(_on_battle_finished)
	_turn_manager.start_battle(allies, enemies)


func _on_turn_started(unit: UnitState, events: Array) -> void:
	_hud.set_turn_text("第 %d 回合" % _turn_manager.round_number)
	var actor := _actor_for(unit)
	if not events.is_empty():
		# 回合开始结算事件（dot 伤害 / 死亡）：播放表现并刷新面板
		if actor:
			_play_events(events, actor)
		_hud.set_current_unit(unit)
	_snap_camera_to_actor(actor)
	if unit.faction() == "ally":
		_begin_ally_turn(actor)
	else:
		_begin_enemy_turn(actor)


func _on_turn_ended(_unit: UnitState) -> void:
	if _active_actor:
		_active_actor.set_selected(false)
	_active_actor = null
	_pending_slot = -1
	_clear_move_overlay()


func _begin_ally_turn(actor: UnitActor) -> void:
	_active_actor = actor
	actor.set_selected(true)
	_pending_slot = -1
	_hud.set_active_slot(-1)
	_hud.set_current_unit(actor.state)
	_hud.set_slots(_slots_for(actor))
	_begin_move_selection(actor)


func _slots_for(actor: UnitActor) -> Array[String]:
	var names: Array[String] = []
	for i in UnitState.SLOT_COUNT_MAX:
		names.append(actor.state.slot_display_name(i))
	return names


func _begin_enemy_turn(actor: UnitActor) -> void:
	_hud.set_current_unit(actor.state)
	_run_enemy_ai(actor)


func _run_enemy_ai(actor: UnitActor) -> void:
	await get_tree().create_timer(0.5).timeout
	if _turn_manager == null or not _turn_manager.active:
		return
	var state: UnitState = actor.state
	if not state.alive:
		_turn_manager.end_turn()
		return
	var target := _nearest_ally(state)
	if target == null:
		_turn_manager.end_turn()
		return
	var ctx := _combat_context()
	if Vector2(state.pos - target.pos).length() <= state.operator.basic_attack.range_m + 0.0001:
		var atk := ActionPipeline.ActionDef.new()
		atk.kind = "attack"
		atk.actor = state
		atk.targets = [target]
		var r := ActionPipeline.execute(atk, ctx)
		_play_events(r.events, actor)
	else:
		if _move_toward(state, target, ctx):
			await get_tree().create_timer(0.4).timeout
			var atk := ActionPipeline.ActionDef.new()
			atk.kind = "attack"
			atk.actor = state
			atk.targets = [target]
			var r := ActionPipeline.execute(atk, ctx)
			_play_events(r.events, actor)
	_turn_manager.end_turn()


func _move_toward(state: UnitState, target: UnitState, ctx: Dictionary) -> bool:
	var budget := state.stamina / maxf(state.operator.move_stamina_per_meter, 0.0001)
	var to := target.pos - state.pos
	var dist := to.length()
	if dist <= 0.0001:
		return false
	# 停在目标体积外（双方半径和 + 余量），避免把落点选到目标身上被阻挡拒绝
	var min_gap := state.operator.body_radius + target.operator.body_radius + 0.01
	var travel := minf(budget, maxf(dist - min_gap, 0.0))
	if travel <= 0.0001:
		return false
	var dest := state.pos + to / dist * travel
	var action := ActionPipeline.ActionDef.new()
	action.kind = "move"
	action.actor = state
	action.target_pos = dest
	var r := ActionPipeline.execute(action, ctx)
	if r.ok:
		_actor_for(state).move_to(dest)
	return r.ok


func _nearest_ally(state: UnitState) -> UnitState:
	var best: UnitState = null
	var best_d := INF
	for a in _ally_actors:
		var u: UnitState = a.state
		if not u.alive:
			continue
		var d := Vector2(state.pos - u.pos).length()
		if d < best_d:
			best_d = d
			best = u
	return best


func _on_battle_finished(result: String) -> void:
	_hud.set_turn_text("")
	if _active_actor:
		_active_actor.set_selected(false)
	_active_actor = null
	_pending_slot = -1
	_clear_move_overlay()
	if result == "victory":
		for e in _enemy_actors:
			e.queue_free()
		_enemy_actors.clear()
		_units = _ally_actors.duplicate()
		_hud.set_quest("任务完成：击败敌人。前往安全入口返回营地。")
	GameState.resolve_combat(result)


## ===================== 玩家输入（战斗 / 战术） =====================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 实时/营地：左键点角色 → 切换主控（队长）并播放一次 Interact
		if GameState.mode in [GameModeDef.Mode.CAMP, GameModeDef.Mode.REALTIME]:
			_handle_realtime_select()
			return
	var in_combat := GameState.mode == GameModeDef.Mode.COMBAT_TURN
	var in_tactical := GameState.mode == GameModeDef.Mode.TACTICAL_TURN
	if not (in_combat or in_tactical):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_combat_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_pending_slot = -1
			_hud.set_active_slot(-1)


func _handle_realtime_select() -> void:
	var hit := _raycast_unit()
	if hit.is_empty():
		return
	var actor := _find_unit_actor(hit.get("collider") as Node)
	if actor == null or not _ally_actors.has(actor):
		return
	var idx := _ally_actors.find(actor)
	if idx >= 0 and idx != _main_index:
		_main_index = idx
		_update_leader()
		_setup_realtime_controller()
		_snap_camera_to_main()
	actor.play_select_interact()


## 队长（主控）高亮：只有当前主控角色常亮选中环。
func _update_leader() -> void:
	for i in _ally_actors.size():
		_ally_actors[i].set_leader(i == _main_index)


func _handle_combat_click() -> void:
	if GameState.mode == GameModeDef.Mode.COMBAT_TURN:
		if _turn_manager == null or not _turn_manager.is_player_turn() or _active_actor == null:
			return
	else:
		if not _tactical_active or _active_actor == null:
			return
	var hit := _raycast_unit()
	if not hit.is_empty():
		var actor := _find_unit_actor(hit.get("collider") as Node)
		if actor != null:
			_on_click_unit(actor)
			return
	# 地面
	var ground := _raycast_ground()
	if not ground.is_empty():
		var pos: Vector3 = ground.get("position")
		_on_click_pos(Vector2(pos.x, pos.z))


func _on_click_unit(actor: UnitActor) -> void:
	if GameState.mode == GameModeDef.Mode.TACTICAL_TURN:
		return  # 战术微操不选中单位，只移动
	var me := _active_actor
	if _pending_slot >= 0:
		var a := _pending_action()
		if a.get("kind", "") == "skill" and (a["skill"] as SkillData).target_mode == SkillData.TargetMode.POINT_AOE:
			_execute_pending(null, actor.state.pos)  # 以单位位置为中心施放 AoE
		else:
			_execute_pending(actor.state, Vector2.ZERO)  # 允许对自己用道具/治疗
		return
	if actor == me:
		return
	if actor.state.faction() == "enemy":
		_try_basic_attack(actor.state)


func _on_click_pos(pos: Vector2) -> void:
	if GameState.mode == GameModeDef.Mode.TACTICAL_TURN:
		_try_tactical_move(pos)
		return
	if _pending_slot >= 0:
		var a := _pending_action()
		if a.get("kind", "") == "skill" and (a["skill"] as SkillData).target_mode == SkillData.TargetMode.POINT_AOE:
			_execute_pending(null, pos)
		return
	_try_combat_move(pos)


func _on_slot_pressed(index: int) -> void:
	if GameState.mode != GameModeDef.Mode.COMBAT_TURN or _active_actor == null:
		return
	var names := _slots_for(_active_actor)
	if index >= names.size() or names[index] == "":
		return
	_pending_slot = index
	_hud.set_active_slot(index)
	var a := _pending_action()
	if a.is_empty():
		_cancel_pending()
		return
	if a["kind"] == "item":
		# 道具：默认对自己使用（点选友方可切换目标）
		_execute_pending(_active_actor.state, Vector2.ZERO)
		return
	if a["kind"] == "skill":
		# 自身 / 全敌 / 全友目标技能：无需点选，立即结算
		match (a["skill"] as SkillData).target_mode:
			SkillData.TargetMode.SELF, SkillData.TargetMode.ALL_ENEMY, SkillData.TargetMode.ALL_ALLY:
				_execute_pending(null, Vector2.ZERO)


func _pending_action() -> Dictionary:
	if _active_actor == null:
		return {}
	return _active_actor.state.resolve_slot(_pending_slot)


func _execute_pending(target: UnitState, pos: Vector2) -> void:
	if _active_actor == null:
		return
	var me: UnitState = _active_actor.state
	var ctx := _combat_context()
	var a := _pending_action()
	if a.is_empty():
		_cancel_pending()
		return
	var action := ActionPipeline.ActionDef.new()
	action.actor = me
	match a["kind"]:
		"attack":
			action.kind = "attack"
			action.targets = [target] if target != null else []
		"skill":
			action.kind = "skill"
			action.skill = a["skill"]
			action.targets = [target] if target != null else []
			action.target_pos = pos
		"item":
			action.kind = "item"
			action.item = a["item"]
			action.targets = [target if target != null and not me.is_enemy_of(target) else me]
	var r := ActionPipeline.execute(action, ctx)
	if r.ok:
		_play_events(r.events, _active_actor)
		_hud.set_current_unit(me)
	_cancel_pending()


func _try_basic_attack(target: UnitState) -> void:
	var me: UnitState = _active_actor.state
	var action := ActionPipeline.ActionDef.new()
	action.kind = "attack"
	action.actor = me
	action.targets = [target]
	var r := ActionPipeline.execute(action, _combat_context())
	if r.ok:
		_play_events(r.events, _active_actor)
		_hud.set_current_unit(me)


func _try_combat_move(pos: Vector2) -> void:
	var me: UnitState = _active_actor.state
	var action := ActionPipeline.ActionDef.new()
	action.kind = "move"
	action.actor = me
	action.target_pos = pos
	var r := ActionPipeline.execute(action, _combat_context())
	if r.ok:
		_active_actor.move_to(pos)
		_hud.set_current_unit(me)
		_begin_move_selection(_active_actor)


func _try_tactical_move(pos: Vector2) -> void:
	var me: UnitState = _active_actor.state
	var action := ActionPipeline.ActionDef.new()
	action.kind = "move"
	action.actor = me
	action.target_pos = pos
	var r := ActionPipeline.execute(action, _combat_context())
	if r.ok:
		_active_actor.move_to(pos)
		_begin_move_selection(_active_actor)


func _cancel_pending() -> void:
	_pending_slot = -1
	_hud.set_active_slot(-1)


## 动作槽重绑定：把某个动作键（attack/skill:N/item/空）绑到指定槽位。
func _on_slot_rebound(slot_index: int, action_key: String) -> void:
	if _active_actor == null:
		return
	if slot_index < 0 or slot_index >= _active_actor.state.slot_bindings.size():
		return
	# 同一动作不可同时绑到两个槽（先解绑旧槽）
	for i in _active_actor.state.slot_bindings.size():
		if _active_actor.state.slot_bindings[i] == action_key and action_key != "":
			_active_actor.state.slot_bindings[i] = ""
	_active_actor.state.slot_bindings[slot_index] = action_key
	_hud.set_slots(_slots_for(_active_actor))


## ===================== 移动范围可视化 =====================

func _begin_move_selection(actor: UnitActor) -> void:
	if actor == null or actor.state == null:
		return
	_active_actor = actor
	var state: UnitState = actor.state
	_move_budget = state.stamina / maxf(state.operator.move_stamina_per_meter, 0.0001)
	_build_move_overlay()


func _build_move_overlay() -> void:
	if _move_overlay:
		_move_overlay.queue_free()
		_move_overlay = null
	if _move_budget <= 0.0 or _active_actor == null:
		return
	var r := _move_budget
	var c := _active_actor.state.pos
	var seg := 64
	var verts := PackedVector3Array()
	verts.append(Vector3(c.x, 0.02, c.y))
	for i in seg:
		var a := TAU * i / seg
		verts.append(Vector3(c.x + cos(a) * r, 0.02, c.y + sin(a) * r))
	var indices := PackedInt32Array()
	for i in seg:
		indices.append(0)
		indices.append(i + 1)
		indices.append((i + 1) % seg + 1)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 1.0, 0.9, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	_move_overlay = MeshInstance3D.new()
	_move_overlay.name = "MoveOverlay"
	_move_overlay.mesh = mesh
	_move_overlay.material_override = mat
	_move_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_map_host.add_child(_move_overlay)


func _clear_move_overlay() -> void:
	if _move_overlay:
		_move_overlay.queue_free()
		_move_overlay = null
	_move_budget = 0.0


## ===================== 结束回合 / 撤退 / 返营 / 交互 =====================

func _on_end_turn() -> void:
	if GameState.mode == GameModeDef.Mode.COMBAT_TURN and _turn_manager and _turn_manager.is_player_turn():
		_turn_manager.end_turn()


func _on_retreat() -> void:
	if GameState.mode == GameModeDef.Mode.COMBAT_TURN and _turn_manager and _turn_manager.is_player_turn():
		_turn_manager.retreat()


func _on_return_camp() -> void:
	GameState.request_return_camp()


func _on_interact() -> void:
	if _player_controller == null or not _player_controller.has_method("get_selected"):
		return
	var sel = _player_controller.get_selected()
	if sel != null and sel.has_method("interact"):
		sel.interact(_ally_actors[_main_index].character if not _ally_actors.is_empty() else null)


func _on_cycle_unit() -> void:
	if GameState.mode not in [GameModeDef.Mode.CAMP, GameModeDef.Mode.REALTIME]:
		return
	if _ally_actors.size() < 2:
		return
	_main_index = (_main_index + 1) % _ally_actors.size()
	_update_leader()
	_setup_realtime_controller()
	_snap_camera_to_main()


## ===================== 背包 / 编队 =====================

func _on_toggle_inventory() -> void:
	if _inventory.visible:
		_inventory.visible = false
	else:
		_inventory.open(GameState.party)


func _on_toggle_operator() -> void:
	if _operator_panel.visible:
		_operator_panel.visible = false
	else:
		_operator_panel.open(GameState.roster)


func _on_inventory_use_item(unit_id: String, item_id: String) -> void:
	# 背包"使用"仅作为命令下发：战斗中且为该单位回合时执行道具动作
	if GameState.mode != GameModeDef.Mode.COMBAT_TURN:
		return
	var unit: UnitState = GameState.get_unit(unit_id)
	if unit == null or _turn_manager == null or _turn_manager.active_unit != unit:
		return
	var item: ItemData = null
	for it in DataFactory.default_items():
		if it.item_id == item_id:
			item = it
			break
	if item == null:
		return
	var action := ActionPipeline.ActionDef.new()
	action.kind = "item"
	action.actor = unit
	action.item = item
	action.targets = [unit]
	var r := ActionPipeline.execute(action, _combat_context())
	if r.ok:
		_play_events(r.events, _actor_for(unit))
		_hud.set_current_unit(unit)


func _on_formation_ids_changed(ids: Array[String]) -> void:
	GameState.set_party_ids(ids)


## ===================== 工具 =====================

func _combat_context() -> Dictionary:
	var units := []
	for a in _units:
		units.append(a.state)
	return {"units": units, "bounds": _bounds()}


func _bounds() -> Rect2:
	return Rect2(-12, -12, 24, 24)


func _actor_for(state: UnitState) -> UnitActor:
	for a in _units:
		if a.state == state:
			return a
	return null


func _snap_camera_to_actor(actor: UnitActor) -> void:
	if actor != null and _camera_focus:
		_camera_focus.global_position = actor.global_position + Vector3(0, 0.5, 0)


func _raycast_unit() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 1000.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = 2
	return get_world_3d().direct_space_state.intersect_ray(q)


func _raycast_ground() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 1000.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(q)


func _find_unit_actor(node: Node) -> UnitActor:
	var n := node
	while n != null:
		if n is UnitActor:
			return n
		n = n.get_parent()
	return null


func _play_events(events: Array, actor: UnitActor) -> void:
	for ev in events:
		match ev.get("kind", ""):
			"move":
				pass
			"damage", "dot":
				var target: UnitState = ev.get("target")
				var ta := _actor_for(target)
				if ta:
					ta.play_hit()
			"death":
				var t2: UnitState = ev.get("target")
				var ta2 := _actor_for(t2)
				if ta2:
					ta2.play_death()
			"action_cast":
				if actor:
					actor.play_attack()
