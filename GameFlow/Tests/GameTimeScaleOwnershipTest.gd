extends SceneTree
## 捕捉慢速覆盖他人暂停、倍率累乘、非1基线错误恢复及弱持有泄漏。
var failures: Array[String] = []
var _baseline: float = 1.0

func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	_baseline = Engine.time_scale
	var probe := GamePauseCoordinator.new()
	if not probe.has_method("acquire_time_scale"):
		_expect(false,"missing scoped time-scale ownership interface")
		probe.free()
		_finish()
		return
	probe.free()
	await _test_scale_ownership_and_baseline()
	await _test_invalid_owner_or_scale()
	await _test_pause_accent_and_scale_independence()
	await _test_owner_free_unbind_scope_exit()
	_finish()

func _make() -> Dictionary:
	var world := Node.new()
	root.add_child(world)
	var manager := GamePauseCoordinator.new()
	world.add_child(manager)
	manager.bind_scope(world)
	var owner := Node.new()
	world.add_child(owner)
	return {"world":world,"manager":manager,"owner":owner}

func _test_scale_ownership_and_baseline() -> void:
	Engine.time_scale = 0.7
	var f := _make()
	var other := Node.new()
	f.world.add_child(other)
	var a: int = f.manager.acquire_time_scale(f.owner,0.05,&"selection")
	_expect(a > 0 and is_equal_approx(Engine.time_scale,0.05) and not paused,"slow does not pause simulation")
	var b: int = f.manager.acquire_time_scale(other,0.02,&"other")
	_expect(is_equal_approx(Engine.time_scale,0.02),"slow caps do not multiply")
	f.manager.release_time_scale(a)
	_expect(is_equal_approx(Engine.time_scale,0.02),"other owner remains")
	f.manager.release_time_scale(b)
	f.manager.release_time_scale(b)
	_expect(is_equal_approx(Engine.time_scale,0.7),"restore non1 baseline idempotently")
	f.world.free()
	Engine.time_scale = 0.02
	f = _make()
	a = f.manager.acquire_time_scale(f.owner,0.05,&"selection")
	_expect(is_equal_approx(Engine.time_scale,0.02),"never accelerate slower baseline")
	f.manager.release_time_scale(a)
	f.world.free()
	Engine.time_scale = 1.0
	await process_frame

func _test_invalid_owner_or_scale() -> void:
	var f := _make()
	for value: float in [0.0,-1.0,NAN,INF,1.1]:
		_expect(f.manager.acquire_time_scale(f.owner,value,&"invalid") == 0,"invalid scale rejected")
	var alien := Node.new()
	root.add_child(alien)
	_expect(f.manager.acquire_time_scale(alien,0.05,&"alien") == 0,"cross-world rejected")
	alien.free()
	_expect(is_equal_approx(Engine.time_scale,1.0),"invalid requests do not write time")
	f.world.free()
	await process_frame

func _test_pause_accent_and_scale_independence() -> void:
	var f := _make()
	var slow: int = f.manager.acquire_time_scale(f.owner,0.05,&"selection")
	var menu: int = f.manager.acquire_pause(f.owner,&"menu")
	f.manager.release_time_scale(slow)
	_expect(paused and not f.manager.is_presentation_allowed(),"slow release cannot unpause menu")
	f.manager.release_pause(menu)
	slow = f.manager.acquire_time_scale(f.owner,0.05,&"selection")
	f.manager.request_release_accent(333,0.075,f.owner)
	await _wait(0.13)
	_expect(not paused and is_equal_approx(Engine.time_scale,0.05),"accent expires in real seconds without clearing slow")
	f.manager.release_time_scale(slow)
	f.world.free()
	await process_frame

func _test_owner_free_unbind_scope_exit() -> void:
	for mode: String in ["owner","unbind","manager","world"]:
		Engine.time_scale = 0.8
		var f := _make()
		f.manager.acquire_time_scale(f.owner,0.05,&"selection")
		match mode:
			"owner": f.owner.free()
			"unbind": f.manager.bind_scope(null)
			"manager": f.manager.free()
			"world": f.world.free()
		await process_frame
		await process_frame
		_expect(is_equal_approx(Engine.time_scale,0.8),"cleanup restores baseline: "+mode)
		if is_instance_valid(f.world): f.world.free()
	Engine.time_scale = 1.0

func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_usec()+int(seconds*1000000)
	while Time.get_ticks_usec() < deadline: await process_frame
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _finish() -> void:
	Engine.time_scale = _baseline
	paused = false
	for label: String in failures: push_error(label)
	if failures.is_empty(): print("GameTimeScaleOwnershipTest: PASS")
	quit(0 if failures.is_empty() else 1)
