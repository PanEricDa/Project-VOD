extends SceneTree

## 炎爆视觉契约：打断清理、施法时长同步、独立命中生命周期及预览资源可运行。
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var paths: Array[String] = [
		"res://Effects/Skills/Pyroblast/PyroblastCastChargeEffect.tscn",
		"res://Effects/Skills/Pyroblast/PyroblastFlightEffect.tscn",
		"res://Effects/Skills/Pyroblast/PyroblastImpactEffect.tscn",
		"res://Effects/Skills/Pyroblast/PyroblastCastChargeEffectPreview.tscn",
		"res://Effects/Skills/Pyroblast/PyroblastFlightEffectPreview.tscn",
		"res://Effects/Skills/Pyroblast/PyroblastImpactEffectPreview.tscn",
		"res://Effects/Skills/Pyroblast/PyroblastVisualSequencePreview.tscn"
	]
	for path: String in paths:
		_expect(ResourceLoader.exists(path), "Visual asset exists: " + path)
	if not failures.is_empty():
		_finish()
		return
	for path: String in paths:
		_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "Editor UID: " + path)
	var world := Node3D.new()
	root.add_child(world)
	var source := Node3D.new()
	world.add_child(source)
	var charge := (load(paths[0]) as PackedScene).instantiate() as Node3D
	charge.set("autoplay", false)
	world.add_child(charge)
	_expect(charge.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and not charge.get_node("VisualRoot/RisingSparks").is_physics_interpolated(), "render-frame procedural sparks must not inherit physics interpolation")
	charge.call("configure_cast", source, Transform3D(Basis.IDENTITY, Vector3(0.4, 0.8, 0)), 2.0)
	charge.call("play")
	await process_frame
	_expect(is_equal_approx(float(charge.get("effect_duration")), 2.0), "Actual cast duration reaches effect")
	source.position = Vector3(2, 0, 0)
	await process_frame
	_expect(charge.global_position.distance_to(source.global_position) < 0.01, "Foot ring follows caster")
	charge.call("stop")
	_expect(not bool(charge.call("is_playing")), "Interrupted charge stops")
	_expect(not charge.get_node("VisualRoot").visible, "Interrupted charge hides visuals")
	charge.call("play")
	_expect(bool(charge.call("is_playing")), "Charge replays after interruption")
	charge.call("stop")
	var flight := (load(paths[1]) as PackedScene).instantiate() as Node3D
	flight.set("autoplay", false)
	world.add_child(flight)
	flight.call("start")
	_expect(bool(flight.call("is_active")), "Flight starts")
	flight.call("stop")
	_expect(not bool(flight.call("is_active")), "Flight stops")
	var impact := (load(paths[2]) as PackedScene).instantiate() as Node3D
	world.add_child(impact)
	await create_timer(0.65).timeout
	_expect(not is_instance_valid(impact), "Independent impact frees itself")
	var caster := (load("res://UnitSystem/AI/Ally/Units/Caster.tscn") as PackedScene).instantiate() as UnitBase
	caster.set("automatic_skill_cast_enabled", false)
	world.add_child(caster)
	var target := (load("res://UnitSystem/Base/00_UnitBase.tscn") as PackedScene).instantiate() as UnitBase
	target.team_id = 2
	world.add_child(target)
	target.position = Vector3(3, 0, 0)
	await physics_frame
	var host := caster.get_node("SkillHost") as SkillHostComponent
	host.configure_owner(caster, world)
	var skill := host.get_node("SkillSocket/PyroblastSkill") as SkillBase
	_expect(host.request_skill(&"pyroblast", target), "Real Pyroblast cast request succeeds")
	if skill.get_state() == SkillBase.SkillState.ACTION_REQUESTED:
		skill.confirm_action_started(Transform3D(Basis.IDENTITY, Vector3(0.4, 0.8, 0)))
	var controlled: Node3D
	for child: Node in world.get_children():
		if child.get_script() == load("res://Effects/Skills/Pyroblast/PyroblastCastChargeEffect.gd") and child != charge:
			controlled = child as Node3D
	_expect(is_instance_valid(controlled), "Skill creates controlled foot-to-hand charge")
	if is_instance_valid(controlled):
		_expect(is_equal_approx(float(controlled.get("effect_duration")), skill.get_effective_cast_time()), "Skill supplies actual cast duration")
		skill.cancel_skill(&"test_interrupt")
		_expect(not bool(controlled.call("is_playing")), "Skill cancellation immediately stops charge")
		await process_frame
		_expect(not is_instance_valid(controlled), "Cancelled charge has no lingering instance")
	# 等待已有公共冷却和取消动作收尾；视觉测试不绕过角色释放合法性。
	await create_timer(1.5).timeout
	skill.reset_skill()
	_expect(host.request_skill(&"pyroblast", target), "Interrupted skill can be requested again")
	if skill.get_state() == SkillBase.SkillState.ACTION_REQUESTED:
		skill.confirm_action_started(Transform3D(Basis.IDENTITY, Vector3(0.4, 0.8, 0)))
	if skill.get_state() == SkillBase.SkillState.CASTING:
		_expect(skill.release_action(Transform3D(Basis.IDENTITY, Vector3(0.4, 0.8, 0))), "Release accepts delivery")
	await process_frame
	var active_charge := false
	for child: Node in world.get_children():
		if child.get_script() == load("res://Effects/Skills/Pyroblast/PyroblastCastChargeEffect.gd") and child != charge:
			active_charge = true
	_expect(not active_charge, "Release clears controlled charge")
	for _frame: int in range(32):
		await physics_frame
	var hit_visual: Node3D
	var remaining_projectiles := 0
	for child: Node in world.get_children():
		if child is AITrackingArcProjectile:
			remaining_projectiles += 1
		if String(child.name).begins_with("PyroblastImpactEffect"):
			hit_visual = child as Node3D
	_expect(remaining_projectiles == 0, "Projectile ends after arrival")
	_expect(is_instance_valid(hit_visual), "Impact survives projectile destruction independently")
	if is_instance_valid(hit_visual):
		_expect(hit_visual.global_position.distance_to(target.global_position + Vector3.UP * 0.25) < 0.01, "Impact uses world hit position")
		await create_timer(0.6).timeout
		_expect(not is_instance_valid(hit_visual), "Runtime impact cleans itself up")
	skill.reset_skill()
	var expired := (load("res://Item/Projectiles/PyroblastProjectile.tscn") as PackedScene).instantiate() as AITrackingArcProjectile
	expired.maximum_lifetime = 0.02
	world.add_child(expired)
	_expect(expired.launch(target, Vector3.UP), "Expiry probe launches")
	await create_timer(0.08).timeout
	var false_impact := false
	for child: Node in world.get_children():
		if String(child.name).begins_with("PyroblastImpactEffect"):
			false_impact = true
	_expect(not false_impact, "Expired projectile does not fabricate impact")
	world.free()
	for index: int in range(3, paths.size()):
		var preview := (load(paths[index]) as PackedScene).instantiate()
		root.add_child(preview)
		await process_frame
		_expect(preview.has_node("Camera3D"), "Preview has camera")
		preview.free()
	_finish()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _finish() -> void:
	for message: String in failures:
		push_error(message)
	if failures.is_empty():
		print("PyroblastVisualEffectTest: PASS")
	quit(0 if failures.is_empty() else 1)
