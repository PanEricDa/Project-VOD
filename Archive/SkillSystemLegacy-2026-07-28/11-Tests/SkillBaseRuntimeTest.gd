extends SceneTree

const DEFINITION_PATH := "res://SkillSystem/01-Core/SkillDefinition.gd"
const SKILL_SCRIPT_PATH := "res://SkillSystem/01-Core/SkillBase.gd"
const SKILL_SCENE_PATH := "res://SkillSystem/01-Core/SkillBase.tscn"
const DEFAULT_DEFINITION_PATH := "res://SkillSystem/09-Presets/DefaultSkillDefinition.tres"
const CONTEXT_PATH := "res://SkillSystem/01-Core/SkillContext.gd"
const FIXTURE_PATH := "res://SkillSystem/11-Tests/Fixtures/TestCombatant.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in [DEFINITION_PATH, SKILL_SCRIPT_PATH, SKILL_SCENE_PATH, DEFAULT_DEFINITION_PATH]:
		_assert_true(ResourceLoader.exists(path), "missing resource: " + path)
	if not failures.is_empty():
		_finish()
		return
	await _verify_scene_contract_and_success()
	await _verify_request_modes_and_range()
	await _verify_relations_and_delivery_failures()
	_finish()


func _make_combatant(name_value: String, position_value: Vector3, team: int) -> Node3D:
	var body: Node3D = (load(FIXTURE_PATH) as PackedScene).instantiate() as Node3D
	body.name = name_value
	body.position = position_value
	(body.get_node(^"FactionComponent") as Node).set("team_id", team)
	root.add_child(body)
	return body


func _make_skill(caster: Node3D, cast_time: float = 0.0, cooldown: float = 0.08) -> Node3D:
	var packed: PackedScene = load(SKILL_SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("SkillBase scene failed to load")
		return null
	var skill: Node3D = packed.instantiate() as Node3D
	if skill == null or skill.get_script() == null:
		failures.append("SkillBase scene failed to instantiate with script")
		return null
	caster.add_child(skill)
	var definition: Resource = (skill.get("skill_definition") as Resource).duplicate(true)
	definition.set("cast_time", cast_time)
	definition.set("skill_cooldown", cooldown)
	var decision: Resource = definition.get("decision_policy") as Resource
	decision.set("normal_delay_min", 0.03)
	decision.set("normal_delay_max", 0.03)
	decision.set("extra_hesitation_chance", 0.0)
	skill.set("skill_definition", definition)
	skill.call("configure_owner", caster, null)
	return skill


func _make_context(caster: Node3D, target: Node3D, mode: int = 0) -> RefCounted:
	var context: RefCounted = (load(CONTEXT_PATH) as Script).new() as RefCounted
	context.set("request_mode", mode)
	context.set("caster", caster)
	context.set("requested_target", target)
	context.set("target_position", target.global_position)
	context.set("delivery_parent", root)
	return context


func _verify_scene_contract_and_success() -> void:
	var caster: Node3D = _make_combatant("SkillCaster", Vector3.ZERO, 1)
	var target: Node3D = _make_combatant("SkillTarget", Vector3(0.0, 50.0, -2.0), 2)
	await process_frame
	var skill: Node3D = _make_skill(caster)
	await process_frame
	for node_path: NodePath in [^"CastOrigin", ^"PresentationRoot", ^"DeliverySocket", ^"SkillAnimationPlayer", ^"SkillAudioPlayer"]:
		_assert_true(skill.has_node(node_path), "missing SkillBase node: " + str(node_path))
	for method_name: StringName in [
		&"configure_owner", &"request_skill", &"begin_cast", &"cancel_skill", &"reset_skill",
		&"can_request", &"can_begin_cast", &"is_target_in_cast_range", &"is_ready",
		&"is_casting", &"get_state", &"get_current_context", &"get_cooldown_remaining",
	]:
		_assert_true(skill.has_method(method_name), "missing SkillBase method: " + str(method_name))
	var definition: Resource = skill.get("skill_definition") as Resource
	_assert_equal(definition.get("skill_id"), &"default_skill", "default skill id")
	_assert_near(float(definition.get("cast_range")), 5.0, 0.001, "default cast range")
	_assert_true(skill.get("delivery_agent_scene") != null, "default delivery scene")

	var context: RefCounted = _make_context(caster, target)
	_assert_true(bool(skill.call("request_skill", context)), "manual request accepted")
	_assert_equal(int(skill.call("get_state")), 2, "manual request queued")
	_assert_true(bool(skill.call("is_target_in_cast_range")), "range ignores target height")
	_assert_true(bool(skill.call("begin_cast")), "cast begins")
	_assert_near(
		float(target.get_node(^"HealthComponent").call("get_current_value")),
		90.0,
		0.001,
		"default skill deals ten damage"
	)
	_assert_true(float(skill.call("get_cooldown_remaining")) > 0.0, "successful launch starts cooldown")
	for _frame: int in range(20):
		if bool(skill.call("is_ready")):
			break
		await physics_frame
	_assert_true(bool(skill.call("is_ready")), "cooldown returns ready")

	caster.queue_free()
	target.queue_free()
	await process_frame


func _verify_request_modes_and_range() -> void:
	var caster: Node3D = _make_combatant("ModeCaster", Vector3.ZERO, 1)
	var target: Node3D = _make_combatant("ModeTarget", Vector3(0.0, 0.0, -2.0), 2)
	await process_frame
	var skill: Node3D = _make_skill(caster, 0.05)
	await process_frame

	_assert_true(bool(skill.call("request_skill", _make_context(caster, target, 1))), "AI request accepted")
	_assert_equal(int(skill.call("get_state")), 1, "AI enters decision wait")
	await create_timer(0.05).timeout
	_assert_equal(int(skill.call("get_state")), 2, "AI decision reaches queued")
	skill.call("cancel_skill", &"test_cancel")

	_assert_true(bool(skill.call("request_skill", _make_context(caster, target, 2))), "forced request accepted")
	_assert_equal(int(skill.call("get_state")), 2, "forced request skips delay")
	_assert_true(bool(skill.call("begin_cast")), "delayed cast begins")
	target.global_position = Vector3(0.0, 0.0, -20.0)
	await create_timer(0.08).timeout
	_assert_true(bool(skill.call("is_ready")), "final range failure returns ready")
	_assert_near(float(skill.call("get_cooldown_remaining")), 0.0, 0.001, "range failure no cooldown")

	caster.queue_free()
	target.queue_free()
	await process_frame


func _verify_relations_and_delivery_failures() -> void:
	var caster: Node3D = _make_combatant("RelationCaster", Vector3.ZERO, 1)
	var target: Node3D = _make_combatant("RelationTarget", Vector3(0.0, 0.0, -2.0), 2)
	await process_frame
	var skill: Node3D = _make_skill(caster)
	await process_frame
	var definition: Resource = skill.get("skill_definition") as Resource
	definition.set("target_relation", 3)
	_assert_true(bool(skill.call("request_skill", _make_context(caster, target))), "hostile relation accepted")
	skill.call("cancel_skill")
	definition.set("target_relation", 2)
	_assert_true(not bool(skill.call("request_skill", _make_context(caster, target))), "friendly relation rejects enemy")
	definition.set("target_relation", 0)

	var original_scene: PackedScene = skill.get("delivery_agent_scene") as PackedScene
	skill.set("delivery_agent_scene", null)
	_assert_true(bool(skill.call("request_skill", _make_context(caster, target))), "missing delivery request queues")
	_assert_true(bool(skill.call("begin_cast")), "missing delivery cast begins")
	_assert_true(bool(skill.call("is_ready")), "missing delivery default returns ready")
	_assert_near(float(skill.call("get_cooldown_remaining")), 0.0, 0.001, "missing delivery no cooldown")

	definition.set("cooldown_on_failed_delivery", true)
	_assert_true(bool(skill.call("request_skill", _make_context(caster, target))), "failure penalty request")
	_assert_true(bool(skill.call("begin_cast")), "failure penalty cast")
	_assert_true(float(skill.call("get_cooldown_remaining")) > 0.0, "failure penalty cooldown")
	skill.call("reset_skill")
	skill.set("delivery_agent_scene", original_scene)

	caster.queue_free()
	target.queue_free()
	await process_frame


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _assert_equal(value: Variant, expected: Variant, message: String) -> void:
	if value != expected:
		failures.append(message + ": expected " + str(expected) + ", got " + str(value))


func _assert_near(value: float, expected: float, tolerance: float, message: String) -> void:
	if absf(value - expected) > tolerance:
		failures.append(message + ": expected " + str(expected) + ", got " + str(value))


func _finish() -> void:
	if failures.is_empty():
		print("SkillBaseRuntimeTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
