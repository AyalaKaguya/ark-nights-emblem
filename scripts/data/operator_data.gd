class_name OperatorData
extends Resource
## 干员数据：明日方舟式基础属性 + 本项目适配层（体力 / 共享技力 / 米制移动）。
## 纯静态数据，不含运行时状态（见 UnitState）。

const SkillData := preload("res://scripts/data/skill_data.gd")

## 稳定 id（存档 / 编队 / 绑定用）。
@export var operator_id := ""
@export var display_name := "干员"
@export var archetype := "近卫"
## 立牌骨骼（build 变体：Relax/Move/Interact/Sit/Sleep；front/back 变体含 Attack/Die）。
@export var skeleton: SpineSkeletonDataResource

@export_group("明日方舟式基础属性")
@export var max_hp := 100
@export var atk := 20
@export var defense := 10
@export var res := 0
## 攻击间隔（秒），用于表现层攻击节奏。
@export_range(0.1, 10.0, 0.1) var attack_interval := 1.6

@export_group("适配层：体力 / 技力 / 移动")
@export_range(0.0, 10.0) var max_stamina := 6.0
@export_range(0.0, 10.0) var stamina_recover_per_turn := 4.0
@export_range(0, 999) var max_sp := 20
@export_range(0, 99) var sp_regen_per_turn := 2
## 移动体力消耗（体力 / 米），数据化。默认 1.0。
@export_range(0.0, 10.0, 0.1) var move_stamina_per_meter := 1.0
## 碰撞半径（米），决定 0.1m 子格占用数量。
@export_range(0.1, 2.0, 0.05) var body_radius := 0.35

@export_group("编成")
## 阵营："ally" / "enemy"。
@export var faction := "ally"
## 脚底指示器颜色（区分单位）。
@export var indicator_color := Color(0.95, 0.95, 0.95, 0.9)
## 普攻：复用 SkillData 结构，消耗单独配置。
@export var basic_attack: SkillData
## 最多三个技能。
@export var skills: Array[SkillData] = []

@export_group("动画映射")
## 骨骼实际动画名（build 变体默认 Relax/Move/Interact/Sit/Sleep；敌人为 Idle/Move_Loop/Attack/Die）。
@export var anim_idle := "Relax"
@export var anim_move := "Move"
@export var anim_interact := "Interact"
@export var anim_sit := "Sit"
@export var anim_sleep := "Sleep"
@export var anim_attack := "Attack"
@export var anim_death := "Die"


## 有效 ATK（含装备与状态加成在 UnitState 里合并，这里仅返回面板值）。
func panel_atk() -> float:
	return atk
