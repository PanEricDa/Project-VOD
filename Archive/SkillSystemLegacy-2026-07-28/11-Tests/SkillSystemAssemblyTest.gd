extends SceneTree

const REQUIRED_DOCS: Array[String] = [
	"res://SkillSystem/README.md",
	"res://SkillSystem/10-Docs/Architecture.md",
	"res://SkillSystem/10-Docs/InspectorAssemblyGuide.md",
	"res://SkillSystem/10-Docs/ExtensionPoints.md",
]
const HOST_SCENE_PATH := "res://SkillSystem/01-Core/SkillHostComponent.tscn"
const SKILL_SCENE_PATH := "res://SkillSystem/01-Core/SkillBase.tscn"
const AGENT_SCENE_PATH := "res://SkillSystem/07-Delivery/00-Agents/BasicDeliveryAgent.tscn"
const FIXTURE_PATH := "res://SkillSystem/11-Tests/Fixtures/TestCombatant.tscn"
const HOLY_LIGHT_DEFINITION_PATH := "res://SkillSystem/00-Skills/HolyLight/HolyLightSkillDefinition.tres"
const NEAREST_SELECTOR_PATH := "res://SkillSystem/03-Targeting/NearestValidTargetSelector.gd"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in REQUIRED_DOCS:
		_assert_true(FileAccess.file_exists(path), "missing module document: " + path)
	if not failures.is_empty():
		_finish()
		return
	await _verify_default_damage_assembly()
	await _verify_configured_heal_assembly()
	_verify_holy_light_target_selector_assembly()
	_verify_runtime_independence()
	_finish()


func _make_combatant(name_value: String, position_value: Vector3, team: int) -> Node3D:
	var body: Node3D = (load(FIXTURE_PATH) as PackedScene).instantiate() as Node3D
	body.name = name_value
	body.position = position_value
	body.get_node(^"FactionComponent").set("team_id", team)
	root.add_child(body)
	return body


func _make_ready_skill() -> Node3D:
	var skill: Node3D = (load(SKILL_SCENE_PATH) as PackedScene).instantiate() as Node3D
	var definition: Resource = (skill.get("skill_definition") as Resource).duplicate(true)
	definition.set("cast_time", 0.0)
	definition.set("skill_cooldown", 0.1)
	skill.set("skill_definition", definition)
	return skill


func _assemble_host(caster: Node3D, skill: Node3D) -> Node:
	var host: Node = (load(HOST_SCENE_PATH) as PackedScene).instantiate()
	host.get_node(^"SkillSocket").add_child(skill)
	caster.add_child(host)
	host.call("configure_owner", caster, root)
	host.call("discover_skills")
	return host


func _verify_default_damage_assembly() -> void:
	var caster: Node3D = _make_combatant("AssemblyCaster", Vector3.ZERO, 1)
	var target: Node3D = _make_combatant("AssemblyTarget", Vector3(0.0, 0.0, -2.0), 2)
	var skill: Node3D = _make_ready_skill()
	var launched_parent := {"node": null}
	skill.delivery_launched.connect(
		func(_context: RefCounted, agent: Node3D) -> void: launched_parent["node"] = agent.get_parent()
	)
	var host: Node = _assemble_host(caster, skill)
	await process_frame
	_assert_true(bool(host.call("request_skill", &"default_skill", target, Vector3.INF, 0)), "default request")
	host.call("_physics_process", 0.016)
	_assert_near(float(target.get_node(^"HealthComponent").call("get_current_value")), 90.0, 0.001, "default damage")
	_assert_equal(launched_parent["node"], root, "delivery uses configured world parent")

	caster.queue_free()
	target.queue_free()
	await process_frame


func _verify_configured_heal_assembly() -> void:
	var caster: Node3D = _make_combatant("HealAssemblyCaster", Vector3.ZERO, 1)
	var target: Node3D = _make_combatant("HealAssemblyTarget", Vector3(0.0, 0.0, -2.0), 1)
	await process_frame
	target.get_node(^"HealthComponent").call("apply_damage", 20.0, caster)
	var agent: Node3D = (load(AGENT_SCENE_PATH) as PackedScene).instantiate() as Node3D
	var payloads: Array = agent.get("payloads") as Array
	var heal_payload: Resource = (payloads[0] as Resource).duplicate(true)
	heal_payload.set("operation", 1)
	var healing_payloads: Array[Resource] = [heal_payload]
	agent.set("payloads", healing_payloads)
	var heal_scene := PackedScene.new()
	_assert_equal(heal_scene.pack(agent), OK, "pack configured heal agent")
	agent.free()
	var skill: Node3D = _make_ready_skill()
	skill.set("delivery_agent_scene", heal_scene)
	var definition: Resource = skill.get("skill_definition") as Resource
	definition.set("target_relation", 2)
	var host: Node = _assemble_host(caster, skill)
	await process_frame
	_assert_true(bool(host.call("request_skill", &"default_skill", target, Vector3.INF, 0)), "heal request")
	host.call("_physics_process", 0.016)
	_assert_near(float(target.get_node(^"HealthComponent").call("get_current_value")), 90.0, 0.001, "configured healing")

	caster.queue_free()
	target.queue_free()
	await process_frame


func _verify_runtime_independence() -> void:
	var forbidden: Array[String] = [
		"Scripts/AI/AllyBase.gd",
		"Scripts/Combat/Skills/SkillModuleBase.gd",
		"FireballSkill",
		"HealingSkill",
	]
	var runtime_files: Array[String] = []
	_collect_runtime_files("res://SkillSystem", runtime_files)
	for path: String in runtime_files:
		var content: String = FileAccess.get_file_as_string(path)
		for token: String in forbidden:
			_assert_true(token not in content, path + " contains forbidden dependency: " + token)


func _verify_holy_light_target_selector_assembly() -> void:
	var definition: Resource = load(HOLY_LIGHT_DEFINITION_PATH) as Resource
	_assert_true(definition != null, "HolyLight definition loads")
	if definition == null:
		return
	var selector: Resource = definition.get("target_selector") as Resource
	_assert_true(selector != null, "HolyLight target selector exists")
	if selector == null:
		return
	var selector_script: Script = selector.get_script() as Script
	_assert_equal(selector_script.resource_path, NEAREST_SELECTOR_PATH, "HolyLight uses nearest valid selector")
	_assert_equal(selector.get("exclude_caster"), true, "HolyLight excludes its caster")


func _collect_runtime_files(path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		failures.append("cannot open module directory: " + path)
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		var child_path: String = path.path_join(entry)
		if directory.current_is_dir():
			# 文档和测试不属于运行时模块。兼容旧名称可让测试在迁移回滚时仍保持语义正确。
			if entry not in ["10-Docs", "11-Tests", "Docs", "Tests"]:
				_collect_runtime_files(child_path, output)
		elif entry.get_extension() in ["gd", "tscn", "tres"]:
			output.append(child_path)
		entry = directory.get_next()
	directory.list_dir_end()


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
		print("SkillSystemAssemblyTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
