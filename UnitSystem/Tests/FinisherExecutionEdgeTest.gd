extends SceneTree
## 独立审查定向用例：同步取消隔离、首发硬中断、长序列、驱动退出与主视觉边界。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	await _range_grace()
	await _cancel_then_restart()
	await _host_cancel_reentry()
	await _stop_on_first_shot()
	await _long_emission()
	await _driver_exit()
	await _freed_impact()
	await _long_impact()
	for message: String in failures: printerr("FAIL: ",message)
	print("FinisherExecutionEdgeTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _fixture() -> Dictionary:
	var scene := load("res://Scenes/Previews/SquadFinisherComparisonPreview.tscn").instantiate() as Node3D
	root.add_child(scene)
	for i: int in range(4): await process_frame
	var actor := scene.get_node("Battle/Caster") as AllyBase
	var host := actor.get_node("SkillHost") as SkillHostComponent
	# 测试局部改变配置，正式静态资源不写入运行状态。
	host.get_finisher_skill().delivery = host.get_finisher_skill().delivery.duplicate()
	return {"scene":scene,"actor":actor,"host":host,"skill":host.get_finisher_skill(),"execution":scene.execution_source}
func _close(f: Dictionary) -> void:
	f.execution.cancel_execution(&"test_cleanup")
	f.scene.free()
	await process_frame
# 在真实B演出中移动原锁定目标，验证容差不会放宽入场，但能保留合法前摇并安全取消超距。
func _range_grace() -> void:
	var f := await _fixture()
	var target: UnitBase = f.scene.targets[0]
	target.global_position = f.actor.global_position + Vector3(f.skill.cast_range+1.0,0,0)
	_expect(not f.execution.begin_finisher(f.actor,171018,1),"target beyond configured initial range cannot enter closeup")
	_expect(f.execution.get_execution_status().phase == &"idle" and is_equal_approx(Engine.time_scale,1.0),"out-of-range initial rejection acquires no cinematic time")
	await _close(f)
	for offset: float in [-0.1,0.2]:
		f = await _fixture()
		target = f.scene.targets[0]
		var edge: float = f.skill.cast_range+f.skill.release_range_tolerance_m
		var distance: float = edge+offset
		target.global_position = f.actor.global_position + Vector3(f.skill.cast_range-0.1,0,0)
		_expect(f.execution.begin_finisher(f.actor,171018,1),"in-range starts B grace case "+str(distance))
		await _wait(func() -> bool: return f.execution.get_execution_status().phase == &"windup",1.0)
		_expect(f.execution.get_execution_status().phase == &"windup","range case reached windup before target displacement")
		target.global_position = f.actor.global_position + Vector3(distance,0,0)
		await _wait(func() -> bool: return f.execution.get_execution_status().phase == &"idle",4.0)
		var status: Dictionary = f.execution.get_execution_status()
		_expect(status.phase == &"idle","range case completes without hanging "+str(distance))
		_expect(status.launched == (5 if offset < 0 else 0),"only in-grace B cast emits all five "+str(distance))
		_expect(is_equal_approx(Engine.time_scale,1.0) and not f.scene.get_node("Battle/CameraRig").is_cinematic_active(),"range result restores world and camera "+str(distance))
		_expect(f.scene.get_node("Battle/SquadChainCommandController").get("_input_blocks").is_empty() and not f.host.has_command_action_lock(),"range result leaves no input or action lock "+str(distance))
		await _close(f)

func _cancel_then_restart() -> void:
	var f := await _fixture()
	f.skill.delivery.shot_interval_seconds = 1.0
	_expect(f.execution.begin_finisher(f.actor,171018,0),"cancel/restart accepted")
	await _wait(func() -> bool:
		var s: Dictionary = f.execution.get_execution_status()
		return s.landed == 1 and s.main_effects_pending == 0,2.0)
	var started: Array[bool] = [false]
	var callback := func(_status: Dictionary) -> void:
		if not started[0]:
			started[0] = true
			_expect(f.execution.begin_finisher(f.actor,171018,1),"ended listener starts new root")
	f.execution.execution_ended.connect(callback)
	f.execution.cancel_execution(&"old_cancel")
	f.execution.execution_ended.disconnect(callback)
	_expect(started[0] and f.execution.get_execution_status().phase == &"pending","old cancellation cannot terminate new root")
	await _close(f)
func _host_cancel_reentry() -> void:
	var f := await _fixture()
	_expect(f.execution.begin_finisher(f.actor,171018,1),"host reentry starts")
	await _wait(func() -> bool: return f.execution.get_execution_status().phase == &"windup",1.0)
	var old: int = f.host.get_active_command_id()
	var once: Array[bool] = [false]
	var callback := func(_ctx: SkillContext,_reason: StringName) -> void:
		if not once[0]:
			once[0] = true
			_expect(f.host.request_finisher(f.scene.targets[0]),"cancelled listener starts new host action")
	f.host.finisher_action_cancelled.connect(callback)
	f.host.cancel_active_skill(&"host_old_cancel")
	f.host.finisher_action_cancelled.disconnect(callback)
	_expect(once[0] and f.host.get_active_command_id() > old and f.host.has_command_action_lock(),"old host cancellation preserves new action")
	await _close(f)
func _stop_on_first_shot() -> void:
	var f := await _fixture()
	var count: Array[int] = [0]
	f.skill.projectile_launched.connect(func(_ctx: SkillContext,_index: int,_point: Vector3) -> void:
		count[0] += 1
		if count[0] == 1: f.host.set_cast_blocked(true))
	_expect(f.execution.begin_finisher(f.actor,171018,1),"first-shot stop accepted")
	# 进退镜现在插入真暂停；等待真实首发而非假定一秒内已发射，再留出后续0.12秒间隔检查未补发。
	await _wait(func() -> bool: return count[0] >= 1,2.5)
	await create_timer(0.16,true,false,true).timeout
	_expect(count[0] == 1,"synchronous first-shot hard block stops remaining four")
	f.host.set_cast_blocked(false)
	await _close(f)
func _long_emission() -> void:
	var f := await _fixture()
	f.skill.delivery.shot_interval_seconds = 0.5
	_expect(f.execution.begin_finisher(f.actor,171018,1),"long sequence accepted")
	await _wait(func() -> bool: return f.execution.get_execution_status().phase == &"idle",5.0)
	var status: Dictionary = f.execution.get_execution_status()
	_expect(status.launched == 5 and status.landed == 5,"legal 0.5 second interval not cut by animation deadline: "+str(status))
	await _close(f)
func _driver_exit() -> void:
	var f := await _fixture()
	var driver: AIAttackController = f.actor.get_combat_system().get_attack_controller()
	var animation := f.actor.get_node("Visual/CasterVisual/CharacterAnimationPlayer") as AnimationPlayer
	var original := animation.callback_mode_process
	_expect(f.execution.begin_finisher(f.actor,171018,1),"driver exit accepted")
	await _wait(func() -> bool: return f.execution.get_execution_status().phase == &"windup",1.0)
	driver.queue_free()
	await process_frame
	await process_frame
	_expect(animation.callback_mode_process == original and not animation.has_animation_library("_skill_cinematic"),"driver exit restores surviving animation player")
	await _close(f)
func _freed_impact() -> void:
	var f := await _fixture()
	_expect(f.execution.begin_finisher(f.actor,171018,1),"freed impact accepted")
	f.skill.impact_presentation_prepared.connect(func(_ctx: SkillContext,instance: Node3D) -> void: instance.free())
	await _wait(func() -> bool: return f.execution.get_execution_status().phase == &"idle",3.0)
	_expect(f.execution.get_execution_status().phase == &"idle","pre-tree freed impacts do not hold B until watchdog")
	await _close(f)
func _long_impact() -> void:
	var f := await _fixture()
	var projectile: Node = f.skill.delivery.projectile_scene.instantiate()
	var impact: Node = projectile.impact_effect_scene.instantiate()
	var player := impact.get_node("AnimationPlayer") as AnimationPlayer
	var library := player.get_animation_library("").duplicate(true) as AnimationLibrary
	player.remove_animation_library("")
	player.add_animation_library("",library)
	library.get_animation("effect").length = 10.0
	var packed_impact := PackedScene.new()
	packed_impact.pack(impact)
	impact.free()
	projectile.impact_effect_scene = packed_impact
	var packed_projectile := PackedScene.new()
	packed_projectile.pack(projectile)
	projectile.free()
	f.skill.delivery.projectile_scene = packed_projectile
	_expect(f.execution.begin_finisher(f.actor,171018,1),"long impact accepted")
	await _wait(func() -> bool: return f.execution.get_execution_status().landed == 5,3.0)
	_expect(f.execution.get("_watchdog") >= 10.0 and f.execution.get_execution_status().phase == &"bombardment","watchdog includes legitimate main visual duration")
	var tasks: Dictionary = f.execution.get("_tasks")
	for record: Dictionary in tasks.values():
		var effect: Node = record.node.get_ref()
		if is_instance_valid(effect): effect.stop()
	await _wait(func() -> bool: return f.execution.get_execution_status().phase == &"idle",2.0)
	_expect(f.execution.get_execution_status().phase == &"idle","stopped owned effects settle")
	await _close(f)
func _wait(predicate: Callable,seconds: float) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
