extends SceneTree
## 同步输入状态订阅者可在持有申请内部取消，返回的token也必须回滚。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var scene := load("res://Scenes/Previews/SquadFinisherComparisonPreview.tscn").instantiate() as Node3D
	root.add_child(scene)
	for i: int in range(4): await process_frame
	var execution := scene.get_node("Battle/SquadFinisherExecutionController") as SquadFinisherExecutionController
	var command := scene.get_node("Battle/SquadChainCommandController") as SquadChainCommandController
	var pause := scene.get_node("Battle/ChainSkillPresentationController/PauseCoordinator") as GamePauseCoordinator
	var actor := scene.get_node("Battle/Caster") as AllyBase
	var once: Array[bool] = [false]
	var callback := func(_slot: int) -> void:
		if not once[0] and execution.get_execution_status().phase == &"pending":
			once[0] = true
			execution.cancel_execution(&"acquisition_callback")
	command.slot_status_changed.connect(callback)
	_expect(not execution.begin_finisher(actor,171018,1),"reentrant cancelled request not accepted")
	command.slot_status_changed.disconnect(callback)
	_expect(once[0] and execution.get_execution_status().phase == &"idle","synchronous cancellation handled")
	_expect(command.get("_input_blocks").is_empty() and pause.get("_scale_tokens").is_empty(),"no leaked input/time token after acquisition callback")
	scene.free()
	await process_frame
	for message: String in failures: printerr("FAIL: ",message)
	print("FinisherExecutionReentrancyTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
