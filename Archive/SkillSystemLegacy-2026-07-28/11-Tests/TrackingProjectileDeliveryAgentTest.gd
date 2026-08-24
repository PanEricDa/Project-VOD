extends SceneTree

const AGENT_SCRIPT_PATH := "res://SkillSystem/07-Delivery/00-Agents/TrackingProjectileDeliveryAgent.gd"
const AGENT_SCENE_PATH := "res://SkillSystem/07-Delivery/00-Agents/TrackingProjectileDeliveryAgent.tscn"
const CONTEXT_PATH := "res://SkillSystem/01-Core/SkillContext.gd"
const EXISTING_FIREBALL_PATH := "res://Item/Projectiles/FireBall.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert_true(ResourceLoader.exists(AGENT_SCRIPT_PATH), "missing tracking projectile agent script")
	_assert_true(ResourceLoader.exists(AGENT_SCENE_PATH), "missing tracking projectile agent scene")
	if not failures.is_empty():
		_finish()
		return

	await _verify_public_configuration()
	await _verify_launch_forwarding_and_impact()
	await _verify_invalid_launch_cleanup()
	await _verify_existing_fireball_contract()
	_finish()


func _verify_public_configuration() -> void:
	var agent := (load(AGENT_SCENE_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(agent)
	await process_frame

	_assert_true(agent != null, "agent scene instantiates")
	_assert_true(agent.get("projectile_scene") == null, "base scene leaves projectile scene unassigned")
	_assert_near(float(agent.get("projectile_speed")), 12.0, 0.001, "default projectile speed")
	_assert_near(float(agent.get("turn_speed_degrees")), 540.0, 0.001, "default turn speed")
	_assert_near(float(agent.get("maximum_lifetime")), 5.0, 0.001, "default maximum lifetime")
	_assert_near(float(agent.get("impact_radius")), 0.0, 0.001, "default impact radius")
	_assert_near(float(agent.get("aim_height")), 0.25, 0.001, "default aim height")
	for signal_name: StringName in [&"projectile_launched", &"projectile_impacted"]:
		_assert_true(agent.has_signal(signal_name), "missing signal: " + str(signal_name))

	agent.queue_free()
	await process_frame


func _verify_launch_forwarding_and_impact() -> void:
	var caster := CharacterBody3D.new()
	var target := CharacterBody3D.new()
	caster.name = "Caster"
	target.name = "Target"
	target.position = Vector3(5.0, 0.0, 3.0)
	root.add_child(caster)
	root.add_child(target)
	await process_frame

	var context: RefCounted = (load(CONTEXT_PATH) as Script).new() as RefCounted
	context.set("caster", caster)
	context.set("resolved_target", target)
	context.set("delivery_parent", root)

	var agent := (load(AGENT_SCENE_PATH) as PackedScene).instantiate() as Node3D
	agent.set("projectile_scene", _make_projectile_scene(true))
	root.add_child(agent)
	await process_frame

	var launched: Array[Node3D] = []
	var impacted_results: Array[RefCounted] = []
	var finished_results: Array[RefCounted] = []
	agent.projectile_launched.connect(
		func(projectile: Node3D) -> void:
			launched.append(projectile)
	)
	agent.delivery_impacted.connect(
		func(_context: RefCounted, result: RefCounted) -> void:
			impacted_results.append(result)
	)
	agent.delivery_finished.connect(
		func(_context: RefCounted, result: RefCounted) -> void:
			finished_results.append(result)
	)

	var origin := Transform3D(Basis.IDENTITY, Vector3(2.0, 1.0, 3.0))
	_assert_true(bool(agent.call("launch", context, origin)), "valid projectile launch accepted")
	_assert_equal(launched.size(), 1, "projectile launched signal count")
	_assert_equal(int(agent.call("get_delivery_state")), 1, "delivery state travelling")
	if launched.size() == 1:
		var projectile := launched[0]
		var launch_args: Array = projectile.get("launch_args") as Array
		_assert_equal(launch_args.size(), 8, "projectile launch argument count")
		if launch_args.size() == 8:
			_assert_equal(launch_args[0], caster, "caster forwarded")
			_assert_equal(launch_args[1], target, "target forwarded")
			_assert_vector_near(launch_args[2], origin.origin, 0.0001, "origin forwarded")
			var expected_direction: Vector3 = (
				target.global_position + Vector3.UP * 0.25 - origin.origin
			).normalized()
			_assert_vector_near(launch_args[3], expected_direction, 0.0001, "aim direction")
			_assert_near(float(launch_args[4]), 12.0, 0.001, "speed forwarded")
			_assert_near(float(launch_args[5]), 540.0, 0.001, "turn speed forwarded")
			_assert_near(float(launch_args[6]), 5.0, 0.001, "lifetime forwarded")
			_assert_near(float(launch_args[7]), 0.0, 0.001, "impact radius forwarded")

		var impact_position := Vector3(4.0, 0.25, 3.0)
		projectile.projectile_impacted.emit(impact_position)
		_assert_equal(impacted_results.size(), 1, "delivery impact emitted once")
		_assert_equal(finished_results.size(), 1, "delivery finish emitted once")
		_assert_equal(int(agent.call("get_delivery_state")), 2, "delivery state impacted")
		if impacted_results.size() == 1:
			var result := impacted_results[0]
			_assert_equal(result.get("succeeded"), true, "impact result succeeds")
			_assert_vector_near(
				result.get("origin_position") as Vector3,
				origin.origin,
				0.0001,
				"result origin"
			)
			_assert_vector_near(
				result.get("impact_position") as Vector3,
				impact_position,
				0.0001,
				"result impact position"
			)
		projectile.projectile_impacted.emit(impact_position)
		_assert_equal(impacted_results.size(), 1, "duplicate impact ignored")
		_assert_equal(finished_results.size(), 1, "duplicate finish ignored")

	caster.queue_free()
	target.queue_free()
	agent.queue_free()
	await process_frame


func _verify_invalid_launch_cleanup() -> void:
	var caster := CharacterBody3D.new()
	var target := CharacterBody3D.new()
	root.add_child(caster)
	root.add_child(target)
	await process_frame
	var context: RefCounted = (load(CONTEXT_PATH) as Script).new() as RefCounted
	context.set("caster", caster)
	context.set("resolved_target", target)
	context.set("delivery_parent", root)

	var agent := (load(AGENT_SCENE_PATH) as PackedScene).instantiate() as Node3D
	agent.set("projectile_scene", _make_projectile_scene(false))
	root.add_child(agent)
	await process_frame
	var child_count_before := root.get_child_count()
	_assert_true(
		not bool(agent.call("launch", context, Transform3D.IDENTITY)),
		"projectile launch rejection is forwarded"
	)
	await process_frame
	_assert_equal(root.get_child_count(), child_count_before, "rejected projectile is cleaned up")
	_assert_equal(int(agent.call("get_delivery_state")), 0, "rejected delivery remains idle")

	context.set("resolved_target", null)
	agent.set("projectile_scene", _make_projectile_scene(true))
	_assert_true(
		not bool(agent.call("launch", context, Transform3D.IDENTITY)),
		"missing target is rejected"
	)

	caster.queue_free()
	target.queue_free()
	agent.queue_free()
	await process_frame


func _verify_existing_fireball_contract() -> void:
	var caster := CharacterBody3D.new()
	var target := CharacterBody3D.new()
	target.position = Vector3(0.0, 0.0, -3.0)
	root.add_child(caster)
	root.add_child(target)
	await process_frame

	var context: RefCounted = (load(CONTEXT_PATH) as Script).new() as RefCounted
	context.set("caster", caster)
	context.set("resolved_target", target)
	context.set("delivery_parent", root)
	var agent := (load(AGENT_SCENE_PATH) as PackedScene).instantiate() as Node3D
	agent.set("projectile_scene", load(EXISTING_FIREBALL_PATH) as PackedScene)
	root.add_child(agent)
	await process_frame

	var launches := [0]
	agent.projectile_launched.connect(
		func(_projectile: Node3D) -> void:
			launches[0] += 1
	)
	_assert_true(
		bool(agent.call("launch", context, Transform3D(Basis.IDENTITY, Vector3.UP * 0.5))),
		"existing FireBall accepts generic delivery contract"
	)
	_assert_equal(launches[0], 1, "existing FireBall launch count")
	agent.call("cancel_delivery", &"test_cleanup")
	await process_frame

	caster.queue_free()
	target.queue_free()
	await process_frame


func _make_projectile_scene(launch_success: bool) -> PackedScene:
	var script := GDScript.new()
	script.source_code = (
		"extends Node3D\n"
		+ "signal projectile_impacted(position: Vector3)\n"
		+ "var launch_args: Array = []\n"
		+ "func launch(caster: Node3D, target: CharacterBody3D, start_position: Vector3, "
		+ "initial_direction: Vector3, speed: float, turn_speed_degrees: float, "
		+ "lifetime: float, impact_radius: float) -> bool:\n"
		+ "\tlaunch_args = [caster, target, start_position, initial_direction, speed, "
		+ "turn_speed_degrees, lifetime, impact_radius]\n"
		+ "\treturn " + ("true" if launch_success else "false") + "\n"
	)
	_assert_equal(script.reload(), OK, "synthetic projectile script compiles")
	var node := Node3D.new()
	node.set_script(script)
	var packed := PackedScene.new()
	_assert_equal(packed.pack(node), OK, "synthetic projectile packs")
	node.free()
	return packed


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
		print("TrackingProjectileDeliveryAgentTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
