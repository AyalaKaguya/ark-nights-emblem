class_name CharacterState
## 角色状态枚举与 Spine 动画映射（状态机以 Spine 动画为基准）。
##
## 每个状态对应一个 Spine 动画；一次性状态（ONE_SHOT）在动画播放完成后
## 会自动回退到进入前的状态。

## 状态标识
enum Id {
	IDLE,
	MOVE,
	INTERACT,
	SIT,
	SLEEP,
}

## 状态 → Spine 动画名（以骨骼实际动画为准）
const ANIMATIONS := {
	Id.IDLE: "Relax",
	Id.MOVE: "Move",
	Id.INTERACT: "Interact",
	Id.SIT: "Sit",
	Id.SLEEP: "Sleep",
}

## 一次性状态：动画播放完成后自动回退
const ONE_SHOT := {
	Id.INTERACT: true,
}

## 状态显示名（调试 / 日志用）
const NAMES := {
	Id.IDLE: "IDLE",
	Id.MOVE: "MOVE",
	Id.INTERACT: "INTERACT",
	Id.SIT: "SIT",
	Id.SLEEP: "SLEEP",
}
