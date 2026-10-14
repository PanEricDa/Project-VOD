extends SceneTree
## 请求用途、单伙伴缓存和动作身份测试；Host使用真实Skill，角色端使用现有Caster动作控制器。
const UNIT = preload("res://UnitSystem/Base/00_UnitBase.tscn")
const SKILL = preload("res://SkillSystem/01-Core/SkillBase.tscn")
var failures: Array[String] = []
var _requests: Dictionary = {}

func _initialize() -> void: call_deferred(&"_run")

func _run() -> void:
	var world = Node3D.new()
	root.add_child(world)
	var caster = UNIT.instantiate() as UnitBase
	caster.team_id = 1
	world.add_child(caster)
	var enemy = UNIT.instantiate() as UnitBase
	enemy.team_id = 2
	enemy.position = Vector3(1, 0, 0)
	world.add_child(enemy)
	var host = caster.get_node("SkillHost") as SkillHostComponent
	host.configure_owner(caster, world)
	caster.set_physics_process(false)
	enemy.set_physics_process(false)
	if not host.has_method(&"enqueue_command"):
		_expect(false, "Host must expose command admission and action lock")
		world.free()
		_finish()
		return
	var skill = SKILL.instantiate() as SkillBase
	skill.skill_id = &"chain"
	skill.cast_range = 10.0
	skill.skill_cooldown = 10.0
	skill.delivery = InstantTargetDeliveryConfig.new()
	var damage = HealthChangeSkillEffect.new()
	damage.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount = 5.0
	skill.add_child(damage)
	skill.add_child(ComboFocusCost.new())
	host.get_node("SkillSocket").add_child(skill)
	host.register_skill(skill)
	host.combo_skill = skill
	var first = _request(101, caster, skill, world)
	var second = _request(102, caster, skill, world)
	skill.call("_start_cooldown")
	host.start_global_cooldown(0.7)
	var normal = SkillContext.new()
	normal.requested_target = enemy
	normal.explicit_target_requested = true
	_expect(not skill.can_request(normal), "normal request respects existing cooldown")
	host.skill_released.connect(_on_released)
	host.command_failed.connect(_on_failed)
	_expect(host.enqueue_command(first), "first admitted")
	_expect(not host.enqueue_command(second), "one pending until animation confirmation")
	_expect(host.get_active_skill() == null, "admission never starts synchronously")
	_expect(host.advance_pending_command(enemy, 0.0), "chain owns next legal frame despite cooldown")
	_expect(host.has_pending_command() and not host.has_command_action_lock(), "action requested is not yet animation start")
	_expect(not host.call("confirm_active_action_started", Transform3D.IDENTITY, 99), "old confirmation ignored")
	_expect(host.call("confirm_active_action_started", Transform3D.IDENTITY, 101), "matching animation starts")
	_expect(not host.has_pending_command() and host.has_command_action_lock(), "pending moves active only at actual start")
	_expect(host.enqueue_command(second), "one next pending while casting")
	_expect(not host.call("release_active_action", Transform3D.IDENTITY, 99), "old release ignored")
	_expect(host.call("release_active_action", Transform3D.IDENTITY, 101), "matching release succeeds")
	_expect(first.has_released() and host.has_command_action_lock(), "release does not unlock actor")
	_expect(is_equal_approx(host.get_global_cooldown_remaining(), 0.7), "chain never restarts shared cooldown")
	_expect(skill.get_cooldown_remaining() > 0.0, "existing skill cooldown not erased")
	host.call("finish_active_action", 99)
	_expect(host.has_command_action_lock(), "old finish cannot clear current action")
	host.call("finish_active_action", 101)
	_expect(not host.has_command_action_lock() and host.has_pending_command(), "finish clears only active, preserves next pending")
	host.cancel_command(102, &"test_cancel")
	_expect(second.has_failed() and not host.has_pending_command(), "pending cancellation reaches owner once")
	var blocker = SkillConditionBase.new()
	blocker.application_scope = SkillConditionBase.ApplicationScope.AUTOMATIC_ONLY
	skill.add_child(blocker)
	_expect(host.prepare_command_context(enemy) != null, "explicit chain skips automatic-only condition")
	blocker.application_scope = SkillConditionBase.ApplicationScope.ALL_REQUESTS
	_expect(host.prepare_command_context(enemy) == null, "all-request condition still applies")
	blocker.free()
	host.set_cast_blocked(true)
	_expect(host.prepare_command_context(enemy) == null, "cast block never bypassed")
	host.set_cast_blocked(false)
	var waiting = _request(103, caster, skill, world)
	host.enqueue_command(waiting)
	host.advance_pending_command(enemy, 8.0)
	_expect(waiting.has_failed() and not host.has_pending_command(), "waiting timeout includes unstarted request")
	var reentrant = _request(104, caster, skill, world)
	host.enqueue_command(reentrant)
	host.advance_pending_command(enemy, 0.0)
	skill.cast_started.connect(_cancel_at_cast.bind(host, 104), CONNECT_ONE_SHOT)
	_expect(not host.call("confirm_active_action_started", Transform3D.IDENTITY, 104), "synchronous cast cancellation cannot resurrect active request")
	_expect(reentrant.has_failed() and host.get_active_command_id() == 0, "cancelled confirmation has no active lock")
	var death_pending = _request(105, caster, skill, world)
	host.enqueue_command(death_pending)
	caster.can_die = true
	caster.apply_damage(100000.0, enemy)
	host.call("_physics_process", 0.0)
	_expect(death_pending.has_failed() and not host.has_pending_command(), "owner death cleans never-started pending without behavior tick")
	world.free()
	_requests.clear()
	await _verify_tagged_native_action()
	_finish()

func _request(id: int, caster: Node3D, skill: SkillBase, world: Node) -> SkillCommandRequest:
	var request = SkillCommandRequest.create(id, 100, caster, skill, world, 8.0, Callable(self, "_allow"))
	_requests[id] = request
	return request

func _cancel_at_cast(_context: SkillContext, host: SkillHostComponent, id: int) -> void:
	host.cancel_command(id, &"cast_listener_cancel")

func _allow() -> bool: return true
func _on_released(ctx: SkillContext) -> void:
	if ctx.command_request != null: ctx.command_request.mark_released()
func _on_failed(id: int, reason: StringName) -> void:
	if _requests.has(id): _requests[id].mark_failed(reason)

func _verify_tagged_native_action() -> void:
	var world = Node3D.new()
	root.add_child(world)
	var actor = load("res://UnitSystem/AI/Ally/Units/Caster.tscn").instantiate() as AllyBase
	actor.automatic_skill_cast_enabled = false
	world.add_child(actor)
	actor.set_physics_process(false)
	var combat = actor.get_combat_system()
	if not combat.has_signal(&"external_action_lifecycle"):
		_expect(false, "native action lifecycle must carry request ID")
		world.free()
		return
	var behavior = actor.get_behavior_state_machine()
	for pair in [[combat.external_action_released, &"_on_external_action_released"], [combat.external_action_finished, &"_on_external_action_finished"], [combat.external_action_cancelled, &"_on_external_action_cancelled"]]:
		var callback = Callable(behavior, pair[1])
		if pair[0].is_connected(callback): pair[0].disconnect(callback)
	var events: Array[Array] = []
	combat.external_action_lifecycle.connect(func(id, event): events.append([id, event]))
	var controller = combat.get_attack_controller()
	_expect(combat.call("request_external_action", 0.2, null, {}, 301), "native tagged cast starts")
	_expect(combat.is_action_in_progress(), "native external action counts as occupied")
	controller.call("_on_external_action_release_requested")
	controller.call("_on_external_action_finish_requested")
	_expect(events == [[301, &"release"], [301, &"finish"]], "native notifications preserve accepted action identity")
	_expect(not combat.is_action_in_progress(), "native finish releases action occupancy")
	world.free()
	await process_frame

func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _finish() -> void:
	for f in failures: push_error(f)
	if failures.is_empty(): print("SkillCommandActivationTest: PASS")
	quit(0 if failures.is_empty() else 1)
