extends Node
## 临时演示驱动：自动推进 开始→营地→箱庭→战斗，逐步截图后退出。
## 仅供验收截图用，不参与正式逻辑；用完从 autoload 移除。

const GameModeDef := preload("res://scripts/game/game_mode.gd")
const DataFactory := preload("res://scripts/game/data_factory.gd")

func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	# 等待自动开始（GameController 1.2s 后 new_game 进入营地）
	await get_tree().create_timer(2.0).timeout
	_capture("camp.png")

	# 出发进入箱庭
	GameState.set_mode(GameModeDef.Mode.REALTIME)
	GameState.request_map(DataFactory.box_manifest())
	await get_tree().create_timer(1.0).timeout
	_capture("box.png")

	# 进入战斗（敌人已就绪）
	GameState.enter_combat()
	await get_tree().create_timer(1.5).timeout
	_capture("combat.png")

	quit()


func _capture(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://screenshots/" + path)


func quit() -> void:
	get_tree().quit(0)
