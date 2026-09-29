extends SceneTree

## 验证 HolyLight 先选取最低生命目标，再执行生命阈值条件；覆盖自动与显式请求。
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	const CONDITION_SCENE_PATH := \
		"res://SkillSystem/03-Extensions/Conditions/TargetHealthCondition.tscn"
	_expect(
		ResourceLoader.get_resource_uid(CONDITION_SCENE_PATH)
			!= ResourceUID.INVALID_ID,
		"Target health condition scene has an editor-indexed UID"
	)
	var world := Node3D.new()
	root.add_child(world)
	var units: Array[UnitBase] = []
	for index in range(3):
		var unit := (load("res://UnitSystem/Base/00_UnitBase.tscn") as PackedScene).instantiate() as UnitBase
		unit.team_id = 1
		world.add_child(unit)
		units.append(unit)
	var caster := units[0]
	var skill := (load("res://SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn") as PackedScene).instantiate() as SkillBase
	world.add_child(skill)
	skill.configure_owner(caster, null, world)
	var condition := skill.get_node_or_null("TargetHealthCondition") as SkillConditionBase
	_expect(condition != null, "HolyLight contains a direct health condition scene instance")
	if condition == null:
		world.free()
		_finish()
		return
	_expect(is_equal_approx(float(condition.get("health_threshold_percent")), 100.0), "Default threshold is 100 percent")
	var context := SkillContext.new()
	context.caster = caster
	context.delivery_parent = world
	context.request_source = SkillContext.RequestSource.AI_AUTOMATIC
	context.candidate_targets.assign([units[1], units[2]])
	_expect(not skill.can_request(context), "Automatic HolyLight rejects all-full-health candidates")
	units[1].apply_damage(20.0)
	units[2].apply_damage(40.0)
	condition.set("health_threshold_percent", 70.0)
	_expect(skill.request_skill(context), "Automatic HolyLight accepts the lowest-health candidate below 70 percent")
	_expect(skill.get_current_context().resolved_target == units[2], "Condition preserves the existing lowest-health target selection")
	skill.cancel_skill()
	condition.set("health_threshold_percent", 60.0)
	_expect(not skill.can_request(context), "Equal threshold is rejected by strict less-than comparison")
	context.explicit_target_requested = true
	context.requested_target = units[1]
	_expect(not skill.can_request(context), "Explicit target with automatic source is still checked")
	context.request_source = SkillContext.RequestSource.EXPLICIT
	_expect(skill.can_request(context), "Manual request skips default automatic-only condition")
	condition.application_scope = SkillConditionBase.ApplicationScope.ALL_REQUESTS
	_expect(not skill.can_request(context), "All-requests scope applies threshold to manual requests")
	var direct := context.duplicate_context() as SkillContext
	direct.resolved_target = null
	_expect(not condition.evaluate(direct), "Missing resolved target is rejected safely")
	direct.resolved_target = Node3D.new()
	world.add_child(direct.resolved_target)
	_expect(not condition.evaluate(direct), "Target without health API is rejected safely")
	direct.resolved_target = units[2]
	condition.set("health_threshold_percent", 101.0)
	_expect(not condition.evaluate(direct), "Out-of-range threshold is rejected")
	world.free()
	_finish()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("TargetHealthConditionTest: PASS")
	quit(0 if failures.is_empty() else 1)
