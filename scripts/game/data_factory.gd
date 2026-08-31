class_name DataFactory
extends RefCounted
## 默认编成 / 数据工厂：以 Resource 构建默认干员、技能、道具、遭遇与地图清单。
## 数值为原型调优值（非真实干员数据）。骨架统一复用已验证的 char_249_mlyss(build, 4.3 JSON)。

const SKELETON_BUILD := "res://assets/character/char_249_mlyss/char_249_mlyss_build.tres"
const SKELETON_AMIYA := "res://assets/character/char_002_amiya/char_002_amiya_build.tres"
const SKELETON_CHEN := "res://assets/character/char_010_chen/char_010_chen_build.tres"
const SKELETON_KALTS := "res://assets/character/char_003_kalts/char_003_kalts_build.tres"
const SKELETON_GOPRO := "res://assets/enemy/enemy_1000_gopro/enemy_1000_gopro.tres"
const SKELETON_BIGBO := "res://assets/enemy/enemy_1001_bigbo/enemy_1001_bigbo.tres"

const SkillData := preload("res://scripts/data/skill_data.gd")
const OperatorData := preload("res://scripts/data/operator_data.gd")
const ItemData := preload("res://scripts/data/item_data.gd")
const StatusEffectData := preload("res://scripts/data/status_effect_data.gd")
const EncounterData := preload("res://scripts/data/encounter_data.gd")
const EncounterUnitEntry := preload("res://scripts/data/encounter_unit_entry.gd")
const MapManifest := preload("res://scripts/data/map_manifest.gd")


static func load_skeleton(path: String = SKELETON_BUILD) -> SpineSkeletonDataResource:
	return load(path) as SpineSkeletonDataResource


## ===================== 技能 =====================

static func make_skill(id: String, name: String, desc: String, target_mode: int, effect_id: String,
		effect_params: Dictionary, range_m: float, stamina_cost: float, sp_cost: int,
		cooldown := 0, effect_radius_m := 0.0, restore_condition := SkillData.RestoreCondition.NONE,
		restore_amount := 0) -> SkillData:
	var s := SkillData.new()
	s.skill_id = id
	s.display_name = name
	s.description = desc
	s.target_mode = target_mode
	s.effect_id = effect_id
	s.effect_params = effect_params
	s.range_m = range_m
	s.stamina_cost = stamina_cost
	s.sp_cost = sp_cost
	s.cooldown = cooldown
	s.effect_radius_m = effect_radius_m
	s.restore_condition = restore_condition
	s.restore_amount = restore_amount
	s.animation = "Attack"
	return s


static func make_basic_attack(range_m: float, atk_mult: float, damage_type: String, stamina_cost := 1.0) -> SkillData:
	return make_skill("basic", "普攻", "基础攻击", SkillData.TargetMode.SINGLE_ENEMY,
		"damage", {"atk_mult": atk_mult, "damage_type": damage_type}, range_m, stamina_cost, 0)


## ===================== 干员 =====================

static func make_operator(id: String, name: String, archetype: String, faction: String,
		max_hp: int, atk: int, defense: int, res: int, color: Color, attack_range: float,
		basic: SkillData, skills: Array[SkillData], skeleton: SpineSkeletonDataResource) -> OperatorData:
	var op := OperatorData.new()
	op.operator_id = id
	op.display_name = name
	op.archetype = archetype
	op.faction = faction
	op.max_hp = max_hp
	op.atk = atk
	op.defense = defense
	op.res = res
	op.indicator_color = color
	op.skeleton = skeleton
	op.max_stamina = 6.0
	op.stamina_recover_per_turn = 4.0
	op.max_sp = 20
	op.sp_regen_per_turn = 2
	op.move_stamina_per_meter = 1.0
	op.body_radius = 0.35
	op.basic_attack = basic
	op.skills = skills
	return op


## 默认可出战干员名单（3 名：近卫 / 术师 / 医疗，均复用 build 骨架作占位立绘）。
static func default_roster(with_skeleton: bool = true) -> Array[OperatorData]:
	var skel_guard: SpineSkeletonDataResource = load_skeleton(SKELETON_AMIYA) if with_skeleton else null
	var skel_caster: SpineSkeletonDataResource = load_skeleton(SKELETON_CHEN) if with_skeleton else null
	var skel_medic: SpineSkeletonDataResource = load_skeleton(SKELETON_KALTS) if with_skeleton else null

	var guard := make_operator(
		"op_guard", "干员·锋刃", "近卫", "ally",
		120, 30, 15, 0, Color(0.4, 0.85, 1.0, 0.9), 1.5,
		make_basic_attack(1.5, 1.0, "physical", 1.0),
		[
			make_skill("guard_skill_1", "锋斩", "单体物理斩击", SkillData.TargetMode.SINGLE_ENEMY,
				"damage", {"atk_mult": 1.5, "damage_type": "physical"}, 1.5, 1.0, 4),
			make_skill("guard_skill_2", "横扫", "对近身全部敌人造成物理伤害", SkillData.TargetMode.ALL_ENEMY,
				"damage", {"atk_mult": 0.9, "damage_type": "physical"}, 1.5, 2.0, 6),
			make_skill("guard_skill_3", "战吼", "2 回合内攻击力 +20%", SkillData.TargetMode.SELF,
				"apply_status", {"status": null}, 0.0, 1.0, 3),
		], skel_guard)
	guard.skills[2].effect_params["status"] = make_atk_buff(2, 0.2)

	var caster := make_operator(
		"op_caster", "干员·源石术", "术师", "ally",
		80, 45, 5, 15, Color(0.75, 0.55, 1.0, 0.9), 5.0,
		make_basic_attack(5.0, 1.0, "arts", 1.0),
		[
			make_skill("caster_skill_1", "术弹", "单体法术伤害", SkillData.TargetMode.SINGLE_ENEMY,
				"damage", {"atk_mult": 1.6, "damage_type": "arts"}, 5.0, 1.0, 5),
			make_skill("caster_skill_2", "范围术式", "对目标区域敌人造成法术伤害", SkillData.TargetMode.POINT_AOE,
				"damage", {"atk_mult": 1.0, "damage_type": "arts"}, 5.0, 2.0, 8, 0, 2.0),
			make_skill("caster_skill_3", "紧急疗愈", "治疗一名友方单位", SkillData.TargetMode.SINGLE_ALLY,
				"heal", {"amount": 45.0}, 5.0, 1.0, 3),
		], skel_caster)

	var medic := make_operator(
		"op_medic", "干员·安疗", "医疗", "ally",
		90, 20, 8, 10, Color(0.45, 0.9, 0.55, 0.9), 3.0,
		make_basic_attack(3.0, 1.0, "physical", 1.0),
		[
			make_skill("medic_skill_1", "治疗", "治疗一名友方单位", SkillData.TargetMode.SINGLE_ALLY,
				"heal", {"amount": 40.0}, 3.0, 1.0, 3),
			make_skill("medic_skill_2", "群疗", "治疗范围内全部友方", SkillData.TargetMode.ALL_ALLY,
				"heal", {"amount": 25.0}, 3.0, 2.0, 6),
			make_skill("medic_skill_3", "净化", "清除友方减益", SkillData.TargetMode.SINGLE_ALLY,
				"cleanse", {}, 3.0, 1.0, 2),
		], skel_medic)

	return [guard, caster, medic]


## 默认敌人（2 名：近战 + 术师，faction=enemy，红色指示器）。
static func default_enemies(with_skeleton: bool = true) -> Array[OperatorData]:
	var skel_grunt: SpineSkeletonDataResource = load_skeleton(SKELETON_GOPRO) if with_skeleton else null
	var skel_caster: SpineSkeletonDataResource = load_skeleton(SKELETON_BIGBO) if with_skeleton else null

	var grunt := make_operator(
		"enemy_grunt", "敌·源石虫", "敌人", "enemy",
		90, 22, 12, 0, Color(0.9, 0.3, 0.3, 0.9), 1.5,
		make_basic_attack(1.5, 1.0, "physical", 1.0),
		[
			make_skill("grunt_skill_1", "重击", "单体物理重击", SkillData.TargetMode.SINGLE_ENEMY,
				"damage", {"atk_mult": 1.4, "damage_type": "physical"}, 1.5, 2.0, 4),
		], skel_grunt)
	_set_enemy_anims(grunt)

	var caster_enemy := make_operator(
		"enemy_caster", "敌·大鲍勃", "敌人", "enemy",
		70, 32, 6, 20, Color(0.85, 0.25, 0.6, 0.9), 5.0,
		make_basic_attack(5.0, 1.0, "arts", 1.0),
		[
			make_skill("ecaster_skill_1", "术式", "单体法术伤害", SkillData.TargetMode.SINGLE_ENEMY,
				"damage", {"atk_mult": 1.5, "damage_type": "arts"}, 5.0, 2.0, 5),
		], skel_caster)
	_set_enemy_anims(caster_enemy)

	return [grunt, caster_enemy]


## 敌人骨骼动画名（战斗模型：Idle/Move_Loop/Attack/Die）。
static func _set_enemy_anims(op: OperatorData) -> void:
	op.anim_idle = "Idle"
	op.anim_move = "Move_Loop"
	op.anim_interact = "Idle"
	op.anim_sit = "Idle"
	op.anim_sleep = "Die"
	op.anim_attack = "Attack"
	op.anim_death = "Die"


## ===================== 道具 =====================

static func default_items() -> Array[ItemData]:
	var heal := ItemData.new()
	heal.item_id = "item_medkit"
	heal.display_name = "急救包"
	heal.description = "恢复 40 点生命值"
	heal.effect_id = "heal"
	heal.effect_params = {"amount": 40.0}
	heal.stamina_cost = 0.0
	heal.sp_cost = 0
	heal.stackable = true
	return [heal]


## ===================== 状态效果 =====================

static func make_atk_buff(duration := 2, amount := 0.2) -> StatusEffectData:
	var s := StatusEffectData.new()
	s.status_id = "atk_buff"
	s.display_name = "攻击强化"
	s.duration_turns = duration
	s.atk_modifier = amount
	s.is_debuff = false
	return s


## ===================== 遭遇 / 地图 =====================

static func default_encounter() -> EncounterData:
	var enc := EncounterData.new()
	enc.encounter_id = "enc_box_2v2"
	enc.display_name = "箱庭遭遇战"
	enc.trigger_radius_m = 8.0
	var enemies := default_enemies(true)
	var e0 := EncounterUnitEntry.new()
	e0.operator = enemies[0]
	e0.pos = Vector2(2.0, 0.0)
	var e1 := EncounterUnitEntry.new()
	e1.operator = enemies[1]
	e1.pos = Vector2(2.0, 2.0)
	enc.enemies = [e0, e1]
	return enc


static func camp_manifest() -> MapManifest:
	var m := MapManifest.new()
	m.map_id = "camp"
	m.display_name = "营地"
	m.scene_path = "res://scenes/camp/camp.tscn"
	m.is_camp = true
	m.is_box_map = false
	m.spawn_points = [Vector2(0, 0), Vector2(1, 0)]
	return m


static func box_manifest() -> MapManifest:
	var m := MapManifest.new()
	m.map_id = "box"
	m.display_name = "箱庭地图"
	m.scene_path = "res://scenes/maps/box_map.tscn"
	m.is_camp = false
	m.is_box_map = true
	m.encounter = default_encounter()
	m.spawn_points = [Vector2(-8, 0), Vector2(-8, 1)]
	m.safe_exit_point = Vector2(-10, 0)
	m.camp_map_id = "camp"
	return m


## 默认编队：前 2 名出战，第 3 名候补。
static func default_active_ids() -> Array[String]:
	return ["op_guard", "op_caster"]
