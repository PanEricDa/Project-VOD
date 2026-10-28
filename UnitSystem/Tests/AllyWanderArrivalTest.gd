extends SceneTree
## 回归：实际运动已在arrival_distance内停止时，编队/战斗游荡到期必须能换目标。
## 保留原减速圈内刷新和计时等待，不能靠持续改目标掩盖停滞。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	player.faction_id = "Player"
	world.add_child(player)
	player.set_physics_process(false)
	var owner = load("res://UnitSystem/Base/AIUnitBase.tscn").instantiate() as AIUnitBase
	world.add_child(owner)
	owner.set_physics_process(false)
	var enemy = load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	enemy.position = Vector3(0,0,-4)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	var state = AllyBehaviorStateMachine.new()
	state.wander_interval_min = 1.0
	state.wander_interval_max = 1.0
	owner.add_child(state)
	state.set_follow_target(player)
	await physics_frame
	await physics_frame
	for combat: bool in [false,true]:
		for sample: Vector3 in [Vector3(0.1,0.125,1),Vector3(0.1,0.149,1),Vector3(0.2,0.18,1),Vector3(0.1,0.3,0),Vector3(0.2,0.3,0)]:
			owner.slowing_distance = sample.x
			owner.arrival_distance = 0.15
			owner.velocity = Vector3.ZERO
			state.configure(owner,null)
			if combat: state.call("_submit_combat_orbit_movement",enemy,0.0)
			else: state.physics_tick(0.0)
			var target: Vector3 = state.get_current_movement_target()
			owner.global_position = target + Vector3(sample.y,0,0)
			owner.set_movement_target(target)
			if sample.y < 0.15:
				owner.call("_process_regular_motion",0.1)
				_check(is_zero_approx(Vector2(owner.velocity.x,owner.velocity.z).length()),"real locomotion stops inside arrival radius")
			if combat: state.call("_submit_combat_orbit_movement",enemy,0.1)
			else: state.physics_tick(0.1)
			_check(state.get_current_movement_target().is_equal_approx(target),"arrival still waits for wander interval")
			if combat: state.call("_submit_combat_orbit_movement",enemy,1.0)
			else: state.physics_tick(1.0)
			var changed := not state.get_current_movement_target().is_equal_approx(target)
			_check(changed == bool(sample.z),"expired %s wander at slowing %.2f / distance %.3f refresh=%s" % ["combat" if combat else "formation",sample.x,sample.y,bool(sample.z)])
	world.free()
	await process_frame
	for message: String in failures: printerr("FAIL: ",message)
	print("AllyWanderArrivalTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _check(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
