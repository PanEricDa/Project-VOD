extends SceneTree

## HolyLight 单场景装配、治疗交付与失败冷却语义测试。

const SKILL_PATH := \
	"res://SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const HEAL_EFFECT_PATH := \
	"res://Effects/Skills/HolyLight/HolyLightHealEffect.tscn"

var _failures: Array[String] = []
var _world: Node3D


class FriendlyWithoutHealth:
	extends Node3D

	func is_targetable() -> bool:
		return true

	func is_dead() -> bool:
		return false

	func is_hostile_to(_other: Node) -> bool:
		return false

	func is_friendly_to(_other: Node) -> bool:
		return true

	func is_neutral_to(_other: Node) -> bool:
		return false


class TestCaster:
	extends Node3D

	func is_targetable() -> bool:
		return true

	func is_dead() -> bool:
		return false

	func is_hostile_to(_other: Node) -> bool:
		return false

	func is_friendly_to(other: Node) -> bool:
		return is_instance_valid(other)

	func is_neutral_to(_other: Node) -> bool:
		return false


func _initialize() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	call_deferred(&"_run")


func _run() -> void:
	if not ResourceLoader.exists(SKILL_PATH):
		_failures.append("HolyLight single-scene asset does not exist")
		_finish()
		return
	var scene := load(SKILL_PATH) as PackedScene
	_expect(scene != null, "HolyLight scene loads")
	_expect(
		ResourceLoader.get_resource_uid(SKILL_PATH)
			!= ResourceUID.INVALID_ID,
		"HolyLight scene has an editor-indexed UID"
	)
	if scene == null:
		_finish()
		return
	var skill := scene.instantiate() as SkillBase
	_world.add_child(skill)
	_expect(skill.skill_id == &"holy_light", "skill ID is holy_light")
	_expect(
		(skill.target_relations & TargetResolver.TargetRelationFlag.FRIENDLY) != 0,
		"targets friendly units"
	)
	_expect(
		skill.target_relations
			== (
				TargetResolver.TargetRelationFlag.SELF
				| TargetResolver.TargetRelationFlag.FRIENDLY
			),
		"HolyLight targets both the caster and friendly units"
	)
	_expect(is_equal_approx(skill.skill_cooldown, 1.0), "HolyLight cooldown is 1 second")
	_expect(
		skill.target_selection_mode
			== TargetResolver.TargetSelectionMode.LOWEST_HEALTH_RATIO,
		"HolyLight selects the valid friendly target with the lowest health ratio"
	)
	_expect(
		not _has_property(skill, &"action_animation_name"),
		"HolyLight does not store a concrete character animation name"
	)
	_expect(
		skill.delivery is InstantTargetDeliveryConfig,
		"uses embedded instant-target delivery"
	)
	_expect(
		skill.delivery.resource_local_to_scene,
		"delivery config is local to the skill scene"
	)
	_expect(
		skill.release_effect_scene != null
		and skill.release_effect_scene.resource_path == HEAL_EFFECT_PATH,
		"release VFX is configured once on the skill root"
	)
	var effects: Array[Node] = []
	for child: Node in skill.get_children():
		if child is SkillEffectBase:
			effects.append(child)
	_expect(effects.size() == 1, "contains one direct effect component")
	if effects.size() == 1:
		_expect(
			int(effects[0].get("operation")) == 1,
			"effect operation is HEAL"
		)
		_expect(
			_has_property(effects[0], &"base_amount")
			and is_equal_approx(float(effects[0].get("base_amount")), 25.0),
			"effect stores 25 base healing"
		)
		_expect(
			_has_property(effects[0], &"power_ratio")
			and is_zero_approx(float(effects[0].get("power_ratio"))),
			"HolyLight keeps fixed-value healing"
		)
		_expect(
			not _has_property(effects[0], &"amount"),
			"effect no longer exposes the legacy amount field"
		)

	var caster := TestCaster.new()
	var target := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	target.team_id = 1
	_world.add_child(caster)
	_world.add_child(target)
	target.apply_damage(50.0, caster)
	var health_changed_count: Array[int] = [0]
	target.health_changed.connect(
		func(
			_previous: float,
			_current: float,
			_maximum: float,
			_source: Node
		) -> void:
			health_changed_count[0] += 1
	)
	skill.configure_owner(caster, null, _world)
	_expect(
		_request_and_release(skill, caster, target),
		"HolyLight releases on a friendly target"
	)
	_expect(
		is_equal_approx(target.get_current_health(), 75.0),
		"instant delivery restores exactly 25 health"
	)
	_expect(
		health_changed_count[0] == 1,
		"health changes exactly once per release"
	)
	var full_health_target := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	full_health_target.team_id = 1
	_world.add_child(full_health_target)
	var full_health_changed_count: Array[int] = [0]
	full_health_target.health_changed.connect(
		func(
			_previous: float,
			_current: float,
			_maximum: float,
			_source: Node
		) -> void:
			full_health_changed_count[0] += 1
	)
	var full_health_skill := scene.instantiate() as SkillBase
	_world.add_child(full_health_skill)
	full_health_skill.configure_owner(caster, null, _world)
	_expect(
		_request_and_release(full_health_skill, caster, full_health_target),
		"HolyLight completes when its target is already at full health"
	)
	_expect(
		is_equal_approx(full_health_target.get_current_health(), 100.0),
		"full-health delivery does not change health"
	)
	_expect(
		full_health_changed_count[0] == 0,
		"full-health delivery does not emit a health change"
	)
	var release_effect := _world.get_node_or_null(
		^"HolyLightHealEffect"
	) as Node3D
	if release_effect == null:
		release_effect = target.get_node_or_null(
			^"HolyLightHealEffect"
		) as Node3D
	_expect(
		release_effect != null
		and release_effect.global_position.distance_to(
			target.global_position
		) <= 0.0001,
		"HolyLight release VFX is anchored to the resolved friendly target"
	)
	_expect(
		release_effect != null
		and release_effect.get_parent() == target,
		"HolyLight target-anchored VFX is attached to the resolved target"
	)
	_expect(
		release_effect != null
		and release_effect.transform.basis.is_equal_approx(Basis.IDENTITY),
		"HolyLight target-anchored VFX does not inherit the tilted action origin"
	)
	if release_effect != null:
		var previous_effect_position: Vector3 = release_effect.global_position
		target.global_position += Vector3(1.5, 0.0, -0.75)
		_expect(
			release_effect.global_position.distance_to(
				previous_effect_position + Vector3(1.5, 0.0, -0.75)
			) <= 0.0001,
			"HolyLight target-anchored VFX follows target movement"
		)

	var failing_skill := scene.instantiate() as SkillBase
	_world.add_child(failing_skill)
	var missing_health := FriendlyWithoutHealth.new()
	_world.add_child(missing_health)
	failing_skill.configure_owner(caster, null, _world)
	_expect(
		not _request_and_release(
			failing_skill,
			caster,
			missing_health
		),
		"missing health API fails delivery"
	)
	_expect(
		is_zero_approx(failing_skill.get_cooldown_remaining())
		and failing_skill.is_ready(),
		"failed delivery does not start cooldown"
	)
	_finish()


func _request_and_release(
	skill: SkillBase,
	caster: Node3D,
	target: Node3D
) -> bool:
	target.global_position = caster.global_position + Vector3.RIGHT
	var context := SkillContext.new()
	context.caster = caster
	context.requested_target = target
	context.candidate_targets = [target]
	context.explicit_target_requested = true
	context.delivery_parent = _world
	if not skill.request_skill(context):
		return false
	if not skill.confirm_action_started(
		Transform3D(
			Basis.from_euler(Vector3(0.65, 0.25, -0.4)),
			caster.global_position + Vector3.UP
		)
	):
		return false
	return skill.release_action(
		Transform3D(
			Basis.from_euler(Vector3(0.65, 0.25, -0.4)),
			caster.global_position + Vector3.UP
		)
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("SingleSceneHolyLightTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
