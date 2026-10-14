extends SceneTree
## 根动作、在途交付、零CD触发子技能与重载回收的真实集成/压力测试。
const FIXTURE = preload("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd")
const DELIVERY_FIXTURES = preload("res://SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd")
var failures: Array[String] = []
var _last_request: SkillCommandRequest
var _lifetime_ids: Array[int] = []
var _child_snapshots: Array[Array] = []
var _watch_scope: Node

func _initialize() -> void: call_deferred(&"_run")

func _setup() -> Dictionary:
	var f = FIXTURE.make_fixture(root, "res://UnitSystem/AI/Ally/Units/Caster.tscn", false)
	var focus = SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 100.0
	f.world.add_child(focus)
	var party: Array[UnitBase] = [f.player, f.actor]
	focus.bind_scope(f.world, party)
	var controller = SquadChainCommandController.new()
	var slots: Array[AllyBase] = [f.actor, null, null, null]
	controller.companions = slots
	controller.focus_source = focus
	f.world.add_child(controller)
	controller.set_round_source(Callable(self, "_round"), Callable(self, "_round"))
	controller.command_accepted.connect(_capture)
	controller.command_lifetime_finished.connect(func(id, _batch): _lifetime_ids.append(id))
	f.focus = focus
	f.controller = controller
	return f

func _run() -> void:
	var f = _setup()
	await physics_frame
	await physics_frame
	f.combo.delivery.projectile_speed = 0.1
	f.controller.submit_slot(0)
	var first_id = _last_request.request_id
	f.host.advance_pending_command(f.enemy, 0.0)
	f.animation.release_action()
	f.animation.finish_action()
	_expect(_lifetime_ids.is_empty(), "actor finish cannot collect flying root")
	f.controller.submit_slot(0)
	var next_id = _last_request.request_id
	f.host.advance_pending_command(f.enemy, 0.0)
	f.combo.get_node("DeliveryRunner").cancel(&"old_miss")
	_expect(_lifetime_ids == [first_id] and f.host.get_active_command_id() == next_id, "old delivery completes own lifetime without clearing new action")
	_expect(f.focus.get_current_focus() == 80.0, "released miss remains charged")
	f.host.cancel_command(next_id, &"test_stop")
	f.world.free()
	_last_request = null
	await process_frame
	_lifetime_ids.clear()
	await _verify_children()
	await _verify_reload_and_transactions()
	for message in failures: push_error(message)
	if failures.is_empty(): print("SquadChainCommandLifecycleTest: PASS")
	quit(0 if failures.is_empty() else 1)

func _verify_children() -> void:
	var f = _setup()
	var arrow = load("res://SkillSystem/00-Skills/ExplosiveArrow/ExplosiveArrowSkill.tscn").instantiate() as SkillBase
	arrow.skill_id = &"chain_child_probe"
	arrow.skill_cooldown = 0.0
	arrow.base_cast_time = 0.2
	arrow.add_child(ComboFocusCost.new())
	f.host.get_node("SkillSocket").add_child(arrow)
	f.host.register_skill(arrow)
	f.host.combo_skill = arrow
	var fragment = load("res://SkillSystem/00-Skills/Trig_ExplosiveFragment/ExplosiveFragmentSkill.tscn").instantiate() as SkillBase
	var projectile_scene = PackedScene.new()
	var fake = DELIVERY_FIXTURES.FakeProjectile.new()
	projectile_scene.pack(fake)
	fake.free()
	var tracking = TrackingProjectileDeliveryConfig.new()
	tracking.projectile_scene = projectile_scene
	fragment.delivery = tracking
	var child_scene = PackedScene.new()
	child_scene.pack(fragment)
	fragment.free()
	arrow.get_node("TriggerFragments").child_skill_scene = child_scene
	for index in range(2):
		var enemy = load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
		enemy.team_id = 2
		enemy.collision_layer = 4
		enemy.position = Vector3(2, 0, index + 1)
		f.world.add_child(enemy)
		enemy.set_physics_process(false)
	_watch_scope = f.world
	_child_snapshots.clear()
	node_added.connect(_observe_child)
	await physics_frame
	await physics_frame
	await physics_frame
	f.controller.submit_slot(0)
	var root_id = _last_request.request_id
	f.host.advance_pending_command(f.enemy, 0.0)
	f.animation.release_action()
	f.animation.finish_action()
	for frame in range(90):
		await physics_frame
		if not _child_snapshots.is_empty(): break
	_expect(_child_snapshots.size() == 2, "real positive arrow hit spawns two nearby child skills")
	for snapshot in _child_snapshots:
		_expect(snapshot == [root_id, 10000, 0, 0.0], "child shares root identity, regular purpose and zero focus yield")
	_expect(_lifetime_ids.is_empty(), "root arrow completed but child flights retain request lifetime")
	for node in f.world.get_children():
		if node is DELIVERY_FIXTURES.FakeProjectile: node.queue_free()
	await process_frame
	await process_frame
	_expect(_lifetime_ids == [root_id], "zero CD child misses finish exactly one root lifetime")
	_expect(f.world.get_children().filter(func(node): return node is SkillBase).is_empty(), "failed direct children reclaimed even after skill READY")
	_expect(f.focus.get_current_focus() == 80.0, "descendants never pay or restore root fee")
	node_added.disconnect(_observe_child)
	_watch_scope = null
	f.world.free()
	_last_request = null
	_lifetime_ids.clear()
	await process_frame

func _observe_child(node: Node) -> void:
	if node is SkillBase and is_instance_valid(_watch_scope) and node.get_parent() == _watch_scope:
		node.delivery_started.connect(func(ctx):
			_child_snapshots.append([ctx.damage_context.request_id, ctx.damage_context.round_id, ctx.purpose, ctx.damage_context.focus_yield_multiplier]))

func _verify_reload_and_transactions() -> void:
	for iteration in range(10):
		var f = _setup()
		f.controller.submit_slot(0)
		var request_ref = weakref(_last_request)
		var scope_ref = weakref(f.world)
		var focus_ref = weakref(f.focus)
		f.world.free()
		_last_request = null
		await process_frame
		_expect(scope_ref.get_ref() == null and focus_ref.get_ref() == null and request_ref.get_ref() == null, "reload releases old scope, pool and request")
	var f = _setup()
	f.combo.delivery = InstantTargetDeliveryConfig.new()
	f.enemy.can_die = false # 压力测试不能因测试伤害清空目标而提前结束。
	f.combo.cast_effect_scene = null
	f.combo.release_effect_scene = null
	var cost = f.combo.get_combo_focus_cost()
	cost.base_focus_cost = 0.0
	cost.repeat_focus_cost = 0.0
	for iteration in range(1000):
		_expect(f.controller.submit_slot(0), "zero cost stress admits request")
		f.host.advance_pending_command(f.enemy, 0.0)
		if iteration % 2 == 0:
			f.animation.release_action()
			f.animation.finish_action()
		else:
			f.host.cancel_command(_last_request.request_id, &"stress_failure")
		_expect(f.focus.get_reserved_focus() == 0.0 and f.controller.get("_records").is_empty(), "stress leaves no promises or root records")
	f.controller.close_round(10000)
	_expect(not f.controller.submit_slot(0), "closed round cannot reopen through input")
	f.world.free()
	_last_request = null
	await process_frame

func _round() -> int: return 10000
func _capture(request: SkillCommandRequest) -> void: _last_request = request
func _expect(ok: bool, label: String) -> void:
	if not ok and not failures.has(label): failures.append(label)
