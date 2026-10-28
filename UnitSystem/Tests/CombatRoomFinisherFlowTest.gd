extends SceneTree
## 正式主场景端到端：普通AI真实伤害积攒专注，真实输入连携，达分选择并完成B演出。
## 夹具前半段临时隔离主动输出验证Q/E，随后恢复真实AI；不写正式资源、不伪造伤害或资格信号。
var failures: Array[String] = []
var accepted: int = 0
var released: int = 0
var _player: PlayerBase
var _player_accepts: Array[int] = [0,0]
var _player_releases: Array[int] = [0,0]
var _damage_events: int = 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var scene := load("res://Scenes/CombatRoom.tscn").instantiate() as Node3D
	var player := scene.get_node("Hero") as PlayerBase
	_player = player
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
	# 只隔离本次运行实例；敌人仍运行原物理循环以消费真实被动位移。
	player.set_physics_process(false)
	for name_value: String in names:
		var ally := scene.get_node(name_value) as AllyBase
		ally.set_physics_process(false)
		ally.automatic_skill_cast_enabled = false
		ally.get_combat_system().set_physics_process(false)
	for node: Node in scene.get_node("EnemyContainer").find_children("*","Node",true,false):
		if node is EnemyBase:
			node.get_targeting_component().detection_enabled = false
			node.get_combat_system().set_physics_process(false)
			node.damage_resolved.connect(func(_event): _damage_events += 1)
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
	var player_host := player.get_node("SkillHost") as SkillHostComponent
	var controller := player.get_node("PlayerSkillController") as PlayerSkillController
	controller.slot_accepted.connect(func(slot,_skill): _player_accepts[slot] += 1)
	for slot: int in range(2):
		player_host.get_regular_skill(slot).release_started.connect(func(_context): _player_releases[slot] += 1)
	_expect(is_zero_approx(focus.get_current_focus()),"no initial grant")
	var pull_ends: Dictionary = {}
	for target: UnitBase in targets:
		target.forced_movement_finished.connect(func(_token,reason): pull_ends[target.get_instance_id()] = {"reason":reason,"position":target.global_position})
	var qe_health := _total_health(targets)
	await _tap(&"player_skill_2")
	await _until(func(): return _player_releases[1] == 1 and player_host.get_active_skill() == null,2.0)
	for target: UnitBase in targets:
		_expect(target.get_status_effect_component().has_named_status(&"temporary_threat") and target.get_threat_component().get_threat_for(player)>1900,"formal E creates real status/contribution")
	await _until(func(): return player_host.is_global_cooldown_ready(),2.0)
	# 朝向与位置在本段冻结，落盘来自释放时快照，不读取拉拽结束时的玩家位置。
	var pull := player_host.get_regular_skill(0).get_node("PullTargetSkillEffect") as PullTargetSkillEffect
	var center := targets[0].global_position
	_expect(player.get_node(PlayerBase.TARGETING_SYSTEM_PATH).request_lock(targets[0]),"formal target Gather locks original enemy")
	await _tap(&"player_skill_1")
	await _until(func(): return pull_ends.size() >= 2,2.0)
	var arrived := 0
	for result: Dictionary in pull_ends.values():
		if result.reason == &"arrived" and Vector2(result.position.x-center.x,result.position.z-center.z).length() <= pull.gather_radius_m+0.08: arrived += 1
	_expect(arrived >= 2,"formal Q physically gathers at least two ordinary enemies into frozen disk")
	_expect(_player_accepts == [1,1] and _player_releases == [1,1],"one actual Q/E input each routes exactly once")
	_expect(_damage_events == 0 and is_equal_approx(qe_health,_total_health(targets)) and is_zero_approx(focus.get_current_focus()),"Q/E do not generate damage or focus")
	_expect(evaluation.get_round_status().phase == SquadChainRoundController.Phase.IDLE and evaluation.get_round_status().last_result.is_empty(),"Q/E do not open a scored chain")
	for target: UnitBase in targets:
		_expect(not target.is_forced_movement_active() and target.get_collision_exceptions().is_empty(),"formal pull releases temporary collisions")
	for node: Node in scene.get_node("EnemyContainer").find_children("*","Node",true,false):
		if node is EnemyBase:
			node.get_targeting_component().detection_enabled = true
			node.get_combat_system().set_physics_process(true)
	# 感知Area重新启用后需物理服务器同步；沿原感知/仇恨选择，不直接锁目标。
	for frame: int in range(4):
		await physics_frame
		await process_frame
	targets[0].refresh_targeting()
	print("MAIN E perception=",targets[0].get_targeting_component().get_perceived_candidates()," target=",targets[0].get_targeting_component().get_locked_target()," threat=",targets[0].get_threat_component().get_threat_for(player))
	_expect(targets[0].get_targeting_component().get_locked_target() == player,"restored real enemy AI selects player by E threat")
	for index: int in range(4):
		var ally := scene.get_node(names[index]) as AllyBase
		ally.position = positions[index]
		ally.set_physics_process(true)
		ally.automatic_skill_cast_enabled = true
		ally.get_combat_system().set_physics_process(true)
	player.set_physics_process(true)
	player.get_node(PlayerBase.TARGETING_SYSTEM_PATH).request_lock(targets[0])
	var health_before := _total_health(targets)
	await _until(func() -> bool: return focus.get_available_focus() >= 20.0,10.0)
	_expect(_total_health(targets) < health_before and focus.get_current_focus() >= 20.0,"autonomous ordinary combat produces actual focus")
	print("MAIN normal combat focus=",focus.get_current_focus()," target_total_hp=",_total_health(targets))
	# 测试仅缩短等待并降低本实例门槛，验证接线而非重新标定战斗平衡。
	evaluation.score_difficulty = 0.1
	evaluation.damage_interval_seconds = 0.5
	# 必须自然等到正式10/12秒CD都结束；避免拿冷却拒绝冒充演出输入隔离。
	var wait_seconds := maxf(player_host.get_regular_skill(0).get_cooldown_remaining(),player_host.get_regular_skill(1).get_cooldown_remaining())+3.0
	await _until(func(): return controller.get_slot_status(0).can_request and controller.get_slot_status(1).can_request,wait_seconds)
	_expect(controller.get_slot_status(0).can_request and controller.get_slot_status(1).can_request,"both real player cooldowns naturally end before gating probes")
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
	_expect(status.slots[2].available and status.slots[0].available and status.slots[1].available and status.slots[3].available,"only equipped legal finisher selectable")
	await _probe_player_gate("selection")
	var tested: Array[StringName] = []
	var phases: Array[StringName] = []
	var last_phase: StringName = &""
	await _tap(&"squad_chain_3")
	var deadline := Time.get_ticks_msec()+7000
	while Time.get_ticks_msec() < deadline:
		var phase: StringName = execution.get_execution_status().phase
		if phase != last_phase:
			phases.append(phase)
			last_phase = phase
		if phase in [&"enter_closeup",&"windup",&"exit_closeup",&"release_pending",&"bombardment"] and not tested.has(phase):
			tested.append(phase)
			await _probe_player_gate(str(phase))
		if phase == &"idle" and execution.get_execution_status().launched == 5: break
		await process_frame
	status = execution.get_execution_status()
	print("MAIN finisher phases=",phases," result=",status)
	_expect(accepted == 1,"selection input never leaks into another chain")
	_expect(status.phase == &"idle" and status.launched == 5 and status.landed == 5 and status.main_effects_pending == 0,"selected actual finisher completes five flights and main effects")
	_expect(phases.has(&"enter_closeup") and phases.has(&"windup") and phases.has(&"exit_closeup") and phases.has(&"bombardment"),"production traverses accepted B camera gates")
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0),"normal time restored")
	_expect(host.get_finisher_action_context() == null,"finisher action lock released")
	_expect(tested.has(&"enter_closeup") and tested.has(&"windup") and tested.has(&"exit_closeup") and tested.has(&"bombardment"),"input probes observed actual B phases")
	await _until(func(): return controller.get_slot_status(0).can_request and controller.get_slot_status(1).can_request,2.0)
	_expect(controller.get_slot_status(0).can_request and controller.get_slot_status(1).can_request,"input permission and ready skills restored after actual B")
	# 新E证明死亡清理确有活动状态，而非对早已到期的空池做恒真断言。
	player.position = targets[0].global_position+Vector3(0,0,1)
	await _tap(&"player_skill_2")
	await _until(func(): return _player_releases[1] == 2,2.0)
	_expect(targets[0].get_status_effect_component().has_named_status(&"temporary_threat") and targets[0].get_threat_component().get_threat_for(player)>1900,"fresh E exists before death cleanup")
	player.apply_damage(100000)
	for target: UnitBase in targets:
		_expect(not target.get_status_effect_component().has_named_status(&"temporary_threat") and is_zero_approx(target.get_threat_component().get_threat_for(player)),"death removes real temporary state and contribution")
		_expect(not target.is_forced_movement_active() and target.get_collision_exceptions().is_empty(),"death/unload leaves no pull collision state")
	var old_id := player.get_instance_id()
	scene.free()
	await process_frame
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0),"unload leaves no pause or slow time")
	var rebuilt := load("res://Scenes/CombatRoom.tscn").instantiate() as Node3D
	root.add_child(rebuilt)
	current_scene = rebuilt
	await process_frame
	await process_frame
	var fresh := rebuilt.get_node("Hero") as PlayerBase
	_expect(fresh.get_instance_id() != old_id and fresh.is_player_input_enabled(),"fresh world has new identity and no input lease")
	_expect(fresh.get_node("SkillHost").get_regular_skill(0).is_ready() and fresh.get_node("SkillHost").get_regular_skill(1).is_ready(),"fresh world inherits no cooldown")
	_expect(rebuilt.get_node("PlayerSkillBar").skill_source == fresh.get_node("PlayerSkillController"),"fresh HUD bound to new local Hero")
	rebuilt.free()
	current_scene = null
	await process_frame
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0),"rebuild exit leaves normal time")
	_finish()
# 两槽已在进入终结前真实ready；测试真实输入与公开请求都被同一许可拒绝。
func _probe_player_gate(label: String) -> void:
	var controller := _player.get_node("PlayerSkillController") as PlayerSkillController
	var host := _player.get_node("SkillHost") as SkillHostComponent
	var before_accepts := _player_accepts.duplicate()
	var before_releases := _player_releases.duplicate()
	_expect(host.get_regular_skill(0).is_ready() and host.get_regular_skill(1).is_ready(),label+": not masked by cooldown")
	await _tap(&"player_skill_1")
	await _tap(&"player_skill_2")
	_expect(not controller.request_slot(0) and not controller.request_slot(1),label+": direct requests reject")
	_expect(_player_accepts == before_accepts and _player_releases == before_releases,label+": no new input acceptance or Effect")
	_expect(host.get_regular_skill(0).is_ready() and host.get_regular_skill(1).is_ready(),label+": no cooldown consumption")

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
