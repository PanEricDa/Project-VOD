extends SceneTree

## 已装备技能才可通过普通请求；终结技走独立入口。

const HOST_SCENE := preload("res://SkillSystem/01-Core/SkillHostComponent.tscn")
const SKILL_SCENE := preload("res://SkillSystem/01-Core/SkillBase.tscn")

var failures: Array[String] = []


class Unit:
	extends Node3D
	var faction: StringName = &"ally"
	func is_targetable() -> bool:
		return true
	func is_dead() -> bool:
		return false
	func is_hostile_to(other: Node) -> bool:
		return other.get("faction") != faction
	func is_friendly_to(other: Node) -> bool:
		return other.get("faction") == faction
	func is_neutral_to(_other: Node) -> bool:
		return false


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var caster := Unit.new()
	root.add_child(caster)
	var enemy := Unit.new()
	enemy.faction = &"enemy"
	root.add_child(enemy)
	enemy.global_position = Vector3(2.0, 0.0, 0.0)
	var host := HOST_SCENE.instantiate() as SkillHostComponent
	caster.add_child(host)
	var a := _skill(host, &"regular_a", 10, 5.0)
	var b := _skill(host, &"regular_b", 20, 8.0)
	var spare := _skill(host, &"spare", 999, 100.0)
	var finisher := _skill(host, &"finisher", 999, 100.0)
	var slots: Array[SkillBase] = [a, b]
	host.regular_skills = slots
	host.finisher_skill = finisher

	_expect(is_equal_approx(host.get_preferred_cast_range(), 8.0), "Unselected skills cannot affect idle range")
	_expect(not host.request_skill(spare.skill_id, enemy), "Unselected skill cannot be requested")
	_expect(not host.request_skill(finisher.skill_id, enemy), "Finisher cannot use ordinary request")
	_expect(host.get_active_skill() == null, "Rejected requests do not activate skills")
	_expect(host.request_best_skill(enemy), "AI can request equipped skill")
	_expect(host.get_active_skill() == b, "AI selects highest eligible regular priority")
	host.cancel_active_skill()

	# 相同优先级仍以注册顺序决定，槽位顺序只给策划和玩家看。
	b.ai_priority = 10
	var reversed_slots: Array[SkillBase] = [b, a]
	host.regular_skills = reversed_slots
	_expect(host.request_best_skill(enemy), "Equal priority remains requestable")
	_expect(host.get_active_skill() == a, "Equal priority keeps registration order")
	host.cancel_active_skill()

	b.ai_priority = 20
	host.regular_skills = slots
	b.automatic_cast_enabled = false
	_expect(is_equal_approx(host.get_preferred_cast_range(), 5.0), "Disabled automatic skill does not set idle range")
	finisher.automatic_cast_enabled = false
	if host.has_method(&"request_finisher"):
		_expect(host.call("request_finisher", enemy), "Finisher can be requested explicitly")
		_expect(host.get_active_skill() == finisher, "Finisher uses equipped instance")
		_expect(is_equal_approx(host.get_preferred_cast_range(), 100.0), "Active finisher uses its own range")
		host.cancel_active_skill()
	else:
		_expect(false, "Host exposes dedicated finisher request")
	_expect(is_equal_approx(host.get_preferred_cast_range(), 5.0), "Idle range returns to regular skill")
	host.finisher_skill = null
	if host.has_method(&"request_finisher"):
		_expect(not host.call("request_finisher", enemy), "Empty finisher slot rejects request")

	caster.free()
	enemy.free()
	if failures.is_empty():
		print("SkillSlotRoutingTest: PASS")
	else:
		for failure: String in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _skill(host: SkillHostComponent, id: StringName, priority: int, range_m: float) -> SkillBase:
	var skill := SKILL_SCENE.instantiate() as SkillBase
	skill.name = String(id)
	skill.skill_id = id
	skill.ai_priority = priority
	skill.cast_range = range_m
	skill.target_relations = TargetResolver.TargetRelationFlag.HOSTILE
	skill.target_selection_mode = TargetResolver.TargetSelectionMode.CURRENT_COMBAT_TARGET
	skill.delivery = InstantTargetDeliveryConfig.new()
	host.get_node(^"SkillSocket").add_child(skill)
	_expect(host.register_skill(skill), "Register %s" % id)
	return skill


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
