extends SceneTree

const HOST_SCRIPT_PATH := "res://SkillSystem/01-Core/SkillHostComponent.gd"
const HOST_SCENE_PATH := "res://SkillSystem/01-Core/SkillHostComponent.tscn"
const SKILL_SCENE_PATH := "res://SkillSystem/01-Core/SkillBase.tscn"
const FIXTURE_PATH := "res://SkillSystem/11-Tests/Fixtures/TestCombatant.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in [HOST_SCRIPT_PATH, HOST_SCENE_PATH]:
		_assert_true(ResourceLoader.exists(path), "missing resource: " + path)
	if not failures.is_empty():
		_finish()
		return
	await _verify_parent_owner_configuration()
	await _verify_casting_permission()
	await _verify_registration_selection_and_cooldown()
	await _verify_approach_and_blocking()
	_finish()


func _make_combatant(name_value: String, position_value: Vector3, team: int) -> Node3D:
	var body: Node3D = (load(FIXTURE_PATH) as PackedScene).instantiate() as Node3D
	body.name = name_value
	body.position = position_value
	body.get_node(^"FactionComponent").set("team_id", team)
	root.add_child(body)
	return body


func _verify_parent_owner_configuration() -> void:
	var caster := Node3D.new()
	caster.name = &"AutomaticOwnerCaster"
	var host: Node = (load(HOST_SCENE_PATH) as PackedScene).instantiate()
	caster.add_child(host)
	root.add_child(caster)
	await process_frame
	_assert_equal(
		host.get("skill_owner"),
		caster,
		"SkillHost automatically configures its direct Node3D parent as owner"
	)
	caster.queue_free()
	await process_frame


func _verify_casting_permission() -> void:
	var caster: Node3D = _make_combatant("PermissionCaster", Vector3.ZERO, 1)
	var target: Node3D = _make_combatant("PermissionTarget", Vector3(0.0, 0.0, -2.0), 2)
	var skill: Node3D = _make_skill(&"permission", 1)
	var host: Node = _make_host(caster, [skill])
	await process_frame
	_assert_true(
		host.has_method(&"set_skill_casting_enabled"),
		"SkillHost exposes the casting permission setter"
	)
	host.call("set_skill_casting_enabled", false)
	_assert_true(
		not bool(host.call("is_skill_casting_enabled")),
		"SkillHost reports a disabled casting permission"
	)
	_assert_true(
		not bool(host.call("request_best_skill", target, Vector3.INF, 0)),
		"disabled SkillHost rejects automatic skill requests"
	)
	caster.queue_free()
	target.queue_free()
	await process_frame


func _make_skill(skill_id: StringName, priority: int) -> Node3D:
	var skill: Node3D = (load(SKILL_SCENE_PATH) as PackedScene).instantiate() as Node3D
	var definition: Resource = (skill.get("skill_definition") as Resource).duplicate(true)
	definition.set("skill_id", skill_id)
	definition.set("display_name", str(skill_id))
	definition.set("ai_priority", priority)
	definition.set("cast_time", 0.0)
	definition.set("skill_cooldown", 0.05)
	var decision: Resource = definition.get("decision_policy") as Resource
	decision.set("normal_delay_min", 0.0)
	decision.set("normal_delay_max", 0.0)
	decision.set("extra_hesitation_chance", 0.0)
	skill.set("skill_definition", definition)
	return skill


func _make_host(caster: Node3D, skills: Array[Node3D]) -> Node:
	var host: Node = (load(HOST_SCENE_PATH) as PackedScene).instantiate()
	var socket: Node = host.get_node(^"SkillSocket")
	for skill: Node3D in skills:
		socket.add_child(skill)
	caster.add_child(host)
	host.call("configure_owner", caster, root)
	host.call("discover_skills")
	return host


func _verify_registration_selection_and_cooldown() -> void:
	var caster: Node3D = _make_combatant("HostCaster", Vector3.ZERO, 1)
	var target: Node3D = _make_combatant("HostTarget", Vector3(0.0, 0.0, -2.0), 2)
	var low: Node3D = _make_skill(&"low", 1)
	var high: Node3D = _make_skill(&"high", 5)
	var host: Node = _make_host(caster, [low, high])
	await process_frame
	var registered: Array = host.call("get_registered_skills") as Array
	_assert_equal(registered.size(), 2, "host discovers direct skills")
	_assert_true(not bool(host.call("register_skill", high)), "duplicate registration rejected")
	_assert_true(bool(host.call("request_best_skill", target, Vector3.INF, 0)), "best request accepted")
	_assert_equal(host.call("get_active_skill"), high, "highest priority selected")
	host.call("_physics_process", 0.016)
	_assert_equal(host.call("get_active_skill"), null, "delivery launch releases slot")
	_assert_true(float(host.call("get_global_cooldown_remaining")) > 0.0, "cast starts global cooldown")
	_assert_near(
		float(target.get_node(^"HealthComponent").call("get_current_value")),
		90.0,
		0.001,
		"selected skill delivered"
	)
	_assert_true(bool(host.call("unregister_skill", low)), "unregister skill")
	_assert_equal((host.call("get_registered_skills") as Array).size(), 1, "registry updated")

	caster.queue_free()
	target.queue_free()
	await process_frame


func _verify_approach_and_blocking() -> void:
	var caster: Node3D = _make_combatant("ApproachCaster", Vector3.ZERO, 1)
	var target: Node3D = _make_combatant("ApproachTarget", Vector3(0.0, 0.0, -12.0), 2)
	var skill: Node3D = _make_skill(&"approach", 0)
	var host: Node = _make_host(caster, [skill])
	await process_frame
	var counts := {"approach": 0, "facing": 0, "locked": 0, "unlocked": 0}
	host.approach_requested.connect(
		func(_context: RefCounted, _range: float, _tolerance: float) -> void: counts["approach"] += 1
	)
	host.facing_requested.connect(func(_context: RefCounted) -> void: counts["facing"] += 1)
	host.movement_lock_requested.connect(
		func(locked: bool) -> void:
			if locked: counts["locked"] += 1
			else: counts["unlocked"] += 1
	)
	_assert_true(bool(host.call("request_skill", &"approach", target, Vector3.INF, 0)), "explicit request")
	host.call("_physics_process", 0.016)
	_assert_true(int(counts["approach"]) > 0, "out of range requests approach")
	_assert_true(int(counts["facing"]) > 0, "queued skill requests facing")
	host.call("set_cast_blocked", true)
	target.global_position = Vector3(0.0, 0.0, -2.0)
	host.call("_physics_process", 0.016)
	_assert_equal(int(skill.call("get_state")), 2, "blocked cast remains queued")
	host.call("start_global_cooldown", 0.0)
	host.call("set_cast_blocked", false)
	host.call("_physics_process", 0.016)
	_assert_equal(host.call("get_active_skill"), null, "unblocked cast completes")
	_assert_near(
		float(target.get_node(^"HealthComponent").call("get_current_value")),
		90.0,
		0.001,
		"unblocked skill delivered"
	)

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
		print("SkillHostComponentTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
