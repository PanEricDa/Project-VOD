extends SceneTree
## 真实帧/单调时钟验证暂停所有权；观察节点常开，战斗探针必须PAUSABLE。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	if not ResourceLoader.exists("res://GameFlow/Pause/GamePauseCoordinator.gd"):
		_expect(false, "pause coordinator must provide finite scoped ownership")
		_finish()
		return
	await _test_duration_boundaries()
	await _test_same_frame_merge()
	await _test_normal_physics_gate()
	await _test_pause_ownership_and_exit()
	await _test_scope_and_duplicate_manager()
	_finish()
func _make() -> Dictionary:
	var world := Node.new()
	root.add_child(world)
	var manager = load("res://GameFlow/Pause/GamePauseCoordinator.gd").new()
	world.add_child(manager)
	manager.bind_scope(world)
	var owner := Node.new()
	world.add_child(owner)
	return {"world":world,"manager":manager,"owner":owner}
func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds*1000000.0)
	while Time.get_ticks_usec() < deadline: await process_frame
func _test_duration_boundaries() -> void:
	var f = _make()
	for value in [0.0,-1.0,NAN,INF,0.31]:
		_expect(f.manager.request_release_accent(10,value,f.owner) == 0 and not paused, "invalid/zero duration cannot pause")
	var token: int = f.manager.request_release_accent(11,0.15,f.owner)
	_expect(token > 0 and paused and f.manager.is_release_accent_only(), "accent pauses immediately")
	var started := Time.get_ticks_usec()
	await _wait(0.05)
	_expect(paused, "accent lasts beyond first 0.05 real seconds")
	await _wait(0.16)
	_expect(not paused and not f.manager.has_release_accent(), "accent restores within bounded real interval")
	print("accent sample elapsed_seconds=", float(Time.get_ticks_usec()-started)/1000000.0)
	f.world.free()
func _test_same_frame_merge() -> void:
	var f = _make()
	var start := Time.get_ticks_usec()
	f.manager.request_release_accent(21,0.1,f.owner)
	f.manager.request_release_accent(22,0.2,f.owner)
	await _wait(0.11)
	f.manager.request_release_accent(21,0.3,f.owner)
	f.manager.request_release_accent(23,0.3,f.owner)
	await _wait(0.12)
	_expect(not paused, "duplicate/late notification must not renew merged interval")
	_expect(float(Time.get_ticks_usec()-start)/1000000.0 < 0.32, "same frame maximum not sum")
	f.world.free()
func _test_normal_physics_gate() -> void:
	# 真实时间经过不等价于正常物理帧已推进；未推进时再次强调必须拒绝。
	var f = _make()
	var token: int = f.manager.request_release_accent(24,0.1,f.owner)
	f.manager.release_pause(token)
	_expect(not paused and f.manager.request_release_accent(25,0.1,f.owner) == 0, "no new accent before normal physics advances")
	await physics_frame
	await process_frame
	_expect(f.manager.request_release_accent(25,0.1,f.owner) > 0 and paused, "one normal physics step reopens accent acceptance")
	f.world.free()

func _test_pause_ownership_and_exit() -> void:
	var f = _make()
	f.manager.request_release_accent(31,0.08,f.owner)
	var token: int = f.manager.acquire_pause(f.owner,&"test_menu")
	_expect(not f.manager.is_presentation_allowed() and not f.manager.is_release_accent_only(), "explicit wins accent")
	await _wait(0.12)
	_expect(paused and not f.manager.has_release_accent(), "accent expiry never releases explicit")
	f.manager.release_pause(token)
	f.manager.release_pause(token)
	_expect(not paused, "idempotent release restores own pause")
	var other := Node.new()
	f.world.add_child(other)
	f.manager.acquire_pause(other,&"deleted_owner")
	other.free()
	await process_frame
	await process_frame
	_expect(not paused, "deleted owner cannot leak token")
	f.manager.acquire_pause(f.owner,&"world_exit")
	f.world.free()
	await process_frame
	await process_frame
	_expect(not paused, "world removal releases its pause")
	paused = true
	f = _make()
	f.manager.request_release_accent(32,0.04,f.owner)
	await _wait(0.07)
	_expect(paused and not f.manager.is_presentation_allowed(), "external baseline cannot be unpaused")
	f.world.free()
	_expect(paused, "unbinding preserves external baseline")
	paused = false
func _test_scope_and_duplicate_manager() -> void:
	var f = _make()
	var other = load("res://GameFlow/Pause/GamePauseCoordinator.gd").new()
	f.world.add_child(other)
	_expect(not other.bind_scope(f.world), "one coordinator per SceneTree")
	var alien := Node.new()
	root.add_child(alien)
	_expect(f.manager.acquire_pause(alien,&"cross_world") == 0, "cross-world owner rejected")
	alien.free()
	f.world.free()
func _finish() -> void:
	paused = false
	for message in failures: push_error(message)
	if failures.is_empty(): print("GamePauseCoordinatorTest: PASS")
	quit(0 if failures.is_empty() else 1)
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)