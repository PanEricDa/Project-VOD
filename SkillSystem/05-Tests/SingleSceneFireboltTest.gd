extends SceneTree

## Firebolt 单场景装配与非零世界坐标发射测试。

const SKILL_PATH := \
	"res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn"
const PROJECTILE_PATH := "res://Item/Projectiles/FireBall.tscn"
const CAST_EFFECT_PATH := \
	"res://Effects/Skills/Fireball/FireballCastChargeEffect.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const MAX_PHYSICS_FRAMES := 180

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	call_deferred(&"_run")


func _run() -> void:
	if not ResourceLoader.exists(SKILL_PATH):
		_failures.append("Firebolt single-scene asset does not exist")
		_finish()
		return
	var scene := load(SKILL_PATH) as PackedScene
	_expect(scene != null, "Firebolt scene loads")
	_expect(
		ResourceLoader.get_resource_uid(SKILL_PATH)
			!= ResourceUID.INVALID_ID,
		"Firebolt scene has an editor-indexed UID"
	)
	if scene == null:
		_finish()
		return
	var skill := scene.instantiate() as SkillBase
	_expect(skill != null, "Firebolt inherits the new SkillBase")
	_world.add_child(skill)
	_expect(skill.skill_id == &"firebolt", "skill ID is firebolt")
	_expect(
		skill.target_relations == TargetResolver.TargetRelationFlag.HOSTILE,
		"targets hostiles"
	)
	_expect(
		skill.target_selection_mode
			== TargetResolver.TargetSelectionMode.CURRENT_COMBAT_TARGET,
		"uses the persistent combat target"
	)
	_expect(is_equal_approx(skill.cast_range, 6.0), "cast range is 6m")
	_expect(is_equal_approx(skill.base_cast_time, 0.75), "base cast time is 0.75s")
	_expect(is_equal_approx(skill.skill_cooldown, 3.0), "cooldown is 3s")
	_expect(
		_has_property(skill, &"threat_multiplier")
			and is_equal_approx(float(skill.get("threat_multiplier")), 1.0),
		"SkillBase exposes the default one-times threat multiplier"
	)
	_expect(
		not _has_property(skill, &"action_animation_name"),
		"Firebolt does not store a concrete character animation name"
	)
	_expect(
		skill.cast_effect_scene != null
		and skill.cast_effect_scene.resource_path == CAST_EFFECT_PATH,
		"cast charge effect is configured on the root"
	)
	var delivery := skill.delivery as TrackingProjectileDeliveryConfig
	_expect(delivery != null, "delivery is an embedded tracking config")
	if delivery != null:
		_expect(delivery.resource_local_to_scene, "delivery config is local to the scene")
		_expect(
			delivery.projectile_scene != null
			and delivery.projectile_scene.resource_path == PROJECTILE_PATH,
			"delivery references FireBall"
		)
		_expect(is_equal_approx(delivery.projectile_speed, 9.0), "speed is 9")
		_expect(is_equal_approx(delivery.turn_speed_degrees, 180.0), "turn speed is 180")
		_expect(is_equal_approx(delivery.maximum_lifetime, 3.0), "lifetime is 3")
		_expect(is_equal_approx(delivery.impact_radius, 1.2), "impact radius is 1.2")
		_expect(is_equal_approx(delivery.aim_height, 0.25), "aim height is 0.25")
	var effects: Array[Node] = []
	for child: Node in skill.get_children():
		if child is SkillEffectBase:
			effects.append(child)
	_expect(effects.size() == 1, "contains one direct damage effect")
	if effects.size() == 1:
		_expect(
			int(effects[0].get("operation")) == 0,
			"damage effect operation is DAMAGE"
		)
		_expect(
			is_equal_approx(float(effects[0].get("base_amount")), 10.0),
			"damage effect stores 10 base damage"
		)
		_expect(
			is_equal_approx(float(effects[0].get("power_ratio")), 1.0),
			"damage effect uses one attack-power ratio"
		)
		_expect(
			not _has_property(effects[0], &"amount"),
			"damage effect no longer exposes the legacy amount field"
		)

	var caster := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	var target := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	_expect(caster != null and target != null, "uses real UnitBase caster and target")
	if caster == null or target == null:
		_finish()
		return
	caster.team_id = 1
	caster.attack_power = 10.0
	target.team_id = 2
	target.defense = 100.0
	target.collision_layer = 4
	target.add_to_group(&"enemy_targets")
	_world.add_child(caster)
	_world.add_child(target)
	caster.global_position = Vector3(10.0, 0.0, 4.0)
	target.global_position = Vector3(14.0, 0.0, 1.0)
	var launch_marker := Marker3D.new()
	launch_marker.position = Vector3(0.4, 1.1, -0.2)
	caster.add_child(launch_marker)
	await physics_frame
	skill.configure_owner(caster, null, _world)
	var context := SkillContext.new()
	context.caster = caster
	context.requested_target = target
	context.explicit_target_requested = true
	context.delivery_parent = _world
	_expect(skill.request_skill(context), "Firebolt accepts a hostile target")
	_expect(
		skill.confirm_action_started(launch_marker.global_transform),
		"cast action starts at the supplied world transform"
	)
	_expect(
		skill.release_action(launch_marker.global_transform),
		"release starts projectile delivery"
	)
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
	var delivery_finished_count: Array[int] = [0]
	skill.delivery_finished.connect(
		func(_context: SkillContext, _result: SkillDeliveryResult) -> void:
			delivery_finished_count[0] += 1
	)
	var projectile := _world.get_node_or_null(^"FireBall") as Node3D
	_expect(projectile != null, "FireBall is instantiated in the delivery parent")
	if projectile != null:
		_expect(
			projectile.global_position.is_equal_approx(
				launch_marker.global_position
			),
			"FireBall starts exactly at the nonzero launch marker"
		)
		_expect(
			not projectile.global_position.is_zero_approx(),
			"FireBall never falls back to the world origin"
		)
		var expected_direction := (
			target.global_position
			+ Vector3.UP * 0.25
			- launch_marker.global_position
		).normalized()
		var current_direction: Vector3 = projectile.get(
			"_current_direction"
		)
		_expect(
			current_direction.is_equal_approx(expected_direction),
			"FireBall initially faces the resolved target"
		)
	for _frame: int in range(MAX_PHYSICS_FRAMES):
		if delivery_finished_count[0] > 0:
			break
		await physics_frame
	_expect(
		delivery_finished_count[0] == 1,
		"Firebolt projectile completes within the physics-frame timeout"
	)
	_expect(
		is_equal_approx(target.get_current_health(), 90.0),
		"Firebolt deals 10 damage: (10 + 10 * 1) * 100 / (100 + 100)"
	)
	_expect(
		health_changed_count[0] == 1,
		"Firebolt causes exactly one health change per release"
	)
	_finish()


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
		print("SingleSceneFireboltTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
