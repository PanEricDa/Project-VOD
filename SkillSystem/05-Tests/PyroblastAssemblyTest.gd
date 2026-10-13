extends SceneTree

## 炎爆作为独立 SkillBase 场景占据 Caster 第二技能槽，使用通用目标策略和效果。

const SKILL_PATH := "res://SkillSystem/00-Skills/Pyroblast/PyroblastSkill.tscn"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ResourceLoader.exists(SKILL_PATH):
		_expect(false, "Pyroblast skill scene exists")
		_finish()
		return
	_expect(ResourceLoader.get_resource_uid(SKILL_PATH) != ResourceUID.INVALID_ID, "Pyroblast skill scene has a registered UID")
	_expect(ResourceLoader.get_resource_uid("res://Item/Projectiles/PyroblastProjectile.tscn") != ResourceUID.INVALID_ID, "Pyroblast projectile scene has a registered UID")
	var caster := (load("res://UnitSystem/AI/Ally/Units/Caster.tscn") as PackedScene).instantiate()
	root.add_child(caster)
	var host := caster.get_node(^"SkillHost") as SkillHostComponent
	_expect(host.regular_skills.size() == 2, "Caster retains two regular slots")
	if host.regular_skills.size() == 2:
		var firebolt := host.regular_skills[0] as SkillBase
		var pyro := host.regular_skills[1] as SkillBase
		_expect(firebolt != null and pyro != null, "Caster equips Firebolt and Pyroblast")
		if firebolt != null and pyro != null:
			_expect(pyro.skill_id == &"pyroblast", "second slot is Pyroblast")
			_expect(is_equal_approx(pyro.base_cast_time, 1.2) and is_equal_approx(pyro.skill_cooldown, 6.0), "Pyroblast uses approved cast and cooldown")
			_expect(pyro.ai_priority > firebolt.ai_priority, "Pyroblast wins AI priority when condition passes")
			_expect(pyro.delivery is ArcProjectileDeliveryConfig, "Pyroblast uses generic Arc delivery")
			if pyro.delivery is ArcProjectileDeliveryConfig:
				var arc := pyro.delivery as ArcProjectileDeliveryConfig
				_expect(arc.shot_count == 1 and is_zero_approx(arc.shot_interval_seconds), "each selected target gets one same-frame projectile")
				_expect(arc.target_expansion is MarkedHostileTargetExpansion, "delivery expands to marked hostiles")
				_expect(arc.projectile_scene != null, "projectile scene is configured")
			var effect_types: Array[StringName] = []
			var has_condition := false
			for child: Node in pyro.get_children():
				if child is SkillEffectBase:
					effect_types.append(child.get_script().get_global_name())
				if child is MarkedHostileCountCondition:
					has_condition = child.minimum_count == 2 and child.application_scope == SkillConditionBase.ApplicationScope.AUTOMATIC_ONLY
			_expect(effect_types.has(&"HealthChangeSkillEffect") and effect_types.has(&"ConsumeNamedStatusSkillEffect"), "damage and generic status consumption are composed")
			_expect(has_condition, "AI checks two marked hostiles without restricting explicit requests")
	caster.free()
	_finish()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("PyroblastAssemblyTest: PASS")
	quit(0 if failures.is_empty() else 1)
