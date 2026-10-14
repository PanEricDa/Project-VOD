extends SceneTree
## 捕捉超额预留、重复扣费退款、错误收益来源及非有限金额。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var path = "res://UnitSystem/Components/Combat/Squad/SquadFocusComponent.gd"
	if not ResourceLoader.exists(path):
		failures.append("focus component missing")
		_finish()
		return
	var world = Node3D.new()
	root.add_child(world)
	var source = UnitBase.new()
	source.team_id = 1
	world.add_child(source)
	var target = UnitBase.new()
	target.team_id = 2
	target.maximum_health = 1000.0
	world.add_child(target)
	var focus = load(path).new()
	focus.auto_bind_parent = false
	focus.initial_focus = 50.0
	world.add_child(focus)
	var party: Array[UnitBase] = [source]
	_expect(focus.bind_scope(world, party), "scope binds")
	_expect(focus.reserve(101, 30.0) and focus.reserve(101, 30.0), "same reservation idempotent")
	_expect(not focus.reserve(102, 25.0) and not focus.reserve(101, 20.0), "overspend or conflicting reserve rejected")
	_expect(focus.get_current_focus() == 50.0 and focus.get_available_focus() == 20.0, "reserve not spend")
	_expect(not focus.release_request(101), "reserved request cannot be forgotten")
	_expect(focus.commit(101, 20.0), "partial commit")
	_expect(focus.get_current_focus() == 30.0 and focus.get_reserved_focus() == 0.0, "unused reservation released")
	_expect(not focus.commit(101, 20.0) and not focus.refund(101), "terminal callbacks no side effects")
	_expect(focus.reserve(103, 10.0) and focus.refund(103) and not focus.refund(103), "refund once")
	var normal = CombatDamageContext.create(source, world)
	CombatValueResolver.apply_damage(source, target, 100.0, 0.0, 1.0, 1.0, 0.0, normal)
	_expect(is_equal_approx(focus.get_current_focus(), 40.0), "real normal damage gain")
	var captured: Array = []
	target.damage_resolved.connect(func(e): captured.append(e))
	CombatValueResolver.apply_damage(source, target, 10.0, 0.0, 1.0, 1.0, 0.0, normal)
	target.damage_resolved.emit(captured[0])
	_expect(is_equal_approx(focus.get_current_focus(), 41.0), "same event not consumed twice")
	var outsider = UnitBase.new()
	outsider.team_id = 1
	world.add_child(outsider)
	CombatValueResolver.apply_damage(outsider, target, 10.0, 0.0, 1.0, 1.0, 0.0, CombatDamageContext.create(outsider, world))
	CombatValueResolver.apply_damage(null, target, 10.0, 0.0, 1.0, 1.0, 0.0, CombatDamageContext.create(null, world))
	CombatValueResolver.apply_damage(source, outsider, 10.0, 0.0, 1.0, 1.0, 0.0, normal)
	CombatValueResolver.apply_healing(source, target, 10.0, 0.0)
	_expect(is_equal_approx(focus.get_current_focus(), 41.0), "nonparty, null, friendly and healing excluded")
	for origin in [2, 3]:
		CombatValueResolver.apply_damage(source, target, 100.0, 0.0, 1.0, 1.0, 0.0, CombatDamageContext.create(source, world, origin))
	target.apply_damage(10.0, source)
	_expect(is_equal_approx(focus.get_current_focus(), 41.0), "zero yield and unknown direct damage no gain")
	_expect(not focus.reserve(105, INF) and not focus.reserve(106, NAN) and not focus.reserve(107, -1.0), "invalid amounts rejected")
	CombatValueResolver.apply_damage(source, target, 9999.0, 0.0, 1.0, 1.0, 0.0, normal)
	_expect(focus.get_current_focus() == 100.0, "capacity clamped")
	focus.unbind_scope()
	_expect(focus.get_reserved_focus() == 0.0 and focus.get_current_focus() == 50.0, "unbind resets session")
	world.free()
	_verify_reentrant_binding()
	_finish()
func _verify_reentrant_binding() -> void:
	var old_world = Node3D.new()
	var new_world = Node3D.new()
	root.add_child(old_world)
	root.add_child(new_world)
	var old_source = UnitBase.new()
	old_source.team_id = 1
	old_world.add_child(old_source)
	var new_source = UnitBase.new()
	new_source.team_id = 1
	new_world.add_child(new_source)
	var target = UnitBase.new()
	target.team_id = 2
	new_world.add_child(target)
	var focus = SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 50.0
	root.add_child(focus)
	var old_party: Array[UnitBase] = [old_source]
	var new_party: Array[UnitBase] = [new_source]
	focus.bind_scope(old_world, old_party)
	var attempts: Array[bool] = []
	focus.scope_changed.connect(func(scope):
		if scope == null and attempts.is_empty(): attempts.append(focus.bind_scope(new_world, new_party)))
	focus.unbind_scope()
	_expect(attempts == [false] and focus.get_bound_scope() == null, "reentrant bind during unbind fails closed instead of claiming success then erasing new session")
	_expect(focus.bind_scope(new_world, new_party) and focus.is_party_member(new_source), "new binding succeeds after old cleanup finishes")
	CombatValueResolver.apply_damage(new_source, target, 10.0, 0.0, 1.0, 1.0, 0.0, CombatDamageContext.create(new_source, new_world))
	_expect(focus.get_current_focus() == 51.0, "new binding keeps damage listener")
	focus.unbind_scope()
	focus.free()
	old_world.free()
	new_world.free()

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for f in failures: push_error(f)
	if failures.is_empty(): print("SquadFocusComponentTest: PASS")
	quit(0 if failures.is_empty() else 1)
