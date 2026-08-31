class_name EncounterUnitEntry
extends Resource
## 遭遇战中的单个敌人编成条目：敌人数据 + 出生世界坐标（米，XZ）。

const OperatorData := preload("res://scripts/data/operator_data.gd")

@export var operator: OperatorData
@export var pos := Vector2.ZERO
