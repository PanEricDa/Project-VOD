extends SceneTree
## 正式终结内容装配契约，不允许以预览脚本、旧技能特效或无UID资源代替交付。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var base := "res://SkillSystem/00-Skills/Finisher_FlameBarrage/"
	var paths := [base+"FlameBarrageFinisherSkill.tscn",base+"FlameBarrageCinematic.tres",base+"FlameBarrageAction.tres","res://Item/Projectiles/FlameBarrageProjectile.tscn","res://Effects/Camera/Presets/FlameBarrageCinematicCamera.tres","res://Scenes/Previews/SquadFinisherComparisonPreview.tscn"]
	for path: String in paths:
		_expect(ResourceLoader.exists(path), "asset exists "+path)
	if not failures.is_empty():
		_finish()
		return
	for path: String in paths:
		_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "Godot registered UID "+path)
	var skill := load(paths[0]).instantiate() as SkillBase
	_expect(skill != null and skill.delivery is ArcProjectileDeliveryConfig and not skill.automatic_cast_enabled, "ordinary SkillBase with generic Arc delivery, automatic off")
	_expect(skill.skill_cooldown == 0 and skill.get_combo_focus_cost() == null, "no additional cost or cooldown")
	var config := skill.delivery as ArcProjectileDeliveryConfig
	_expect(config.destination_mode == 1 and config.shot_count == 5 and is_equal_approx(config.shot_interval_seconds,0.12) and config.validate_configuration().is_empty(), "five ground shots use valid human-configured ground radii")
	# 正式命中资产沿原接口缩放；用两个明确样本验证视觉随半径变化，不锁死策划当前调参。
	var projectile := config.projectile_scene.instantiate() as Node3D
	var impact := projectile.get("impact_effect_scene").instantiate() as Node3D
	var original_scale := impact.scale
	impact.call("configure_impact_radius",1.5)
	_expect(impact.scale.is_equal_approx(original_scale*0.5),"1.5-meter impact halves the authored three-meter visual")
	impact.call("configure_impact_radius",3.0)
	_expect(impact.scale.is_equal_approx(original_scale),"reconfiguring impact to three meters restores visual without cumulative scaling")
	impact.free()
	projectile.free()
	_expect(skill.cinematic_profile.validate_configuration().is_empty(), "dedicated animation has valid markers")
	# 用户延长后的前摇须在正式配置中保留，不能被旧base_cast_time重新加速压回原长度。
	var profile := skill.cinematic_profile
	var releases := profile.marker_times(&"release_action")
	_expect(is_equal_approx(profile.action_animation.length,1.33333333) and releases.size() == 1 and is_equal_approx(releases[0],0.6), "formal action includes updated longer windup and full recovery")
	_expect(releases.size() == 1 and is_equal_approx(skill.get_effective_cast_time(),releases[0]), "default action plays at authored speed instead of compressing windup")
	# 身体和武器必须共同保持蓄力姿态0.5秒，而非拉慢后续动作；方法标记同步顺延。
	var action := profile.action_animation
	var rotation_track := action.find_track(NodePath("CharacterRoot:rotation:y"),Animation.TYPE_VALUE)
	var socket_track := action.find_track(NodePath("CharacterRoot/WeaponSocket:position"),Animation.TYPE_VALUE)
	_expect(rotation_track >= 0 and socket_track >= 0,"full-pose hold tracks exist")
	if rotation_track >= 0 and socket_track >= 0:
		for sample: float in [0.16666667,0.3,0.5,0.6666666]:
			_expect(is_equal_approx(float(action.value_track_interpolate(rotation_track,sample)),0.5348367),"body holds ready pose during extended closeup "+str(sample))
			_expect((action.value_track_interpolate(socket_track,sample) as Vector3).is_equal_approx(Vector3(0.34,0.60809654,-0.3993689)),"weapon holds ready pose during extended closeup "+str(sample))
	var finishes := profile.marker_times(&"finish_action")
	_expect(finishes.size() == 1 and is_equal_approx(finishes[0],0.76666667),"finish marker shifted with later movement")
	var caster := load("res://UnitSystem/AI/Ally/Units/Caster.tscn").instantiate() as AllyBase
	root.add_child(caster)
	var host := caster.get_node("SkillHost") as SkillHostComponent
	_expect(host.get_finisher_skill() != null and host.get_finisher_skill().skill_id == skill.skill_id, "Caster finisher slot assembled visibly")
	_expect(not host.get_equipped_regular_skills().has(host.get_finisher_skill()) and host.combo_skill != host.finisher_skill, "regular combo finisher separate instances")
	caster.free()
	skill.free()
	await process_frame
	await process_frame
	_finish()
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message in failures: printerr("FAIL: ",message)
	print("FlameBarrageAssemblyTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
