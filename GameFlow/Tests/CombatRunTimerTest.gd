extends SceneTree

## 捕获起步误触发、结算后继续累加、失败刷新纪录、重玩丢失本次启动最佳时间等回归。
const TIMER_PATH := "res://GameFlow/Components/CombatRunTimer.tscn"
const ROOM_PATH := "res://Scenes/CombatRoom.tscn"
const CONTENT := ^"Backdrop/CenterContainer/Panel/Content"
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	if not ResourceLoader.exists(TIMER_PATH):
		_expect(false, "independent CombatRunTimer scene must exist")
		_finish()
		return
	var game_run: Node = root.get_node(^"GameRunController")
	var room: Node = (load(ROOM_PATH) as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await _settle()
	var timer: Node = room.get_node_or_null(^"CombatRunTimer")
	_expect(timer != null, "main combat scene equips the timer")
	if timer == null:
		room.queue_free()
		await process_frame
		_finish()
		return
	_expect(timer.get_child_count() == 1, "instanced timer must not duplicate its inherited UI children")
	var player: PlayerBase = room.get_node(^"Hero") as PlayerBase
	var flow: CombatRoomController = room.get_node(^"CombatRoomController") as CombatRoomController
	var overlay: Node = game_run.get_node(^"RunResultOverlay")
	_expect(timer.get("player") == player, "Inspector player reference resolves to the main Hero")
	timer.set_process(false)
	timer.set_physics_process(false)
	player.set_physics_process(false)
	_expect(_clock(timer) == "00:00:00", "clock starts at zero")
	timer.call("_process", 10.0)
	_expect(is_zero_approx(float(timer.call("get_elapsed_seconds"))), "waiting before movement is not timed")
	# 出生/外力造成的位置变化没有移动输入，不应起步。
	player.position.x += 0.2
	timer.call("_physics_process", 0.016)
	_expect(not bool(timer.call("has_started")), "position changes without player intent do not start a run")
	# 仅按住移动但被阻挡、没有位移，也不开始。
	Input.action_press(&"player_move_forward")
	timer.call("_physics_process", 0.016)
	await process_frame
	_expect(not bool(timer.call("has_started")), "movement input without displacement does not start")
	timer.call("_physics_process", 0.016)
	player.position.z -= 0.2
	await process_frame
	Input.action_release(&"player_move_forward")
	_expect(bool(timer.call("has_started")), "first actual player movement starts the clock")
	timer.call("_process", 62.348)
	_expect(_clock(timer) == "01:02:34", "six digits show minutes, seconds and centiseconds")
	flow.room_completed.emit()
	timer.call("_process", 10.0)
	_expect(is_equal_approx(float(timer.call("get_elapsed_seconds")), 62.348), "victory freezes elapsed time synchronously")
	_expect(_result(overlay, "RunTime") == "本轮时间：01:02:34", "success overlay shows this run")
	_expect(_result(overlay, "BestTime") == "最佳通关：01:02:34", "first victory establishes session best")
	flow.room_completed.emit()
	_expect(_result(overlay, "BestTime") == "最佳通关：01:02:34", "duplicate completion cannot corrupt best")
	# 真正沿重玩按钮执行路径重载主场景，不手工重建或复制纪录。
	game_run.call("_on_restart_requested")
	await _settle()
	room = current_scene
	timer = room.get_node(^"CombatRunTimer")
	_expect(_clock(timer) == "00:00:00" and not bool(timer.call("has_started")), "restart resets the clock and returns to waiting")
	await _start_fixture_run(timer, 20.0)
	flow = room.get_node(^"CombatRoomController") as CombatRoomController
	flow.room_completed.emit()
	_expect(_result(overlay, "BestTime") == "最佳通关：00:20:00", "faster victory replaces prior session best")
	game_run.call("_on_restart_requested")
	await _settle()
	room = current_scene
	timer = room.get_node(^"CombatRunTimer")
	await _start_fixture_run(timer, 5.0)
	flow = room.get_node(^"CombatRoomController") as CombatRoomController
	flow.room_failed.emit()
	timer.call("_process", 10.0)
	_expect(_result(overlay, "RunTime") == "本轮时间：00:05:00（未通关）", "failure shows frozen elapsed time without claiming completion")
	_expect(_result(overlay, "BestTime") == "最佳通关：00:20:00", "failed short run never replaces best")
	game_run.call("_on_restart_requested")
	await _settle()
	room = current_scene
	timer = room.get_node(^"CombatRunTimer")
	await _start_fixture_run(timer, 40.0)
	flow = room.get_node(^"CombatRoomController") as CombatRoomController
	flow.room_completed.emit()
	_expect(_result(overlay, "BestTime") == "最佳通关：00:20:00", "slower victory preserves best across several scene reloads")
	# 格式进位以真实累计值推导，不按每帧字符串截断。
	var script: Script = load("res://GameFlow/Components/CombatRunTimer.gd")
	_expect(script.call("format_time", 59.999) == "00:59:99", "format does not round prematurely into next minute")
	_expect(script.call("format_time", 60.0) == "01:00:00", "whole minute rolls over correctly")
	_expect(script.call("format_time", 7000.0) == "99:59:99", "six-digit display saturates instead of wrapping")
	current_scene = null
	room.queue_free()
	await _settle()
	await _verify_real_movement_edges()
	# 通过真实无计时器的旧房间胜利信号验证兼容，不直接模拟UI结果。
	room = load("res://Scenes/TestCombatRoom.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _settle()
	(room.get_node(^"CombatRoomController") as CombatRoomController).room_completed.emit()
	var rows: Control = overlay.get_node(NodePath(str(CONTENT) + "/Timing")) as Control
	_expect((overlay.get_node(^"Backdrop") as Control).visible, "legacy room still shows the result overlay")
	_expect(not rows.visible, "rooms without a timer hide stale timing rows")
	current_scene = null
	room.queue_free()
	await _settle()
	overlay.call("hide_result")
	_finish()

func _verify_real_movement_edges() -> void:
	for forced: bool in [false, true]:
		var world := Node3D.new()
		root.add_child(world)
		var player: PlayerBase = load("res://UnitSystem/Player/PlayerBase.tscn").instantiate() as PlayerBase
		player.dash_distance = 0.002
		world.add_child(player)
		var timer: Node = load(TIMER_PATH).instantiate()
		timer.set("player", player)
		world.add_child(timer)
		await process_frame
		var before: Vector3 = player.global_position
		if forced:
			player.request_forced_movement(player, before + Vector3.RIGHT * 0.2, 0.001)
			Input.action_press(PlayerBase.MOVE_FORWARD_ACTION)
		else:
			Input.action_press(PlayerBase.DASH_ACTION)
		await physics_frame
		await process_frame
		var moved := Vector2(player.global_position.x-before.x, player.global_position.z-before.z).length()
		_expect(moved > 0.0001, "real physics fixture actually moves")
		if forced:
			_expect(player.get_forced_movement_token() == 0, "forced movement ends in the sampled physical step")
			_expect(not bool(timer.call("has_started")), "ending external movement with a held direction must not start the clock")
		else:
			_expect(not player.is_player_dashing(), "short dash completes in its first physical step")
			_expect(bool(timer.call("has_started")), "first real dash starts the clock even when already completed")
		Input.action_release(PlayerBase.DASH_ACTION)
		Input.action_release(PlayerBase.MOVE_FORWARD_ACTION)
		world.queue_free()
		await process_frame

func _start_fixture_run(timer: Node, seconds: float) -> void:
	timer.set_process(false)
	timer.set_physics_process(false)
	var player: PlayerBase = timer.get("player") as PlayerBase
	player.set_physics_process(false)
	Input.action_press(&"player_move_forward")
	timer.call("_physics_process", 0.016)
	player.position.z -= 0.2
	await process_frame
	Input.action_release(&"player_move_forward")
	timer.call("_process", seconds)

func _clock(timer: Node) -> String:
	return (timer.get_node(^"Panel/Time") as Label).text

func _result(overlay: Node, row: String) -> String:
	return (overlay.get_node(NodePath(str(CONTENT) + "/Timing/" + row)) as Label).text

func _settle() -> void:
	for index: int in range(5):
		await process_frame

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		push_error("CombatRunTimerTest: " + message)

func _finish() -> void:
	Input.action_release(&"player_move_forward")
	if _failures.is_empty():
		print("CombatRunTimerTest: PASS")
		quit(0)
	else:
		printerr("CombatRunTimerTest: FAIL\n- " + "\n- ".join(_failures))
		quit(1)
