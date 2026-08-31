class_name MapManifest
extends Resource
## 地图清单：描述一张可加载的场景与其中的遭遇 / 出生点。

const EncounterData := preload("res://scripts/data/encounter_data.gd")

@export var map_id := ""
@export var display_name := "地图"
## 场景路径（res://...）。
@export var scene_path := ""
## 是否为营地（决定能否进入编队设施）。
@export var is_camp := false
## 是否为战斗箱庭地图。
@export var is_box_map := false
## 遭遇战（箱庭地图用）。
@export var encounter: EncounterData
## 玩家单位出生点（世界米坐标，XZ）。
@export var spawn_points: Array[Vector2] = []
## 安全入口（返营触发点，世界米坐标；营地则留空）。
@export var safe_exit_point := Vector2.ZERO
## 返营后回到的营地地图 id。
@export var camp_map_id := "camp"
