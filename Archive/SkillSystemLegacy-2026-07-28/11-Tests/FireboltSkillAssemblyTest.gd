extends SceneTree

const SKILL_PATH := "res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn"
const DEFINITION_PATH := "res://SkillSystem/00-Skills/Firebolt/FireboltSkillDefinition.tres"
const DELIVERY_PATH := "res://SkillSystem/00-Skills/Firebolt/FireboltDelivery.tscn"
const SKILL_BASE_PATH := "res://SkillSystem/01-Core/SkillBase.tscn"
const DELIVERY_BASE_PATH := (
	"res://SkillSystem/07-Delivery/00-Agents/TrackingProjectileDeliveryAgent.tscn"
)
const PROJECTILE_PATH := "res://Item/Projectiles/FireBall.tscn"
const CAST_EFFECT_PATH := "res://Effects/Skills/Fireball/FireballCastChargeEffect.tscn"
const CONTEXT_PATH := "res://SkillSystem/01-Core/SkillContext.gd"
const FACTION_SCENE_PATH := "res://Scenes/Components/Combat/FactionComponent.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in [SKILL_PATH, DEFINITION_PATH, DELIVERY_PATH]:
		_assert_true(ResourceLoader.exists(path), "missing Firebolt resource: " + path)
	if not failures.is_empty():
		_finish()
		return

	_verify_definition()
	await _verify_scene_assembly()
	await _verify_runtime_delivery()
	_finish()


func _verify_definition() -> void:
	var definition := load(DEFINITION_PATH) as Resource
	_assert_true(definition != null, "definition loads")
	if definition == null:
		return
	_assert_equal(definition.get("skill_id"), &"firebolt", "skill id")
	_assert_equal(definition.get("display_name"), "Firebolt", "display name")
	_assert_equal(definition.get("target_relation"), 3, "hostile target relation")
	_assert_equal(definition.get("require_targetable"), true, "requires targetable")
	_assert_near(float(definition.get("cast_range")), 6.0, 0.001, "cast range")
	_assert_near(float(definition.get("cast_range_tolerance")), 0.25, 0.001, "range tolerance")
	_assert_true(float(definition.get("cast_time")) >= 0.0, "cast time is non-negative")
	_assert_equal(definition.get("can_move_while_casting"), false, "cast movement lock")
	_assert_true(
		float(definition.get("skill_cooldown")) >= 0.0,
		"skill cooldown is non-negative"
	)

	var selector := definition.get("target_selector") as Resource
	var decision := definition.get("decision_policy") as Resource
	var presentation := definition.get("cast_presentation") as Resource
	_assert_script_path(
		selector,
		"res://SkillSystem/03-Targeting/ProvidedTargetSelector.gd",
		"provided target selector"
	)
	_assert_script_path(
		decision,
		"res://SkillSystem/04-Decisions/BasicRandomDecisionPolicy.gd",
		"random decision policy"
	)
	if decision != null:
		_assert_near(float(decision.get("normal_delay_min")), 0.3, 0.001, "decision minimum")
		_assert_near(float(decision.get("normal_delay_max")), 3.0, 0.001, "decision maximum")
		_assert_near(
			float(decision.get("extra_hesitation_chance")),
			0.10,
			0.001,
			"extra hesitation chance"
		)
		_assert_near(float(decision.get("extra_hesitation_min")), 3.0, 0.001, "extra delay minimum")
		_assert_near(float(decision.get("extra_hesitation_max")), 5.0, 0.001, "extra delay maximum")
	_assert_script_path(
		presentation,
		"res://SkillSystem/06-Presentation/SceneSkillPresentation.gd",
		"cast presentation"
	)
	if presentation != null:
		var effect_scene := presentation.get("effect_scene") as PackedScene
		_assert_equal(
			effect_scene.resource_path if effect_scene != null else "",
			CAST_EFFECT_PATH,
			"cast effect scene"
		)


func _verify_scene_assembly() -> void:
	var delivery_scene := load(DELIVERY_PATH) as PackedScene
	var delivery_state := delivery_scene.get_state()
	var delivery_base := delivery_state.get_base_scene_state()
	_assert_equal(
		delivery_base.get_path() if delivery_base != null else "",
		DELIVERY_BASE_PATH,
		"delivery inherits tracking projectile base"
	)
	var delivery := delivery_scene.instantiate() as Node3D
	root.add_child(delivery)
	await process_frame
	var projectile_scene := delivery.get("projectile_scene") as PackedScene
	_assert_equal(
		projectile_scene.resource_path if projectile_scene != null else "",
		PROJECTILE_PATH,
		"projectile scene"
	)
	_assert_near(float(delivery.get("projectile_speed")), 9.0, 0.001, "projectile speed")
	_assert_near(float(delivery.get("turn_speed_degrees")), 180.0, 0.001, "turn speed")
	_assert_near(float(delivery.get("maximum_lifetime")), 3.0, 0.001, "maximum lifetime")
	_assert_near(float(delivery.get("impact_radius")), 1.2, 0.001, "impact radius")
	delivery.queue_free()

	var skill_scene := load(SKILL_PATH) as PackedScene
	var skill_state := skill_scene.get_state()
	var skill_base := skill_state.get_base_scene_state()
	_assert_equal(
		skill_base.get_path() if skill_base != null else "",
		SKILL_BASE_PATH,
		"skill inherits SkillBase"
	)
	var skill := skill_scene.instantiate() as Node3D
	root.add_child(skill)
	await process_frame
	_assert_equal(
		(skill.get("skill_definition") as Resource).resource_path,
		DEFINITION_PATH,
		"definition assignment"
	)
	_assert_equal(
		(skill.get("delivery_agent_scene") as PackedScene).resource_path,
		DELIVERY_PATH,
		"delivery assignment"
	)
	_assert_equal(skill.get("cast_origin_path"), ^"CastOrigin", "cast origin path")
	_assert_equal(skill.get("presentation_root_path"), ^"PresentationRoot", "presentation root path")
	_assert_equal(skill.get("delivery_socket_path"), ^"DeliverySocket", "delivery socket path")
	_assert_equal(
		skill.get("animation_player_path"),
		^"SkillAnimationPlayer",
		"animation player path"
	)
	_assert_vector_near(
		(skill.get_node(^"CastOrigin") as Marker3D).position,
		Vector3(0.38, 0.45, -0.12),
		0.0001,
		"cast origin local position"
	)
	_assert_vector_near(
		(skill.get_node(^"DeliverySocket") as Marker3D).position,
		Vector3(0.38, 0.45, -0.12),
		0.0001,
		"delivery socket local position"
	)
	skill.queue_free()
	await process_frame


func _verify_runtime_delivery() -> void:
	var caster := CharacterBody3D.new()
	var target := CharacterBody3D.new()
	caster.name = "FireboltCaster"
	target.name = "FireboltTarget"
	target.position = Vector3(0.0, 0.0, -3.0)
	_add_faction(caster, &"ally", 1)
	_add_faction(target, &"enemy", 2)
	root.add_child(caster)
	root.add_child(target)
	var skill := (load(SKILL_PATH) as PackedScene).instantiate() as Node3D
	caster.add_child(skill)
	await process_frame
	skill.call("configure_owner", caster, null)

	var context: RefCounted = (load(CONTEXT_PATH) as Script).new() as RefCounted
	context.set("request_mode", 2)
	context.set("requested_target", target)
	context.set("delivery_parent", root)
	var launched_agents: Array[Node3D] = []
	var observed_launch_positions: Array[Vector3] = []
	skill.delivery_launched.connect(
		func(_context: RefCounted, agent: Node3D) -> void:
			launched_agents.append(agent)
			var projectile := agent.call("get_active_projectile") as Node3D
			if projectile != null:
				observed_launch_positions.append(projectile.global_position)
	)

	_assert_true(bool(skill.call("request_skill", context)), "Firebolt request accepted")
	_assert_true(bool(skill.call("begin_cast")), "Firebolt cast begins")
	var definition := skill.get("skill_definition") as Resource
	var configured_cast_time := float(definition.get("cast_time"))
	var configured_cooldown := float(definition.get("skill_cooldown"))
	await create_timer(configured_cast_time + 0.1).timeout
	_assert_equal(launched_agents.size(), 1, "one delivery agent launched")
	_assert_equal(observed_launch_positions.size(), 1, "one projectile launch position captured")
	if observed_launch_positions.size() == 1:
		_assert_vector_near(
			observed_launch_positions[0],
			skill.get_node(^"DeliverySocket").global_position,
			0.0001,
			"projectile starts from delivery socket"
		)
	if launched_agents.size() == 1:
		var projectile := launched_agents[0].call("get_active_projectile") as Node3D
		_assert_true(projectile != null, "delivery created live projectile")
		launched_agents[0].call("cancel_delivery", &"test_cleanup")
	_assert_near(
		float(skill.call("get_cooldown_remaining")),
		configured_cooldown,
		0.2,
		"successful cooldown follows definition"
	)

	caster.queue_free()
	target.queue_free()
	await process_frame


func _add_faction(body: CharacterBody3D, faction_id: StringName, team_id: int) -> void:
	var faction := (load(FACTION_SCENE_PATH) as PackedScene).instantiate()
	faction.name = "FactionComponent"
	faction.set("faction_id", faction_id)
	faction.set("team_id", team_id)
	faction.set("targetable", true)
	body.add_child(faction)


func _assert_script_path(resource: Resource, expected: String, message: String) -> void:
	var actual := ""
	if resource != null and resource.get_script() is Script:
		actual = (resource.get_script() as Script).resource_path
	_assert_equal(actual, expected, message)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _assert_equal(value: Variant, expected: Variant, message: String) -> void:
	if value != expected:
		failures.append(message + ": expected " + str(expected) + ", got " + str(value))


func _assert_near(value: float, expected: float, tolerance: float, message: String) -> void:
	if absf(value - expected) > tolerance:
		failures.append(message + ": expected " + str(expected) + ", got " + str(value))


func _assert_vector_near(
	value: Vector3,
	expected: Vector3,
	tolerance: float,
	message: String
) -> void:
	if value.distance_to(expected) > tolerance:
		failures.append(message + ": expected " + str(expected) + ", got " + str(value))


func _finish() -> void:
	if failures.is_empty():
		print("FireboltSkillAssemblyTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
