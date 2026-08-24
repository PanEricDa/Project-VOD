extends SceneTree

## 单场景 SkillBase 的核心状态与配置契约测试。

const SKILL_SCENE_PATH := \
	"res://SkillSystem/01-Core/SkillBase.tscn"

var _failures: Array[String] = []
var _world: Node3D


class TestUnit:
	extends Node3D

	var faction: StringName = &"neutral"
	var targetable: bool = true
	var dead: bool = false
	var health_ratio: float = 1.0
	var cast_speed_multiplier: float = 1.0

	func is_targetable() -> bool:
		return targetable

	func is_dead() -> bool:
		return dead

	func get_health_ratio() -> float:
		return health_ratio

	func is_friendly_to(other: Node) -> bool:
		return other != null and other.get("faction") == faction

	func is_hostile_to(other: Node) -> bool:
		return other != null and other.get("faction") != faction

	func is_neutral_to(other: Node) -> bool:
		return other != null and other.get("faction") == &"neutral"

	func get_cast_speed_multiplier() -> float:
		return cast_speed_multiplier


class RecordingEffect:
	extends SkillEffectBase

	var apply_count: int = 0

	func apply(
		_context: SkillContext,
		_result: SkillDeliveryResult,
		_target: Node3D
	) -> bool:
		apply_count += 1
		return true


class TestCharacterUnit:
	extends CharacterBody3D

	var faction: StringName = &"neutral"

	func is_targetable() -> bool:
		return true

	func is_dead() -> bool:
		return false

	func is_friendly_to(other: Node) -> bool:
		return other != null and other.get("faction") == faction

	func is_hostile_to(other: Node) -> bool:
		return other != null and other.get("faction") != faction

	func is_neutral_to(other: Node) -> bool:
		return other != null and other.get("faction") == &"neutral"


class SynchronousExitProjectile:
	extends Node3D

	signal projectile_impacted(position: Vector3)

	static var last_instance: Node3D

	func launch(
		_caster: Node3D,
		_target: CharacterBody3D,
		_origin: Vector3,
		_initial_direction: Vector3,
		_speed: float,
		_turn_speed: float,
		_lifetime: float,
		_impact_radius: float
	) -> bool:
		last_instance = self
		get_parent().remove_child(self)
		return true


func _initialize() -> void:
	_world = Node3D.new()
	_world.name = "SkillBaseTestWorld"
	get_root().add_child(_world)
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	if not ResourceLoader.exists(SKILL_SCENE_PATH):
		_failures.append("Single-scene SkillBase scene does not exist")
		_finish()
		return
	var scene := load(SKILL_SCENE_PATH) as PackedScene
	_expect(scene != null, "SkillBase scene loads")
	if scene == null:
		_finish()
		return
	_verify_scene_contract(scene)
	_verify_targeting_and_queue(scene)
	_verify_release_and_cooldown(scene)
	await _verify_deferred_projectile_failure_lifecycle(scene)
	_finish()


func _verify_scene_contract(scene: PackedScene) -> void:
	var skill: Node = scene.instantiate()
	_world.add_child(skill)
	_expect(not skill is Node3D, "SkillBase root is a non-spatial Node")
	_expect(skill.has_node(^"DeliveryRunner"), "SkillBase owns DeliveryRunner")
	_expect(skill.has_node(^"RuntimeEffects"), "SkillBase owns RuntimeEffects")
	_expect(
		not _has_property(skill, &"skill_definition"),
		"SkillBase has no Definition slot"
	)
	_expect(
		not _has_property(skill, &"delivery_agent_scene"),
		"SkillBase has no Delivery scene slot"
	)
	_expect(
		not _has_property(skill, &"action_animation_name"),
		"SkillBase does not depend on a concrete character animation name"
	)
	for property_name: StringName in [
		&"skill_id", &"display_name", &"icon", &"ai_priority",
		&"target_relations", &"target_selection_mode", &"cast_range",
		&"require_targetable", &"require_alive",
		&"validate_target_on_release",
		&"base_cast_time",
		&"can_move_while_casting", &"can_turn_while_casting",
		&"cancel_when_target_invalid", &"skill_cooldown",
		&"cooldown_on_failed_release", &"automatic_cast_enabled",
		&"decision_delay_min", &"decision_delay_max",
		&"extra_hesitation_chance", &"extra_hesitation_min",
		&"extra_hesitation_max", &"cast_effect_scene",
		&"release_effect_scene", &"cancel_effect_scene", &"delivery",
	]:
		_expect(
			_has_property(skill, property_name),
			"SkillBase exposes root property: " + String(property_name)
		)
	skill.queue_free()


func _verify_targeting_and_queue(scene: PackedScene) -> void:
	var caster := TestUnit.new()
	caster.faction = &"ally"
	var near_enemy := TestUnit.new()
	near_enemy.faction = &"enemy"
	var far_enemy := TestUnit.new()
	far_enemy.faction = &"enemy"
	_world.add_child(caster)
	_world.add_child(near_enemy)
	_world.add_child(far_enemy)
	near_enemy.global_position = Vector3(2.0, 0.0, 0.0)
	far_enemy.global_position = Vector3(8.0, 0.0, 0.0)

	var skill: Node = scene.instantiate()
	var effect := RecordingEffect.new()
	skill.add_child(effect)
	_world.add_child(skill)
	skill.set(
		"target_relations",
		TargetResolver.TargetRelationFlag.HOSTILE
	)
	skill.set(
		"target_selection_mode",
		TargetResolver.TargetSelectionMode.NEAREST
	)
	skill.set("cast_range", 5.0)
	skill.set("delivery", InstantTargetDeliveryConfig.new())
	skill.call("configure_owner", caster, null, _world)

	var action_count: Array[int] = [0]
	var range_count: Array[int] = [0]
	skill.action_requested.connect(
		func(
			_skill: SkillBase,
			_target: Node3D,
			_effective_cast_time: float
		) -> void:
			action_count[0] += 1
	)
	skill.cast_range_required.connect(
		func(_context: SkillContext, _cast_range: float) -> void:
			range_count[0] += 1
	)

	var context := SkillContext.new()
	context.requested_target = far_enemy
	context.candidate_targets.assign([near_enemy])
	context.explicit_target_requested = true
	context.delivery_parent = _world
	_expect(bool(skill.call("request_skill", context)), "Far valid target is queued")
	_expect(range_count[0] == 1, "Far target emits range request")
	_expect(action_count[0] == 0, "Far target does not start animation")
	far_enemy.global_position = Vector3(4.0, 0.0, 0.0)
	_expect(bool(skill.call("try_request_action")), "Queued target starts in range")
	_expect(action_count[0] == 1, "Action request emits exactly once")
	skill.call("cancel_skill", &"test_reset")

	var duplicated_context := context.duplicate_context() as SkillContext
	_expect(
		duplicated_context.explicit_target_requested,
		"SkillContext copies the explicit-target request flag"
	)
	var wrong_relation_context := SkillContext.new()
	wrong_relation_context.requested_target = caster
	wrong_relation_context.explicit_target_requested = true
	wrong_relation_context.delivery_parent = _world
	_expect(
		not bool(skill.call("request_skill", wrong_relation_context)),
		"explicit request still rejects a wrong target relation"
	)
	near_enemy.dead = true
	var dead_context := SkillContext.new()
	dead_context.requested_target = near_enemy
	dead_context.explicit_target_requested = true
	dead_context.delivery_parent = _world
	_expect(
		not bool(skill.call("request_skill", dead_context)),
		"explicit request respects Require Alive"
	)
	near_enemy.dead = false
	near_enemy.targetable = false
	var untargetable_context := SkillContext.new()
	untargetable_context.requested_target = near_enemy
	untargetable_context.explicit_target_requested = true
	untargetable_context.delivery_parent = _world
	_expect(
		not bool(skill.call("request_skill", untargetable_context)),
		"explicit request respects Require Targetable"
	)
	near_enemy.targetable = true

	var auto_context := SkillContext.new()
	auto_context.candidate_targets.assign([far_enemy, near_enemy])
	auto_context.delivery_parent = _world
	_expect(bool(skill.call("request_skill", auto_context)), "Auto-nearest request resolves")
	var resolved: SkillContext = skill.call("get_current_context") as SkillContext
	_expect(resolved.resolved_target == near_enemy, "Auto-nearest chooses nearest enemy")
	skill.call("cancel_skill", &"self_friendly_test")

	caster.health_ratio = 0.1
	var friendly := TestUnit.new()
	friendly.faction = &"ally"
	friendly.health_ratio = 0.6
	_world.add_child(friendly)
	skill.set(
		"target_relations",
		(
			TargetResolver.TargetRelationFlag.SELF
			| TargetResolver.TargetRelationFlag.FRIENDLY
		)
	)
	skill.set(
		"target_selection_mode",
		TargetResolver.TargetSelectionMode.LOWEST_HEALTH_RATIO
	)
	var lowest_health_context := SkillContext.new()
	lowest_health_context.candidate_targets.assign([friendly])
	lowest_health_context.delivery_parent = _world
	_expect(
		bool(skill.call("request_skill", lowest_health_context)),
		"automatic Self plus Friendly request resolves"
	)
	var lowest_health_resolved := (
		skill.call("get_current_context") as SkillContext
	)
	_expect(
		lowest_health_resolved.resolved_target == caster,
		"Lowest Health Ratio can select the owner when Self is enabled"
	)

	skill.queue_free()
	caster.queue_free()
	near_enemy.queue_free()
	far_enemy.queue_free()
	friendly.queue_free()


func _verify_release_and_cooldown(scene: PackedScene) -> void:
	var caster := TestUnit.new()
	caster.faction = &"ally"
	caster.cast_speed_multiplier = 2.0
	var enemy := TestUnit.new()
	enemy.faction = &"enemy"
	_world.add_child(caster)
	_world.add_child(enemy)
	enemy.global_position = Vector3(2.0, 0.0, 0.0)

	var skill: Node = scene.instantiate()
	var effect := RecordingEffect.new()
	skill.add_child(effect)
	_world.add_child(skill)
	skill.set(
		"target_relations",
		TargetResolver.TargetRelationFlag.HOSTILE
	)
	skill.set("cast_range", 5.0)
	skill.set("base_cast_time", 1.2)
	skill.set("skill_cooldown", 3.0)
	# AI 的随机等待应在成功交付后才开始；首发动作本身不得被该配置延迟。
	skill.set("decision_delay_min", 0.5)
	skill.set("decision_delay_max", 0.5)
	skill.set("extra_hesitation_chance", 0.0)
	skill.set("delivery", InstantTargetDeliveryConfig.new())
	skill.call("configure_owner", caster, null, _world)
	_expect(
		is_equal_approx(float(skill.call("get_effective_cast_time")), 0.6),
		"Cast speed multiplier scales effective cast time"
	)

	var context := SkillContext.new()
	context.requested_target = enemy
	context.explicit_target_requested = true
	context.delivery_parent = _world
	_expect(bool(skill.call("request_skill", context)), "Release test request starts")
	var cast_transform := Transform3D(Basis.IDENTITY, Vector3(9.0, 1.0, 5.0))
	_expect(
		bool(skill.call("confirm_action_started", cast_transform)),
		"Action confirmation starts cast"
	)
	var release_transform := Transform3D(Basis.IDENTITY, Vector3(10.0, 1.0, 4.0))
	_expect(
		bool(skill.call("release_action", release_transform)),
		"Release starts instant delivery"
	)
	_expect(effect.apply_count == 1, "Release applies instant effect once")
	_expect(
		is_equal_approx(float(skill.call("get_cooldown_remaining")), 0.0),
		"Successful delivery does not start cooldown before post-release hesitation ends"
	)
	_expect(
		int(skill.call("get_state")) == 6,
		"Successful delivery enters the post-release hesitation state"
	)
	skill.call("_physics_process", 0.5)
	_expect(
		is_equal_approx(float(skill.call("get_cooldown_remaining")), 3.0),
		"Cooldown starts after the post-release hesitation ends"
	)

	skill.queue_free()
	caster.queue_free()
	enemy.queue_free()


func _verify_deferred_projectile_failure_lifecycle(scene: PackedScene) -> void:
	var caster := TestUnit.new()
	caster.faction = &"ally"
	var enemy := TestCharacterUnit.new()
	enemy.faction = &"enemy"
	_world.add_child(caster)
	_world.add_child(enemy)
	enemy.global_position = Vector3(2.0, 0.0, 0.0)
	var template := SynchronousExitProjectile.new()
	var projectile_scene := PackedScene.new()
	_expect(projectile_scene.pack(template) == OK, "SkillBase exit projectile packs")
	template.free()
	var delivery := TrackingProjectileDeliveryConfig.new()
	delivery.projectile_scene = projectile_scene
	delivery.projectile_speed = 9.0
	var skill: SkillBase = scene.instantiate() as SkillBase
	_world.add_child(skill)
	skill.target_relations = TargetResolver.TargetRelationFlag.HOSTILE
	skill.cast_range = 5.0
	skill.delivery = delivery
	skill.configure_owner(caster, null, _world)
	var lifecycle_events: Array[String] = []
	var failed_count: Array[int] = [0]
	var finished_count: Array[int] = [0]
	skill.delivery_started.connect(
		func(_context: SkillContext) -> void:
			lifecycle_events.append("started")
	)
	skill.skill_failed.connect(
		func(_context: SkillContext, _reason: StringName) -> void:
			failed_count[0] += 1
			lifecycle_events.append("failed")
	)
	skill.delivery_finished.connect(
		func(_context: SkillContext, _result: SkillDeliveryResult) -> void:
			finished_count[0] += 1
			lifecycle_events.append("finished")
	)
	var context := SkillContext.new()
	context.requested_target = enemy
	context.explicit_target_requested = true
	context.delivery_parent = _world
	_expect(skill.request_skill(context), "SkillBase queues synchronous-exit projectile")
	_expect(skill.confirm_action_started(Transform3D.IDENTITY), "SkillBase starts projectile cast")
	_expect(
		skill.release_action(Transform3D.IDENTITY),
		"SkillBase accepts the projectile launch before deferred exit"
	)
	_expect(
		lifecycle_events == ["started"] and failed_count[0] == 0,
		"SkillBase starts delivery before deferred failure"
	)
	await process_frame
	_expect(
		lifecycle_events == ["started", "failed"]
			and failed_count[0] == 1
			and finished_count[0] == 0,
		"SkillBase receives deferred projectile failure after leaving CASTING"
	)
	if is_instance_valid(SynchronousExitProjectile.last_instance):
		SynchronousExitProjectile.last_instance.free()
	skill.queue_free()
	caster.queue_free()
	enemy.queue_free()


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("SingleSceneSkillBaseTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
