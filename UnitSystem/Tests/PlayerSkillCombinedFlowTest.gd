extends SceneTree
## 捕捉测试模式串入队伍、Q/E伪造伤害/专注、真实队伍/连携断链；夹具调整仅运行时有效。
const SCENE := "res://Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn"
const MODE := &"player_skills_threat_test_mode"
var failures: Array[String] = []
var _world: Node3D
var _hero: PlayerBase
var _targets: Array[UnitBase] = []
var _accepted: int = 0
var _released: int = 0
var _damage: int = 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for mode: int in range(3):
		root.set_meta(MODE,mode)
		var scene := load(SCENE).instantiate() as Node3D
		root.add_child(scene)
		current_scene = scene
		await process_frame
		await process_frame
		_expect(scene.get_node("ValidationActors").get_child_count() == [0,1,4][mode], "mode %d has correct actual companion count" % mode)
		_expect((scene.get_node_or_null("SquadChainCommandController") != null) == (mode == 2), "non-squad mode removes active squad systems before ready")
		if mode != 2:
			scene.free()
			current_scene = null
			await process_frame
		else:
			_world = scene
	if _world.get_node_or_null("SquadChainCommandController") == null:
		_world.free()
		_finish()
		return
	_hero = _world.get_node("Hero")
	var focus := _world.get_node("SquadFocusComponent") as SquadFocusComponent
	var command := _world.get_node("SquadChainCommandController") as SquadChainCommandController
	_expect(command.get_bound_scope() == _world and focus.get_bound_scope() == _world, "one local world owns real command and focus")
	var party: Array[UnitBase] = [_hero]
	var positions := [Vector3(0,0,1),Vector3(-3,0,2),Vector3(-2,0,2),Vector3(0,0,2)]
	for i: int in range(4):
		var ally: AllyBase = command.companions[i]
		party.append(ally)
		ally.position = positions[i]
		ally.get_node("SkillHost").configure_owner(ally,_world)
		ally.set_physics_process(false)
		ally.automatic_skill_cast_enabled = false
		ally.get_combat_system().set_physics_process(false)
	# 重新绑定同一真实池以从0开始测试，不产生测试专用费用/伤害管线。
	focus.unbind_scope()
	focus.initial_focus = 0
	focus.focus_gain_difficulty = 0.1
	focus.bind_scope(_world,party)
	_hero.position = Vector3(-1,0,2.8)
	_hero.set_physics_process(false)
	for enemy: EnemyBase in _world.get_node("EnemyContainer").get_children():
		enemy.maximum_health = 50000
		enemy.apply_healing(50000)
		enemy.attack_power = 0
		enemy.movement_speed = 0
		enemy.get_targeting_component().detection_enabled = false
		enemy.get_combat_system().set_physics_process(false)
		enemy.damage_resolved.connect(func(_event): _damage += 1)
		_targets.append(enemy)
	_world.get_node("EnemyContainer/Unsupported").position = Vector3(-1,0,-1.8)
	var ends: Dictionary = {}
	for enemy: EnemyBase in _world.get_node("EnemyContainer").get_children():
		var receiver: UnitBase = enemy if enemy.forced_movement_enabled else null
		if receiver != null:
			receiver.forced_movement_finished.connect(func(_token,reason): ends[enemy.name] = {"position":enemy.global_position,"reason":reason})
	paused = true
	await _probe_input_gate("explicit pause")
	paused = false
	_hero.set_player_input_enabled(false)
	await _probe_input_gate("player permission disabled")
	_hero.set_player_input_enabled(true)
	var lease_owner := Node.new()
	_world.add_child(lease_owner)
	var lease_a := command.acquire_input_block(lease_owner,&"test_owner_a")
	var lease_b := command.acquire_input_block(_world,&"test_owner_b")
	_expect(not _hero.is_player_input_enabled(),"command input ownership reaches common player permission")
	command.release_input_block(lease_a)
	_expect(not _hero.is_player_input_enabled(),"releasing one input owner preserves another")
	_hero.set_player_input_enabled(false)
	command.release_input_block(lease_b)
	_expect(not _hero.is_player_input_enabled(),"releasing ownership preserves external baseline false")
	_hero.set_player_input_enabled(true)
	var vanished := command.acquire_input_block(lease_owner,&"test_owner_exit")
	lease_owner.free()
	await process_frame
	_expect(_hero.is_player_input_enabled(),"normal owner exit releases only its input lease")
	command.release_input_block(vanished)
	await _tap(&"player_skill_2")
	await _until(func(): return _world.get_status_snapshot().slots[1].finished == 1,2.0)
	_expect(_targets[0].get_status_effect_component().has_named_status(&"temporary_threat") and _targets[0].get_threat_component().get_threat_for(_hero)>1900, "E creates real bound temporary threat")
	await _until(func(): return _hero.get_node("SkillHost").is_global_cooldown_ready(),2.0)
	_hero.get_node(PlayerBase.TARGETING_SYSTEM_PATH).request_lock(_world.get_node("EnemyContainer/TrainingMelee"))
	await _tap(&"player_skill_1")
	await _until(func(): return ends.has(&"TrainingRanged"),2.0)
	for label: StringName in [&"TrainingRanged"]:
		var end: Dictionary = ends.get(label,{})
		_expect(end.get("reason") == &"arrived" and Vector2(end.get("position",Vector3(100,0,100)).x+2,end.get("position",Vector3(100,0,100)).z-1.0).length()<0.03,"Q reaches frozen gather disk: "+str(label))
	_expect(_damage == 0 and is_zero_approx(focus.get_current_focus()), "Q/E have no direct damage or focus while autonomous output isolated")
	for enemy: EnemyBase in _world.get_node("EnemyContainer").get_children():
		enemy.get_targeting_component().detection_enabled = true
		enemy.get_combat_system().set_physics_process(true)
	# 静止高耐久敌人避免随机击杀；恢复真实伙伴行为而非人工伤害或加专注。
	for i: int in range(4):
		var ally: AllyBase = command.companions[i]
		ally.position = positions[i]
		ally.set_physics_process(true)
		ally.automatic_skill_cast_enabled = true
		ally.get_combat_system().set_physics_process(true)
	_hero.get_node(PlayerBase.TARGETING_SYSTEM_PATH).request_lock(_targets[0])
	await _until(func(): return focus.get_available_focus() >= 20,12.0)
	_expect(_damage > 0 and focus.get_current_focus() >= 20,"ordinary autonomous damage generates actual focus from zero")
	command.command_accepted.connect(func(_request): _accepted += 1)
	command.command_released.connect(func(_id,_cost): _released += 1)
	var evaluation := _world.get_node("SquadChainRoundController") as SquadChainRoundController
	evaluation.score_difficulty = 0.1
	evaluation.damage_interval_seconds = 0.5
	var selection := _world.get_node("SquadFinisherSelectionController") as SquadFinisherSelectionController
	await _tap(&"squad_chain_3")
	await _until(func(): return selection.get_selection_status().phase in [1,2],8.0)
	_expect(_accepted == 1 and _released == 1,"actual input3 uses real command pipeline once")
	_expect(selection.get_selection_status().phase in [1,2] and evaluation.get_round_status().last_result.get("score",0) >= 100,"actual chain damage produces qualified finisher window")
	print("JOINT focus=",focus.get_current_focus()," damage events=",_damage," chain accepted/released=",_accepted,"/",_released)
	if selection.get_selection_status().phase in [1,2]:
		await _probe_input_gate("real finisher selection")
		await _tap(&"squad_chain_3")
		var execution := _world.get_node("SquadFinisherExecutionController") as SquadFinisherExecutionController
		var phases: Array[StringName] = []
		var tested: Array[StringName] = []
		var deadline := Time.get_ticks_msec()+9000
		while Time.get_ticks_msec()<deadline:
			var phase: StringName = execution.get_execution_status().phase
			if not phases.has(phase): phases.append(phase)
			if phase in [&"enter_closeup",&"windup",&"exit_closeup",&"bombardment"] and not tested.has(phase):
				tested.append(phase)
				await _probe_input_gate(str(phase))
			if phase == &"idle" and execution.get_execution_status().launched == 5: break
			await process_frame
		var result := execution.get_execution_status()
		print("JOINT finisher phases=",phases," result=",result)
		_expect(phases.has(&"enter_closeup") and phases.has(&"windup") and phases.has(&"exit_closeup") and phases.has(&"bombardment"),"real B cinematic crosses all camera gates")
		_expect(result.phase == &"idle" and result.launched == 5 and result.landed == 5 and result.main_effects_pending == 0,"real finisher releases all five projectiles and completes effects")
		_expect(_accepted == 1 and not paused and is_equal_approx(Engine.time_scale,1),"finisher input does not leak another chain and restores time")
	var controller := _hero.get_node("PlayerSkillController") as PlayerSkillController
	await _until(func(): return controller.get_slot_status(1).can_request,3.0)
	var casts_before: int = _world.get_status_snapshot().slots[1].accepted
	await _tap(&"player_skill_2")
	await _until(func(): return _world.get_status_snapshot().slots[1].accepted>casts_before,1.0)
	_expect(_world.get_status_snapshot().slots[1].accepted == casts_before+1,"Q/E resume after actual finisher")
	await _until(func(): return _world.get_status_snapshot().slots[1].finished>=2,2.0)
	_hero.apply_damage(100000)
	_expect(_hero.is_dead() and not controller.get_slot_status(0).can_request,"normal death blocks new requests")
	for enemy: UnitBase in _targets:
		_expect(not enemy.get_status_effect_component().has_named_status(&"temporary_threat") and is_zero_approx(enemy.get_threat_component().get_threat_for(_hero)),"source death removes E state and temporary contribution")
	var old_id := _hero.get_instance_id()
	_world.free()
	current_scene = null
	await process_frame
	root.set_meta(MODE,2)
	_world = load(SCENE).instantiate()
	root.add_child(_world)
	current_scene = _world
	await process_frame
	await process_frame
	_expect(_world.get_node("Hero").get_instance_id() != old_id and _world.get_status_snapshot().slots[0].accepted == 0,"one normal scene rebuild has new identity and clean counters")
	_expect(_world.get_node("Hero/SkillHost").get_regular_skill(0).is_ready(),"rebuilt scene does not inherit old cooldown")
	_world.free()
	current_scene = null
	await process_frame
	_expect(not paused and is_equal_approx(Engine.time_scale,1),"scene exit restores time")
	_finish()

# 真实输入与公开请求均须受同一个输入许可约束；不根据time_scale猜测终结状态。
func _probe_input_gate(label: String) -> void:
	var controller := _hero.get_node("PlayerSkillController") as PlayerSkillController
	var host := _hero.get_node("SkillHost") as SkillHostComponent
	var before: Dictionary = _world.get_status_snapshot()
	var cds := [host.get_regular_skill(0).get_cooldown_remaining(),host.get_regular_skill(1).get_cooldown_remaining()]
	var health := _total_health()
	await _tap(&"player_skill_1")
	await _tap(&"player_skill_2")
	_expect(not controller.request_slot(0) and not controller.request_slot(1),label+": direct requests must reject")
	var after: Dictionary = _world.get_status_snapshot()
	_expect(after.slots[0].accepted == before.slots[0].accepted and after.slots[1].accepted == before.slots[1].accepted,label+": input must not accept Q/E")
	_expect(after.slots[0].released == before.slots[0].released and after.slots[1].released == before.slots[1].released,label+": no new release/Effect")
	_expect(host.get_regular_skill(0).get_cooldown_remaining()<=cds[0]+0.01 and host.get_regular_skill(1).get_cooldown_remaining()<=cds[1]+0.01,label+": no cooldown consumed")
	if label == "explicit pause": _expect(is_equal_approx(health,_total_health()),"full pause freezes actual damage")
	# 仅失败运行的夹具收尾；正确实现不会进入此分支。
	if host.get_active_skill() != null: host.cancel_active_skill(&"failed_gate_fixture")

func _total_health() -> float:
	var total := 0.0
	for unit: UnitBase in _targets: total += unit.get_current_health()
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
func _until(predicate: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
func _expect(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _finish() -> void:
	for message: String in failures: printerr("FAIL: ",message)
	print("PlayerSkillCombinedFlowTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
