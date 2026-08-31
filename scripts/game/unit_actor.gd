class_name UnitActor
extends Node3D
## 单位表现适配器：把纯运行时状态 UnitState 绑定到 HD2DCharacter 立牌（移动 / 动画 / 选中）。
## HD2DCharacter 仅作为视觉与移动适配器，不承载任何战斗 / 背包 / 编队逻辑。

const HD2DCharacter := preload("res://scripts/character/hd2d_character.gd")
const CHARACTER_SCENE := preload("res://scenes/character/hd2d_character.tscn")
const UnitState := preload("res://scripts/game/unit_state.gd")
const CharacterState := preload("res://scripts/character/character_state.gd")

## 战斗动画 → build 变体可用动画的回退映射（build 无 Attack/Die/Hit）。
const ANIM_MAP := {
	"idle": ["Relax"],
	"move": ["Move"],
	"attack": ["Interact", "Relax"],
	"hit": ["Interact", "Relax"],
	"death": ["Sleep", "Relax"],
	"interact": ["Interact"],
}

var state: UnitState
var character: HD2DCharacter
var _selection_ring: MeshInstance3D
var _selected := false
var _faction_glow := Color(1.0, 0.84, 0.2, 1.0)


func _ready() -> void:
	add_to_group("unit_actor")


## 绑定状态并创建立牌。
func setup(unit_state: UnitState) -> void:
	state = unit_state
	character = CHARACTER_SCENE.instantiate()
	character.name = "Character"
	add_child(character)
	character.show_status_panel = false
	if state.operator and state.operator.skeleton:
		character.set_skeleton_data(state.operator.skeleton)
	character.identity_name = state.operator.display_name if state.operator else "?"
	_apply_animation_mapping()
	_apply_faction_visuals()
	_build_selection_ring()
	sync_position()
	state.changed.connect(_on_state_changed)


## 按骨骼注入状态机动画映射（敌人骨骼无 Relax/Move 等，覆盖为 Idle/Move_Loop/Attack/Die）。
func _apply_animation_mapping() -> void:
	if state == null or state.operator == null or character == null:
		return
	var op := state.operator
	character.set_animation_map({
		CharacterState.Id.IDLE: op.anim_idle,
		CharacterState.Id.MOVE: op.anim_move,
		CharacterState.Id.INTERACT: op.anim_interact,
		CharacterState.Id.SIT: op.anim_sit,
		CharacterState.Id.SLEEP: op.anim_sleep,
	})
	if state.faction() == "enemy":
		character.set_idle_interact_enabled(false)


func _apply_faction_visuals() -> void:
	if state == null or state.operator == null:
		return
	character.indicator_color = state.operator.indicator_color
	if state.faction() == "enemy":
		_faction_glow = Color(1.0, 0.3, 0.3, 1.0)
		character.set_glow_color(_faction_glow)
	else:
		_faction_glow = Color(1.0, 0.84, 0.2, 1.0)
		character.set_glow_color(_faction_glow)


## 脚底选中环（每个单位一个，非逐格）。
func _build_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "SelectionRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	_selection_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.84, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.84, 0.2)
	mat.emission_energy_multiplier = 1.5
	mat.disable_receive_shadows = true
	_selection_ring.material_override = mat
	_selection_ring.rotation_degrees = Vector3(90, 0, 0)
	_selection_ring.position.y = 0.03
	add_child(_selection_ring)
	_selection_ring.visible = false


func set_selected(on: bool) -> void:
	_selected = on
	if _selection_ring:
		_selection_ring.visible = on


func is_selected() -> bool:
	return _selected


## 同步 3D 位置到权威世界坐标。
func sync_position() -> void:
	if state == null or character == null:
		return
	character.global_position = Vector3(state.pos.x, 0.0, state.pos.y)


## 平滑移动到目标世界位置（XZ 米坐标）。
func move_to(pos: Vector2, arrive: Callable = Callable()) -> void:
	var target := Vector3(pos.x, character.global_position.y, pos.y)
	character.move_to(target, arrive)


func set_facing_to(pos: Vector3) -> void:
	if character:
		character.set_facing_to(pos)


func play_idle() -> void:
	_play_candidates([_op_anim("anim_idle", "Relax"), "Relax"])


func play_move() -> void:
	_play_candidates([_op_anim("anim_move", "Move"), "Move"])


func play_attack() -> void:
	_play_candidates([_op_anim("anim_attack", "Attack"), "Interact", "Relax"])


func play_hit() -> void:
	_play_candidates([_op_anim("anim_attack", "Attack"), "Interact", "Relax"])


func play_death() -> void:
	_play_candidates([_op_anim("anim_death", "Die"), "Sleep", "Relax"])


func play_interact() -> void:
	_play_candidates([_op_anim("anim_interact", "Interact"), "Relax"])


## 选中瞬间播放一次 Interact（走状态机一次性状态，播完自动回 IDLE）。
func play_select_interact() -> void:
	if character != null:
		character.set_state(CharacterState.Id.INTERACT, CharacterState.Id.IDLE)


## 标记是否为队长（主控）。队长常亮脚底选中环。
func set_leader(on: bool) -> void:
	if _selection_ring:
		_selection_ring.visible = on or _selected


## 读取干员动画名（缺失回退到 build 变体约定名）。
func _op_anim(field: String, fallback: String) -> String:
	if state != null and state.operator != null:
		var v: String = state.operator.get(field)
		if v != "":
			return v
	return fallback


## 在候选动画名中取第一个存在的播放；全部缺失时回退 Relax（不崩溃）。
func _play_candidates(candidates: Array, loop := false) -> void:
	if character == null:
		return
	for anim in candidates:
		if _has_animation(anim):
			character.play_animation(anim, loop)
			return
	character.play_animation("Relax", loop)


## 查询骨骼是否包含指定动画（缺失时明确回退，不崩溃）。
func _has_animation(anim: String) -> bool:
	if character == null:
		return false
	var sprite = character.spine_sprite
	if sprite == null:
		return false
	var skeleton = sprite.get_skeleton()
	if skeleton == null:
		return false
	var data = skeleton.get_data()
	if data == null:
		return false
	return data.find_animation(anim) != null


func _on_state_changed() -> void:
	if state == null:
		return
	if not state.alive:
		play_death()
		if _selection_ring:
			_selection_ring.visible = false
