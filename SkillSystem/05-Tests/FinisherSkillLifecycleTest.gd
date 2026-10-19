extends SceneTree
## 真实Caster终结动作入口：先预检再抢占、专属动画、来源、门闩及恢复。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var path := "res://SkillSystem/01-Core/SkillCinematicProfile.gd"
	if not ResourceLoader.exists(path):
		failures.append("missing cinematic profile")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := load("res://UnitSystem/AI/Ally/Units/Caster.tscn").instantiate() as AllyBase
	caster.automatic_skill_cast_enabled = false
	world.add_child(caster)
	caster.set_physics_process(false)
	var enemy := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	enemy.team_id = 2
	world.add_child(enemy)
	enemy.position = Vector3(0, 0, -3)
	var host := caster.get_node("SkillHost") as SkillHostComponent
	host.configure_owner(caster, world)
	var skill := load("res://SkillSystem/00-Templates/RangedSkillTemplate.tscn").instantiate() as SkillBase
	skill.skill_id = &"test_finisher"
	skill.cast_range = 6
	skill.base_cast_time = 1.0 / 3.0
	skill.skill_cooldown = 0
	skill.automatic_cast_enabled = false
	var config := InstantTargetDeliveryConfig.new()
	skill.delivery = config
	var profile: Resource = load(path).new()
	profile.set("action_animation", load("res://Item/Weapon/MagicGlobe/MagicGlobeAnimationLibrary.res").get_animation("finish_cast_1"))
	skill.set("cinematic_profile", profile)
	var effect := HealthChangeSkillEffect.new()
	effect.operation = HealthChangeSkillEffect.Operation.DAMAGE
	effect.base_amount = 5
	effect.power_ratio = 0
	skill.add_child(effect)
	host.get_node("SkillSocket").add_child(skill)
	host.register_skill(skill)
	host.finisher_skill = skill
	await physics_frame
	_expect(host.request_skill(&"firebolt", enemy), "old normal cast starts")
	var old := host.get_active_skill()
	enemy.position.z = -100
	_expect(host.call("prepare_finisher_context", enemy) == null, "out of range finisher rejected")
	_expect(host.get_active_skill() == old, "preflight rejection preserves old action")
	enemy.position.z = -3
	var context: SkillContext = host.call("prepare_finisher_context", enemy)
	_expect(context != null, "finisher context prepared")
	if context == null:
		world.free()
		_finish()
		return
	_expect(context.purpose == 2 and context.damage_context.origin == CombatDamageContext.Origin.FINISHER and context.damage_context.focus_yield_multiplier == 0, "finisher is separate purpose and source with zero focus yield")
	var clock := SkillExecutionClock.new()
	clock.configure(world)
	context.execution_clock = clock
	_expect(host.call("activate_finisher", context), "finisher preempts normal action after preflight")
	var animation := caster.get_node("Visual/CasterVisual/CharacterAnimationPlayer") as AnimationPlayer
	_expect(str(animation.current_animation).begins_with("_skill_cinematic/"), "dedicated animation not weapon basic_cast")
	var id := host.get_active_command_id()
	_expect(id > 0 and host.has_command_action_lock(), "positive identity owns finisher action")
	host.finish_active_action(id + 1)
	_expect(host.get_active_skill() == skill, "stale finish cannot close finisher")
	for frame: int in range(75): await physics_frame
	_expect(not host.has_command_action_lock() and host.get_active_skill() == null, "finished action releases host")
	_expect(animation.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "manual animation clock restored")
	host.set_cast_blocked(true)
	_expect(not host.request_finisher(enemy), "hard cast block prevents finisher")
	world.free()
	await process_frame
	await process_frame
	_test_release_range_grace()
	await process_frame
	_finish()

# 真实SkillBase入口/释放与Instant交付验证；只替换测试实例的交付和视觉，避免随机落点掩盖射程结果。
func _test_release_range_grace() -> void:
	var probe := load("res://SkillSystem/00-Skills/Finisher_FlameBarrage/FlameBarrageFinisherSkill.tscn").instantiate() as SkillBase
	var base := probe.cast_range
	var edge := base+probe.release_range_tolerance_m
	probe.free()
	# 围绕当前配置取边界；调整正式技能射程不应要求回退为旧6米。
	var cases := [
		{"label":"configured finisher accepts drift within grace","start":base-0.1,"end":edge-0.1,"begin":true,"release":true,"default_grace":false},
		{"label":"configured finisher accepts release range edge","start":base,"end":edge,"begin":true,"release":true,"default_grace":false},
		{"label":"finisher rejects beyond release grace","start":base-0.1,"end":edge+0.1,"begin":true,"release":false,"default_grace":false},
		{"label":"grace cannot expand initial cast range","start":base+1.0,"end":base+1.0,"begin":false,"release":false,"default_grace":false},
		{"label":"large displacement still cancels release","start":base-0.1,"end":edge+12.0,"begin":true,"release":false,"default_grace":false},
		{"label":"zero grace preserves previous release range","start":base-0.1,"end":base+0.2,"begin":true,"release":false,"default_grace":true},
	]
	for entry: Dictionary in cases:
		var world := Node3D.new()
		root.add_child(world)
		var source := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
		var target := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
		source.team_id = 1
		target.team_id = 2
		world.add_child(source)
		world.add_child(target)
		target.position.x = entry.start
		var skill := load("res://SkillSystem/00-Skills/Finisher_FlameBarrage/FlameBarrageFinisherSkill.tscn").instantiate() as SkillBase
		skill.delivery = InstantTargetDeliveryConfig.new()
		skill.cast_effect_scene = null
		skill.release_effect_scene = null
		if entry.default_grace and skill.get("release_range_tolerance_m") != null:
			skill.set("release_range_tolerance_m",0.0)
		world.add_child(skill)
		skill.configure_owner(source,null,world)
		var context := SkillContext.new()
		context.caster = source
		context.request_source = SkillContext.RequestSource.EXPLICIT
		context.purpose = SkillContext.Purpose.FINISHER
		context.requested_target = target
		context.explicit_target_requested = true
		context.delivery_parent = world
		var available := skill.can_start_in_place(context)
		_expect(available == entry.begin,entry.label+": initial availability")
		if entry.begin:
			_expect(skill.activate(context),entry.label+": activation")
			_expect(skill.confirm_action_started(Transform3D.IDENTITY),entry.label+": animation confirmed")
			target.position.x = entry.end
			var before := target.get_current_health()
			var released := skill.release_action(Transform3D.IDENTITY)
			_expect(released == entry.release,entry.label+": release decision")
			_expect((target.get_current_health() < before) == entry.release,entry.label+": actual damage")
		world.free()

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message in failures: printerr("FAIL: ",message)
	print("FinisherSkillLifecycleTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
