extends SceneTree
## 验证UnitBase内置请求；真实Player/AI物理消费，不由测试直接推进位移。
var failures: Array[String] = []
var units: Array[Node] = []
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame
func _body(at: Vector3):
	var body = load("res://UnitSystem/Base/AIUnitBase.gd").new()
	var movement := Node3D.new()
	movement.name = "MovementSystem"
	var nav := NavigationAgent3D.new()
	nav.name = "NavigationAgent3D"
	movement.add_child(nav)
	body.add_child(movement)
	var visual := Node3D.new()
	visual.name = "Visual"
	body.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4,1,0.4)
	shape.shape = box
	body.add_child(shape)
	body.position = at
	body.gravity_multiplier = 0.0
	body.collision_layer = 4
	body.collision_mask = 5
	root.add_child(body)
	units.append(body)
	return body
func _run() -> void:
	var probe := UnitBase.new()
	var supported := probe.has_method("request_forced_movement")
	probe.free()
	_check(supported,"UnitBase provides built-in forced movement without receiver")
	if not supported:
		_finish()
		return
	var source := UnitBase.new()
	root.add_child(source)
	units.append(source)
	var body = _body(Vector3.ZERO)
	var receiver = body
	var reasons: Array[StringName] = []
	receiver.forced_movement_finished.connect(func(_token: int, reason: StringName): reasons.append(reason))
	var token: int = receiver.call("request_forced_movement",source,Vector3(3,0,0),0.35)
	_check(token>0,"valid request is accepted")
	await _frames(23)
	_check(body.position.distance_to(Vector3(3,0,0))<0.08,"open-ground displacement reaches 3m through real physics in 0.35s")
	_check(not receiver.call("is_forced_movement_active") and body.velocity.length()<0.01,"arrival clears active request and residual velocity")
	# 无效替换/旧取消/回调重入不能删除新身份。
	token = receiver.call("request_forced_movement",source,Vector3(4,0,0),1.0)
	_check(receiver.call("request_forced_movement",source,Vector3.INF,0.35)==0 and receiver.call("get_forced_movement_token")==token,"invalid replacement preserves existing request")
	var second: int = receiver.call("request_forced_movement",source,Vector3(5,0,0),0.35)
	receiver.call("cancel_forced_movement",token)
	_check(receiver.call("get_forced_movement_token")==second and reasons.has(&"replaced"),"old cancel cannot erase accepted replacement")
	var reentered := [0]
	receiver.forced_movement_finished.connect(func(_old: int, reason: StringName):
		if reason==&"cancelled" and reentered[0]==0:
			reentered[0]=receiver.call("request_forced_movement",source,Vector3(6,0,0),0.35)
	)
	receiver.call("cancel_forced_movement",second)
	_check(reentered[0]>0 and receiver.call("get_forced_movement_token")==reentered[0],"terminal callback can start a new request without being cleared")
	await _frames(23)
	_check(absf(body.position.x-6.0)<0.08,"reentrant request actually moves")
	# 替换通知重入：外层较早接受的请求不得覆盖通知里更晚提交的请求。
	var replace_body = _body(Vector3(0,0,12))
	var replace_receiver = replace_body
	var replacement := [0]
	var initial_token: int = replace_receiver.call("request_forced_movement",source,Vector3(1,0,12),0.35)
	replace_receiver.forced_movement_finished.connect(func(old: int, reason: StringName):
		if old==initial_token and reason==&"replaced":
			replacement[0] = replace_receiver.call("request_forced_movement",source,Vector3(-2,0,12),0.35)
	)
	var outer_token: int = replace_receiver.call("request_forced_movement",source,Vector3(2,0,12),0.35)
	replace_receiver.call("cancel_forced_movement",outer_token)
	_check(replacement[0]>outer_token and replace_receiver.call("get_forced_movement_token")==replacement[0],"replacement callback's newer request survives outer return/old cancellation")
	await _frames(23)
	_check(absf(replace_body.position.x+2.0)<0.08,"newest reentrant replacement determines actual motion")
	# 外力只覆盖XZ，不能把Y吸到技能目的地，也不能停止正常重力。
	var falling = _body(Vector3(0,4,20))
	falling.gravity_multiplier = 1.0
	falling.call("request_forced_movement",source,Vector3(2,99,20),0.35)
	await _frames(23)
	_check(absf(falling.position.x-2.0)<0.08 and falling.position.y<3.8 and falling.position.y>2.5,"horizontal forced movement preserves gravity instead of snapping destination Y")
	# 墙体/身体只截断，不在撤掉障碍后补位。
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2,4,4)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	wall.position = Vector3(7,0,0)
	root.add_child(wall)
	await _frames(2)
	receiver.call("request_forced_movement",source,Vector3(9,0,0),0.35)
	await _frames(23)
	_check(body.position.x<6.75 and reasons.back()==&"blocked","wall blocks forced displacement")
	var stopped: Vector3 = body.position
	wall.queue_free()
	await _frames(25)
	_check(body.position.distance_to(stopped)<0.01,"no catchup after removing wall")
	var blocker = _body(Vector3(8,0,0))
	await _frames(2)
	receiver.call("request_forced_movement",source,Vector3(10,0,0),0.35)
	await _frames(23)
	_check(body.position.x<7.65 and blocker.position.x>7.99,"other AI body blocks instead of being penetrated")
	await _test_unit_overlap_collision_lifecycle(source)
	# 暂停、慢放及受击锁：只消费实际物理战斗时间。
	var timed = _body(Vector3(0,0,5))
	var timed_receiver = timed
	timed_receiver.call("request_forced_movement",source,Vector3(3,0,5),0.35)
	paused = true
	await create_timer(0.08,true,false,true).timeout
	_check(timed.position.distance_to(Vector3(0,0,5))<0.01,"pause consumes no forced movement")
	paused = false
	Engine.time_scale = 0.05
	await _frames(12)
	_check(timed.position.x>0.02 and timed.position.x<0.15 and timed_receiver.call("is_forced_movement_active"),"5% time advances only 5% displacement, without double scaling")
	Engine.time_scale = 1.0
	timed.set("_hit_movement_lock_remaining",0.1)
	var before: Vector3 = timed.position
	await _frames(4)
	_check(timed.position.distance_to(before)<0.01,"hit movement lock freezes consumption")
	await _frames(30)
	_check(absf(timed.position.x-3.0)<0.08,"hit lock resumes without lost/catchup slices")
	# 被覆盖的攻击/冲刺/动画推进不得在结束后突然恢复。
	var motion_source := Node.new()
	root.add_child(motion_source)
	timed.request_dash(Vector3(10,0,5))
	timed.submit_skill_motion_step(motion_source,0,1,Vector3(4,0,0),false)
	timed_receiver.call("request_forced_movement",source,Vector3(4,0,5),0.1)
	await _frames(8)
	before = timed.position
	await _frames(10)
	_check(timed.position.distance_to(before)<0.01 and not timed.is_dashing(),"overwritten dash/animation slices never resume after pull")
	timed.cancel_skill_motion(motion_source,0,1)
	motion_source.queue_free()
	# 离树终态在节点退出时清理；重加不恢复旧请求。
	replace_receiver.call("request_forced_movement",source,Vector3(8,0,12),0.35)
	root.remove_child(replace_body)
	_check(not replace_receiver.call("is_forced_movement_active"),"owner leaving tree immediately terminates request")
	root.add_child(replace_body)
	await _frames(2)
	_check(absf(replace_body.position.x+2.0)<0.08,"reentered owner cannot revive old movement")
	# 生命周期和无接收能力父节点。
	timed_receiver.call("request_forced_movement",source,Vector3(8,0,5),0.35)
	root.remove_child(source)
	await _frames(2)
	_check(not timed_receiver.call("is_forced_movement_active"),"source leaving tree cancels before movement")
	root.add_child(source)
	timed_receiver.call("request_forced_movement",source,Vector3(8,0,5),0.35)
	source.apply_damage(9999)
	await _frames(2)
	_check(not timed_receiver.call("is_forced_movement_active"),"source death cancels")
	source.revive(100)
	timed_receiver.call("request_forced_movement",source,Vector3(8,0,5),0.35)
	timed.apply_damage(9999)
	await _frames(2)
	_check(not timed_receiver.call("is_forced_movement_active"),"owner death cancels")
	await _test_disabled_and_exit_reentry(source)
	await _test_player_physics_and_no_double_move(source)
	for node: Node in units:
		if is_instance_valid(node): node.queue_free()
	await _frames(2)
	_finish()
# 忽略单位是单次请求策略；默认外力仍保留原碰撞，墙地/命中层和旧例外不可被整体关闭。
func _test_unit_overlap_collision_lifecycle(source: UnitBase) -> void:
	var moving = _body(Vector3(0,0,30))
	var receiver = moving
	var supported := false
	for method: Dictionary in receiver.get_method_list():
		if method.name==&"request_forced_movement": supported = method.args.size()==4
	_check(supported,"pull request supports temporary unit-collision exclusion")
	if not supported: return
	var blocker = _body(Vector3(2,0,30))
	var old_exception = _body(Vector3(20,0,30))
	moving.add_collision_exception_with(old_exception)
	var mask_before: int = moving.collision_mask
	var layer_before: int = moving.collision_layer
	var ended: Array[Dictionary] = []
	receiver.forced_movement_finished.connect(func(_token: int, reason: StringName):
		ended.append({"position":moving.position,"reason":reason,"blocker_exception":moving.get_collision_exceptions().has(blocker)})
	)
	receiver.call("request_forced_movement",source,Vector3(2,0,30),0.35,true)
	_check(moving.get_collision_exceptions().has(blocker),"pull excludes other unit body before physics")
	_check(moving.collision_mask==mask_before and moving.collision_layer==layer_before,"unit exclusion keeps original collision layers/masks intact")
	await _frames(12)
	var late_unit = _body(Vector3(1.6,0,30))
	_check(moving.get_collision_exceptions().has(late_unit),"unit spawned during pull is also excluded")
	await _frames(1)
	late_unit.queue_free()
	await _frames(1)
	_check(moving.get_collision_exceptions().all(func(value):return is_instance_valid(value)),"freed ignored body leaves no stale physics exception")
	await _frames(12)
	_check(not ended.is_empty() and ended[0].reason==&"arrived" and ended[0].position.distance_to(Vector3(2,0,30))<0.08,"pull can finish at an occupied position without unit-blocked termination")
	_check(not moving.get_collision_exceptions().has(blocker),"arrival restores temporary unit collisions")
	_check(moving.get_collision_exceptions().has(old_exception),"arrival preserves pre-existing collision exception")
	_check(not ended.is_empty() and not ended[0].blocker_exception,"collision state is restored before terminal notification")
	var token: int = receiver.call("request_forced_movement",source,Vector3(3,0,30),0.35,true)
	receiver.call("cancel_forced_movement",token)
	_check(not moving.get_collision_exceptions().has(blocker),"manual cancellation restores collision state")
	receiver.call("request_forced_movement",source,Vector3(3,0,30),0.35,true)
	var ordinary: int = receiver.call("request_forced_movement",source,Vector3(3,0,30),0.35)
	_check(not moving.get_collision_exceptions().has(blocker) and receiver.call("get_forced_movement_token")==ordinary,"replacement with ordinary movement restores collision immediately")
	receiver.call("cancel_forced_movement",ordinary)
	var temporary_source := UnitBase.new()
	root.add_child(temporary_source)
	receiver.call("request_forced_movement",temporary_source,Vector3(3,0,30),0.35,true)
	temporary_source.apply_damage(9999)
	await _frames(2)
	_check(not receiver.call("is_forced_movement_active") and not moving.get_collision_exceptions().has(blocker),"source death restores unit collisions")
	temporary_source.queue_free()
	var restart := [0]
	var old_token: int = receiver.call("request_forced_movement",source,Vector3(3,0,30),0.35,true)
	receiver.forced_movement_finished.connect(func(old: int, reason: StringName):
		if old==old_token and reason==&"cancelled":
			restart[0]=receiver.call("request_forced_movement",source,Vector3(4,0,30),0.35,true)
	)
	receiver.call("cancel_forced_movement",old_token)
	_check(restart[0]>0 and moving.get_collision_exceptions().has(blocker),"old cancellation cannot restore over a reentrant new pull")
	receiver.call("cancel_forced_movement",restart[0])
	receiver.call("request_forced_movement",source,Vector3(4,0,30),0.35,true)
	root.remove_child(source)
	await _frames(2)
	_check(not receiver.call("is_forced_movement_active") and not moving.get_collision_exceptions().has(blocker),"source leaving tree restores collisions")
	root.add_child(source)
	receiver.call("request_forced_movement",source,Vector3(4,0,30),0.35,true)
	root.remove_child(moving)
	_check(not receiver.call("is_forced_movement_active") and not moving.get_collision_exceptions().has(blocker),"owner exit restores collisions synchronously")
	root.add_child(moving)
	receiver.call("request_forced_movement",source,Vector3(4,0,30),0.35,true)
	moving.apply_damage(99999)
	await _frames(2)
	_check(not receiver.call("is_forced_movement_active") and not moving.get_collision_exceptions().has(blocker),"owner death restores collisions")
	# 世界碰撞仍需生效：单次开启忽略单位也不能穿过静态墙。
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2,4,4)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(1,0,40)
	root.add_child(wall)
	var wall_target = _body(Vector3(0,0,40))
	await _frames(2)
	wall_target.call("request_forced_movement",source,Vector3(3,0,40),0.35,true)
	await _frames(23)
	_check(wall_target.position.x<0.75 and not wall_target.call("is_forced_movement_active"),"ignoring units still stops at a world wall")
	wall.queue_free()
	# 单位离树时，终态通知不得重新发起请求或留下永久例外。
	var detached_owner = _body(Vector3(0,0,50))
	var detached_receiver = detached_owner
	var exit_reentry := [-1]
	detached_receiver.call("request_forced_movement",source,Vector3(2,0,50),0.35,true)
	detached_receiver.forced_movement_finished.connect(func(_old: int,reason: StringName):
		if reason==&"owner_invalid":
			exit_reentry[0]=detached_receiver.call("request_forced_movement",source,Vector3(3,0,50),0.35,true)
	)
	root.remove_child(detached_owner)
	_check(exit_reentry[0]==0 and not detached_receiver.call("is_forced_movement_active") and detached_owner.get_collision_exceptions().is_empty(),"unit exit rejects reentrant pull and cannot leak collision exceptions")
	root.add_child(detached_owner)
	if detached_receiver.call("is_forced_movement_active"): detached_receiver.call("cancel_forced_movement",detached_receiver.call("get_forced_movement_token"))

func _finish() -> void:
	paused = false
	Engine.time_scale = 1.0
	for message: String in failures: printerr("FAIL: ",message)
	print("UnitForcedMovementTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

# 关闭开关必须在终态回调前拒绝新请求；重新开启不会复活旧位移。
func _test_disabled_and_exit_reentry(source: UnitBase) -> void:
	var body = _body(Vector3(0,0,60))
	var blocker = _body(Vector3(2,0,60))
	var reentered := [-1]
	var reasons: Array[StringName] = []
	body.forced_movement_finished.connect(func(_id: int, reason: StringName):
		reasons.append(reason)
		if reason == &"disabled": reentered[0] = body.call("request_forced_movement",source,Vector3(3,0,60),0.35,true)
	)
	body.call("request_forced_movement",source,Vector3(3,0,60),0.35,true)
	_check(body.get_collision_exceptions().has(blocker),"default capability excludes body for pull")
	body.set("forced_movement_enabled",false)
	_check(not body.call("is_forced_movement_active") and reasons == [&"disabled"] and reentered[0] == 0,"disabled closes admission before synchronous callback")
	_check(body.get_collision_exceptions().is_empty(),"disabled restores own collision exceptions")
	body.set("forced_movement_enabled",true)
	await _frames(2)
	_check(not body.call("is_forced_movement_active") and body.position.distance_to(Vector3(0,0,60))<0.01,"re-enable never resumes old motion")

# 持续输入和攻击推进不可叠加到外力；禁输入仍可受外力，且不取消真实技能动作。
func _test_player_physics_and_no_double_move(source: UnitBase) -> void:
	var world = load("res://Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(2)
	var hero = world.get_node("Hero")
	var host = hero.get_node("SkillHost")
	hero.gravity_multiplier = 0.0
	var start: Vector3 = hero.global_position
	var ends: Array[Vector3] = []
	hero.connect("forced_movement_finished",func(_id: int,_reason: StringName):
		ends.append(hero.global_position)
		Input.action_release(&"player_move_right")
	)
	hero.request_attack_motion(Vector3.RIGHT,5.0,10.0)
	_check(hero.get_node("PlayerSkillController").request_slot(1),"real self skill starts before passive movement")
	Input.action_press(&"player_move_right")
	hero.call("request_forced_movement",source,start+Vector3(3,99,0),0.35,true)
	await _frames(2)
	_check(host.get_active_skill()!=null,"passive movement does not cancel already accepted skill action")
	await _frames(23)
	_check(not ends.is_empty() and ends[0].distance_to(start+Vector3(3,0,0))<0.08,"player uses exactly one physical output and ignores destination Y")
	_check(not hero.is_attack_motion_active() and not hero.is_player_dashing(),"overridden active movement never catches up")
	hero.set_player_input_enabled(false)
	start = hero.global_position
	hero.call("request_forced_movement",source,start+Vector3.RIGHT,0.1,true)
	await _frames(8)
	_check(hero.global_position.distance_to(start+Vector3.RIGHT)<0.08,"blocking local input is not immunity to external movement")
	hero.set_player_input_enabled(true)
	world.free()
	current_scene = null
	await process_frame
