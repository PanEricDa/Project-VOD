extends SceneTree

## 强效治疗术的技能配置、治疗交付、自动施放阈值与 Priest 装配契约。

const SKILL_PATH := "res://SkillSystem/00-Skills/GreaterHeal/GreaterHealSkill.tscn"
const PRIEST_PATH := "res://UnitSystem/AI/Ally/Units/Priest.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const EFFECT_PATH := "res://Effects/Skills/GreaterHeal/GreaterHealEffect.tscn"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	call_deferred(&"_run")


func _run() -> void:
	_expect(ResourceLoader.exists(SKILL_PATH), "Greater Heal scene exists")
	if not ResourceLoader.exists(SKILL_PATH):
		_finish()
		return
	_expect(
		ResourceLoader.get_resource_uid(SKILL_PATH) != ResourceUID.INVALID_ID,
		"Greater Heal scene has an editor-indexed UID"
	)
	var scene := load(SKILL_PATH) as PackedScene
	var skill := scene.instantiate() as SkillBase if scene != null else null
	_expect(skill != null, "Greater Heal inherits SkillBase")
	if skill == null:
		_finish()
		return
	_world.add_child(skill)
	await process_frame

	_expect(skill.skill_id == &"greater_heal", "Greater Heal has a stable skill id")
	_expect(skill.ai_priority == 100, "Greater Heal outranks Holy Light")
	_expect(is_equal_approx(skill.base_cast_time, 0.8), "Greater Heal casts in 0.8 seconds")
	_expect(is_equal_approx(skill.skill_cooldown, 15.0), "Greater Heal has a 15 second cooldown")
	_expect(
		is_equal_approx(skill.decision_delay_min, 0.3)
			and is_equal_approx(skill.decision_delay_max, 0.8)
			and is_equal_approx(skill.extra_hesitation_chance, 0.1)
			and is_equal_approx(skill.extra_hesitation_min, 1.0)
			and is_equal_approx(skill.extra_hesitation_max, 3.0),
		"Greater Heal uses the configured post-release wait and extra hesitation"
	)
	_expect(
		skill.target_selection_mode
			== TargetResolver.TargetSelectionMode.LOWEST_HEALTH_RATIO,
		"Greater Heal selects the lowest-health valid friendly target"
	)
	_expect(
		skill.release_effect_scene != null
			and skill.release_effect_scene.resource_path == EFFECT_PATH,
		"Greater Heal uses the distinct Descending Seal effect"
	)

	var heal_effect := skill.get_node_or_null(^"HealEffect") as HealthChangeSkillEffect
	_expect(heal_effect != null, "Greater Heal owns a health-change effect")
	if heal_effect != null:
		_expect(
			is_equal_approx(heal_effect.base_amount, 150.0)
				and is_zero_approx(heal_effect.power_ratio),
			"Greater Heal restores a fixed 150 health"
		)
	var condition := skill.get_node_or_null(^"TargetHealthCondition") as TargetHealthCondition
	_expect(condition != null, "Greater Heal owns a target-health condition")
	if condition != null:
		_expect(
			is_equal_approx(condition.health_threshold_percent, 40.0),
			"Greater Heal automatic casting requires health below 40 percent"
		)

	var caster := (load(UNIT_PATH) as PackedScene).instantiate() as UnitBase
	var target := (load(UNIT_PATH) as PackedScene).instantiate() as UnitBase
	caster.team_id = 1
	target.team_id = 1
	target.maximum_health = 250.0
	_world.add_child(caster)
	_world.add_child(target)
	target.apply_damage(150.0, caster)
	skill.configure_owner(caster, null, _world)
	_expect(_release_on(skill, caster, target), "Greater Heal releases on its friendly target")
	_expect(
		is_equal_approx(target.get_current_health(), 250.0),
		"Greater Heal restores exactly 150 health"
	)

	var priest := (load(PRIEST_PATH) as PackedScene).instantiate() as AllyBase
	_expect(priest != null, "Priest scene instantiates")
	if priest != null:
		var socket := priest.get_node_or_null(^"SkillHost/SkillSocket")
		_expect(socket != null, "Priest owns a skill socket")
		if socket != null:
			_expect(socket.has_node(^"HolyLightSkill"), "Priest keeps Holy Light")
			_expect(socket.has_node(^"GreaterHealSkill"), "Priest equips Greater Heal")
		priest.free()
	_finish()


func _release_on(skill: SkillBase, caster: Node3D, target: Node3D) -> bool:
	target.global_position = caster.global_position + Vector3.RIGHT
	var context := SkillContext.new()
	context.caster = caster
	context.requested_target = target
	context.candidate_targets = [target]
	context.explicit_target_requested = true
	context.delivery_parent = _world
	if not skill.request_skill(context):
		return false
	if not skill.confirm_action_started(Transform3D(Basis.IDENTITY, caster.global_position)):
		return false
	return skill.release_action(Transform3D(Basis.IDENTITY, caster.global_position))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("GreaterHealSkillTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
