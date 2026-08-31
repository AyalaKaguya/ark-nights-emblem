class_name StatusEffectData
extends Resource
## 状态效果数据（增益 / 减益）：持续回合与属性修正。

@export var status_id := ""
@export var display_name := "状态"
## 持续回合数（0 = 永续）。
@export var duration_turns := 1
## 属性百分比修正（0.2 = +20%，-0.2 = -20%）。
@export var atk_modifier := 0.0
@export var def_modifier := 0.0
@export var res_modifier := 0.0
## 每回合结算的固定伤害（毒 / 灼烧等，0 = 无）。
@export var dot_per_turn := 0
## 是否为减益（用于 HUD 分类图标）。
@export var is_debuff := false
