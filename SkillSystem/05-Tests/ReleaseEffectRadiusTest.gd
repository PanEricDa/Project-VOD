extends SceneTree
## 回归：释放环必须读取本次技能半径；不能固定8米、放大圣徽或污染其他实例。
var failures: Array[String] = []
const SKILL = "res://SkillSystem/00-Skills/Finisher_HolyBlessing/HolyBlessingFinisherSkill.tscn"
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var world = Node3D.new()
	root.add_child(world)
	world.scale = Vector3(2,1.5,2)
	var caster = Node3D.new()
	world.add_child(caster)
	var skill = load(SKILL).instantiate() as SkillBase
	caster.add_child(skill)
	var context = SkillContext.new()
	context.caster = caster
	context.resolved_target = caster
	context.delivery_parent = world
	var player = SkillReleasePresentationPlayer.new()
	world.add_child(player)
	var visuals: Array[Node3D] = []
	player.release_instance_prepared.connect(func(_fact, visual): visuals.append(visual))
	var original_radius: float = skill.delivery.effect_radius
	for radius: float in [original_radius,4.5]:
		skill.delivery = skill.delivery.duplicate()
		skill.delivery.effect_radius = radius
		var fact = SkillPresentationContext.create(skill,context,Transform3D.IDENTITY)
		var snapshot = player.prepare_release(context,Transform3D.IDENTITY,skill.release_effect_scene,3,null,null,fact)
		# 施法快照不能被后续编辑同一资源改写。
		skill.delivery.effect_radius = 2.0
		player.play_release(snapshot)
		var visual = visuals.back()
		visual.set_process(false)
		var animation: AnimationPlayer = visual.get_node("AnimationPlayer")
		animation.seek(0.35,true)
		var wave: MeshInstance3D = visual.find_child("GoldWave",true,false)
		var visible_radius: float = (wave.mesh as TorusMesh).outer_radius * wave.global_basis.x.length()
		_check(is_equal_approx(visible_radius,radius),"visible wave reaches captured radius %.2f before fading (got %.2f)" % [radius,visible_radius])
		_check(wave.transparency < 0.5,"range remains visible at full radius")
		var seal: Node3D = visual.get_node("VisualRoot/FlashSeal")
		_check(is_equal_approx(seal.global_basis.x.length(),0.6790698),"center seal remains unscaled")
		var earlier_radius: float = visible_radius
		visual.call("configure_effect_radius",radius) if visual.has_method("configure_effect_radius") else null
		_check(is_equal_approx(wave.global_basis.x.length() * (wave.mesh as TorusMesh).outer_radius,earlier_radius),"repeat configuration does not compound")
		if visual.has_method("configure_effect_radius"):
			for invalid: float in [0.0,-1.0,INF,NAN]:
				visual.call("configure_effect_radius",invalid)
			_check(wave.global_basis.is_finite() and is_equal_approx(wave.global_basis.x.length(),radius),"invalid radius preserves valid presentation")
	# 更小范围的新实例不能修改旧实例或共享动画资产。
	var first_wave: MeshInstance3D = visuals.front().find_child("GoldWave",true,false)
	_check(is_equal_approx(first_wave.global_basis.x.length(),original_radius),"simultaneous instances retain separate sizes")
	world.free()
	await process_frame
	var preview = load("res://Effects/Skills/HolyBlessing/HolyBlessingReleaseEffectPreview.tscn").instantiate()
	preview.auto_repeat = false
	root.add_child(preview)
	preview.set_process(false)
	var effect: Node3D = preview.get_node("Transient").get_child(0)
	effect.set_process(false)
	effect.get_node("AnimationPlayer").seek(0.35,true)
	var preview_wave: MeshInstance3D = effect.find_child("GoldWave",true,false)
	_check(is_equal_approx(preview_wave.global_basis.x.length(),original_radius),"preview reads formal skill radius")
	var camera: Camera3D = preview.get_node("Camera3D")
	var screen := camera.get_viewport().get_visible_rect()
	for direction: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		_check(screen.has_point(camera.unproject_position(direction*original_radius)),"preview camera includes full range boundary")
	preview.free()
	await process_frame
	for failure: String in failures: printerr("FAIL: ",failure)
	print("ReleaseEffectRadiusTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _check(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
