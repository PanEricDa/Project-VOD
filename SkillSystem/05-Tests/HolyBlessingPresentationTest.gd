extends SceneTree
## 防止横转圈数错误、反向归位、预览无实际动作、纯视觉误留阴影或丢失正式资源索引。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var path := "res://Effects/Skills/HolyBlessing/HolyBlessingSequenceEffectPreview.tscn"
	if not ResourceLoader.exists(path):
		printerr("FAIL: HolyBlessing independent preview missing")
		quit(1)
		return
	var scene = load(path).instantiate()
	scene.auto_repeat = false
	root.add_child(scene)
	scene.set_process(false)
	var player: AnimationPlayer = scene.get_node("Actor/HeroVisual/CharacterAnimationPlayer")
	var socket: Node3D = scene.get_node("Actor/HeroVisual/CharacterRoot/WeaponSocket")
	player.seek(0,true)
	var initial := socket.transform
	player.seek(0.2,true)
	var prior := socket.basis.y
	prior.y = 0
	prior = prior.normalized()
	var total: float = 0
	for step: int in range(1,81):
		var time := 0.2+0.45*step/80.0
		player.seek(time,true)
		var direction := socket.basis.y
		direction.y = 0
		direction = direction.normalized()
		total += prior.signed_angle_to(direction,Vector3.UP)
		prior = direction
	_check(is_equal_approx(absf(total),TAU*2), "staff completes two continuous horizontal rotations")
	player.seek(0.65,true)
	var held := socket.transform
	player.seek(0.9,true)
	_check(socket.transform.is_equal_approx(held), "staff holds pose before downward strike")
	player.seek(1.15,true)
	_check(socket.basis.y.dot(Vector3.UP) > 0.99, "release pose has upright staff")
	var bottom := socket.global_transform * Vector3(0,-0.375,0)
	_check(absf(bottom.y) < 0.06, "staff butt reaches ground at release")
	player.seek(1.5,true)
	_check(socket.transform.is_equal_approx(initial), "recovery returns to initial equivalent pose without spin reversal")
	var profile = load("res://SkillSystem/00-Skills/Finisher_HolyBlessing/HolyBlessingCinematic.tres")
	_check(profile.validate_configuration().is_empty(), "unique release and finish markers persist")
	var staff = load("res://Item/Weapon/Staff/StaffAnimationLibrary.res")
	_check(staff.has_animation("finish_cast_1"), "workbench staff clip persisted")
	var action: Animation = staff.get_animation("finish_cast_1")
	_check(action.length <= 1.5 and action.loop_mode == Animation.LOOP_NONE, "staff finisher is short and non-looping")
	scene.free()
	await process_frame
	for part: String in ["Cast","Release","Buff","Sequence"]:
		var preview_path := "res://Effects/Skills/HolyBlessing/HolyBlessing"+part+"EffectPreview.tscn"
		_check(ResourceLoader.get_resource_uid(preview_path) != ResourceUID.INVALID_ID, "preview native UID "+part)
		var preview = load(preview_path).instantiate()
		preview.auto_repeat = false
		root.add_child(preview)
		preview.free()
	for part: String in ["Cast","Release","Buff"]:
		var visual_path := "res://Effects/Skills/HolyBlessing/HolyBlessing"+part+"Effect.tscn"
		_check(ResourceLoader.get_resource_uid(visual_path) != ResourceUID.INVALID_ID, "visual native UID "+part)
		var visual = load(visual_path).instantiate()
		for geometry: GeometryInstance3D in visual.find_children("*","GeometryInstance3D",true,false):
			_check(geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "effect never casts black shadow "+str(geometry.name))
		if part == "Buff":
			root.add_child(visual)
			_check(visual.has_method("finish_presentation"), "state visual supports cosmetic fade without another buff timer")
			if visual.has_method("finish_presentation"):
				visual.call("finish_presentation")
				var end := Time.get_ticks_msec()+1000
				while is_instance_valid(visual) and Time.get_ticks_msec()<end: await process_frame
				if is_instance_valid(visual):
					print("Fade diagnostic ",visual.get_node("AnimationPlayer").current_animation," position=",visual.get_node("AnimationPlayer").current_animation_position," ending=",visual.get("_ending")," signals=",visual.get_node("AnimationPlayer").animation_finished.get_connections())
				_check(not is_instance_valid(visual), "finished state visual fades and self-releases")
			else:
				visual.free()
		else:
			visual.free()
	await process_frame
	for failure: String in failures: printerr("FAIL: ",failure)
	print("HolyBlessingPresentationTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _check(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
