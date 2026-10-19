extends SceneTree
## 真实伤害驱动的动态伤害间隔：达标前不变、100—150分陡降、下限、快照及原闭窗规则。
const W = preload("res://UnitSystem/Tests/SquadChainRoundWindowTest.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	await _test_curve_from_real_scores()
	await _test_refresh_pause_and_late_damage()
	await _test_configuration_snapshot_and_short_base()
	await _test_invalid_configuration()
	_finish()
func _fixture(target_score: float) -> Dictionary:
	var f := W.make_fixture(root)
	f.round.damage_interval_seconds = 2.5
	f.round.set("minimum_damage_interval_seconds",0.8)
	f.round.set("minimum_interval_score",150.0)
	# 单次100真实伤害，H0=1/D0=100时原曲线为40+60；仅用原难度参数生成给定评分。
	f.round.hit_score_scale = 1
	f.round.damage_score_scale = 100.0
	f.round.score_difficulty = 500.0/target_score
	return f
func _test_curve_from_real_scores() -> void:
	# 字面期望来自独立计算的归一化指数曲线，不调用被测计算函数生成期望。
	for row: Array in [[99.0,2.5],[100.0,2.5],[100.01,2.498926897],[110.0,1.692791223],[120.0,1.249785653],[125.0,1.110123390],[130.0,1.006659042],[140.0,0.873228328],[150.0,0.8],[500.0,0.8]]:
		var f := _fixture(row[0])
		await physics_frame
		var qualified: Array = []
		f.round.finisher_qualified.connect(func(result): qualified.append(result))
		var request := W.start_released(f)
		W.deal(f,request,100)
		var status: Dictionary = f.round.get_round_status()
		_expect(absf(status.score-row[0]) < 0.00001,"actual score "+str(row[0]))
		_expect(absf(status.interval_seconds-row[1]) < 0.00001 and absf(status.remaining_seconds-row[1]) < 0.00001,"damage sets correct adaptive deadline "+str(row))
		_expect(qualified.is_empty(),"reaching score alone never opens selection")
		W.advance(f,row[1]-0.00001)
		_expect(f.round.peek_current_round() == request.round_id,"window not closed early "+str(row))
		W.advance(f,0.00002)
		_expect(f.round.peek_current_round() == 0 and qualified.size() == (1 if row[0]>=100.0 else 0),"adaptive deadline closes and qualifies exactly once "+str(row))
		f.world.free()
		await process_frame
func _test_refresh_pause_and_late_damage() -> void:
	var f := _fixture(150)
	await physics_frame
	var request := W.start_released(f)
	var events: Array = []
	f.enemy.damage_resolved.connect(func(event): events.append(event))
	W.deal(f,request,100)
	W.advance(f,0.3)
	var before: Dictionary = f.round.get_round_status()
	f.enemy.damage_resolved.emit(events[0])
	_expect(f.round.get_round_status() == before,"duplicate damage neither scores nor refreshes shortened interval")
	paused = true
	await create_timer(0.03,true,false,true).timeout
	_expect(f.round.get_round_status() == before,"true pause does not advance adaptive countdown")
	paused = false
	# 恰好0.8秒仍可命中；更高分只刷新下限，不把窗口缩到0。
	W.advance(f,0.5,false)
	W.deal(f,request,1)
	var status: Dictionary = f.round.get_round_status()
	_expect(status.hit_count == 2 and is_equal_approx(status.remaining_seconds,0.8),"damage at exact adaptive deadline refreshes floor")
	var finished: Array = []
	f.round.round_finished.connect(func(result): finished.append(result))
	W.advance(f,0.800001)
	var last: Dictionary = f.round.get_round_status().last_result
	W.deal(f,request,50)
	_expect(finished.size() == 1 and f.round.get_round_status().last_result == last,"late damage cannot reopen closed window or change result")
	f.world.free()
	await process_frame
func _test_configuration_snapshot_and_short_base() -> void:
	var f := _fixture(150)
	await physics_frame
	var request := W.start_released(f)
	f.round.damage_interval_seconds = 4.0
	f.round.set("minimum_damage_interval_seconds",1.0)
	f.round.set("minimum_interval_score",200.0)
	W.deal(f,request,100)
	_expect(is_equal_approx(f.round.get_round_status().remaining_seconds,0.8),"active request uses admitted curve snapshot")
	W.advance(f,0.800001)
	f.animation.finish_action()
	request = W.start_released(f)
	W.deal(f,request,100)
	_expect(absf(f.round.get_round_status().remaining_seconds-1.5472765714) < 0.00001,"next round captures updated base floor and score endpoint")
	f.world.free()
	await process_frame
	f = _fixture(500)
	f.round.damage_interval_seconds = 0.1
	await physics_frame
	request = W.start_released(f)
	W.deal(f,request,100)
	_expect(is_equal_approx(f.round.get_round_status().remaining_seconds,0.1),"minimum cannot lengthen a shorter custom base interval")
	f.world.free()
	await process_frame
func _test_invalid_configuration() -> void:
	for row: Array in [["minimum_damage_interval_seconds",0.0],["minimum_damage_interval_seconds",NAN],["minimum_damage_interval_seconds",INF],["minimum_interval_score",100.0],["minimum_interval_score",NAN],["minimum_interval_score",INF]]:
		var f := _fixture(150)
		await physics_frame
		f.round.set(row[0],row[1])
		_expect(f.round.acquire_round() == 0,"invalid adaptive configuration refuses new round "+str(row))
		_expect(is_zero_approx(f.focus.get_reserved_focus()),"invalid curve never reserves focus")
		f.world.free()
		await process_frame
func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message: String in failures: printerr("FAIL: ",message)
	print("SquadChainAdaptiveWindowTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
