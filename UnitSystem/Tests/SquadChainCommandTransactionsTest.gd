extends SceneTree
## 队伍指令的真实Host/动画/Focus事务；不使用假支付器，也不把接受和命中混为一谈。
const DELIVERY_FIXTURES = preload("res://SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd")
const FIXTURE = preload("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd")
var failures: Array[String] = []
var round_id: int = 10000

class FailingEffect:
	extends SkillEffectBase
	func apply(_context: SkillContext, _result: SkillDeliveryResult, _target: Node3D) -> bool: return false

class FailingArea:
	extends Node3D
	func launch(_context: SkillContext) -> bool: return false

class ResetFocusCost:
	extends SkillCostBase
	var focus: SquadFocusComponent
	func can_pay(_context: SkillContext) -> bool: return true
	func commit(_context: SkillContext) -> bool:
		focus.reset_focus()
		return true

func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var path = "res://UnitSystem/Components/Combat/Squad/SquadChainCommandController.gd"
	if not ResourceLoader.exists(path):
		_expect(false, "squad controller must join existing focus transactions to real commands")
		_finish()
		return
	var f = FIXTURE.make_fixture(root, "res://UnitSystem/AI/Ally/Units/Caster.tscn", false)
	await physics_frame
	await physics_frame
	var focus = SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 100.0
	f.world.add_child(focus)
	var party: Array[UnitBase] = [f.player, f.actor]
	focus.bind_scope(f.world, party)
	var controller = load(path).new()
	var slots: Array[AllyBase] = [f.actor, null, null, null]
	controller.companions = slots
	controller.focus_source = focus
	f.world.add_child(controller)
	_expect(not controller.submit_slot(0) and focus.get_reserved_focus() == 0.0, "missing round source fails closed")
	controller.set_round_source(Callable(self, "_peek"), Callable(self, "_acquire"))
	var accepted: Array[SkillCommandRequest] = []
	var charged: Array[float] = []
	controller.command_accepted.connect(func(request): accepted.append(request))
	controller.command_released.connect(func(_id, fee): charged.append(fee))
	var released_roots: Array[int] = []
	f.host.skill_released.connect(func(ctx):
		if ctx.command_request != null: released_roots.append(ctx.command_request.request_id))
	for i in range(100): controller.get_slot_status(0)
	_expect(focus.get_current_focus() == 100.0 and focus.get_reserved_focus() == 0.0, "UI quote is non-mutating")
	_expect(controller.submit_slot(0), "first root accepted")
	_expect(focus.get_reserved_focus() == 20.0, "first reservation exact")
	f.host.advance_pending_command(f.enemy, 0.0)
	_expect(controller.submit_slot(0), "one next pending accepted after action starts")
	_expect(focus.get_reserved_focus() == 50.0, "pending successor upper bound thirty")
	f.host.cancel_command(accepted[0].request_id, &"test_failed_predecessor")
	f.host.advance_pending_command(f.enemy, 0.0)
	f.animation.release_action()
	_expect(charged == [20.0] and focus.get_current_focus() == 80.0 and focus.get_reserved_focus() == 0.0, "failed predecessor reduces final cost to20 and releases surplus10")
	f.animation.finish_action()
	_expect(controller.get_slot_status(0).estimated_cost == 30.0, "successful release counts repeat even before hit")
	# 接受后的同步Effect失败仍收费并计重复，未释放失败才退款。
	f.combo.delivery = InstantTargetDeliveryConfig.new()
	var failure_effect = FailingEffect.new()
	f.combo.add_child(failure_effect)
	_expect(controller.submit_slot(0), "instant root accepted")
	f.host.advance_pending_command(f.enemy, 0.0)
	f.animation.release_action()
	_expect(charged == [20.0, 30.0] and focus.get_current_focus() == 50.0, "accepted Instant effect failure never refunds")
	f.animation.finish_action()
	failure_effect.free()
	var false_projectile = DELIVERY_FIXTURES.FalseLaunchProjectile.new()
	var false_scene = PackedScene.new()
	false_scene.pack(false_projectile)
	false_projectile.free()
	var false_tracking = TrackingProjectileDeliveryConfig.new()
	false_tracking.projectile_scene = false_scene
	f.combo.delivery = false_tracking
	_expect(controller.submit_slot(0), "failed-launch probe accepted for animation")
	f.host.advance_pending_command(f.enemy, 0.0)
	f.animation.release_action()
	_expect(charged == [20.0, 30.0] and focus.get_current_focus() == 50.0 and focus.get_reserved_focus() == 0.0, "Tracking launch rejected before acceptance refunds without repeat")
	var area_scene = PackedScene.new()
	var area = FailingArea.new()
	area_scene.pack(area)
	area.free()
	var ground = GroundAreaDeliveryConfig.new()
	ground.area_scene = area_scene
	f.combo.delivery = ground
	_expect(controller.submit_slot(0), "GroundArea root accepted")
	f.host.advance_pending_command(f.enemy, 0.0)
	f.animation.release_action()
	_expect(charged == [20.0, 30.0, 40.0] and focus.get_current_focus() == 10.0, "accepted GroundArea launch failure stays charged")
	f.animation.finish_action()
	focus.reset_focus()
	f.combo.delivery = InstantTargetDeliveryConfig.new()
	# 其他资源提交意外重置Focus，最终释放授权必须检查本请求实际承诺是否仍存在。
	var reset_cost = ResetFocusCost.new()
	reset_cost.focus = focus
	f.combo.add_child(reset_cost)
	var health_before_reset = f.enemy.get_current_health()
	_expect(controller.submit_slot(0), "reset-resource probe reserved")
	f.host.advance_pending_command(f.enemy, 0.0)
	f.animation.release_action()
	_expect(charged == [20.0, 30.0, 40.0] and focus.get_reserved_focus() == 0.0 and released_roots.size() == 3 and f.enemy.get_current_health() == health_before_reset, "lost own reservation cannot produce free accepted delivery")
	reset_cost.free()
	# acquire后余额改变造成受理失败，未开窗轮次所有者仍得到0活请求通知。
	round_id += 1
	var activity: Array[Array] = []
	controller.request_activity_changed.connect(func(id, count): activity.append([id, count]))
	controller.set_round_source(Callable(self, "_peek"), Callable(self, "_drain_on_acquire").bind(focus))
	focus.reset_focus()
	_expect(not controller.submit_slot(0), "balance changed on acquire rejects request")
	_expect(activity.has([round_id, 0]) and focus.get_reserved_focus() == 0.0, "empty acquired batch notified and no reservation retained")
	f.world.free()
	await process_frame
	await _verify_four_actor_reservations(path)
	await _verify_reentrant_admission(path)
	_finish()

func _verify_four_actor_reservations(path: String) -> void:
	var f = FIXTURE.make_fixture(root, "res://UnitSystem/AI/Ally/Units/Caster.tscn", false)
	var actors: Array[AllyBase] = [f.actor]
	for i in range(3):
		var actor = load("res://UnitSystem/AI/Ally/Units/Caster.tscn").instantiate() as AllyBase
		actor.automatic_skill_cast_enabled = false
		actor.position = Vector3(-i - 1, 0, 0)
		f.world.add_child(actor)
		actor.set_physics_process(false)
		var host = actor.get_node("SkillHost") as SkillHostComponent
		host.configure_owner(actor, f.world)
		var combo = load("res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn").instantiate() as SkillBase
		combo.skill_id = &"test_chain"
		combo.add_child(ComboFocusCost.new())
		host.get_node("SkillSocket").add_child(combo)
		host.register_skill(combo)
		host.combo_skill = combo
		actor.get_targeting_component().call("_set_locked_target", f.enemy)
		actor.get_targeting_component().set_physics_process(false)
		actors.append(actor)
	await physics_frame
	await physics_frame
	var focus = SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 100.0
	f.world.add_child(focus)
	var party: Array[UnitBase] = [f.player]
	party.append_array(actors)
	focus.bind_scope(f.world, party)
	var controller = load(path).new()
	controller.companions = actors
	controller.focus_source = focus
	f.world.add_child(controller)
	controller.set_round_source(Callable(self, "_peek"), Callable(self, "_acquire"))
	for index in range(4): _expect(controller.submit_slot(index), "four actors reserve independently")
	_expect(focus.get_reserved_focus() == 80.0 and focus.get_available_focus() == 20.0, "four reservations bounded by common pool")
	_expect(not controller.submit_slot(0) and focus.get_reserved_focus() == 80.0, "full actor cache rejected without extra promise")
	focus.unbind_scope()
	_expect(focus.get_reserved_focus() == 0.0, "unbind clears all unused reservations")
	for actor in actors: _expect(not actor.get_node("SkillHost").has_pending_command(), "unbind clears each host pending")
	f.world.free()
	await process_frame

func _verify_reentrant_admission(path: String) -> void:
	for mode in range(4):
		var f = FIXTURE.make_fixture(root, "res://UnitSystem/AI/Ally/Units/Caster.tscn", false)
		await physics_frame
		await physics_frame
		var focus = SquadFocusComponent.new()
		focus.auto_bind_parent = false
		focus.initial_focus = 100.0
		f.world.add_child(focus)
		var party: Array[UnitBase] = [f.player, f.actor]
		focus.bind_scope(f.world, party)
		var controller = load(path).new()
		var slots: Array[AllyBase] = [f.actor, null, null, null]
		controller.companions = slots
		controller.focus_source = focus
		f.world.add_child(controller)
		controller.set_round_source(Callable(self, "_peek"), Callable(self, "_acquire"))
		var accepted: Array[int] = []
		controller.command_accepted.connect(func(request): accepted.append(request.request_id))
		var once: Array[bool] = [false]
		if mode < 2:
			focus.focus_changed.connect(func(_total, reserved, _available):
				if reserved <= 0.0 or once[0]: return
				once[0] = true
				if mode == 0: focus.reset_focus()
				else:
					focus.unbind_scope()
					focus.bind_scope(f.world, party))
		elif mode == 2:
			controller.set_round_source(Callable(self, "_peek"), Callable(self, "_rebind_on_acquire").bind(focus, f.world, party))
		else:
			f.host.command_state_changed.connect(func(): controller.set_input_enabled(false))
		var submitted: bool = controller.submit_slot(0)
		if mode < 3:
			_expect(not submitted, "reentrant reserve/reset/rebind/acquire cannot admit old session mode%d" % mode)
			_expect(accepted.is_empty() and not f.host.has_pending_command() and focus.get_reserved_focus() == 0.0 and controller.get("_records").is_empty(), "invalidated admission leaves no accepted request/promise mode%d" % mode)
		else:
			_expect(submitted and accepted.size() == 1 and f.host.has_pending_command() and focus.get_reserved_focus() == 20.0, "input disable after successful Host admission must not falsely reject or cancel owned pending")
		focus.unbind_scope()
		f.world.free()
		await process_frame

func _rebind_on_acquire(focus: SquadFocusComponent, world: Node, party: Array[UnitBase]) -> int:
	focus.unbind_scope()
	focus.bind_scope(world, party)
	return round_id

func _peek() -> int: return round_id
func _acquire() -> int: return round_id
func _drain_on_acquire(focus: SquadFocusComponent) -> int:
	focus.initial_focus = 0.0
	focus.reset_focus()
	return round_id
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _finish() -> void:
	for message in failures: push_error(message)
	if failures.is_empty(): print("SquadChainCommandTransactionsTest: PASS")
	quit(0 if failures.is_empty() else 1)
