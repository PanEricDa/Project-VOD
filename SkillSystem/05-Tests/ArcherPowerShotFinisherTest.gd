extends SceneTree
## 真实SkillBase/弧线交付/正式战斗装配：一箭一个目标、玩家锁定、B时钟与取消清理。
const SKILL := "res://SkillSystem/00-Skills/Finisher_ArcherPowerShot/ArcherPowerShotFinisherSkill.tscn"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_expect(ResourceLoader.exists(SKILL), "Archer single-target finisher exists")
	if ResourceLoader.exists(SKILL):
		_test_authored_action_assembly()
		await _test_single_target_delivery()
		await _test_real_cinematic()
	for failure: String in failures:
		push_error(failure)
	print("ArcherPowerShotFinisherTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

## 正式Action必须同步工作台已保存片段，防止只更新预览而实际技能仍播放旧占位动作。
func _test_authored_action_assembly() -> void:
	var authored := (load("res://Item/Weapon/Bow/BowAnimationLibrary.res") as AnimationLibrary).get_animation("finish_attack_1")
	var skill := load(SKILL).instantiate() as SkillBase
	var official := skill.cinematic_profile.action_animation
	var motion := skill.get_motion_component()
	_expect(motion != null and motion.direction == SkillMotionComponent.Direction.BACKWARD and is_equal_approx(motion.distance_m,0.8), "formal finisher equips reusable 0.8m retreat")
	var begins := skill.cinematic_profile.marker_times(&"begin_skill_motion")
	var ends := skill.cinematic_profile.marker_times(&"end_skill_motion")
	_expect(begins.size() == 1 and ends.size() == 1 and begins[0] < ends[0], "formal action has one authored motion interval")
	_expect(skill.cinematic_profile.validate_configuration().is_empty(), "authored action retains the existing cinematic marker contract")
	_expect(is_equal_approx(official.length,authored.length) and official.get_track_count() == authored.get_track_count(), "formal finisher uses the authored animation rather than the old placeholder")
	var marker_times := skill.cinematic_profile.marker_times(&"release_action")
	_expect(marker_times.size() == 1 and is_equal_approx(skill.base_cast_time,marker_times[0]), "cast time preserves the authored release timing at original speed")
	for track: int in range(mini(official.get_track_count(),authored.get_track_count())):
		_expect(official.track_get_path(track) == authored.track_get_path(track) and official.track_get_type(track) == authored.track_get_type(track) and official.track_get_key_count(track) == authored.track_get_key_count(track), "formal tracks preserve authored targets and key counts")
		if official.track_get_type(track) != authored.track_get_type(track): continue
		for key: int in range(mini(official.track_get_key_count(track),authored.track_get_key_count(track))):
			_expect(is_equal_approx(official.track_get_key_time(track,key),authored.track_get_key_time(track,key)) and official.track_get_key_value(track,key) == authored.track_get_key_value(track,key), "formal snapshot preserves every authored pose and method key")
	skill.free()

func _test_single_target_delivery() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var actor := _unit(world, 1, Vector3.ZERO)
	actor.attack_power = 15.0
	var target := _unit(world, 2, Vector3(3,0,0))
	var neighbor := _unit(world, 2, Vector3(3.1,0,0))
	var friendly := _unit(world, 1, Vector3(3,0,0.1))
	var skill := load(SKILL).instantiate() as SkillBase
	var host := actor.get_node("SkillHost") as SkillHostComponent
	host.get_node("SkillSocket").add_child(skill)
	skill.configure_owner(actor,host,world)
	await process_frame
	var config := skill.delivery as ArcProjectileDeliveryConfig
	_expect(config != null and config.destination_mode == ArcProjectileDeliveryConfig.DestinationMode.UNIT_TARGET and config.shot_count == 1 and config.target_expansion == null, "one unit-target arrow without scatter or expansion")
	_expect(skill.cinematic_profile != null and skill.cinematic_profile.validate_configuration().is_empty(), "placeholder action supports the existing cinematic contract")
	_expect(not skill.automatic_cast_enabled and skill.skill_cooldown == 0.0, "finisher is external-only without an extra cooldown")
	_expect(skill.cast_effect_scene != null and skill.cast_effect_scene.resource_path == "res://Effects/Skills/ArcherPowerShot/ArcherPowerShotCastEffect.tscn", "formal finisher equips its muzzle-following green-blue charge")
	_expect(config.projectile_scene.resource_path == "res://Item/Projectiles/ArcherPowerShotProjectile.tscn", "formal finisher uses its dedicated straight light arrow")
	for resource: Resource in [skill.cinematic_profile,skill.cinematic_profile.action_animation,skill.camera_effect_profile]:
		_expect(ResourceLoader.get_resource_uid(resource.resource_path) != ResourceUID.INVALID_ID, "formal resource has an editor-registered UID")
	var context := SkillContext.new()
	context.caster = actor
	context.host = host
	context.delivery_parent = world
	context.requested_target = target
	context.explicit_target_requested = true
	context.candidate_targets.assign([target,neighbor,friendly])
	context.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
	context.activation_transform = actor.global_transform
	context.damage_context = CombatDamageContext.create(actor,world,CombatDamageContext.Origin.FINISHER,71,0,skill.skill_id)
	var facts := {"hits":0,"finished":false}
	target.damage_resolved.connect(func(event: CombatDamageEvent):
		if event.origin == CombatDamageContext.Origin.FINISHER:
			facts.hits += 1
			_expect(is_zero_approx(event.focus_yield_multiplier), "finisher damage does not carry focus recovery")
	)
	skill.delivery_finished.connect(func(_context,_result): facts.finished = true)
	_expect(skill.activate(context), "configured skill uses shared activation and projectile delivery")
	await _until(func() -> bool: return facts.finished, 2.0)
	_expect(facts.finished and facts.hits == 1 and is_equal_approx(target.get_current_health(),640.0), "one arrow deals360 raw damage exactly once")
	_expect(neighbor.get_current_health() == 1000.0 and friendly.get_current_health() == 1000.0 and actor.get_current_health() == 1000.0, "nearby enemies and allies are not hit")
	target.global_position = Vector3(skill.cast_range+1.0,0,0)
	_expect(not skill.activate(context), "configured initial range rejects a target one meter beyond it; tolerance does not extend initial range")
	world.free()
	await process_frame

func _test_real_cinematic() -> void:
	var scene := load("res://Scenes/CombatRoom.tscn").instantiate() as Node3D
	var actor := scene.get_node("Archer") as AllyBase
	for companion_name: String in ["Guardian","Priest","Caster","Archer"]:
		scene.get_node(companion_name).set("automatic_skill_cast_enabled",false)
	var player := scene.get_node("Hero") as PlayerBase
	player.position = actor.position + Vector3(-1,0,0)
	var target := _enemy(scene, actor.position+Vector3(3,0,0))
	var neighbor := _enemy(scene, actor.position+Vector3(2,0,0))
	root.add_child(scene)
	current_scene = scene
	actor.set_physics_process(false)
	var host := actor.get_node("SkillHost") as SkillHostComponent
	host.configure_owner(actor,scene)
	for frame: int in range(8): await physics_frame
	player.get_node(PlayerBase.TARGETING_SYSTEM_PATH).request_lock(target)
	var execution := scene.get_node("SquadFinisherExecutionController") as SquadFinisherExecutionController
	var command := scene.get_node("SquadChainCommandController") as SquadChainCommandController
	var camera := scene.get_node("CameraRig") as CameraFollowController
	var skill := host.get_finisher_skill()
	_expect(command.companions[3] == actor and skill != null and skill.scene_file_path == SKILL, "button4 actor equips the independent finisher")
	_expect(host.get_equipped_regular_skills().size() == 2 and host.get_combo_skill() != null, "regular and combo slots remain unchanged")
	var facts := {"target_hits":0,"neighbor_hits":0,"damage":0.0}
	target.damage_resolved.connect(func(event: CombatDamageEvent):
		if event.origin == CombatDamageContext.Origin.FINISHER:
			facts.target_hits += 1
			facts.damage += event.actual_damage
	)
	neighbor.damage_resolved.connect(func(event: CombatDamageEvent):
		if event.origin == CombatDamageContext.Origin.FINISHER: facts.neighbor_hits += 1
	)
	_expect(execution.begin_finisher(actor), "director accepts the equipped Archer finisher")
	var deadline := Time.get_ticks_msec()+5000
	var framed_as_single := false
	var slow_in_flight := false
	var impact_holds_slow := false
	var charge_seen := false
	while execution.get_execution_status().phase != &"idle" and Time.get_ticks_msec() < deadline:
		var state := execution.get_execution_status()
		if state.main_effects_pending > 0 and is_equal_approx(Engine.time_scale,0.05): impact_holds_slow = true
		var charge = skill.get("_cast_effect_instance")
		if is_instance_valid(charge) and charge.scene_file_path == "res://Effects/Skills/ArcherPowerShot/ArcherPowerShotCastEffect.tscn" and charge.call("is_playing"): charge_seen = true
		if state.phase == &"exit_closeup":
			framed_as_single = is_zero_approx(float(camera.get("_cinematic_radius")))
		if state.launched == 1 and state.landed == 0:
			slow_in_flight = is_equal_approx(Engine.time_scale,0.05)
		await process_frame
	var result := execution.get_execution_status()
	print("Archer runtime result: ",result)
	_expect(result.reason == &"completed" and result.launched == 1 and result.landed == 1, "single arrow completes B cinematic promptly")
	_expect(facts.target_hits == 1 and facts.neighbor_hits == 0 and is_equal_approx(facts.damage,360.0), "player locked target wins over the nearer enemy and receives one hit")
	_expect(framed_as_single, "single-target cinematic ignores unused ground scatter radii")
	_expect(slow_in_flight, "world stays five percent slow while the arrow uses its execution clock")
	_expect(impact_holds_slow and charge_seen, "formal cinematic plays its charge and waits for directional impact visuals before restoring world time")
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0), "successful hit restores time")
	# 交付结束允许世界恢复，但角色仍须把作者定义的后摇播放完，才释放动作锁。
	await _until(func() -> bool: return host.get_finisher_action_context() == null, 3.0)
	_expect(host.get_finisher_action_context() == null, "authored recovery completes without leaving an action lock")
	# 前摇期间目标死亡，沿现有合法性检查取消，不能留下镜头或时间占用。
	_expect(execution.begin_finisher(actor), "another explicit finisher request can start without cooldown")
	await _until(func() -> bool: return execution.get_execution_status().phase == &"windup", 2.0)
	_expect(execution.get_execution_status().phase == &"windup", "cancellation fixture actually reaches windup before target death")
	target.apply_damage(99999.0,actor)
	await _until(func() -> bool: return execution.get_execution_status().phase == &"idle", 2.0)
	print("Archer dead-target result: ",execution.get_execution_status())
	_expect(execution.get_execution_status().phase == &"idle" and execution.get_execution_status().launched == 0 and execution.get_execution_status().reason == &"target_invalid_on_release", "dead target before release cancels specifically for invalid target without an arrow")
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0) and not camera.is_cinematic_active(), "cancelled windup releases its camera and time ownership")
	scene.free()
	current_scene = null
	await process_frame

func _unit(world: Node, team: int, point: Vector3) -> UnitBase:
	var unit := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	unit.team_id = team
	unit.maximum_health = 1000.0
	unit.defense = 0.0
	world.add_child(unit)
	unit.global_position = point
	return unit

func _enemy(scene: Node, point: Vector3) -> EnemyBase:
	var enemy := load("res://UnitSystem/AI/Enemy/Units/GoblinWarrior.tscn").instantiate() as EnemyBase
	enemy.maximum_health = 1000.0
	enemy.defense = 0.0
	enemy.attack_power = 0.0
	enemy.movement_speed = 0.0
	enemy.position = point
	scene.add_child(enemy)
	return enemy

func _until(predicate: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000.0)
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
