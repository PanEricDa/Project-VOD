extends SceneTree

const PATHS: Array[String] = [
	"res://SkillSystem/07-Delivery/01-Trajectories/SkillTrajectoryBase.gd",
	"res://SkillSystem/07-Delivery/01-Trajectories/DirectTrajectory.gd",
	"res://SkillSystem/07-Delivery/02-Collisions/SkillCollisionPolicyBase.gd",
	"res://SkillSystem/07-Delivery/02-Collisions/ArrivalCollisionPolicy.gd",
	"res://SkillSystem/07-Delivery/03-Impacts/SkillImpactSelectorBase.gd",
	"res://SkillSystem/07-Delivery/03-Impacts/DirectImpactSelector.gd",
	"res://SkillSystem/08-Payloads/SkillPayloadBase.gd",
	"res://SkillSystem/08-Payloads/HealthChangePayload.gd",
	"res://SkillSystem/07-Delivery/00-Agents/SkillDeliveryAgentBase.gd",
	"res://SkillSystem/07-Delivery/00-Agents/BasicDeliveryAgent.gd",
	"res://SkillSystem/07-Delivery/00-Agents/BasicDeliveryAgent.tscn",
]
const CONTEXT_PATH := "res://SkillSystem/01-Core/SkillContext.gd"
const FIXTURE_PATH := "res://SkillSystem/11-Tests/Fixtures/TestCombatant.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in PATHS:
		_assert_true(ResourceLoader.exists(path), "missing resource: " + path)
	if not failures.is_empty():
		_finish()
		return

	await _verify_base_contracts()
	await _verify_instant_damage()
	await _verify_timed_world_delivery()
	await _verify_healing_and_missing_health()
	_finish()


func _make_combatant(name_value: String, position_value: Vector3) -> Node3D:
	var body: Node3D = (load(FIXTURE_PATH) as PackedScene).instantiate() as Node3D
	body.name = name_value
	body.position = position_value
	root.add_child(body)
	return body


func _make_context(caster: Node3D, target: Node3D) -> RefCounted:
	var context: RefCounted = (load(CONTEXT_PATH) as Script).new() as RefCounted
	context.set("caster", caster)
	context.set("requested_target", target)
	context.set("resolved_target", target)
	context.set("target_position", target.global_position)
	context.set("delivery_parent", root)
	return context


func _verify_base_contracts() -> void:
	var context: RefCounted = (load(CONTEXT_PATH) as Script).new() as RefCounted
	var base_trajectory: Resource = (load(PATHS[0]) as Script).new() as Resource
	var base_collision: Resource = (load(PATHS[2]) as Script).new() as Resource
	var base_impact: Resource = (load(PATHS[4]) as Script).new() as Resource
	var base_payload: Resource = (load(PATHS[6]) as Script).new() as Resource
	_assert_near(
		float(base_trajectory.call("get_travel_duration", context, Vector3.ZERO, Vector3.ONE)),
		0.0,
		0.001,
		"base trajectory duration"
	)
	_assert_equal(
		base_collision.call(
			"evaluate", context, Transform3D.IDENTITY, Transform3D.IDENTITY, 1.0
		),
		null,
		"base collision returns no result"
	)
	_assert_true(
		(base_impact.call("select_targets", context, null) as Array).is_empty(),
		"base impact is empty"
	)
	_assert_true(not bool(base_payload.call("apply", context, null, null)), "base payload fails")
	await process_frame


func _verify_instant_damage() -> void:
	var caster: Node3D = _make_combatant("CasterInstant", Vector3.ZERO)
	var target: Node3D = _make_combatant("TargetInstant", Vector3(0.0, 0.0, -3.0))
	await process_frame
	var context: RefCounted = _make_context(caster, target)
	var agent: Node3D = (load(PATHS[10]) as PackedScene).instantiate() as Node3D
	root.add_child(agent)
	var state := {"impacted": 0, "finished": 0}
	agent.delivery_impacted.connect(func(_context: RefCounted, _result: RefCounted) -> void: state["impacted"] += 1)
	agent.delivery_finished.connect(func(_context: RefCounted, _result: RefCounted) -> void: state["finished"] += 1)
	_assert_true(bool(agent.call("launch", context, Transform3D.IDENTITY)), "instant launch accepted")
	var health: Node = target.get_node(^"HealthComponent")
	_assert_near(float(health.call("get_current_value")), 90.0, 0.001, "instant damage")
	_assert_equal(state["impacted"], 1, "instant impact count")
	_assert_equal(state["finished"], 1, "instant finish count")
	caster.queue_free()
	target.queue_free()
	await process_frame


func _verify_timed_world_delivery() -> void:
	var caster: Node3D = _make_combatant("CasterTimed", Vector3(1.0, 0.0, 1.0))
	var target: Node3D = _make_combatant("TargetTimed", Vector3(1.0, 0.0, -3.0))
	await process_frame
	var destination: Vector3 = target.global_position
	var context: RefCounted = _make_context(caster, target)
	var agent: Node3D = (load(PATHS[10]) as PackedScene).instantiate() as Node3D
	var trajectory: Resource = agent.get("trajectory") as Resource
	trajectory = trajectory.duplicate(true)
	trajectory.set("travel_duration", 0.05)
	agent.set("trajectory", trajectory)
	root.add_child(agent)
	var observed := {"impact_position": Vector3.INF}
	agent.delivery_impacted.connect(
		func(_context: RefCounted, result: RefCounted) -> void:
			observed["impact_position"] = result.get("impact_position")
	)
	_assert_true(bool(agent.call("launch", context, Transform3D(Basis.IDENTITY, caster.global_position))), "timed launch")
	_assert_equal(int(agent.call("get_delivery_state")), 1, "timed state travelling")
	caster.global_position += Vector3(8.0, 0.0, 0.0)
	await create_timer(0.10).timeout
	_assert_equal(observed["impact_position"], destination, "timed delivery uses snapshot destination")
	var health: Node = target.get_node(^"HealthComponent")
	_assert_near(float(health.call("get_current_value")), 90.0, 0.001, "timed damage")
	caster.queue_free()
	target.queue_free()
	await process_frame


func _verify_healing_and_missing_health() -> void:
	var caster: Node3D = _make_combatant("CasterHeal", Vector3.ZERO)
	var target: Node3D = _make_combatant("TargetHeal", Vector3(0.0, 0.0, -1.0))
	await process_frame
	var health: Node = target.get_node(^"HealthComponent")
	health.call("apply_damage", 50.0, caster)
	var context: RefCounted = _make_context(caster, target)
	var heal_agent: Node3D = (load(PATHS[10]) as PackedScene).instantiate() as Node3D
	var payloads: Array = heal_agent.get("payloads") as Array
	var heal_payload: Resource = (payloads[0] as Resource).duplicate(true)
	heal_payload.set("operation", 1)
	var healing_payloads: Array[Resource] = [heal_payload]
	heal_agent.set("payloads", healing_payloads)
	_assert_equal(heal_payload.get("operation"), 1, "heal payload operation configured")
	var configured_payloads: Array = heal_agent.get("payloads") as Array
	_assert_equal((configured_payloads[0] as Resource).get("operation"), 1, "agent payload replaced")
	root.add_child(heal_agent)
	_assert_true(bool(heal_agent.call("launch", context, Transform3D.IDENTITY)), "heal launch")
	_assert_near(float(health.call("get_current_value")), 60.0, 0.001, "healing payload")

	var invalid_target := Node3D.new()
	invalid_target.name = "NoHealthTarget"
	root.add_child(invalid_target)
	var invalid_context: RefCounted = _make_context(caster, invalid_target)
	var invalid_agent: Node3D = (load(PATHS[10]) as PackedScene).instantiate() as Node3D
	root.add_child(invalid_agent)
	var failed_count := {"value": 0}
	invalid_agent.payload_failed.connect(
		func(_context: RefCounted, _result: RefCounted, _target: Node3D, _payload: Resource) -> void:
			failed_count["value"] += 1
	)
	_assert_true(bool(invalid_agent.call("launch", invalid_context, Transform3D.IDENTITY)), "missing health still launches")
	_assert_equal(failed_count["value"], 1, "missing health payload failure")

	caster.queue_free()
	target.queue_free()
	invalid_target.queue_free()
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
		print("SkillDeliveryPipelineTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
