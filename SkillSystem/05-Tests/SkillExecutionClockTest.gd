extends SceneTree
## 验证请求时钟共享、正常演出秒数、真暂停和普通时间回退，不依赖实际等待。
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var path := "res://SkillSystem/01-Core/SkillExecutionClock.gd"
	if not ResourceLoader.exists(path):
		failures.append("missing request execution clock")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var clock: RefCounted = load(path).new()
	clock.call("configure", world)
	Engine.time_scale = 0.05
	_expect(is_equal_approx(clock.call("get_delta", 0.05 / 60.0), 1.0 / 60.0), "presentation delta normal speed")
	_expect(is_equal_approx(clock.call("get_delta", 0.05 / 60.0), 1.0 / 60.0), "same physics frame multiple consumers do not consume time")
	var context := SkillContext.new()
	context.set("execution_clock", clock)
	var copy: SkillContext = context.duplicate_context()
	_expect(copy.get("execution_clock") == clock, "context copies share request clock")
	paused = true
	_expect(clock.call("get_delta", 0.01) == 0, "true pause freezes")
	paused = false
	clock.call("use_world_time")
	_expect(is_equal_approx(clock.call("get_delta", 0.0008333333, false), 0.0008333333), "A restores ordinary world delta")
	_expect(float(clock.call("get_presentation_delta", 0.01, false)) <= 0.1, "long stalls do not accumulate background time")
	Engine.time_scale = 1.0
	for frame: int in range(40):
		await process_frame
		clock.call("get_presentation_delta", 0.016, false)
	_expect((clock.get("_frame_scales") as Dictionary).size() <= 2, "presentation-only readers do not retain unbounded per-frame cache")
	world.free()
	_finish()
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message in failures: printerr("FAIL: ", message)
	print("SkillExecutionClockTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
