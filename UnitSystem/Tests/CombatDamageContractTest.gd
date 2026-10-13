extends SceneTree
## 数据契约：漏传归属、共享可变命中或重复消费都会让本测试失败。
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred(&"_run")
func _run() -> void:
	var cp = "res://UnitSystem/Combat/CombatDamageContext.gd"
	var ep = "res://UnitSystem/Combat/CombatDamageEvent.gd"
	if not ResourceLoader.exists(cp) or not ResourceLoader.exists(ep):
		failures.append("required damage contracts are missing")
		_finish()
		return
	var C = load(cp)
	var E = load(ep)
	var world = Node3D.new()
	root.add_child(world)
	var source = UnitBase.new()
	source.team_id = 1
	world.add_child(source)
	var target = UnitBase.new()
	target.team_id = 2
	world.add_child(target)
	var normal = C.create(source, world)
	_expect(normal.focus_yield_multiplier == 1.0, "normal damage yields focus")
	for origin in [0, 2, 3]:
		_expect(C.create(source, world, origin).focus_yield_multiplier == 0.0, "non-normal has zero yield")
	var parent = C.create(source, world, 2, 11, 22, &"arrow")
	var child = parent.for_hit(C.allocate_id())
	_expect(child.request_id == 11 and child.round_id == 22 and child.hit_id > 0 and parent.hit_id == 0, "independent hit preserves provenance")
	var event = E.create(child, target, 10.0, 3.0)
	var other = E.create(child, target, 3.0, 1.0)
	_expect(event.actual_damage == 7.0 and event.event_id != other.event_id and event.hit_id == other.hit_id, "actual transactions distinct within same hit")
	_expect(event.claim(&"focus") and not event.claim(&"focus") and event.claim(&"score"), "consumer-local exactly once")
	_expect(not event.claim(&""), "empty consumer rejected")
	_expect(E.create(child, target, 1.0, 1.0) == null and E.create(child, target, INF, 0.0) == null, "invalid or zero damage rejected")
	var sid = source.get_instance_id()
	source.free()
	target.free()
	_expect(event.source_instance_id == sid and event.target_team_id == 2 and event.actual_damage == 7.0, "snapshots survive node disposal")
	world.free()
	_finish()
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for f in failures: push_error(f)
	if failures.is_empty(): print("CombatDamageContractTest: PASS")
	quit(0 if failures.is_empty() else 1)
