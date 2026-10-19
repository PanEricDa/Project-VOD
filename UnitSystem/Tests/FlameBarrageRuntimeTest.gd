extends SceneTree
## 真实场景端到端：A/B、五发、真暂停、伤害、真实资格选择与卸载所有权。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var scene := load("res://Scenes/Previews/SquadFinisherComparisonPreview.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i: int in range(4): await process_frame
	await physics_frame
	var execution := scene.get_node("Battle/SquadFinisherExecutionController") as SquadFinisherExecutionController
	var actor := scene.get_node("Battle/Caster") as AllyBase
	var camera := scene.get_node("Battle/CameraRig") as CameraFollowController
	var focus := scene.get_node("Battle/SquadFocusComponent") as SquadFocusComponent
	var pause := scene.get_node("Battle/ChainSkillPresentationController/PauseCoordinator") as GamePauseCoordinator
	_expect(execution.get_actor_availability(actor) == &"", "Caster available in real assembled preview")
	for mode: int in [1,0]:
		scene.reset_preview()
		var initial_focus := focus.get_current_focus()
		var hp := _health(scene)
		_expect(execution.begin_finisher(actor, 171018, mode), "mode %d accepted" % mode)
		await _wait(func() -> bool: return execution.get_execution_status().launched >= 1, 3.0)
		var status := execution.get_execution_status()
		_expect(status.launched >= 1, "mode %d first shot succeeds: %s" % [mode,status])
		if mode == 1:
			_expect(is_equal_approx(Engine.time_scale,0.05) and camera.is_cinematic_active(), "B keeps world slow and battle camera owned")
			var token := pause.acquire_pause(execution,&"test_menu")
			var before := execution.get_execution_status()
			await create_timer(0.15,true,false,true).timeout
			var after := execution.get_execution_status()
			_expect(before.launched == after.launched and before.landed == after.landed, "true pause freezes request")
			pause.release_pause(token)
		else:
			_expect(is_equal_approx(Engine.time_scale,1.0) and not camera.is_cinematic_active(), "A restores world and camera on first shot")
		await _wait(func() -> bool: return execution.get_execution_status().phase == &"idle",5.0)
		status = execution.get_execution_status()
		_expect(status.phase == &"idle" and status.launched == 5 and status.landed == 5 and status.main_effects_pending == 0, "mode %d complete five shots: %s" % [mode,status])
		_expect(_health(scene) < hp, "mode %d delivers actual damage" % mode)
		_expect(is_equal_approx(focus.get_current_focus(),initial_focus), "finisher does not gain focus")
		_expect(is_equal_approx(Engine.time_scale,1.0) and not camera.is_cinematic_active(), "ownership restored after mode %d" % mode)
	# 由真实连携伤害生成资格，而非向选择窗口伪造事件；测试只降低本实例评分门槛。
	scene.reset_preview()
	var round_controller := scene.get_node("Battle/SquadChainRoundController") as SquadChainRoundController
	round_controller.score_difficulty = 0.1
	round_controller.damage_interval_seconds = 0.1
	focus.initial_focus = 100
	focus.reset_focus()
	var command := scene.get_node("Battle/SquadChainCommandController") as SquadChainCommandController
	var selection := scene.get_node("Battle/SquadFinisherSelectionController") as SquadFinisherSelectionController
	_expect(command.submit_slot(2), "real chain request accepted")
	await _wait(func() -> bool: return selection.get_selection_status().phase in [1,2],5.0)
	var selection_status := selection.get_selection_status()
	_expect(selection_status.phase in [1,2], "actual scored chain opens selection: %s" % selection_status)
	_expect(not selection.try_select_slot(0), "unequipped Guardian gray/unselectable")
	_expect(selection.try_select_slot(2), "Caster selection enters real execution")
	_expect(selection.get_selection_status().phase == 0 and Engine.time_scale <= 0.05, "selection transfers ownership without normal-speed gap")
	await _wait(func() -> bool: return execution.get_execution_status().phase == &"idle",5.0)
	_expect(execution.get_execution_status().launched == 5, "selected finisher performs all five shots")
	# 控制器中途删除只能释放自己的时间持有，菜单/其他慢放保持。
	scene.reset_preview()
	var other := Node.new()
	scene.get_node("Battle").add_child(other)
	var other_token := pause.acquire_time_scale(other,0.4,&"other_effect")
	_expect(execution.begin_finisher(actor,171018,1), "teardown execution accepted")
	await _wait(func() -> bool: return execution.get_execution_status().launched >= 1,3.0)
	execution.queue_free()
	await process_frame
	await process_frame
	_expect(is_equal_approx(Engine.time_scale,0.4) and not camera.is_cinematic_active(), "deleting execution preserves other time owner")
	pause.release_time_scale(other_token)
	other.free()
	scene.free()
	await process_frame
	_expect(is_equal_approx(Engine.time_scale,1.0) and not paused, "scope teardown leaves no time state")
	for message: String in failures: printerr("FAIL: ",message)
	print("FlameBarrageRuntimeTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _wait(predicate: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
func _health(scene: Node) -> float:
	var total := 0.0
	for target: UnitBase in scene.targets: total += target.get_current_health()
	return total
func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
