class_name PartyData
extends Resource
## 编队数据：可用干员名单 + 出战名单（id 列表）。
## 运行时单位状态由 GameState.party（UnitState 数组）持有，编队改动只写回 id 集合。

const OperatorData := preload("res://scripts/data/operator_data.gd")

@export var roster: Array[OperatorData] = []
@export var active_ids: Array[String] = []
