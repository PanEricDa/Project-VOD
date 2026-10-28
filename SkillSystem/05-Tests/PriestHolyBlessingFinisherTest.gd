extends SceneTree

const SKILL = "res://SkillSystem/00-Skills/Finisher_HolyBlessing/HolyBlessingFinisherSkill.tscn"
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	if not ResourceLoader.exists(SKILL):
		printerr("FAIL: Priest blessing finisher scene missing")
		quit(1)
		return
	await _area_case()
	await _director_case()
	for failure: String in failures: printerr("FAIL: ",failure)
	print("PriestHolyBlessingFinisherTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _area_case() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world,1,Vector3.ZERO)
	var friendly := _unit(world,1,Vector3(8,0,0))
	var outside := _unit(world,1,Vector3(8.1,0,0))
	var hostile := _unit(world,2,Vector3(1,0,0))
	var dead := _unit(world,1,Vector3(1,0,0))
	dead.apply_damage(100000)
	var skill := load(SKILL).instantiate() as SkillBase
	world.add_child(skill)
	skill.configure_owner(caster,null,world)
	var context := SkillContext.new()
	context.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
	context.explicit_target_requested = true
	context.requested_target = caster
	context.activation_transform = caster.global_transform
	context.candidate_targets.assign([caster,friendly,friendly,outside,hostile,dead])
	_check(skill.activate(context), "shared pipeline releases self-centered blessing")
	for unit: UnitBase in [caster,friendly]:
		var status: StatusEffectComponent = unit.get_status_effect_component()
		_check(is_equal_approx(CombatValueResolver.calculate_damage(unit,hostile,100,0),130), "self and boundary friend gain30 percent damage")
		_check(status.get_active_modifier_count() == 1, "recipient receives one modifier despite duplicates")
		_check(unit.has_node(^"StatusModifierVisuals"), "recipient gets state-owned visual container")
	_check(outside.get_status_effect_component().get_active_modifier_count() == 0, "outside target not blessed")
	_check(hostile.get_status_effect_component().get_active_modifier_count() == 0, "hostiles not blessed")
	_check(dead.get_status_effect_component().get_active_modifier_count() == 0, "dead ally not blessed")
	friendly.position = Vector3(20,0,0)
	var status: StatusEffectComponent = friendly.get_status_effect_component()
	status.advance_effects(10)
	_check(is_equal_approx(CombatValueResolver.calculate_damage(friendly,hostile,100,0),130), "leaving radius keeps applied blessing")
	var visuals := friendly.get_node(^"StatusModifierVisuals")
	_check(visuals.get_child_count() == 1, "one visual instance is active")
	friendly.position = Vector3(8,0,0)
	_check(skill.activate(context), "repeat release succeeds in fixture")
	_check(status.get_active_modifier_count() == 1 and visuals.get_child_count() == 1, "refresh neither stacks buff nor duplicates visual")
	status.advance_effects(15)
	var fade_end := Time.get_ticks_msec()+1000
	while visuals.get_child_count() > 0 and Time.get_ticks_msec()<fade_end: await process_frame
	_check(is_equal_approx(CombatValueResolver.calculate_damage(friendly,hostile,100,0),100), "15-second expiry removes bonus")
	_check(visuals.get_child_count() == 0, "state expiry removes persistent visual")
	_check(skill.cinematic_profile.validate_configuration().is_empty(), "formal cinematic animation markers valid")
	for resource: Resource in [skill.cinematic_profile,skill.camera_effect_profile,skill.cinematic_profile.action_animation]:
		_check(ResourceLoader.get_resource_uid(resource.resource_path) != ResourceUID.INVALID_ID, "formal resource UID is registered")
	world.free()
	await process_frame

func _director_case() -> void:
	var scene = load("res://Scenes/CombatRoom.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor := scene.get_node(^"Priest") as AllyBase
	actor.set_physics_process(false)
	actor.automatic_skill_cast_enabled = false
	var execution := scene.get_node(^"SquadFinisherExecutionController") as SquadFinisherExecutionController
	var host := actor.get_node(^"SkillHost") as SkillHostComponent
	host.configure_owner(actor,scene)
	var skill := host.get_finisher_skill()
	_check(skill != null and skill.scene_file_path == SKILL, "Priest formally equips finisher")
	await physics_frame
	var beyond_perception := _unit(scene,1,actor.global_position+Vector3(7.8,0,0))
	var late_friend := _unit(scene,1,actor.global_position+Vector3(9,0,0))
	_check(execution.get_actor_availability(actor).is_empty(), "Priest selectable without enemy lock")
	host.finisher_action_cancelled.connect(func(_ctx,why): print("Priest cancelled: ",why))
	skill.skill_failed.connect(func(_ctx,why): print("Priest failed: ",why))
	host.skill_released.connect(func(ctx): print("Priest release: ",ctx.purpose))
	host.finisher_action_started.connect(func(_ctx): print("Priest started"))
	_check(execution.begin_finisher(actor), "director starts real Priest finisher")
	var deadline := Time.get_ticks_msec()+4500
	var saw_closeup := false
	var moved_during_windup := false
	while execution.get_execution_status().phase != &"idle" and Time.get_ticks_msec()<deadline:
		var windup: bool = execution.get_execution_status().phase == &"windup"
		saw_closeup = saw_closeup or windup
		if windup and not moved_during_windup:
			moved_during_windup = true
			late_friend.global_position = actor.global_position+Vector3(7.9,0,0)
		await process_frame
	_check(saw_closeup and moved_during_windup, "real finisher includes closeup and ally enters during actual windup")
	print("Priest director result: ",execution.get_execution_status())
	var player := actor.get_node("Visual").find_child("CharacterAnimationPlayer",true,false) as AnimationPlayer
	print("Priest animation: ",player.current_animation," pos=",player.current_animation_position," speed=",player.get_playing_speed()," paused=",paused," scale=",Engine.time_scale," context=",host.get_finisher_action_context())
	_check(execution.get_execution_status().reason == &"completed", "instant blessing completes B director")
	print("Priest multiplier=",actor.get_outgoing_damage_multiplier()," modifiers=",actor.get_status_effect_component().get_active_modifier_count()," skill_effect=",skill.get_node("DamageBlessingEffect").modifier_stat," recipients=",skill.get_node("DamageBlessingEffect").target_mode," candidates=",host.prepare_finisher_context().candidate_targets.size())
	_check(is_equal_approx(CombatValueResolver.calculate_damage(actor,null,100,0),130), "actual animation marker applies blessing")
	_check(is_equal_approx(CombatValueResolver.calculate_damage(beyond_perception,null,100,0),130), "real release blesses ally beyond6m perception but inside8m")
	_check(is_equal_approx(CombatValueResolver.calculate_damage(late_friend,null,100,0),130), "ally entering radius during windup receives blessing")
	_check(not paused and is_equal_approx(Engine.time_scale,1), "world pause and slow tokens released")
	var end := Time.get_ticks_msec()+1500
	while host.has_command_action_lock() and Time.get_ticks_msec()<end: await process_frame
	_check(not host.has_command_action_lock(), "recovery animation releases action lock")
	scene.free()
	current_scene = null
	await process_frame

func _unit(world: Node,team: int,at: Vector3) -> UnitBase:
	var unit := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	unit.team_id = team
	unit.maximum_health = 10000
	unit.defense = 0
	unit.position = at
	world.add_child(unit)
	unit.get_status_effect_component().set_physics_process(false)
	return unit
func _check(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
