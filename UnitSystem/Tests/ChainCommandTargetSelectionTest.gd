extends SceneTree
## 玩家锁定意图、待执行重选与已开始目标冻结，复用真实Caster/Player/感知组件。
const FIXTURE = preload("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd")
var failures: Array[String] = []

func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var f = FIXTURE.make_fixture(root)
	var b = load("res://UnitSystem/AI/Enemy/EnemyBase.tscn").instantiate() as UnitBase
	b.maximum_health = 10000.0
	b.position = Vector3(3, 0, 0)
	f.world.add_child(b)
	b.set_physics_process(false)
	b.get_targeting_component().set_physics_process(false)
	await physics_frame
	await physics_frame
	var host: SkillHostComponent = f.host
	var behavior = f.actor.get_behavior_state_machine()
	var player_targeting = f.player.get_node("TargetingSystem")
	player_targeting.request_lock(f.enemy)
	var request = SkillCommandRequest.create(301, 300, f.actor, f.combo, f.world, 8.0, Callable(self, "_allow"))
	f.requests[301] = request
	host.enqueue_command(request)
	player_targeting.request_lock(b)
	behavior.physics_tick(0.01)
	_expect(host.get_active_command_id() == 301, "current player intent executes at start")
	var ctx = f.combo.get_current_context()
	_expect(ctx != null and ctx.resolved_target == b, "pending changed lock selects B")
	_expect(f.actor.get_locked_target() == f.enemy, "player intent never overwrites valid AI lock A")
	player_targeting.request_lock(f.enemy)
	var released: Array[Node3D] = []
	host.skill_released.connect(func(context): released.append(context.resolved_target))
	f.animation.release_action()
	_expect(released == [b], "started request target stays B after player changes lock")
	f.animation.finish_action()
	var heal = load("res://SkillSystem/00-Skills/GreaterHeal/GreaterHealSkill.tscn").instantiate() as SkillBase
	heal.skill_id = &"test_chain_heal"
	heal.skill_cooldown = 0.0
	heal.add_child(ComboFocusCost.new())
	host.get_node("SkillSocket").add_child(heal)
	host.register_skill(heal)
	host.combo_skill = heal
	f.actor.apply_damage(20.0, f.enemy)
	var prepared = host.prepare_command_context(f.enemy)
	_expect(prepared != null and prepared.resolved_target == f.actor, "heal ignores enemy lock and uses friendly health selection")
	host.combo_skill = f.combo
	f.combo.cast_range = 0.1
	var timeout = SkillCommandRequest.create(302, 300, f.actor, f.combo, f.world, 8.0, Callable(self, "_allow"))
	f.requests[302] = timeout
	host.enqueue_command(timeout)
	for step in range(9):
		player_targeting.request_lock(f.enemy if step % 2 == 0 else b)
		behavior.physics_tick(1.0)
	_expect(timeout.has_failed() and timeout.has_wait_expired() and not host.has_pending_command(), "switching approach targets cannot refresh 8 second deadline")
	f.combo.cast_range = 6.0
	player_targeting.clear_locked_target()
	f.enemy.can_die = true
	f.enemy.apply_damage(100000.0, f.actor)
	var fallback = host.prepare_command_context()
	_expect(fallback != null and fallback.resolved_target == b, "dead AI current target reselects through existing targeting policy")
	var dead_target_request = SkillCommandRequest.create(303, 300, f.actor, f.combo, f.world, 8.0, Callable(self, "_allow"))
	f.requests[303] = dead_target_request
	host.enqueue_command(dead_target_request)
	var driver = f.actor.get_combat_system().get_attack_controller()
	if driver.is_action_in_progress():
		var clip = f.animation.get_animation(f.animation.current_animation)
		f.animation.advance(clip.length / f.animation.get_playing_speed() + 0.05)
	behavior.physics_tick(0.01)
	_expect(host.get_active_command_id() == 303 and not dead_target_request.has_failed(), "dead pre-start target does not end valid new command")
	f.animation.release_action()
	f.animation.finish_action()
	f.world.free()
	await process_frame
	for message in failures: push_error(message)
	if failures.is_empty(): print("ChainCommandTargetSelectionTest: PASS")
	quit(0 if failures.is_empty() else 1)

func _allow() -> bool: return true
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
