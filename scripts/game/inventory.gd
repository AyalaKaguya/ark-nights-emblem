class_name Inventory
extends RefCounted
## 独立背包（每名角色一个实例）：item_id → 数量。
## 纯运行时状态，与表现层解耦。

var _items := {}


func add_item(item_id: String, count: int = 1) -> void:
	if count <= 0:
		return
	_items[item_id] = int(_items.get(item_id, 0)) + count


func remove_item(item_id: String, count: int = 1) -> bool:
	var cur := int(_items.get(item_id, 0))
	if cur < count:
		return false
	var left := cur - count
	if left <= 0:
		_items.erase(item_id)
	else:
		_items[item_id] = left
	return true


func count(item_id: String) -> int:
	return int(_items.get(item_id, 0))


func has(item_id: String) -> bool:
	return count(item_id) > 0


func items() -> Dictionary:
	return _items


func to_dict() -> Dictionary:
	return _items.duplicate()


func from_dict(d: Dictionary) -> void:
	_items = {}
	for k in d:
		_items[k] = int(d[k])


func is_empty() -> bool:
	return _items.is_empty()
