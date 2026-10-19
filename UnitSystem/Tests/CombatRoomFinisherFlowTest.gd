extends SceneTree
## 正式主场景端到端：普通AI真实伤害积攒专注，真实输入连携，达分选择并完成B演出。
## 只在测试实例中调整站位/敌人耐久、专注与评分难度；不写正式资源、不冻结伙伴AI、不伪造伤害或资格信号。
var failures: Array[String] = []
var accepted: int = 0
var released: int = 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var scene := load("res://Scenes/CombatRoom.tscn").instantiate() as Node3D
	var player := scene.get_node("Hero") as PlayerBase
	scene.get_node("SquadFocusComponent").focus_gain_difficulty = 0.1
	# 夹具从零验证实际获取，不受策划在正式房间配置的初始专注影响。
	scene.get_node("SquadFocusComponent").initial_focus = 0.0
	player.position = Vector3(-1,0,3)
	var names := ["Guardian","Priest","Caster","Archer"]
	var positions := [Vector3(0,0,1),Vector3(-3,0,2),Vector3(-2,0,2),Vector3(2,0,2)]
	for index: int in range(4):
		scene.get_node(names[index]).position = positions[index]
	var targets: Array[UnitBase] = []
	var pack := scene.get_node("EnemyContainer/Pack_A") as Node3D
	pack.position = Vector3.ZERO
	for child: Node in pack.get_children():
		var enemy := child as UnitBase
		enemy.maximum_health = 50000.0
		enemy.attack_power = 0.0
		enemy.movement_speed = 0.0
		enemy.position = Vector3(float(targets.size())*0.5-0.5,0,-1)
		targets.append(enemy)
	root.add_child(scene)
	current_scene = scene
	# 手工SceneTree加载与引擎启动不同：子节点ready时current_scene尚未赋值。
	# 沿既有装配接口显式绑定夹具世界，不修改生产自动装配策略。
	for name_value: String in names:
		var unit := scene.get_node(name_value) as AllyBase
		unit.get_node("SkillHost").configure_owner(unit,scene)
	for frame: int in range(5): await process_frame
	await physics_frame
	var focus := scene.get_node("SquadFocusComponent") as SquadFocusComponent
	var command := scene.get_node("SquadChainCommandController") as SquadChainCommandController
	var evaluation := scene.get_node("SquadChainRoundController") as SquadChainRoundController
	var selection := scene.get_node("SquadFinisherSelectionController") as SquadFinisherSelectionController
	var execution := scene.get_node("SquadFinisherExecutionController") as SquadFinisherExecutionController
	var actor := scene.get_node("Caster") as AllyBase
	var host := actor.get_node("SkillHost") as SkillHostComponent
	command.command_accepted.connect(func(_request): accepted += 1)
	command.command_released.connect(func(_request_id,_cost): released += 1)
	command.command_rejected.connect(func(slot,reason): print("MAIN rejected ",slot," ",reason))
	player.get_node(PlayerBase.TARGETING_SYSTEM_PATH).request_lock(targets[0])
	_expect(is_zero_approx(focus.get_current_focus()),"no initial grant")
	var health_before := _total_health(targets)
	await _until(func() -> bool: return focus.get_available_focus() >= 20.0,10.0)
	_expect(_total_health(targets) < health_before and focus.get_current_focus() >= 20.0,"autonomous ordinary combat produces actual focus")
	print("MAIN normal combat focus=",focus.get_current_focus()," target_total_hp=",_total_health(targets))
	# 测试仅缩短等待并降低本实例门槛，验证接线而非重新标定战斗平衡。
	evaluation.score_difficulty = 0.1
	evaluation.damage_interval_seconds = 0.5
	var flash_evidence := {"seen":false,"feet":false,"casting":false}
	await _tap(&"squad_chain_3")
	await _until(func() -> bool:
		var combo := host.get_combo_skill()
		var visual = combo.get("_cast_effect_instance")
		if is_instance_valid(visual) and visual.scene_file_path == "res://Effects/Skills/Shared/ReleaseAccentFlash.tscn":
			flash_evidence.seen = true
			flash_evidence.feet = visual.get_parent() == actor
			flash_evidence.casting = combo.get_state() == SkillBase.SkillState.CASTING
		return selection.get_selection_status().phase in [1,2],8.0)
	_expect(flash_evidence.seen and flash_evidence.feet and flash_evidence.casting,"formal chain actually plays shared flash at caster feet during casting")
	print("MAIN chain flash=",flash_evidence)
	var status := selection.get_selection_status()
	_expect(accepted == 1 and released == 1,"input3 routes once through actual command and release")
	_expect(status.phase in [1,2] and is_equal_approx(Engine.time_scale,0.05),"real scored damage opens five-percent selection")
	_expect(evaluation.get_round_status().last_result.get("score",0) >= 100.0,"qualification derives from actual finalized score")
	if status.phase not in [1,2]:
		print("MAIN failure command=",command.get_slot_status(2)," round=",evaluation.get_round_status()," selection=",status)
		scene.free()
		await process_frame
		_finish()
		return
	_expect(status.slots[2].available and not status.slots[0].available and not status.slots[1].available and not status.slots[3].available,"only equipped legal finisher selectable")
	var phases: Array[StringName] = []
	var last_phase: StringName = &""
	await _tap(&"squad_chain_3")
	var deadline := Time.get_ticks_msec()+7000
	while Time.get_ticks_msec() < deadline:
		var phase: StringName = execution.get_execution_status().phase
		if phase != last_phase:
			phases.append(phase)
			last_phase = phase
		if phase == &"idle" and execution.get_execution_status().launched == 5: break
		await process_frame
	status = execution.get_execution_status()
	print("MAIN finisher phases=",phases," result=",status)
	_expect(accepted == 1,"selection input never leaks into another chain")
	_expect(status.phase == &"idle" and status.launched == 5 and status.landed == 5 and status.main_effects_pending == 0,"selected actual finisher completes five flights and main effects")
	_expect(phases.has(&"enter_closeup") and phases.has(&"windup") and phases.has(&"exit_closeup") and phases.has(&"bombardment"),"production traverses accepted B camera gates")
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0),"normal time restored")
	_expect(host.get_finisher_action_context() == null,"finisher action lock released")
	scene.free()
	await process_frame
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0),"unload leaves no pause or slow time")
	_finish()
func _total_health(targets: Array[UnitBase]) -> float:
	var total := 0.0
	for target: UnitBase in targets: total += target.get_current_health()
	return total
func _tap(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
func _until(predicate: Callable,seconds: float) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message: String in failures: printerr("FAIL: ",message)
	print("CombatRoomFinisherFlowTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
