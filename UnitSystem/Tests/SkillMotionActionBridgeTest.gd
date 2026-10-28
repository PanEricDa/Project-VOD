extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _clip(a: float, b: float) -> Animation:
	var x := Animation.new()
	x.length = 1.5
	var t := x.add_track(Animation.TYPE_METHOD)
	x.track_set_path(t, NodePath("CharacterAnimationPlayer"))
	x.track_insert_key(t, 0.25, {"method": &"release_action", "args": []})
	x.track_insert_key(t, a, {"method": &"begin_skill_motion", "args": []})
	x.track_insert_key(t, b, {"method": &"end_skill_motion", "args": []})
	return x
func _run() -> void:
	var owner = load("res://UnitSystem/AI/Ally/AllyBase.tscn").instantiate()
	root.add_child(owner)
	owner.set_physics_process(false)
	var visual = load("res://UnitSystem/Visuals/Ally/AllyVisual.tscn").instantiate()
	owner.get_node("Visual").add_child(visual)
	var c := AIAttackController.new()
	owner.add_child(c)
	c.configure(owner)
	c.equip_weapon(load("res://Item/Weapon/MagicGlobe/MagicGlobeData.tres"))
	c.set_physics_process(false)
	var ap = visual.get_node("CharacterAnimationPlayer")
	_check(ap.has_method("begin_skill_motion") and ap.has_method("end_skill_motion"), "animation motion event endpoints exist")
	_check(c.has_signal("external_action_motion_sample") and c.has_method("get_external_action_serial"), "controller exposes cursor samples and serial")
	if c.has_signal("external_action_motion_sample"):
		var samples: Array[Dictionary] = []
		c.connect("external_action_motion_sample", func(_id: int, _serial: int, sample: Dictionary): samples.append(sample))
		_check(c.request_external_action(0.25, null, {"action_animation":_clip(1.0,1.5),"skill_motion_enabled":true}), "motion action accepted")
		var serial: int = c.call("get_external_action_serial")
		c.call("_physics_process", 0.25)
		c.call("_physics_process", 1.0)
		_check(not samples.is_empty(), "crossing begin emits actual cursor")
		if not samples.is_empty():
			_check(is_equal_approx(samples.back().position, 1.25), "sample uses actual animation seconds")
			_check(samples.back().interval == Vector2(1.0,1.5), "sample includes authored interval")
		c.call("_physics_process", 0.5)
		_check(not samples.is_empty() and samples.back().terminal, "natural clip end submits terminal before reset")
		_check(not c.is_action_in_progress(), "natural completion releases occupancy")
		_check(c.request_external_action(0.25, null, {"action_animation":_clip(0.0,1.5),"skill_motion_enabled":true}), "zero-frame begin accepted")
		_check(int(c.call("get_external_action_serial")) > serial, "ordinary id zero gets a new serial")
		c.cancel_external_action()
		var bad := _clip(1.2,0.5)
		# 配置验证直接测试解析器，避免预期拒绝污染错误输出。
		_check((c.call("_resolve_motion_interval", bad, true) as Vector2) == Vector2(-1,-1), "inverted interval rejected")
		var disabled := _clip(0.1,0.8)
		disabled.track_set_enabled(0,false)
		_check((c.call("_resolve_motion_interval", disabled, true) as Vector2) == Vector2(-1,-1), "disabled markers cannot define live motion")
		var duplicate := _clip(0.1,0.8)
		duplicate.track_insert_key(0,0.6,{"method":&"begin_skill_motion","args":[]})
		_check((c.call("_resolve_motion_interval", duplicate, true) as Vector2) == Vector2(-1,-1), "duplicate begin rejected")
		var missing := _clip(0.1,0.8)
		missing.track_remove_key(0,2)
		_check((c.call("_resolve_motion_interval", missing, true) as Vector2) == Vector2(-1,-1), "missing end rejected")
		var early_finish := _clip(0.1,0.8)
		early_finish.track_insert_key(0,0.7,{"method":&"finish_action","args":[]})
		_check((c.call("_resolve_motion_interval", early_finish, false) as Vector2) == Vector2(-1,-1), "normal finish cannot precede motion end")
		_check(c.request_external_action(0.25,null,{"action_animation":_clip(0.0,1.5),"skill_motion_enabled":true}),"large-step fixture accepted")
		c.call("_physics_process",0.25)
		c.call("_physics_process",5.0)
		_check(not samples.is_empty() and samples.back().terminal and is_equal_approx(samples.back().position,1.5),"large step clamps to actual end and submits final progress")
	owner.queue_free()
	await process_frame
	if failures.is_empty(): print("SkillMotionActionBridgeTest: PASS")
	else:
		for f: String in failures: printerr("FAIL: ",f)
	quit(0 if failures.is_empty() else 1)
