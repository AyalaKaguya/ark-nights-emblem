class_name EncounterData
extends Resource
## 遭遇战数据：敌人编成。

const EncounterUnitEntry := preload("res://scripts/data/encounter_unit_entry.gd")

@export var encounter_id := ""
@export var display_name := "遭遇战"
## 触发战斗的警戒半径（米）：主控单位进入该范围即开战（0=不自动触发）。
@export_range(0.0, 50.0, 0.5) var trigger_radius_m := 6.0
@export var enemies: Array[EncounterUnitEntry] = []
