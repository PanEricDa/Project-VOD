extends SceneTree

## 验证真实 Host 请求入口的条件适用范围及基础合法性不被绕过。
var failures: Array[String] = []

class RejectCondition:
	extends SkillConditionBase
	var checks: int = 0
	func evaluate(_context: SkillContext) -> bool:
		checks += 1
		return false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := (load("res://UnitSystem/Base/00_UnitBase.tscn") as PackedScene).instantiate() as UnitBase
	world.add_child(caster)
	var host := caster.get_node("SkillHost") as SkillHostComponent
	var skill := (load("res://SkillSystem/01-Core/SkillBase.tscn") as PackedScene).instantiate() as SkillBase
	skill.skill_id = &"scope_test"
	skill.target_relations = TargetResolver.TargetRelationFlag.SELF
	skill.target_selection_mode = TargetResolver.TargetSelectionMode.NEAREST
	skill.delivery = InstantTargetDeliveryConfig.new()
	var condition := RejectCondition.new()
	skill.add_child(condition)
	host.get_node("SkillSocket").add_child(skill)
	host.register_skill(skill)
	var equipped_slots: Array[SkillBase] = [skill, null]
	host.regular_skills = equipped_slots
	_expect(host.request_skill(skill.skill_id, caster), "Explicit request skips automatic-only condition")
	_expect(condition.checks == 0, "Skipped condition is not evaluated")
	var context := skill.get_current_context()
	_expect(context.request_source == SkillContext.RequestSource.EXPLICIT, "Explicit source is recorded")
	_expect((context.duplicate_context() as SkillContext).request_source == context.request_source, "Source survives context copying")
	host.cancel_active_skill()
	_expect(not host.request_best_skill(caster), "Automatic request checks and rejects soft condition")
	_expect(condition.checks == 1, "Automatic condition is evaluated once")
	condition.application_scope = SkillConditionBase.ApplicationScope.ALL_REQUESTS
	_expect(not host.request_skill(skill.skill_id, caster), "All-requests condition rejects explicit request")
	_expect(not host.request_best_skill(caster), "All-requests condition also rejects automatic request")
	condition.application_scope = SkillConditionBase.ApplicationScope.AUTOMATIC_ONLY
	_expect(not host.request_skill(skill.skill_id, caster, [], Vector3.INF, SkillContext.RequestSource.AI_AUTOMATIC), "Explicit target does not imply manual source")
	_expect(not host.request_skill(skill.skill_id, null), "Manual request still rejects invalid target")
	host.start_global_cooldown(10.0)
	_expect(not host.request_skill(skill.skill_id, caster), "Manual request still obeys global cooldown")
	world.free()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("SkillConditionScopeTest: PASS")
	quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
