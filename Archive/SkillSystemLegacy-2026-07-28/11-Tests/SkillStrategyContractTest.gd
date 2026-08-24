extends SceneTree

const PATHS: Array[String] = [
	"res://SkillSystem/01-Core/SkillContext.gd",
	"res://SkillSystem/01-Core/SkillDeliveryResult.gd",
	"res://SkillSystem/02-Conditions/SkillConditionBase.gd",
	"res://SkillSystem/02-Conditions/AlwaysSkillCondition.gd",
	"res://SkillSystem/03-Targeting/SkillTargetSelectorBase.gd",
	"res://SkillSystem/03-Targeting/ProvidedTargetSelector.gd",
	"res://SkillSystem/04-Decisions/SkillDecisionPolicyBase.gd",
	"res://SkillSystem/04-Decisions/BasicRandomDecisionPolicy.gd",
	"res://SkillSystem/05-Costs/SkillCostBase.gd",
	"res://SkillSystem/05-Costs/NoSkillCost.gd",
	"res://SkillSystem/06-Presentation/SkillPresentationBase.gd",
	"res://SkillSystem/06-Presentation/SceneSkillPresentation.gd",
	"res://SkillSystem/11-Tests/Fixtures/TestCombatant.tscn",
	"res://SkillSystem/01-Core/SkillDefinition.gd",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in PATHS:
		_assert_true(ResourceLoader.exists(path), "missing resource: " + path)
	if not failures.is_empty():
		_finish()
		return

	var context_script: Script = load(PATHS[0]) as Script
	var context_a: RefCounted = context_script.new() as RefCounted
	var context_b: RefCounted = context_script.new() as RefCounted
	context_a.set("metadata", {"request": "a"})
	_assert_true((context_b.get("metadata") as Dictionary).is_empty(), "contexts own metadata")
	var copy: RefCounted = context_a.call("duplicate_context") as RefCounted
	(copy.get("metadata") as Dictionary)["request"] = "copy"
	_assert_equal((context_a.get("metadata") as Dictionary)["request"], "a", "duplicate metadata")
	context_a.set("target_relation", 2)
	context_a.set("require_targetable", false)
	context_a.set("cast_range", 7.5)
	context_a.set("cast_range_tolerance", 0.4)
	copy = context_a.call("duplicate_context") as RefCounted
	_assert_equal(copy.get("target_relation"), 2, "duplicate target relation")
	_assert_equal(copy.get("require_targetable"), false, "duplicate targetable requirement")
	_assert_equal(copy.get("cast_range"), 7.5, "duplicate cast range")
	_assert_equal(copy.get("cast_range_tolerance"), 0.4, "duplicate range tolerance")

	var definition: Resource = (load(PATHS[13]) as Script).new() as Resource
	var selector_property: Dictionary = {}
	for property: Dictionary in definition.get_property_list():
		if property.get("name", "") == "target_selector":
			selector_property = property
			break
	_assert_true(not selector_property.is_empty(), "definition exposes target selector")
	_assert_equal(selector_property.get("type"), TYPE_OBJECT, "target selector uses object type")
	_assert_equal(
		selector_property.get("hint"),
		PROPERTY_HINT_RESOURCE_TYPE,
		"target selector uses resource type hint"
	)
	_assert_true(
		str(selector_property.get("hint_string", "")).contains("IndependentSkillTargetSelectorBase"),
		"target selector restricts Inspector resource type"
	)

	var base_condition: Resource = (load(PATHS[2]) as Script).new() as Resource
	var always_condition: Resource = (load(PATHS[3]) as Script).new() as Resource
	_assert_true(not bool(base_condition.call("evaluate", context_a)), "base condition fails safely")
	_assert_equal(
		base_condition.call("get_failure_reason", context_a),
		&"condition_not_implemented",
		"base condition reason"
	)
	_assert_true(bool(always_condition.call("evaluate", context_a)), "always condition passes")

	var target := Node3D.new()
	target.name = "ProvidedTarget"
	target.position = Vector3(2.0, 1.0, -3.0)
	root.add_child(target)
	var base_selector: Resource = (load(PATHS[4]) as Script).new() as Resource
	var provided_selector: Resource = (load(PATHS[5]) as Script).new() as Resource
	_assert_true(not bool(base_selector.call("resolve_target", context_a)), "base selector fails safely")
	context_a.set("requested_target", target)
	_assert_true(bool(provided_selector.call("resolve_target", context_a)), "provided target resolves")
	_assert_equal(context_a.get("resolved_target"), target, "resolved target reference")
	_assert_equal(context_a.get("target_position"), target.global_position, "resolved target position")

	var base_decision: Resource = (load(PATHS[6]) as Script).new() as Resource
	var random_policy: Resource = (load(PATHS[7]) as Script).new() as Resource
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	_assert_near(float(base_decision.call("get_decision_delay", context_a, rng)), 0.0, 0.001, "base delay")
	random_policy.set("normal_delay_min", 0.5)
	random_policy.set("normal_delay_max", 0.5)
	random_policy.set("extra_hesitation_chance", 0.0)
	context_a.set("request_mode", 1)
	_assert_near(float(random_policy.call("get_decision_delay", context_a, rng)), 0.5, 0.001, "AI delay")
	random_policy.set("extra_hesitation_chance", 1.0)
	random_policy.set("extra_hesitation_min", 3.0)
	random_policy.set("extra_hesitation_max", 3.0)
	_assert_near(float(random_policy.call("get_decision_delay", context_a, rng)), 3.5, 0.001, "extra delay")
	context_a.set("request_mode", 0)
	_assert_near(float(random_policy.call("get_decision_delay", context_a, rng)), 0.0, 0.001, "manual delay")
	context_a.set("request_mode", 2)
	_assert_near(float(random_policy.call("get_decision_delay", context_a, rng)), 0.0, 0.001, "forced delay")

	var base_cost: Resource = (load(PATHS[8]) as Script).new() as Resource
	var no_cost: Resource = (load(PATHS[9]) as Script).new() as Resource
	_assert_true(not bool(base_cost.call("can_pay", context_a)), "base cost rejects")
	_assert_true(not bool(base_cost.call("commit", context_a)), "base cost commit rejects")
	_assert_true(bool(no_cost.call("can_pay", context_a)), "no cost available")
	_assert_true(bool(no_cost.call("commit", context_a)), "no cost commits")
	no_cost.call("refund", context_a)

	var base_presentation: Resource = (load(PATHS[10]) as Script).new() as Resource
	var scene_presentation: Resource = (load(PATHS[11]) as Script).new() as Resource
	_assert_equal(
		base_presentation.call("play", root, Transform3D.IDENTITY, context_a, null),
		null,
		"base presentation safe"
	)
	_assert_equal(
		scene_presentation.call("play", root, Transform3D.IDENTITY, context_a, null),
		null,
		"empty scene presentation optional"
	)

	var fixture: Node3D = (load(PATHS[12]) as PackedScene).instantiate() as Node3D
	_assert_true(fixture != null, "fixture instantiates")
	_assert_true(fixture.has_node(^"HealthComponent"), "fixture health")
	_assert_true(fixture.has_node(^"FactionComponent"), "fixture faction")
	fixture.free()
	target.queue_free()
	await process_frame
	_finish()


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
		print("SkillStrategyContractTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
