extends SceneTree
## 真实SkillBase与瞬发交付：自身中心范围、先伤后破甲、刷新到期及独立终结装配。
const SKILL = "res://SkillSystem/00-Skills/Finisher_GuardianArmorBreak/GuardianArmorBreakFinisherSkill.tscn"
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	_expect(ResourceLoader.exists(SKILL), "Guardian finisher skill scene exists")
	if not ResourceLoader.exists(SKILL):
		_finish()
		return
	_test_animation_asset()
	await _test_area_and_refresh()
	await _test_real_execution()
	_finish()
## 防止空片段、错误动画库、丢失方法帧或正式技能仍引用旧盾击；同时检查蓄力停势与最终归位。
func _test_animation_asset() -> void:
	var library := load("res://Item/Weapon/Shield/ShieldAnimationLibrary.res") as AnimationLibrary
	_expect(library.has_animation(&"finish_attack_1"), "Shield library persists the existing finisher clip")
	if not library.has_animation(&"finish_attack_1"): return
	var animation := library.get_animation(&"finish_attack_1")
	var profile := SkillCinematicProfile.new()
	profile.action_animation = animation
	_expect(profile.validate_configuration().is_empty(), "finisher is non-looping with unique valid release and finish markers")
	_expect(is_equal_approx(animation.length,1.33333333333333), "Guardian uses the approved Caster-length action framework")
	_expect(profile.marker_times(&"release_action").size() == 1 and is_equal_approx(profile.marker_times(&"release_action")[0],0.6), "shield impact releases at0.6 seconds")
	_expect(profile.marker_times(&"finish_action").size() == 1 and is_equal_approx(profile.marker_times(&"finish_action")[0],0.76666666666667), "finish marker follows release")
	var workbench := load("res://UnitSystem/Visuals/Workbench/HeroAnimationWorkbench.tscn").instantiate() as Node3D
	var player := workbench.get_node("HeroVisual/CharacterAnimationPlayer") as AnimationPlayer
	var body := workbench.get_node("HeroVisual/CharacterRoot") as Node3D
	var socket := workbench.get_node("HeroVisual/CharacterRoot/WeaponSocket") as Node3D
	_expect(socket.has_node("ProjectileOrigin") and player.has_animation_library(&"unit"), "workbench preserves base endpoints regardless of the currently authored weapon")
	# 工作台的预览武器随制作任务切换；Guardian姿态测试显式装载盾牌，不能依赖当前保存的预览选择。
	for child: Node in socket.get_children():
		if not child.scene_file_path.is_empty():
			socket.remove_child(child)
			child.free()
	var shield := load("res://Item/Weapon/Shield/IronShieldVisual.tscn").instantiate() as Node3D
	socket.add_child(shield)
	# 先在离树夹具中替换预览武器，避免临时Staff CSG进树后立即销毁留下异步几何任务。
	root.add_child(workbench)
	player.add_animation_library(&"guardian_fixture", library)
	if player.has_animation(&"guardian_fixture/finish_attack_1"):
		player.play(&"guardian_fixture/finish_attack_1")
		player.seek(0.25,true)
		var held_body := body.transform
		var held_shield := socket.transform
		_expect(socket.position.y > 0.7, "pre-release shield is raised rather than the old short bash")
		player.seek(0.48,true)
		_expect(body.transform.is_equal_approx(held_body) and socket.transform.is_equal_approx(held_shield), "windup holds a stable readable close-up pose")
		player.seek(0.6,true)
		# 释放姿态以策划最新动画为准，不锁死盾牌高度或强迫在此帧砸到地面。
		_expect(body.transform.is_finite() and socket.transform.is_finite(), "authored release pose has valid finite transforms")
		player.seek(animation.length,true)
		_expect(body.position.is_zero_approx() and body.rotation.is_zero_approx(), "body returns to its baseline without residual turn")
		_expect(socket.position.is_equal_approx(Vector3(0.32,0.28,-0.22)) and socket.rotation.is_zero_approx(), "shield returns to the common socket baseline")
		player.stop()
	workbench.free()
	var skill := load(SKILL).instantiate() as SkillBase
	var official := skill.cinematic_profile.action_animation
	_expect(skill.cinematic_profile.validate_configuration().is_empty(), "official cinematic accepts the synchronized action")
	_expect(is_equal_approx(skill.base_cast_time,0.6) and is_equal_approx(official.length,animation.length), "skill timing no longer compresses the new animation")
	_expect(official.get_track_count() == animation.get_track_count(), "formal snapshot contains the authored tracks")
	for track: int in range(animation.get_track_count()):
		_expect(animation.track_get_path(track) in [^"CharacterRoot:position",^"CharacterRoot:rotation",^"CharacterRoot/WeaponSocket:position",^"CharacterRoot/WeaponSocket:rotation",^"CharacterAnimationPlayer"], "animation only drives the two visual endpoints and standard event bridge")
		if track >= official.get_track_count(): continue
		_expect(official.track_get_path(track) == animation.track_get_path(track) and official.track_get_key_count(track) == animation.track_get_key_count(track), "formal animation track matches the authored library clip")
		for key: int in range(mini(animation.track_get_key_count(track),official.track_get_key_count(track))):
			_expect(is_equal_approx(official.track_get_key_time(track,key),animation.track_get_key_time(track,key)) and official.track_get_key_value(track,key) == animation.track_get_key_value(track,key), "formal snapshot preserves the authored pose and timing")
	_expect(ResourceLoader.get_resource_uid("res://Item/Weapon/Shield/ShieldAnimationLibrary.res") == ResourceUID.text_to_id("uid://njpdtps8x2gh"), "shield library retains its existing UID")
	skill.free()
func _test_area_and_refresh() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var actor := _unit(world,1,Vector3.ZERO)
	actor.attack_power = 8.0
	var near := _unit(world,2,Vector3(2,0,0))
	var edge := _unit(world,2,Vector3(4,0,0))
	var outside := _unit(world,2,Vector3(4.1,0,0))
	var friendly := _unit(world,1,Vector3(1,0,0))
	var skill := load(SKILL).instantiate() as SkillBase
	actor.get_node("SkillHost/SkillSocket").add_child(skill)
	skill.configure_owner(actor,actor.get_node("SkillHost"),world)
	await process_frame
	var snapshots: Array[float] = []
	near.damage_resolved.connect(func(_event): snapshots.append(near.get_defense()))
	var context := SkillContext.new()
	context.caster = actor
	context.host = actor.get_node("SkillHost")
	context.delivery_parent = world
	context.candidate_targets.assign([near,edge,outside,friendly])
	context.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
	context.activation_transform = actor.global_transform
	# 内容测试走通用触发；正式FINISHER角色动作与导演在下一个用例独立验证。
	context.purpose = SkillContext.Purpose.REGULAR
	context.damage_context = CombatDamageContext.create(actor,world,CombatDamageContext.Origin.FINISHER,77,0)
	context.explicit_target_requested = true
	context.requested_target = actor
	_expect(skill.activate(context), "configured finisher uses shared activation and instant pipeline")
	_expect(snapshots == [80.0], "damage resolves before armor reduction on first hit")
	_expect(is_equal_approx(near.get_current_health(),1000.0-28.0/1.8), "base20 plus attack8 damage passes through existing defense formula")
	_expect(near.get_current_health() < 1000.0 and edge.get_current_health() < 1000.0, "inside and four-meter boundary enemies hit")
	_expect(near.get_current_health() == edge.get_current_health(), "each enemy takes exactly one equal hit")
	_expect(is_equal_approx(near.get_defense(),60.0) and is_equal_approx(edge.get_defense(),60.0), "hit enemies lose25 percent defense")
	var row := near.get_node("WorldUIRoot/WorldHealthBar/HealthBarViewport/DebuffDots")
	_expect(row.has_node("DefenseDownDot"), "actual finisher armor break appears in the floating health bar")
	_expect(outside.get_current_health() == 1000.0 and outside.get_defense() == 80.0, "out-of-radius enemy untouched")
	_expect(friendly.get_current_health() == 1000.0 and friendly.get_defense() == 80.0, "friendly untouched")
	var status := near.get_status_effect_component()
	status.advance_effects(10.0)
	_expect(skill.activate(context), "zero cooldown finisher can be triggered again in test")
	_expect(status.get_active_modifier_count() == 1 and near.get_defense() == 60.0, "repeat skill refreshes rather than stacking")
	status.advance_effects(14.9)
	_expect(near.get_defense() == 60.0, "refreshed effect remains until15 seconds")
	status.advance_effects(0.1)
	_expect(near.get_defense() == 80.0, "expiry restores defense")
	_expect(not row.has_node("DefenseDownDot"), "actual armor expiry removes its floating marker")
	# 前序伤害击杀首个目标时，后续破甲应安全跳过它，并继续处理其他敌人。
	near.apply_damage(near.get_current_health()-1.0,actor)
	var edge_health := edge.get_current_health()
	_expect(skill.activate(context), "lethal target does not cancel the area delivery")
	_expect(near.is_dead() and near.get_status_effect_component().get_active_modifier_count() == 0, "dead target gets no lingering armor modifier")
	_expect(edge.get_current_health() < edge_health and edge.get_defense() == 60.0, "later targets still receive damage and armor break")
	for resource: Resource in [skill.cinematic_profile,skill.camera_effect_profile,skill.cinematic_profile.action_animation]:
		_expect(ResourceLoader.get_resource_uid(resource.resource_path) != ResourceUID.INVALID_ID, "formal resource has valid UID")
	world.free()
	await process_frame
func _test_real_execution() -> void:
	var scene := load("res://Scenes/CombatRoom.tscn").instantiate() as Node3D
	var actor := scene.get_node("Guardian") as AllyBase
	actor.automatic_skill_cast_enabled = false
	root.add_child(scene)
	current_scene = scene
	actor.set_physics_process(false)
	var host := actor.get_node("SkillHost") as SkillHostComponent
	host.configure_owner(actor,scene)
	var target := load("res://UnitSystem/AI/Enemy/Units/GoblinWarrior.tscn").instantiate() as EnemyBase
	target.maximum_health = 1000.0
	target.defense = 80.0
	target.attack_power = 0.0
	target.movement_speed = 0.0
	scene.add_child(target)
	target.global_position = actor.global_position+Vector3(2,0,0)
	target.get_status_effect_component().set_physics_process(false)
	for frame: int in range(8): await physics_frame
	var execution := scene.get_node("SquadFinisherExecutionController") as SquadFinisherExecutionController
	var skill := host.get_finisher_skill()
	_expect(skill != null and skill.scene_file_path == SKILL, "Guardian equips separate finisher without changing regular/combo slots")
	if skill != null:
		_expect(execution.get_actor_availability(actor).is_empty(), "equipped Guardian is selectable")
		_expect(execution.begin_finisher(actor), "director accepts Guardian self-centered finisher")
		var deadline := Time.get_ticks_msec()+4000
		var area_framed := false
		var camera := scene.get_node("CameraRig") as CameraFollowController
		while execution.get_execution_status().phase != &"idle" and Time.get_ticks_msec()<deadline:
			if execution.get_execution_status().phase == &"exit_closeup":
				area_framed = is_equal_approx(float(camera.get("_cinematic_radius")),4.0)
			await process_frame
		_expect(area_framed, "camera frames delivery radius without another manual range setting")
		var result := execution.get_execution_status()
		print("Guardian runtime result: ",result.reason," defense=",target.get_defense()," health=",target.get_current_health())
		_expect(result.phase == &"idle" and result.reason == &"completed", "instant finisher completes B cinematic without waiting for projectile counters")
		_expect(target.get_defense() == 60.0 and target.get_current_health()<1000.0, "real animation release applies damage and debuff")
		_expect(target.get_node("WorldUIRoot/WorldHealthBar/HealthBarViewport/DebuffDots").has_node("DefenseDownDot"), "real cinematic release shows the armor-break marker")
		_expect(not paused and is_equal_approx(Engine.time_scale,1.0), "real release restores world and camera time")
	scene.free()
	current_scene = null
	await process_frame
func _unit(world: Node, team: int, point: Vector3) -> UnitBase:
	var unit := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	unit.team_id = team
	unit.maximum_health = 1000.0
	unit.defense = 80.0
	world.add_child(unit)
	unit.global_position = point
	unit.get_status_effect_component().set_physics_process(false)
	return unit
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for failure: String in failures: push_error(failure)
	print("GuardianArmorBreakFinisherTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
