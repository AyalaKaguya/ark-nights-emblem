class_name EquipmentData
extends Resource
## 装备数据：占用槽位并提供属性加成（加成在 UnitState 结算时合并）。

enum Slot { WEAPON, ARMOR, ACCESSORY }

@export var equipment_id := ""
@export var display_name := "装备"
@export var slot: Slot = Slot.WEAPON
## 属性加成（平加）。
@export var max_hp_bonus := 0
@export var atk_bonus := 0
@export var def_bonus := 0
@export var res_bonus := 0
