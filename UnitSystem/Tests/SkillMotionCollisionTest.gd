extends SceneTree
var failures: Array[String] = []
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var unit = load("res://UnitSystem/AI/Ally/AllyBase.tscn").instantiate()
	root.add_child(unit)
	unit.gravity_multiplier = 0.0
	var source := Node.new()
	root.add_child(source)
	_check(unit.has_method("submit_skill_motion_step"), "unit exposes collision-consumed motion intent")
	if unit.has_method("submit_skill_motion_step"):
		var before: Vector3 = unit.position
		var facing: Vector3 = -unit.get_node("Visual").global_basis.z
		for i: int in range(10):
			unit.submit_skill_motion_step(source,0,1,Vector3(0,0,0.08),i==9)
			await physics_frame
			await process_frame
		_check(absf(unit.position.z-before.z-0.8)<0.03,"unobstructed actual physics retreat is 0.8m")
		_check((-unit.get_node("Visual").global_basis.z).dot(facing)>0.99,"retreat does not turn actor backwards")
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4,4,0.1)
		shape.shape = box
		wall.add_child(shape)
		root.add_child(wall)
		wall.position = unit.position + Vector3(0,0,0.55)
		await physics_frame
		before = unit.position
		for i: int in range(10):
			unit.submit_skill_motion_step(source,0,2,Vector3(0,0,0.08),i==9)
			await physics_frame
			await process_frame
		var moved: float = unit.position.z-before.z
		_check(moved>=-0.01 and moved<0.7,"wall truncates displacement")
		wall.queue_free()
		for i: int in range(4): await physics_frame
		_check(absf(unit.position.z-before.z-moved)<0.01,"no missed-distance catchup after wall removal")
		unit.submit_skill_motion_step(source,0,3,Vector3(0,0,0.1),false)
		unit.cancel_skill_motion(source,0,2)
		await physics_frame
		await process_frame
		_check(unit.position.z>before.z+moved+0.05,"old cancellation cannot erase new request")
		unit.cancel_skill_motion(source,0,3)
		before = unit.position
		unit.set("_hit_movement_lock_remaining",0.08)
		for i: int in range(3):
			unit.submit_skill_motion_step(source,0,4,Vector3(0,0,0.08),i==2)
			await physics_frame
			await process_frame
		for i: int in range(6): await physics_frame
		await process_frame
		_check(unit.position.distance_to(before)<0.01,"hit movement lock discards blocked animation slices without catchup")
		unit.submit_skill_motion_step(source,0,5,Vector3(0,0,0.1),false)
		root.remove_child(source)
		await physics_frame
		await process_frame
		_check(unit.position.distance_to(before)<0.01 and not bool(unit.get("_skill_motion_active")),"source leaving tree clears pending motion before physics")
		root.add_child(source)
		unit.submit_skill_motion_step(source,0,6,Vector3(0,0,0.1),false)
		unit.apply_damage(99999.0)
		await physics_frame
		await process_frame
		_check(unit.position.distance_to(before)<0.01 and not bool(unit.get("_skill_motion_active")),"death clears pending motion")
	unit.queue_free()
	source.queue_free()
	await process_frame
	if failures.is_empty(): print("SkillMotionCollisionTest: PASS")
	else:
		for f: String in failures: printerr("FAIL: ",f)
	quit(0 if failures.is_empty() else 1)
