extends SceneTree

## 验证 GuardianTauntSkill 单场景技能的继承、参数、组件组合与内嵌 Delivery 契约。
## 技能必须只由场景配置构成：继承 RangedSkillTemplate，无独立根脚本、无 MeleeAction、
## Delivery 为场景内嵌 Resource，效果目标收集为施法者中心范围模式。

const SKILL_SCENE_PATH := (
	"res://SkillSystem/00-Skills/GuardianTaunt/GuardianTauntSkill.tscn"
)
const RELEASE_EFFECT_PATH := (
	"res://Effects/Skills/GuardianTaunt/GuardianTauntReleaseEffect.tscn"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(
		ResourceLoader.exists(SKILL_SCENE_PATH),
		"GuardianTauntSkill scene exists"
	)
	if not ResourceLoader.exists(SKILL_SCENE_PATH):
		_finish()
		return
	var skill := (
		(load(SKILL_SCENE_PATH) as PackedScene).instantiate() as SkillBase
	)
	_expect(skill != null, "Guardian Taunt inherits the shared SkillBase")
	if skill == null:
		_finish()
		return
	var host := Node3D.new()
	root.add_child(host)
	host.add_child(skill)
	await process_frame

	_expect(
		skill.skill_id == &"guardian_taunt",
		"Guardian Taunt exposes its stable skill id"
	)
	_expect(
		skill.target_relations == TargetResolver.TargetRelationFlag.HOSTILE,
		"Guardian Taunt uses a hostile trigger target"
	)
	_expect(
		skill.target_selection_mode == TargetResolver.TargetSelectionMode.NEAREST,
		"Guardian Taunt selects the nearest perceived hostile"
	)
	_expect(
		is_equal_approx(skill.cast_range, 0.8),
		"Guardian Taunt preserves the Guardian melee engagement distance"
	)
	_expect(
		is_equal_approx(skill.base_cast_time, 0.2),
		"Guardian Taunt uses the designed short cast time"
	)
	_expect(
		is_equal_approx(skill.skill_cooldown, 15.0),
		"Guardian Taunt has the designed long cooldown"
	)
	_expect(
		skill.ai_priority == 80,
		"Guardian Taunt outranks Shield Bash when both are ready"
	)
	_expect(
		skill.automatic_cast_enabled,
		"Guardian Taunt is an automatic skill"
	)
	_expect(
		is_zero_approx(skill.decision_delay_min)
			and is_zero_approx(skill.decision_delay_max)
			and is_zero_approx(skill.extra_hesitation_chance),
		"Guardian Taunt keeps random hesitation disabled"
	)
	_expect(
		skill.delivery is InstantTargetDeliveryConfig,
		"Guardian Taunt reuses Instant Delivery"
	)
	var delivery := skill.delivery as InstantTargetDeliveryConfig
	_expect(
		delivery.target_collection_mode
			== InstantTargetDeliveryConfig.TargetCollectionMode.CASTER_RADIUS,
		"Guardian Taunt enables caster-radius collection"
	)
	_expect(
		is_equal_approx(delivery.effect_radius, 5.0),
		"Guardian Taunt delivery radius is five meters"
	)
	_expect(
		delivery.affected_relations
			== TargetResolver.TargetRelationFlag.HOSTILE,
		"Guardian Taunt only affects hostile units"
	)
	_expect(
		delivery.resource_local_to_scene
			and String(delivery.resource_path).is_empty(),
		"Guardian Taunt delivery is an inline scene resource"
	)
	var threat_effect := skill.get_node_or_null(^"ThreatEffect")
	_expect(
		threat_effect is ThreatChangeSkillEffect,
		"Guardian Taunt owns one fixed threat effect"
	)
	if threat_effect is ThreatChangeSkillEffect:
		_expect(
			is_equal_approx(
				(threat_effect as ThreatChangeSkillEffect).threat_amount,
				200.0
			),
			"Guardian Taunt injects the designed fixed threat"
		)
	_expect(
		skill.get_node_or_null(^"MeleeAction") == null,
		"Guardian Taunt has no melee action child"
	)
	_expect(
		skill.release_effect_scene != null
			and skill.release_effect_scene.resource_path == RELEASE_EFFECT_PATH,
		"Guardian Taunt configures its distinct release effect"
	)
	_expect(
		skill.release_effect_anchor == SkillBase.PresentationAnchor.CASTER_FEET,
		"Guardian Taunt anchors its release effect at the caster feet"
	)
	_expect(
		skill.get_script() != null
			and String(skill.get_script().resource_path).ends_with("SkillBase.gd"),
		"Guardian Taunt adds no dedicated root script"
	)

	host.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("GuardianTauntSkillTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("GuardianTauntSkillTest: FAIL (%d)" % _failures.size())
	quit(1)
