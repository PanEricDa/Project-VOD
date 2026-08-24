extends SceneTree

## 验证房间结算 UI 与玩家统一输入开关的最小公开契约。
## 本测试不依赖具体房间或单位摆放，因此可在无窗口环境中稳定执行。

const GAME_RUN_CONTROLLER_PATH: String = "res://GameFlow/GameRunController.gd"
const RESULT_OVERLAY_PATH: String = "res://GameFlow/UI/RunResultOverlay.tscn"
const HERO_SCENE_PATH: String = "res://UnitSystem/Player/Hero/Hero.tscn"
const ENCOUNTER_SCENE_PATH: String = "res://UnitSystem/Encounter/EncounterController.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	await _verify_result_signal_disables_player_input()
	_expect(
		ResourceLoader.exists(GAME_RUN_CONTROLLER_PATH),
		"GameRunController must exist as the global result-flow entry"
	)
	_expect(
		load(GAME_RUN_CONTROLLER_PATH) != null,
		"GameRunController script must compile so the Autoload can instantiate it"
	)
	_expect(
		ResourceLoader.exists(RESULT_OVERLAY_PATH),
		"RunResultOverlay scene must exist as the reusable result presentation"
	)
	_expect(
		load(RESULT_OVERLAY_PATH) != null,
		"RunResultOverlay scene must compile and instantiate safely"
	)
	var player := PlayerBase.new()
	_expect(
		player.has_method(&"set_player_input_enabled"),
		"PlayerBase must expose the unified input gate"
	)
	_expect(
		player.has_method(&"is_player_input_enabled"),
		"PlayerBase must expose the input-gate debug query"
	)
	player.free()
	_finish()


func _verify_result_signal_disables_player_input() -> void:
	var game_run: Node = root.get_node_or_null(^"GameRunController")
	_expect(game_run != null, "GameRunController must be registered as an Autoload")
	if game_run == null:
		return

	var room := Node3D.new()
	room.name = "ResultFlowRoom"
	root.add_child(room)
	current_scene = room
	var enemy_container := Node3D.new()
	enemy_container.name = "EnemyContainer"
	room.add_child(enemy_container)
	var encounter := (load(ENCOUNTER_SCENE_PATH) as PackedScene).instantiate()
	encounter.name = "EncounterController"
	room.add_child(encounter)
	var hero := (load(HERO_SCENE_PATH) as PackedScene).instantiate() as PlayerBase
	room.add_child(hero)
	var room_controller := CombatRoomController.new()
	room_controller.name = "CombatRoomController"
	room.add_child(room_controller)
	await process_frame
	await process_frame
	room_controller.room_completed.emit()
	await process_frame
	_expect(
		not hero.is_player_input_enabled(),
		"room completion must disable PlayerBase input without pausing the world"
	)
	var overlay: CanvasLayer = game_run.get_node_or_null(^"RunResultOverlay") as CanvasLayer
	_expect(overlay != null, "GameRunController must create its reusable result overlay")
	if overlay != null:
		var backdrop := overlay.get_node_or_null(^"Backdrop") as Control
		_expect(backdrop != null and backdrop.visible, "room completion must show the result overlay")
		hero.set_player_input_enabled(true)
		room_controller.room_failed.emit()
		await process_frame
		var title := overlay.get_node_or_null(
			^"Backdrop/CenterContainer/Panel/Content/Title"
		) as Label
		_expect(
			title != null and title.text == "战败",
			"room failure must reuse the overlay with failure presentation"
		)
		_expect(
			not hero.is_player_input_enabled(),
			"room failure must also disable PlayerBase input"
		)
	room.queue_free()
	current_scene = null
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("GameRunResultFlowTest failed: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("GameRunResultFlowTest: PASS")
		quit(0)
		return
	printerr("GameRunResultFlowTest: FAIL\n- " + "\n- ".join(_failures))
	quit(1)
