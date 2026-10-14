extends SceneTree
## 真实伙伴动画的指令优先级集成测试，静态夹具构建供目标测试复用，不植入生产测试方法。
var failures: Array[String] = []

static func make_fixture(parent: Node, actor_path: String = "res://UnitSystem/AI/Ally/Units/Caster.tscn", manage_requests: bool = true) -> Dictionary:
	var world = Node3D.new()
	parent.add_child(world)
	var player = load("res://UnitSystem/Player/Hero/Hero.tscn").instantiate() as PlayerBase
	player.gravity_multiplier = 0.0
	player.position = Vector3(0, 0, 2)
	world.add_child(player)
	player.set_physics_process(false)
	var actor = load(actor_path).instantiate() as AllyBase
	actor.gravity_multiplier = 0.0
	actor.automatic_skill_cast_enabled = false
	world.add_child(actor)
	actor.set_physics_process(false)
	var enemy = load("res://UnitSystem/AI/Enemy/EnemyBase.tscn").instantiate() as UnitBase
	enemy.maximum_health = 10000.0
	enemy.position = Vector3(2, 0, 0)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	if enemy.has_method(&"get_targeting_component"): enemy.get_targeting_component().set_physics_process(false)
	var host = actor.get_node("SkillHost") as SkillHostComponent
	host.configure_owner(actor, world)
	var combo = load("res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn").instantiate() as SkillBase
	combo.skill_id = &"test_chain"
	combo.skill_cooldown = 0.0
	combo.base_cast_time = 0.2
	combo.cast_range = 6.0
	combo.automatic_cast_enabled = false
	combo.add_child(ComboFocusCost.new())
	host.get_node("SkillSocket").add_child(combo)
	host.register_skill(combo)
	host.combo_skill = combo
	var targeting = actor.get_targeting_component()
	targeting.call("_set_locked_target", enemy)
	targeting.set_physics_process(false)
	actor.get_behavior_state_machine().set_follow_target(player)
	var animation = actor.get_node("Visual").find_child("CharacterAnimationPlayer", true, false) as CharacterAnimationEventPlayer
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var requests: Dictionary = {}
	if manage_requests:
		host.skill_released.connect(func(ctx):
			if ctx.command_request != null: ctx.command_request.mark_released())
		host.command_failed.connect(func(id, reason):
			if requests.has(id): requests[id].mark_failed(reason))
	return {"world": world, "player": player, "actor": actor, "enemy": enemy, "host": host, "combo": combo, "animation": animation, "requests": requests}

func _initialize() -> void: call_deferred(&"_run")

func _run() -> void:
	var f = make_fixture(root)
	await physics_frame
	await physics_frame
	var host: SkillHostComponent = f.host
	var behavior = f.actor.get_behavior_state_machine()
	var combat = f.actor.get_combat_system()
	var regular = host.get_regular_skill(0)
	regular.base_cast_time = 0.2
	var first = SkillCommandRequest.create(201, 200, f.actor, f.combo, f.world, 8.0, Callable(self, "_allow"))
	f.requests[201] = first
	_expect(host.request_skill(regular.skill_id, f.enemy), "real normal cast starts")
	_expect(combat.is_action_in_progress(), "normal cast really occupies driver")
	_expect(host.enqueue_command(first), "chain accepted while normal cast active")
	behavior.physics_tick(0.01)
	_expect(host.has_pending_command() and host.get_active_command_id() == 0, "chain waits started normal animation")
	var clip = f.animation.get_animation(f.animation.current_animation)
	f.animation.advance(clip.length / f.animation.get_playing_speed() + 0.05)
	behavior.physics_tick(0.01)
	_expect(host.get_active_command_id() == 201 and host.has_command_action_lock(), "chain starts at earliest idle chance")
	_expect(combat.get_attack_controller().get_external_request_id() == 201, "behavior forwards chain action identity")
	var before_cd = float(behavior.get("_shared_action_cooldown_remaining"))
	f.animation.release_action()
	_expect(first.has_released() and host.has_command_action_lock(), "real release keeps lock until action finish")
	_expect(is_equal_approx(before_cd, float(behavior.get("_shared_action_cooldown_remaining"))), "chain release does not extend normal shared cooldown")
	f.player.position = Vector3(100, 0, 0)
	behavior.physics_tick(0.01)
	_expect(host.has_command_action_lock(), "forced disengage cannot override started chain")
	f.animation.finish_action()
	_expect(not host.has_command_action_lock(), "tagged finish returns actor lock")
	f.world.free()
	f = make_fixture(root)
	host = f.host
	behavior = f.actor.get_behavior_state_machine()
	combat = f.actor.get_combat_system()
	regular = host.get_regular_skill(0)
	f.enemy.position = Vector3(9, 0, 0)
	regular.reset_skill()
	regular.cast_range = 1.0
	_expect(host.request_skill(regular.skill_id, f.enemy), "unstarted normal approach queued")
	f.enemy.position = Vector3(2, 0, 0)
	var next = SkillCommandRequest.create(202, 200, f.actor, f.combo, f.world, 8.0, Callable(self, "_allow"))
	f.requests[202] = next
	host.enqueue_command(next)
	behavior.physics_tick(0.01)
	_expect(host.get_active_command_id() == 202, "unstarted regular approach yields to command")
	host.set_cast_blocked(true)
	_expect(not combat.is_action_in_progress() and next.has_failed(), "cast block cancels actual native driver and request")
	f.world.free()
	f = make_fixture(root)
	host = f.host
	combat = f.actor.get_combat_system()
	regular = host.get_regular_skill(0)
	_expect(host.request_skill(regular.skill_id, f.enemy), "normal interruption probe starts")
	regular.cancel_skill(&"direct_interrupt")
	f.animation.release_action()
	_expect(not combat.is_action_in_progress(), "cancelled normal skill shuts down native driver at old release marker")
	f.world.free()
	await _verify_melee_cancel_closes_window()
	await process_frame
	for message in failures: push_error(message)
	if failures.is_empty(): print("AllyChainCommandPriorityTest: PASS")
	quit(0 if failures.is_empty() else 1)

func _verify_melee_cancel_closes_window() -> void:
	var f = make_fixture(root, "res://UnitSystem/AI/Ally/Units/Guardian.tscn")
	await physics_frame
	await physics_frame
	var host: SkillHostComponent = f.host
	var combo = host.get_node("SkillSocket/ComboGuardianBashSkill") as SkillBase
	host.combo_skill = combo
	f.enemy.position = Vector3(0, 0, -0.4)
	var focus = SquadFocusComponent.new()
	focus.auto_bind_parent = false
	f.world.add_child(focus)
	var party: Array[UnitBase] = [f.player, f.actor]
	focus.bind_scope(f.world, party)
	var request = SkillCommandRequest.create(401, 400, f.actor, combo, f.world, 8.0, Callable(self, "_allow"))
	f.requests[401] = request
	_expect(host.enqueue_command(request), "Guardian native melee request admitted")
	f.actor.get_behavior_state_machine().physics_tick(0.01)
	f.animation.release_action()
	f.enemy.position = Vector3(20, 0, 0)
	var combat = f.actor.get_combat_system()
	var hitbox = combat.get_node("MeleeHitbox")
	combat.get_attack_controller().call("_on_hit_window_open_requested")
	_expect(hitbox.get("_detection_active"), "real melee animation opens hitbox")
	host.set_cast_blocked(true)
	_expect(not hitbox.get("_detection_active"), "cancel closes native hit window synchronously")
	var before: float = f.enemy.get_current_health()
	var focus_before: float = focus.get_current_focus()
	f.enemy.position = Vector3(0, 0, -0.4)
	await physics_frame
	await physics_frame
	hitbox.call("_physics_process", 0.01)
	_expect(f.enemy.get_current_health() == before and focus.get_current_focus() == focus_before, "enemy entering cancelled window takes no residual ordinary damage or Focus gain")
	f.world.free()

func _allow() -> bool: return true
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
