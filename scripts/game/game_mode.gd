class_name GameModeDef
extends RefCounted
## 游戏模式定义。

enum Mode {
	CAMP,            # 营地（可行走 + 设施交互）
	REALTIME,        # 实时探索（动态）
	TACTICAL_TURN,   # 非战斗战术微操（按体力逐格移动）
	COMBAT_TURN,     # 回合战斗（遭遇 / 主动攻击）
}

const NAMES := {
	Mode.CAMP: "CAMP",
	Mode.REALTIME: "REALTIME",
	Mode.TACTICAL_TURN: "TACTICAL_TURN",
	Mode.COMBAT_TURN: "COMBAT_TURN",
}

static func name_of(mode: int) -> String:
	return NAMES.get(mode, "?")
