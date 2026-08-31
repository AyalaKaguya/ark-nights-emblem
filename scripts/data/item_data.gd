class_name ItemData
extends Resource
## 道具数据：消耗品定义（效果 + 消耗）。

@export var item_id := ""
@export var display_name := "道具"
@export_multiline var description := ""
## 效果 id（heal / damage / apply_status ...）。
@export var effect_id := "heal"
@export var effect_params: Dictionary = {}
## 使用消耗（体力 / 技力），数据化，默认免费动作。
@export var stamina_cost := 0.0
@export var sp_cost := 0
## 是否可堆叠（同类道具计数合并）。
@export var stackable := true


func tooltip_text() -> String:
	return "%s\n%s" % [display_name, description]
