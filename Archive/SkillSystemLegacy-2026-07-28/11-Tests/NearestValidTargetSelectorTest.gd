extends SceneTree

const SELECTOR_PATH := "res://SkillSystem/03-Targeting/NearestValidTargetSelector.gd"
const CONTEXT_PATH := "res://SkillSystem/01-Core/SkillContext.gd"
const FIXTURE_PATH := "res://SkillSystem/11-Tests/Fixtures/TestCombatant.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert_true(ResourceLoader.exists(SELECTOR_PATH), "nearest valid selector resource exists")
	if not failures.is_empty():
		_finish()
		return

	var caster: Node3D = _make_combatant("Caster", Vector3.ZERO, 1, true)
	var friendly_near: Node3D = _make_combatant("FriendlyNear", Vector3(0.0, 8.0, -1.0), 1, true)
	var friendly_far: Node3D = _make_combatant("FriendlyFar", Vector3(0.0, 0.0, -4.0), 1, true)
	var hostile_near: Node3D = _make_combatant("HostileNear", Vector3(0.0, 0.0, -0.5), 2, true)
	_make_combatant("UntargetableFriendly", Vector3(0.0, 0.0, -0.25), 1, false)
	await process_frame

	var selector: Resource = (load(SELECTOR_PATH) as Script).new() as Resource
	var context: RefCounted = _make_context(caster, 2, true, 5.0, 0.0)
	_assert_true(bool(selector.call("resolve_target", context)), "nearest friendly resolves")
	_assert_equal(context.get("resolved_target"), friendly_near, "nearest valid friendly selected")

	selector.set("exclude_caster", false)
	context = _make_context(caster, 2, true, 5.0, 0.0)
	_assert_true(bool(selector.call("resolve_target", context)), "caster may be selected when enabled")
	_assert_equal(context.get("resolved_target"), caster, "friendly relation includes caster")

	selector.set("exclude_caster", true)
	context = _make_context(caster, 3, true, 5.0, 0.0)
	_assert_true(bool(selector.call("resolve_target", context)), "nearest hostile resolves")
	_assert_equal(context.get("resolved_target"), hostile_near, "definition relation drives selection")

	context = _make_context(caster, 2, true, 0.5, 0.0)
	_assert_true(not bool(selector.call("resolve_target", context)), "no valid target inside range fails")
	_assert_equal(context.get("resolved_target"), null, "failed search leaves no resolved target")

	context = _make_context(caster, 2, true, 0.9, 0.1)
	_assert_true(bool(selector.call("resolve_target", context)), "range tolerance and horizontal distance apply")
	_assert_equal(context.get("resolved_target"), friendly_near, "height does not affect search range")

	for child: Node in root.get_children():
		child.queue_free()
	await process_frame
	_finish()


func _make_combatant(
	name_value: String,
	position_value: Vector3,
	team: int,
	targetable: bool
) -> Node3D:
	var combatant: Node3D = (load(FIXTURE_PATH) as PackedScene).instantiate() as Node3D
	combatant.name = name_value
	combatant.position = position_value
	var faction: Node = combatant.get_node(^"FactionComponent")
	faction.set("team_id", team)
	faction.set("targetable", targetable)
	root.add_child(combatant)
	return combatant


func _make_context(
	caster: Node3D,
	target_relation: int,
	require_targetable: bool,
	cast_range: float,
	cast_range_tolerance: float
) -> RefCounted:
	var context: RefCounted = (load(CONTEXT_PATH) as Script).new() as RefCounted
	context.set("caster", caster)
	context.set("target_relation", target_relation)
	context.set("require_targetable", require_targetable)
	context.set("cast_range", cast_range)
	context.set("cast_range_tolerance", cast_range_tolerance)
	return context


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _assert_equal(value: Variant, expected: Variant, message: String) -> void:
	if value != expected:
		failures.append(message + ": expected " + str(expected) + ", got " + str(value))


func _finish() -> void:
	if failures.is_empty():
		print("NearestValidTargetSelectorTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
