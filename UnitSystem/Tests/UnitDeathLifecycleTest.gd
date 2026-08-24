extends SceneTree

const HERO_SCENE_PATH: String = "res://UnitSystem/Player/Hero/Hero.tscn"
const SABER_SCENE_PATH: String = (
	"res://UnitSystem/AI/Ally/Units/Saber.tscn"
)
const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const SKILL_SCENE_PATH: String = "res://SkillSystem/01-Core/SkillBase.tscn"
const MAX_SETUP_FRAMES: int = 4
const MAX_DEATH_PHYSICS_FRAMES: int = 3

var _failures: Array[String] = []
var _world: Node3D


class CandidateProvider:
	extends Node

	var candidates: Array[Node3D] = []

	func get_perceived_candidates(
		_maximum_distance: float = -1.0
	) -> Array[Node3D]:
		return candidates.duplicate()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "UnitDeathLifecycleTestWorld"
	root.add_child(_world)

	await _test_unit_base_lifecycle()
	await _test_player_death_lifecycle()
	await _test_ai_death_lifecycle()
	await _test_skill_host_death_guard()
	_finish()


func _test_unit_base_lifecycle() -> void:
	var unit := _create_unit("LifecycleUnit", 2, Vector3.ZERO)
	if unit == null:
		return
	var died_count: Array[int] = [0]
	unit.died.connect(
		func(_source: Node) -> void:
			died_count[0] += 1
	)

	_expect(
		is_equal_approx(unit.apply_damage(unit.maximum_health), unit.maximum_health),
		"UnitBase applies one lethal hit"
	)
	_expect(died_count[0] == 1, "lethal damage emits died exactly once")
	_expect(
		is_equal_approx(unit.apply_damage(1.0), 0.0) and died_count[0] == 1,
		"repeated damage on a dead unit does not emit died again"
	)
	_expect(not unit.is_targetable(), "dead UnitBase is not targetable at runtime")
	_expect(
		unit.targetable,
		"death preserves the exported targetable configuration"
	)
	_expect(unit.revive(25.0), "dead UnitBase revives explicitly")
	_expect(unit.is_targetable(), "revived UnitBase is targetable again")


func _test_player_death_lifecycle() -> void:
	var hero := _instantiate_scene(HERO_SCENE_PATH, "Hero") as PlayerBase
	var target := _create_unit(
		"PlayerTarget",
		2,
		Vector3(0.0, 4.0, -1.0)
	)
	if hero == null or target == null:
		return
	hero.position = Vector3(0.0, 4.0, 0.0)
	target.add_to_group(&"enemy_targets")
	await _wait_frames(MAX_SETUP_FRAMES)

	var controller := (
		hero.get_node_or_null(^"AttackController") as PlayerAttackController
	)
	var targeting := (
		hero.get_node_or_null(^"TargetingSystem")
			as PlayerTargetingComponent
	)
	var skill_host := (
		hero.get_node_or_null(^"SkillHost") as SkillHostComponent
	)
	_expect(controller != null, "Hero exposes PlayerAttackController")
	_expect(targeting != null, "Hero exposes PlayerTargetingComponent")
	_expect(skill_host != null, "Hero exposes SkillHostComponent")
	if controller == null or targeting == null or skill_host == null:
		return

	var provider := CandidateProvider.new()
	provider.candidates.assign([target])
	hero.add_child(provider)
	skill_host.set_target_candidate_provider(provider)
	var skill := _register_test_skill(skill_host, &"player_death_skill")
	_expect(skill != null, "Hero registers a real test SkillBase")
	_expect(
		targeting.request_lock(target),
		"living Hero can lock a hostile target"
	)
	controller.request_attack()
	_expect(controller.is_attacking(), "living Hero starts a sword attack")
	_expect(
		hero.request_attack_motion(Vector3.FORWARD, 1.0, 3.0),
		"living Hero starts attack motion"
	)
	if skill != null:
		_expect(
			skill_host.request_skill(skill.skill_id, target),
			"living Hero starts a skill request"
		)

	hero.velocity = Vector3(2.0, 0.0, -3.0)
	var targetable_configuration: bool = hero.targetable
	hero.apply_damage(hero.maximum_health)

	_expect(hero.is_dead(), "Hero reaches the dead state")
	_expect(not controller.is_attacking(), "Hero death cancels the active attack")
	_expect(
		not hero.is_attack_motion_active(),
		"Hero death cancels attack motion"
	)
	_expect(not hero.is_player_dashing(), "Hero death clears dash runtime state")
	_expect(hero.get_locked_target() == null, "Hero death clears target lock")
	_expect(
		skill_host.get_active_skill() == null,
		"Hero death cancels the active skill"
	)
	_expect_horizontal_velocity_zero(hero, "Hero death zeros horizontal velocity")
	_expect(
		hero.targetable == targetable_configuration,
		"Hero death preserves targetable configuration"
	)
	_expect(
		hero.is_physics_processing(),
		"Hero death keeps root physics processing enabled"
	)

	# 入口 guard 必须独立于死亡回调是否已清理旧状态；先手动清空再重新请求，
	# 可确保测试真正因缺少死亡判断而失败。
	controller.cancel_combo()
	hero.cancel_attack_motion()
	targeting.clear_locked_target()
	skill_host.cancel_active_skill(&"test_guard_isolation")
	if skill != null:
		skill.reset_skill()
	controller.request_attack()
	_expect(
		not controller.is_attacking(),
		"dead Hero rejects PlayerAttackController.request_attack"
	)
	_expect(
		not hero.request_attack_motion(Vector3.FORWARD, 1.0, 3.0),
		"dead Hero rejects new attack motion"
	)
	_expect(
		not targeting.request_lock(target),
		"dead Hero rejects PlayerTargetingComponent.request_lock"
	)
	if skill != null:
		_expect(
			not skill_host.request_skill(skill.skill_id, target),
			"dead Hero rejects SkillHost.request_skill"
		)

	var dead_y_before: float = hero.global_position.y
	await _wait_frames(MAX_DEATH_PHYSICS_FRAMES, true)
	_expect(
		hero.global_position.y < dead_y_before,
		"dead Hero still applies gravity and CharacterBody3D movement"
	)
	_expect_horizontal_velocity_zero(
		hero,
		"dead Hero keeps horizontal velocity at zero"
	)

	_expect(hero.revive(50.0), "Hero revives explicitly")
	_expect(
		not controller.is_attacking()
		and not hero.is_attack_motion_active()
		and not hero.is_player_dashing()
		and hero.get_locked_target() == null
		and skill_host.get_active_skill() == null,
		"Hero revive does not restore pre-death actions"
	)
	_expect(
		targeting.request_lock(target),
		"revived Hero can accept a new target lock"
	)
	controller.request_attack()
	_expect(controller.is_attacking(), "revived Hero can start a new attack")
	controller.cancel_combo()


func _test_ai_death_lifecycle() -> void:
	var saber := _instantiate_scene(SABER_SCENE_PATH, "Saber") as AllyBase
	var target := _create_unit(
		"AITarget",
		2,
		Vector3(8.0, 4.0, -0.8)
	)
	if saber == null or target == null:
		return
	saber.position = Vector3(8.0, 4.0, 0.0)
	# 准备阶段由测试直接提交动作，避免行为状态机抢先改变断言前置状态。
	saber.set_physics_process(false)
	await _wait_frames(MAX_SETUP_FRAMES, true)

	var combat := saber.get_combat_system()
	var targeting := saber.get_targeting_component()
	var skill_host := (
		saber.get_node_or_null(^"SkillHost") as SkillHostComponent
	)
	var behavior := saber.get_behavior_state_machine()
	var attack_controller := (
		combat.get_attack_controller() if combat != null else null
	)
	_expect(combat != null, "Saber exposes AICombatSystem")
	_expect(targeting != null, "Saber exposes AITargetingComponent")
	_expect(skill_host != null, "Saber exposes SkillHostComponent")
	_expect(behavior != null, "Saber exposes AllyBehaviorStateMachine")
	_expect(attack_controller != null, "Saber exposes AIAttackController")
	if (
		combat == null
		or targeting == null
		or skill_host == null
		or behavior == null
		or attack_controller == null
	):
		return
	_expect(
		_install_runtime_cast_animation(saber),
		"Saber receives a runtime-only compatible basic_cast_1"
	)

	targeting.refresh_target()
	_expect(targeting.get_locked_target() == target, "living Saber locks target")
	_expect(
		combat.request_basic_attack(target),
		"living Saber starts a basic attack"
	)
	combat.cancel_current_action()

	var provider := CandidateProvider.new()
	provider.candidates.assign([target])
	saber.add_child(provider)
	skill_host.set_target_candidate_provider(provider)
	var skill := _register_test_skill(skill_host, &"saber_death_skill")
	_expect(skill != null, "Saber registers a real test SkillBase")
	if skill == null:
		return
	_expect(
		skill_host.request_skill(skill.skill_id, target),
		"living Saber starts a real skill request"
	)
	_expect(
		skill_host.get_active_skill() == skill,
		"living Saber SkillHost owns the active skill slot"
	)
	_expect(
		bool(behavior.get("_skill_movement_locked")),
		"living Saber skill request holds the behavior movement lock"
	)
	_expect(
		not attack_controller.can_attack(),
		"living Saber skill request occupies the external action controller"
	)
	saber.set_movement_target(Vector3(9.0, 4.0, 0.0))
	_expect(saber.has_movement_target(), "living Saber stores a movement target")

	saber.set_physics_process(true)
	saber.velocity = Vector3(-2.0, 0.0, 4.0)
	var detection_configuration: bool = targeting.detection_enabled
	var suspend_before: float = targeting.get_detection_suspend_remaining()
	saber.apply_damage(saber.maximum_health)

	_expect(saber.is_dead(), "Saber reaches the dead state")
	_expect(not combat.is_attacking(), "Saber death cancels current attack")
	_expect(not saber.has_movement_target(), "Saber death clears movement target")
	_expect(
		not saber.is_attack_motion_active()
		and not saber.is_dashing()
		and not saber.is_recovering(),
		"Saber death resets attack, dash and recovery motion"
	)
	_expect(
		targeting.get_locked_target() == null,
		"Saber death clears AI target lock"
	)
	_expect(
		skill_host.is_skill_casting_enabled(),
		"Saber death preserves the SkillHost casting configuration"
	)
	_expect(
		skill_host.get_active_skill() == null,
		"Saber death releases the SkillHost active slot"
	)
	_expect(
		not bool(behavior.get("_skill_movement_locked")),
		"Saber death releases the behavior movement lock"
	)
	_expect(
		attack_controller.can_attack(),
		"Saber death releases external action controller occupancy"
	)
	_expect_horizontal_velocity_zero(saber, "Saber death zeros horizontal velocity")
	_expect(
		targeting.detection_enabled == detection_configuration,
		"Saber death preserves AI detection configuration"
	)
	_expect(
		is_equal_approx(
			targeting.get_detection_suspend_remaining(),
			suspend_before
		),
		"Saber death does not create a targeting suspension"
	)
	_expect(
		saber.is_physics_processing(),
		"Saber death keeps root physics processing enabled"
	)

	combat.cancel_current_action()
	_expect(
		not combat.request_basic_attack(target),
		"dead Saber rejects AICombatSystem.request_basic_attack"
	)
	combat.cancel_current_action()
	skill.reset_skill()
	_expect(
		not skill_host.request_skill(skill.skill_id, target),
		"dead Saber rejects SkillHost.request_skill"
	)
	_expect(
		not skill_host.request_best_skill(target),
		"dead Saber rejects SkillHost.request_best_skill"
	)
	_expect(
		not combat.request_external_action(0.2),
		"dead Saber rejects AICombatSystem.request_external_action"
	)
	combat.cancel_external_action()
	saber.set_movement_target(Vector3(12.0, 4.0, 0.0))
	_expect(
		not saber.has_movement_target(),
		"dead Saber rejects a new movement target"
	)
	_expect(
		not saber.request_attack_motion(Vector3.FORWARD, 1.0, 3.0),
		"dead Saber rejects new attack motion"
	)
	_expect(
		not saber.request_dash(Vector3(12.0, 4.0, 0.0)),
		"dead Saber rejects a new dash"
	)
	targeting.clear_locked_target()
	targeting.refresh_target()
	_expect(
		targeting.get_locked_target() == null,
		"dead Saber target refresh cannot reacquire"
	)

	var dead_y_before: float = saber.global_position.y
	await _wait_frames(MAX_DEATH_PHYSICS_FRAMES, true)
	_expect(
		saber.global_position.y < dead_y_before,
		"dead Saber still applies gravity and CharacterBody3D movement"
	)
	_expect_horizontal_velocity_zero(
		saber,
		"dead Saber keeps horizontal velocity at zero"
	)

	saber.set_physics_process(false)
	_expect(saber.revive(50.0), "Saber revives explicitly")
	_expect(
		not combat.is_attacking()
		and not saber.has_movement_target()
		and not saber.is_attack_motion_active()
		and not saber.is_dashing()
		and targeting.get_locked_target() == null
		and skill_host.get_active_skill() == null
		and not bool(behavior.get("_skill_movement_locked"))
		and attack_controller.can_attack()
		and skill_host.is_skill_casting_enabled(),
		"Saber revive does not restore pre-death actions"
	)
	await _wait_frames(MAX_SETUP_FRAMES, true)
	targeting.refresh_target()
	_expect(
		targeting.get_locked_target() == target,
		"revived Saber can reacquire on a normal refresh"
	)
	_expect(
		combat.request_basic_attack(target),
		"revived Saber can accept a new basic attack"
	)
	combat.cancel_current_action()
	_expect(
		combat.request_external_action(0.2),
		"revived Saber can accept a fresh external action"
	)
	_expect(
		not attack_controller.can_attack(),
		"fresh revived external action occupies the controller"
	)
	combat.cancel_external_action()
	_expect(
		skill_host.request_skill(skill.skill_id, target),
		"revived Saber can accept a fresh explicit skill request"
	)
	_expect(
		skill_host.get_active_skill() == skill
		and bool(behavior.get("_skill_movement_locked"))
		and not attack_controller.can_attack(),
		"revived explicit skill request acquires fresh action state"
	)
	combat.cancel_external_action()
	_expect(
		skill_host.get_active_skill() == null
		and not bool(behavior.get("_skill_movement_locked"))
		and attack_controller.can_attack(),
		"explicit skill cleanup releases all fresh action state"
	)
	skill.reset_skill()
	_expect(
		skill_host.request_best_skill(target),
		"revived Saber can accept a fresh automatic skill request"
	)
	_expect(
		skill_host.get_active_skill() == skill
		and bool(behavior.get("_skill_movement_locked"))
		and not attack_controller.can_attack(),
		"revived automatic skill request acquires fresh action state"
	)
	combat.cancel_external_action()

	_world.remove_child(saber)
	_expect(
		not combat.request_external_action(0.2),
		"detached Saber rejects AICombatSystem.request_external_action"
	)
	_world.add_child(saber)


func _test_skill_host_death_guard() -> void:
	var caster := _create_unit(
		"SkillCaster",
		1,
		Vector3(16.0, 4.0, 0.0)
	)
	var target := _create_unit(
		"SkillTarget",
		2,
		Vector3(16.0, 4.0, -1.0)
	)
	if caster == null or target == null:
		return
	var host := caster.get_node_or_null(^"SkillHost") as SkillHostComponent
	_expect(host != null, "UnitBase exposes SkillHostComponent")
	if host == null:
		return
	var provider := CandidateProvider.new()
	provider.candidates.assign([target])
	caster.add_child(provider)
	host.set_target_candidate_provider(provider)
	var skill := _register_test_skill(host, &"host_death_guard")
	_expect(skill != null, "SkillHost registers a real minimal SkillBase")
	if skill == null:
		return

	_expect(
		host.request_skill(skill.skill_id, target),
		"living caster accepts explicit skill request"
	)
	host.cancel_active_skill(&"test_setup")
	skill.reset_skill()
	var casting_enabled_before: bool = host.is_skill_casting_enabled()
	caster.apply_damage(caster.maximum_health)

	_expect(
		not host.request_skill(skill.skill_id, target),
		"dead caster rejects request_skill"
	)
	host.cancel_active_skill(&"test_guard_isolation")
	skill.reset_skill()
	_expect(
		not host.request_best_skill(target),
		"dead caster rejects request_best_skill"
	)
	host.cancel_active_skill(&"test_guard_isolation")
	skill.reset_skill()
	_expect(
		host.is_skill_casting_enabled() == casting_enabled_before,
		"death guard preserves the user skill-casting configuration"
	)

	_expect(caster.revive(25.0), "skill caster revives explicitly")
	_expect(
		host.request_skill(skill.skill_id, target),
		"revived caster accepts a new explicit skill request"
	)
	host.cancel_active_skill(&"test_cleanup")
	skill.reset_skill()
	_expect(
		host.request_best_skill(target),
		"revived caster accepts a new automatic skill request"
	)
	host.cancel_active_skill(&"test_cleanup")


func _register_test_skill(
	host: SkillHostComponent,
	skill_id: StringName
) -> SkillBase:
	var scene := load(SKILL_SCENE_PATH) as PackedScene
	_expect(scene != null, "SkillBase scene loads for %s" % skill_id)
	if scene == null:
		return null
	var skill := scene.instantiate() as SkillBase
	_expect(skill != null, "SkillBase scene instantiates for %s" % skill_id)
	if skill == null:
		return null
	skill.name = String(skill_id)
	skill.skill_id = skill_id
	skill.target_relations = TargetResolver.TargetRelationFlag.HOSTILE
	skill.target_selection_mode = TargetResolver.TargetSelectionMode.NEAREST
	skill.cast_range = 5.0
	skill.base_cast_time = 0.1
	skill.skill_cooldown = 0.0
	skill.decision_delay_min = 0.0
	skill.decision_delay_max = 0.0
	skill.extra_hesitation_chance = 0.0
	skill.delivery = InstantTargetDeliveryConfig.new()
	var socket := host.get_node_or_null(^"SkillSocket")
	_expect(socket != null, "SkillHost owns SkillSocket for %s" % skill_id)
	if socket == null:
		skill.free()
		return null
	socket.add_child(skill)
	_expect(host.register_skill(skill), "SkillHost registers %s" % skill_id)
	return skill


func _install_runtime_cast_animation(unit: AIUnitBase) -> bool:
	var visual_slot := unit.get_node_or_null(^"Visual") as Node3D
	if visual_slot == null or visual_slot.get_child_count() != 1:
		return false
	var visual_root := visual_slot.get_child(0) as Node3D
	if visual_root == null:
		return false
	var animation_player := visual_root.get_node_or_null(
		^"CharacterAnimationPlayer"
	) as AnimationPlayer
	if animation_player == null:
		return false

	var weapon_library := AnimationLibrary.new()
	if animation_player.has_animation_library(&"weapon"):
		var source_library := animation_player.get_animation_library(
			&"weapon"
		)
		weapon_library = source_library.duplicate(true) as AnimationLibrary
		animation_player.remove_animation_library(&"weapon")
	if weapon_library.has_animation(&"basic_cast_1"):
		weapon_library.remove_animation(&"basic_cast_1")
	weapon_library.add_animation(
		&"basic_cast_1",
		_create_runtime_cast_animation()
	)
	animation_player.add_animation_library(&"weapon", weapon_library)
	return animation_player.has_animation(&"weapon/basic_cast_1")


func _create_runtime_cast_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_METHOD)
	# 只为测试实例提供标准施法 marker，不保存或修改任何正式动画资源。
	animation.track_set_path(track, NodePath("CharacterAnimationPlayer"))
	animation.track_insert_key(
		track,
		0.5,
		{"method": &"release_action", "args": []}
	)
	animation.track_insert_key(
		track,
		1.0,
		{"method": &"finish_action", "args": []}
	)
	return animation


func _instantiate_scene(scene_path: String, node_name: String) -> UnitBase:
	var scene := load(scene_path) as PackedScene
	_expect(scene != null, "%s scene loads" % node_name)
	if scene == null:
		return null
	var unit := scene.instantiate() as UnitBase
	_expect(unit != null, "%s scene instantiates as UnitBase" % node_name)
	if unit == null:
		return null
	unit.name = node_name
	_world.add_child(unit)
	return unit


func _create_unit(
	unit_name: String,
	unit_team_id: int,
	unit_position: Vector3
) -> UnitBase:
	var unit := _instantiate_scene(UNIT_SCENE_PATH, unit_name)
	if unit == null:
		return null
	unit.team_id = unit_team_id
	unit.collision_layer = 4 if unit_team_id == 2 else 2
	unit.collision_mask = 0
	unit.position = unit_position
	return unit


func _wait_frames(frame_count: int, physics: bool = false) -> void:
	for _frame_index: int in range(frame_count):
		if physics:
			await physics_frame
		else:
			await process_frame


func _expect_horizontal_velocity_zero(unit: CharacterBody3D, message: String) -> void:
	_expect(
		is_zero_approx(unit.velocity.x) and is_zero_approx(unit.velocity.z),
		"%s (velocity=%s)" % [message, unit.velocity]
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("UnitDeathLifecycleTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("UnitDeathLifecycleTest: FAIL (%d)" % _failures.size())
	quit(1)
