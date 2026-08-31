class_name SaveGame
extends Resource
## 版本化存档：只存可序列化数据（字典 / 数组），运行时状态由 GameState 转换。
## 队伍单位：operator_id + hp/sp/stamina/世界坐标(x,y) + 背包；装备与状态效果按 id 存。

const CURRENT_VERSION := 2

@export var version := CURRENT_VERSION
@export var current_map_id := ""
## 每项：{ "unit_id": "", "operator_id": "", "hp": 0.0, "sp": 0, "stamina": 0.0,
##        "x": 0.0, "y": 0.0, "inventory": {item_id: count}, "statuses": [status_id], "cooldowns": {skill_id: turns} }
@export var party: Array[Dictionary] = []
## 出战名单（operator_id，与 party 顺序对应）。
@export var active_ids: Array[String] = []
## 全局标志（任务 / 已触发事件等）。
@export var flags: Dictionary = {}


func is_compatible() -> bool:
	return version == CURRENT_VERSION


func clear() -> void:
	version = CURRENT_VERSION
	current_map_id = ""
	party = []
	active_ids = []
	flags = {}
