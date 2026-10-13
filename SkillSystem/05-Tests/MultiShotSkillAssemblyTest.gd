extends SceneTree

## 通用连射模板可实例化为独立技能，Archer 的第二常规槽装备自己的连射实例。

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var template := load("res://SkillSystem/00-Templates/MultiShotSkillTemplate.tscn") as PackedScene
	var skill_scene := load("res://SkillSystem/00-Skills/RapidShot/RapidShotSkill.tscn") as PackedScene
	_expect(template != null, "generic multi-shot skill template loads")
	_expect(skill_scene != null, "rapid-shot skill scene loads")
	if skill_scene != null:
		var skill := skill_scene.instantiate() as SkillBase
		var other := skill_scene.instantiate() as SkillBase
		root.add_child(skill)
		root.add_child(other)
		_expect(skill != null and skill.delivery is ArcProjectileDeliveryConfig, "rapid shot uses ordinary SkillBase and arc delivery")
		if skill != null and skill.delivery is ArcProjectileDeliveryConfig:
			var config := skill.delivery as ArcProjectileDeliveryConfig
			_expect(config.shot_count == 3 and config.shot_interval_seconds > 0.0, "rapid shot fires three spaced arrows")
			_expect(config.projectile_scene != null, "rapid-shot projectile is configurable")
			_expect(skill.get_node_or_null(^"DamageEffect") is HealthChangeSkillEffect, "rapid shot uses reusable damage effect")
			_expect(skill.delivery != other.delivery, "two skill instances own independent delivery configuration")
			config.shot_count = 2
			_expect((other.delivery as ArcProjectileDeliveryConfig).shot_count == 3, "one instance can change shot count without changing another")
		skill.free()
		other.free()
	var archer_scene := load("res://UnitSystem/AI/Ally/Units/Archer.tscn") as PackedScene
	var archer := archer_scene.instantiate() as Node3D
	root.add_child(archer)
	var host := archer.get_node(^"SkillHost") as SkillHostComponent
	_expect(host.get_regular_skill(1) == archer.get_node_or_null(^"SkillHost/SkillSocket/RapidShotSkill"), "archer equips rapid shot in second regular slot")
	_expect(host.get_regular_skill(1) != null, "archer second skill slot is not empty")
	archer.free()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("MultiShotSkillAssemblyTest: PASS")
	quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
