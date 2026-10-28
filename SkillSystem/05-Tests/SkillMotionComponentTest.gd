extends SceneTree
var failures: Array[String] = []
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	if not ResourceLoader.exists("res://SkillSystem/03-Extensions/SkillMotionComponent.gd"):
		printerr("FAIL: reusable SkillMotionComponent is missing")
		quit(1)
		return
	_check(ResourceLoader.get_resource_uid("res://SkillSystem/03-Extensions/SkillMotionComponent.tscn") != ResourceUID.INVALID_ID,"native component scene has registered UID")
	var c = load("res://SkillSystem/03-Extensions/SkillMotionComponent.gd").new()
	var sample := {"interval":Vector2(1,1.5),"previous_position":0.9,"position":1.25,"forward":Vector3.FORWARD,"terminal":false}
	var a: Dictionary = c.sample_motion(0,1,sample)
	_check(a.accepted and a.displacement.is_equal_approx(Vector3(0,0,0.4)), "first half retreat is 0.4m")
	sample.position = 1.5
	sample.terminal = true
	a = c.sample_motion(0,1,sample)
	_check(a.accepted and a.terminal and a.displacement.is_equal_approx(Vector3(0,0,0.4)), "terminal half completes exactly 0.8m")
	_check(not c.sample_motion(0,1,sample).accepted, "duplicate terminal does not move")
	sample.position = 1.25
	sample.terminal = false
	_check(c.sample_motion(0,2,sample).accepted, "new serial can start")
	_check(not c.sample_motion(0,1,sample).accepted, "stale serial cannot replace active interval")
	c.cancel_motion(0,1)
	sample.position = 1.5
	_check(c.sample_motion(0,2,sample).accepted, "old cancellation cannot clear new interval")
	for direction: int in range(4):
		c.direction = direction
		sample.position = 1.5
		sample.terminal = true
		a = c.sample_motion(0,3+direction,sample)
		var expected := [Vector3(0,0,-0.8),Vector3(0,0,0.8),Vector3(-0.8,0,0),Vector3(0.8,0,0)]
		_check(a.accepted and a.displacement.is_equal_approx(expected[direction]), "each local direction resolves correctly")
	sample.forward = Vector3.ZERO
	_check(not c.sample_motion(0,10,sample).accepted,"zero heading rejected")
	sample.forward = Vector3(NAN,0,0)
	_check(not c.sample_motion(0,10,sample).accepted,"nonfinite heading rejected")
	sample.forward = Vector3.FORWARD
	sample.interval = Vector2(1.5,1.0)
	_check(not c.sample_motion(0,10,sample).accepted,"inverted interval rejected")
	sample.interval = Vector2(1,1.5)
	sample.position = NAN
	_check(not c.sample_motion(0,10,sample).accepted,"nonfinite cursor rejected")
	sample.position = 1.5
	c.distance_m = NAN
	_check(not c.validate_configuration().is_empty(), "invalid distance detected")
	_check(not c.sample_motion(0,10,sample).accepted, "invalid configuration refuses movement")
	c.free()
	if failures.is_empty(): print("SkillMotionComponentTest: PASS")
	else:
		for f: String in failures: printerr("FAIL: ", f)
	quit(0 if failures.is_empty() else 1)
