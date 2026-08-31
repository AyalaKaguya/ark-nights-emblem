class_name SkillData
extends Resource
## 技能 / 普攻数据：声明体力消耗、技力消耗、恢复条件、冷却、目标方式、范围与效果。
## 属于"Resource 定义数据"层，不包含任何运行时状态。

## 目标方式：决定动作的目标合法性校验与可选目标集合。
enum TargetMode {
	NONE,           # 无目标（被动 / 仅自身结算）
	SELF,           # 自身
	SINGLE_ENEMY,   # 单个敌人
	SINGLE_ALLY,    # 单个友方（含自身）
	ALL_ENEMY,      # 全部敌人
	ALL_ALLY,       # 全部友方
	POINT_AOE,      # 点目标（对范围内全部敌方结算）
}

## 范围形状：决定"在施放范围内"的几何判定。
enum RangeShape { CIRCLE, SQUARE }

## 技力恢复条件：额外技力回复的触发时机（默认还有每回合固定回技力）。
enum RestoreCondition { NONE, ON_TURN_START, ON_ATTACK, ON_HIT, ON_KILL }

## 稳定技能 id（存档 / 绑定 / 校验用）。
@export var skill_id := ""
## 显示名。
@export var display_name := "技能"
@export_multiline var description := ""

## 体力消耗（本项目适配层）。
@export var stamina_cost := 0.0
## 技力消耗（干员共享技力池）。
@export var sp_cost := 0
## 冷却（自身回合数；0 = 无冷却）。
@export_range(0, 99) var cooldown := 0

@export var target_mode: TargetMode = TargetMode.SINGLE_ENEMY
@export var range_shape: RangeShape = RangeShape.CIRCLE
## 施放范围（米）：目标必须在此范围内。
@export_range(0.0, 100.0, 0.1) var range_m := 2.0
## 效果半径（米）：0 = 单体；>0 时对范围内目标结算。
@export_range(0.0, 100.0, 0.1) var effect_radius_m := 0.0

@export var restore_condition: RestoreCondition = RestoreCondition.NONE
## 满足恢复条件时额外回复的技力值。
@export var restore_amount := 0

## 施放动画名（Spine，缺失时由表现层回退）。
@export var animation := "Attack"

## 效果 id（见 EffectResolver 支持的表）。
@export var effect_id := "damage"
## 效果参数（如 { "atk_mult": 1.5, "damage_type": "physical" }）。
@export var effect_params: Dictionary = {}


## 短描述（HUD tooltip 用）。
func tooltip_text() -> String:
	var cost := ""
	if stamina_cost > 0.0:
		cost += "体力%.1f" % stamina_cost
	if sp_cost > 0:
		cost += (" " if cost != "" else "") + "技力%d" % sp_cost
	var line := "%s（%s）" % [display_name, cost if cost != "" else "无消耗"]
	if description != "":
		line += "\n" + description
	return line
