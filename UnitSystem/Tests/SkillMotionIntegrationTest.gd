extends SceneTree
var failures: Array[String] = []
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("_run_lifecycle" if OS.get_cmdline_user_args().has("--lifecycle-only") else "_run")
func _run_lifecycle() -> void:
	for mode: int in range(7):
		if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] != str(mode): continue
		await _cancellation_case(mode)
	if OS.get_cmdline_user_args().size() <= 1 or OS.get_cmdline_user_args()[1] == "reentrant": await _reentrant_case()
	for message: String in failures: printerr("FAIL: ", message)
	print("SkillMotionLifecycle: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _run() -> void:
	var skill := SkillBase.new()
	var component = load("res://SkillSystem/03-Extensions/SkillMotionComponent.tscn").instantiate()
	skill.add_child(component)
	_check(skill.has_method("get_motion_component"), "SkillBase exposes typed motion component")
	_check(bool(skill.get_action_payload().get("skill_motion_enabled",false)), "normal action payload enables attached motion")
	var host := SkillHostComponent.new()
	_check(host.has_method("consume_action_motion_sample") and host.has_signal("skill_motion_step_requested"), "host routes motion independently of casting state")
	var combat := AICombatSystem.new()
	_check(combat.has_signal("external_action_motion_sample") and combat.has_method("get_external_action_serial"), "combat forwards sample contract")
	combat.free()
	host.free()
	skill.free()
	for scale: float in [1.0,0.05,0.2]:
		for speed: float in [0.5,1.0,2.0]:
			await _runtime_case(scale,speed,false)
	await _runtime_case(0.05,1.0,true)
	await _runtime_case(1.0,1.0,false,true)
	await _runtime_case(1.0,1.0,false,false,true)
	for mode: int in range(7): await _cancellation_case(mode)
	await _room_case()
	await _reentrant_case()
	Engine.time_scale = 1.0
	if failures.is_empty(): print("SkillMotionIntegrationTest: PASS")
	else:
		for f: String in failures: printerr("FAIL: ", f)
	quit(0 if failures.is_empty() else 1)


func _runtime_case(scale: float, speed: float, exercise_hold: bool, regular: bool = false, end_at_clip: bool = false) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var actor = load("res://UnitSystem/AI/Ally/Units/Archer.tscn").instantiate()
	actor.automatic_skill_cast_enabled = false
	actor.gravity_multiplier = 0.0
	var target = load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate()
	target.team_id = 2
	target.maximum_health = 10000
	target.defense = 0
	world.add_child(target)
	target.position = Vector3(0,0,-3)
	world.add_child(actor)
	var h := actor.get_node("SkillHost") as SkillHostComponent
	h.configure_owner(actor,world)
	var equipped := h.get_finisher_skill()
	if end_at_clip:
		equipped.cinematic_profile = equipped.cinematic_profile.duplicate(true)
		var animation := equipped.cinematic_profile.action_animation
		for t: int in range(animation.get_track_count()):
			if animation.track_get_type(t) != Animation.TYPE_METHOD: continue
			for k: int in range(animation.track_get_key_count(t)):
				var value: Dictionary = animation.track_get_key_value(t,k)
				if value.get("method") == &"end_skill_motion":
					animation.track_set_key_time(t,k,animation.length)
					break
	equipped.base_cast_time = equipped.cinematic_profile.marker_times(&"release_action")[0] / speed
	var clock := SkillExecutionClock.new()
	clock.configure(world)
	var context := h.prepare_finisher_context(target,[target])
	_check(context != null,"real equipped finisher prepares")
	if context == null:
		world.free()
		return
	context.execution_clock = clock
	if regular:
		equipped.cinematic_profile = null
		var action := MeleeSkillAction.new()
		action.action_animation_name = &"finish_attack_1"
		equipped.add_child(action)
		h.finisher_skill = null
		h.regular_skills = [equipped,null]
	var facts := {"began":false,"terminal":false,"start":Vector3.ZERO,"first":Vector3.ZERO,"total":Vector3.ZERO,"steps":0,"hits":0,"after_release":false}
	target.damage_resolved.connect(func(event: CombatDamageEvent):
		if event.skill_id == equipped.skill_id: facts.hits += 1)
	h.skill_motion_step_requested.connect(func(_id: int, _serial: int, step: Vector3, terminal: bool):
		if not facts.began:
			facts.began = true
			facts.start = actor.position
			facts.first = step
		facts.steps += 1
		facts.total += step
		facts.terminal = terminal
		if equipped.get_state() != SkillBase.SkillState.CASTING: facts.after_release = true)
	Engine.time_scale = scale
	await physics_frame
	_check(h.request_skill(equipped.skill_id,target,[target]) if regular else h.activate_finisher(context),"actual Host starts motion skill")
	var deadline := Time.get_ticks_msec()+7000
	var held := false
	var switched := false
	var before_pause := Vector3.ZERO
	while not facts.terminal and Time.get_ticks_msec()<deadline:
		await process_frame
		if exercise_hold and facts.began and not held:
			held = true
			clock.hold_action(true)
			before_pause = actor.position
			await create_timer(0.06,true,false,true).timeout
			_check(actor.position.distance_to(before_pause)<0.001,"camera action hold stops physical displacement")
			paused = true
			await create_timer(0.04,true,false,true).timeout
			_check(actor.position.distance_to(before_pause)<0.001,"true pause stops movement")
			paused = false
			clock.hold_action(false)
		if exercise_hold and facts.total.length()>=0.4 and not switched:
			switched = true
			Engine.time_scale = 1.0
			clock.use_world_time()
	# 信号早于同帧角色物理；渲染帧观察时末段已消费。
	await process_frame
	_check(facts.began and facts.terminal, "motion interval completes scale=%s speed=%s" % [scale,speed])
	if facts.began:
		var displacement: Vector3 = actor.position-facts.start
		_check(absf(displacement.z-0.8)<0.03 and absf(displacement.x)<0.01,"actual collision displacement .8m scale=%s speed=%s got=%s" % [scale,speed,displacement])
		_check((-actor.get_node("Visual").global_basis.z).dot(Vector3.FORWARD)>0.99,"stable facing during backflip")
		_check(facts.after_release,"released skill still routes recovery motion")
	var finish_deadline := Time.get_ticks_msec()+3000
	while actor.get_combat_system().is_action_in_progress() and Time.get_ticks_msec()<finish_deadline: await process_frame
	_check(h.get_finisher_action_context()==null,"motion action releases lock")
	_check(facts.hits==1,"already-launched arrow hits exactly once")
	var stop: Vector3 = actor.position
	for i: int in range(3): await physics_frame
	_check(actor.position.distance_to(stop)<0.01,"no residual motion")
	Engine.time_scale = 1.0
	world.free()
	await process_frame


func _cancellation_case(mode: int) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var actor = load("res://UnitSystem/AI/Ally/Units/Archer.tscn").instantiate()
	actor.automatic_skill_cast_enabled = false
	actor.gravity_multiplier = 0.0
	world.add_child(actor)
	var target = load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate()
	target.team_id = 2
	target.maximum_health = 10000
	world.add_child(target)
	target.position = Vector3(0,0,-3)
	var host := actor.get_node("SkillHost") as SkillHostComponent
	host.configure_owner(actor,world)
	var seen := {"motion":false,"hits":0}
	host.skill_motion_step_requested.connect(func(_id,_serial,_step,_terminal): seen.motion = true)
	target.damage_resolved.connect(func(_event): seen.hits += 1)
	var equipped := host.get_finisher_skill()
	if mode == 4:
		equipped.cinematic_profile = null
		var action := MeleeSkillAction.new()
		action.action_animation_name = &"finish_attack_1"
		equipped.add_child(action)
		host.finisher_skill = null
		host.regular_skills = [equipped,null]
	var orphan: Node
	if mode == 5:
		host.skill_motion_step_requested.connect(func(_id,_serial,_step,terminal):
			if terminal:
				seen["terminal"] = true
				seen["terminal_position"] = actor.position
				host.cancel_active_skill(&"terminal_hard_cancel"))
	_check(host.request_skill(equipped.skill_id,target,[target]) if mode == 4 else host.request_finisher(target,[target]),"cancellation fixture begins through Host")
	var deadline := Time.get_ticks_msec()+4000
	while not seen.motion and Time.get_ticks_msec()<deadline: await process_frame
	_check(seen.motion,"cancellation fixture reaches moving recovery")
	match mode:
		0: host.cancel_active_skill(&"test_interrupt")
		1: equipped.get_motion_component().free()
		2:
			orphan = equipped.get_motion_component()
			equipped.remove_child(orphan)
		3: actor.get_behavior_state_machine().configure(actor,actor.get_targeting_component(),actor.get_combat_system(),null)
		4:
			orphan = actor.get_combat_system().get_attack_controller()
			orphan.get_parent().remove_child(orphan)
		5:
			while not seen.get("terminal",false) and Time.get_ticks_msec()<deadline: await process_frame
		6:
			orphan = equipped
			equipped.get_parent().remove_child(equipped)
	var point: Vector3 = actor.position
	for i: int in range(6): await physics_frame
	await process_frame
	_check(actor.position.distance_to(point)<0.03,"hard cancellation stops motion mode=%d" % mode)
	if mode == 5: _check(actor.position.distance_to(seen.get("terminal_position",actor.position))<0.0001,"hard cancellation retracts queued terminal slice")
	deadline = Time.get_ticks_msec()+3000
	while actor.get_combat_system().is_action_in_progress() and Time.get_ticks_msec()<deadline: await process_frame
	_check(not bool(actor.get("_skill_motion_active")),"cleanup leaves no navigation lock mode=%d" % mode)
	if mode == 4:
		var ap = actor.get_node("Visual").get_child(0).get_node("CharacterAnimationPlayer")
		_check(ap.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,"removing normal controller restores animation processing")
	if orphan != null: orphan.free()
	_check(seen.hits==1,"cancelled recovery does not retract or duplicate launched arrow")
	world.free()
	await process_frame

func _room_case() -> void:
	var scene = load("res://Scenes/CombatRoom.tscn").instantiate()
	for name: String in ["Guardian","Priest","Caster","Archer"]: scene.get_node(name).automatic_skill_cast_enabled = false
	var actor := scene.get_node("Archer") as AllyBase
	var target = load("res://UnitSystem/AI/Enemy/Units/GoblinWarrior.tscn").instantiate()
	target.position = actor.position + Vector3(3,0,0)
	target.maximum_health = 10000
	target.defense = 0
	target.attack_power = 0
	target.movement_speed = 0
	scene.add_child(target)
	root.add_child(scene)
	current_scene = scene
	for name: String in ["Guardian","Priest","Caster"]: scene.get_node(name).set_physics_process(false)
	target.set_physics_process(false)
	var player := scene.get_node("Hero") as PlayerBase
	player.position = actor.position+Vector3(-1,0,0)
	for i: int in range(5): await physics_frame
	player.get_node(PlayerBase.TARGETING_SYSTEM_PATH).request_lock(target)
	var host := actor.get_node("SkillHost") as SkillHostComponent
	host.configure_owner(actor,scene)
	var facts := {"began":false,"terminal":false,"start":Vector3.ZERO,"direction":Vector3.ZERO,"hits":0}
	host.skill_motion_step_requested.connect(func(_id,_serial,step,terminal):
		if not facts.began:
			facts.began = true
			facts.start = actor.position
			facts.direction = step.normalized()
		facts.terminal = terminal)
	target.damage_resolved.connect(func(event: CombatDamageEvent):
		if event.origin == CombatDamageContext.Origin.FINISHER: facts.hits += 1)
	var director := scene.get_node("SquadFinisherExecutionController") as SquadFinisherExecutionController
	_check(director.begin_finisher(actor),"CombatRoom actual B director starts Archer")
	var deadline := Time.get_ticks_msec()+6000
	while not facts.terminal and Time.get_ticks_msec()<deadline: await process_frame
	await process_frame
	_check(actor.is_physics_processing() and facts.terminal,"CombatRoom Archer keeps true physics processing")
	if facts.terminal:
		var moved: Vector3 = actor.position - facts.start
		moved.y = 0
		_check(absf(moved.dot(facts.direction)-0.8)<0.03,"CombatRoom actual director retreats 0.8m")
		_check((-actor.get_node("Visual").global_basis.z).dot(-facts.direction)>0.99,"CombatRoom remains facing target")
	deadline = Time.get_ticks_msec()+3000
	while host.get_finisher_action_context()!=null and Time.get_ticks_msec()<deadline: await process_frame
	_check(facts.hits==1 and is_equal_approx(Engine.time_scale,1.0) and not paused,"CombatRoom arrow once, world restored, recovery finishes")
	scene.free()
	current_scene = null
	await process_frame


func _reentrant_case() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var actor = load("res://UnitSystem/AI/Ally/Units/Archer.tscn").instantiate()
	actor.automatic_skill_cast_enabled = false
	actor.gravity_multiplier = 0
	world.add_child(actor)
	var target = load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate()
	target.team_id = 2
	target.maximum_health = 10000
	world.add_child(target)
	target.position = Vector3(0,0,-3)
	var host := actor.get_node("SkillHost") as SkillHostComponent
	host.configure_owner(actor,world)
	var skill := host.get_finisher_skill()
	var facts := {"switched":false,"accepted_new":false,"new_serial":-1,"hits":0}
	target.damage_resolved.connect(func(_event): facts.hits += 1)
	skill.cast_started.connect(func(_context):
		if facts.switched: return
		facts.switched = true
		host.cancel_active_skill(&"replace_cast")
		facts.accepted_new = host.request_finisher(target,[target])
		facts.new_serial = actor.get_combat_system().get_external_action_serial())
	host.request_finisher(target,[target])
	_check(facts.switched and facts.accepted_new,"cast listener synchronously starts replacement action")
	_check(host.get_finisher_action_context()!=null and actor.get_combat_system().get_external_action_serial()==facts.new_serial,"old confirmation failure cannot cancel replacement action")
	var deadline := Time.get_ticks_msec()+4000
	while actor.get_combat_system().is_action_in_progress() and Time.get_ticks_msec()<deadline: await process_frame
	_check(facts.hits==1,"replacement action delivers once through real behavior layer")
	_check(not bool(actor.get("_skill_motion_active")),"replacement action leaves no motion lock")
	world.free()
	await process_frame
