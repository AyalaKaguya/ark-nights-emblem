class_name DamageFormula
extends RefCounted
## 明日方舟式伤害公式（本地可配置数值的纯计算）。

const UnitState := preload("res://scripts/game/unit_state.gd")

## 物理：ATK - DEF，保底 5% ATK。
static func physical(atk: float, defense: float) -> float:
	return maxf(atk - defense, atk * 0.05)


## 法术：ATK * (100 - RES) / 100。
static func arts(atk: float, res: float) -> float:
	return atk * (100.0 - res) / 100.0


## 按类型计算。
static func compute(atk: float, target: UnitState, damage_type: String) -> float:
	match damage_type:
		"arts":
			return arts(atk, target.effective_res())
		_:
			return physical(atk, target.effective_def())
