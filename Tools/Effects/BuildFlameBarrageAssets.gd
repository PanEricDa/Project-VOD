extends RefCounted

## 一次性原生资产生成工具；只创建缺失资产，拒绝覆盖，后续美术调整直接编辑场景和动画轨道。
const BASE := "res://Effects/Skills/FlameBarrage/"
const GOLD := Color(1.0, 0.76, 0.24, 0.9)
const WHITE := Color(1.0, 0.94, 0.65, 1.0)
const RED := Color(1.0, 0.12, 0.025, 0.65)
const ORANGE := Color(1.0, 0.38, 0.035, 0.8)

## 通过 ResourceSaver 创建四个正式视觉场景和五个预览；目标已存在则返回 ERR_ALREADY_EXISTS，绝不覆盖用户调整。
static func build() -> Error:
	var parts := ["Cast", "Release", "Flight", "Impact"]
	var outputs: Array[String] = ["FlameBarrageVisualSequencePreview.tscn"]
	for part: String in parts:
		outputs.append("FlameBarrage" + part + "Effect.tscn")
		outputs.append("FlameBarrage" + part + "EffectPreview.tscn")
	for output: String in outputs:
		if FileAccess.file_exists(BASE + output):
			return ERR_ALREADY_EXISTS
	for i: int in range(4):
		var result := _build_effect(parts[i])
		if result != OK:
			return result
	for i: int in range(5):
		var result := _build_preview(i)
		if result != OK:
			return result
	return OK

static func _material(color: Color, additive: bool = true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if additive or color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	return mat

static func _node(parent: Node, node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	parent.add_child(node)
	return node

static func _mesh(parent: Node, node_name: String, shape: Mesh, color: Color, additive: bool = true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = shape
	node.material_override = _material(color, additive)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func _sphere(radius: float) -> SphereMesh:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 24
	shape.rings = 12
	return shape

# 带透明边缘的圆弧面：vertical=true 位于XY平面，否则位于XZ地面。
static func _arc(radius: float, width: float, begin: float = 0.0, end: float = TAU, vertical: bool = false) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(64):
		var a: float = lerpf(begin, end, float(i) / 64.0)
		var b: float = lerpf(begin, end, float(i + 1) / 64.0)
		for lane: int in range(2):
			var r0: float = radius - width * 0.5 + width * float(lane) * 0.5
			var r1: float = r0 + width * 0.5
			var alpha0: float = 0.0 if lane == 0 else 1.0
			var alpha1: float = 1.0 if lane == 0 else 0.0
			var polar := func(angle: float, r: float) -> Vector3:
				return Vector3(cos(angle) * r, sin(angle) * r, 0) if vertical else Vector3(cos(angle) * r, 0, sin(angle) * r)
			var points := [polar.call(a, r0), polar.call(a, r1), polar.call(b, r1), polar.call(a, r0), polar.call(b, r1), polar.call(b, r0)]
			var alphas := [alpha0, alpha1, alpha1, alpha0, alpha1, alpha0]
			for k: int in range(6):
				tool.set_color(Color(1, 1, 1, alphas[k]))
				tool.add_vertex(points[k])
	tool.generate_normals()
	return tool.commit()

# 弯曲火舌，由透明外沿包住亮的中脊；不是旧技能网格或材质的拷贝。
static func _leaf(length: float, width: float, curl: float = 0.0) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(8):
		var t0: float = float(i) / 8.0
		var t1: float = float(i + 1) / 8.0
		for side: int in [-1, 1]:
			var a := Vector3(sin(t0 * PI) * curl, t0 * length, 0)
			var b := Vector3(sin(t1 * PI) * curl, t1 * length, 0)
			var wa: float = sin(PI * (0.1 + t0 * 0.9)) * width * 0.5
			var wb: float = sin(PI * (0.1 + t1 * 0.9)) * width * 0.5
			var points := [a, a + Vector3.RIGHT * wa * side, b + Vector3.RIGHT * wb * side, a, b + Vector3.RIGHT * wb * side, b]
			var alphas := [1.0 - t0 * 0.6, 0.0, 0.0, 1.0 - t0 * 0.6, 0.0, 1.0 - t1 * 0.6]
			for k: int in range(6):
				tool.set_color(Color(1, 1, 1, alphas[k]))
				tool.add_vertex(points[k])
	tool.generate_normals()
	return tool.commit()

static func _track(animation: Animation, path: String, keys: Array, values: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	for i: int in range(keys.size()):
		animation.track_insert_key(track, keys[i], values[i])

static func _fade(animation: Animation, node: Node3D, duration: float, peak: float = 0.02) -> void:
	_track(animation, str(node.get_path()).trim_prefix("/") + ":transparency", [0.0, peak, duration], [1.0, 0.0, 1.0])

static func _animate_fade(animation: Animation, path: String, keys: Array, values: Array) -> void:
	_track(animation, path + ":transparency", keys, values)

static func _build_effect(part: String) -> Error:
	var root := Node3D.new()
	root.name = "FlameBarrage" + part + "Effect"
	root.set_script(load(BASE + "FlameBarrageEffectPlayer.gd"))
	root.set("autoplay", true)
	root.set("auto_free_on_finished", part in ["Release", "Impact"])
	var visual := _node(root, "VisualRoot")
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	var anim := Animation.new()
	if part == "Cast":
		anim.length = 1.0 / 3.0
		var crown := _node(visual, "Crown")
		crown.position = Vector3(0, 0.65, 0.25)
		for i: int in range(5):
			var begin: float = deg_to_rad(12.0 + i * 32.0)
			_mesh(crown, "CrownArc%d" % i, _arc(0.67, 0.075, begin, begin + deg_to_rad(24), true), GOLD)
		for i: int in range(9):
			var angle: float = deg_to_rad(14.0 + i * 19.0)
			var flame := _mesh(crown, "CrownFlame%d" % i, _leaf(0.3 + 0.08 * (i % 3), 0.14, 0.07), ORANGE)
			flame.position = Vector3(cos(angle), sin(angle), 0) * 0.69
			flame.rotation.z = angle - PI * 0.5
			_animate_fade(anim, "VisualRoot/Crown/" + str(flame.name), [0, 0.08, 0.22, anim.length], [1.0, 0.1, 0.0, 1.0])
		var focus := _node(visual, "Focus")
		focus.position = Vector3(0.32, 0.33, -0.67)
		_mesh(focus, "GatherCore", _sphere(0.14), WHITE)
		_track(anim, "VisualRoot/Focus/GatherCore:scale", [0, 0.18, 0.3, anim.length], [Vector3.ONE * 0.01, Vector3.ONE * 0.3, Vector3.ONE, Vector3.ONE * 0.25])
		_animate_fade(anim, "VisualRoot/Focus/GatherCore", [0, 0.18, 0.3, anim.length], [1.0, 0.3, 0.0, 1.0])
		for i: int in range(16):
			var spark := _mesh(focus, "GatherSpark%d" % i, _sphere(0.022 + (i % 3) * 0.006), GOLD)
			var angle: float = TAU * float(i) / 16.0
			var start := Vector3(cos(angle) * 0.75, 0.65 + sin(angle) * 0.75, 0.25)
			_track(anim, "VisualRoot/Focus/" + str(spark.name) + ":position", [0, 0.14, 0.31, anim.length], [start * 0.8 - focus.position, start - focus.position, Vector3.ZERO, Vector3.ZERO])
			_animate_fade(anim, "VisualRoot/Focus/" + str(spark.name), [0, 0.1, 0.29, anim.length], [1.0, 0.0, 0.15, 1.0])
		_track(anim, "VisualRoot/Crown:scale", [0, 0.12, 0.24, anim.length], [Vector3.ONE * 0.3, Vector3.ONE, Vector3.ONE * 0.9, Vector3.ONE * 0.45])
		for child: Node in crown.get_children():
			if child is MeshInstance3D and str(child.name).begins_with("CrownArc"):
				_animate_fade(anim, "VisualRoot/Crown/" + str(child.name), [0, 0.06, 0.21, anim.length], [1.0, 0.0, 0.2, 1.0])
	elif part == "Release":
		anim.length = 0.14
		_mesh(visual, "ForwardRing", _arc(0.5, 0.09, 0, TAU, true), GOLD)
		_track(anim, "VisualRoot/ForwardRing:scale", [0, 0.06, 0.14], [Vector3.ONE * 0.25, Vector3.ONE, Vector3.ONE * 1.4])
		_track(anim, "VisualRoot/ForwardRing:position", [0, 0.14], [Vector3.ZERO, Vector3(0, 0, -0.35)])
		_animate_fade(anim, "VisualRoot/ForwardRing", [0, 0.025, 0.14], [0.4, 0.0, 1.0])
		for i: int in range(8):
			var flame := _mesh(visual, "ReleaseFlame%d" % i, _leaf(0.65, 0.28, 0.12), ORANGE if i % 2 == 0 else GOLD)
			var angle: float = TAU * float(i) / 8.0
			var direction := Vector3(cos(angle) * 0.5, sin(angle) * 0.5, -1.0).normalized()
			flame.basis = Basis(Quaternion(Vector3.UP, direction))
			_track(anim, "VisualRoot/" + str(flame.name) + ":scale", [0, 0.045, 0.14], [Vector3.ONE * 0.05, Vector3.ONE, Vector3.ONE * 0.4])
			_animate_fade(anim, "VisualRoot/" + str(flame.name), [0, 0.035, 0.14], [0.4, 0.0, 1.0])
	elif part == "Flight":
		anim.length = 0.5
		anim.loop_mode = Animation.LOOP_LINEAR
		_mesh(visual, "GoldCore", _sphere(0.22), WHITE, false)
		_mesh(visual, "MoltenShell", _sphere(0.32), Color(1, 0.22, 0.025, 0.42))
		_track(anim, "VisualRoot/MoltenShell:scale", [0, 0.25, 0.5], [Vector3(1, 0.95, 1.02), Vector3(1.05, 1, 0.96), Vector3(1, 0.95, 1.02)])
		for i: int in range(10):
			var angle: float = TAU * float(i) / 10.0
			var tail := _mesh(visual, "CurlingFlame%d" % i, _leaf(0.7 + (i % 3) * 0.13, 0.28, 0.13), ORANGE if i % 2 == 0 else RED)
			tail.position = Vector3(cos(angle), sin(angle), 0) * 0.18
			tail.basis = Basis(Quaternion(Vector3.UP, Vector3(cos(angle) * 0.3, sin(angle) * 0.3, 1.0).normalized()))
			_track(anim, "VisualRoot/" + str(tail.name) + ":scale", [0, 0.25, 0.5], [Vector3.ONE, Vector3(0.8 + (i % 2) * 0.4, 0.8, 1.0), Vector3.ONE])
		for i: int in range(6):
			var ember := _mesh(visual, "Ember%d" % i, _sphere(0.025), GOLD)
			var angle: float = i * 2.4
			ember.position = Vector3(cos(angle) * 0.32, sin(angle) * 0.32, 0.35 + i * 0.1)
			_animate_fade(anim, "VisualRoot/" + str(ember.name), [0, 0.25, 0.5], [0.8, 0.1, 0.8])
	else:
		anim.length = 0.35
		var ring := _mesh(visual, "ShockRing", _arc(3.0, 0.22), ORANGE)
		ring.position.y = 0.035
		_track(anim, "VisualRoot/ShockRing:scale", [0, 0.05, 0.2, 0.35], [Vector3.ONE * 0.05, Vector3.ONE * 0.25, Vector3.ONE, Vector3.ONE * 1.04])
		_animate_fade(anim, "VisualRoot/ShockRing", [0, 0.04, 0.18, 0.35], [0.6, 0.0, 0.1, 1.0])
		var flash := _mesh(visual, "ContactFlash", _sphere(0.7), WHITE)
		flash.position.y = 0.3
		_track(anim, "VisualRoot/ContactFlash:scale", [0, 0.035, 0.07], [Vector3.ONE * 0.1, Vector3(1, 0.5, 1), Vector3.ONE * 0.01])
		_animate_fade(anim, "VisualRoot/ContactFlash", [0, 0.02, 0.06, 0.35], [0, 0.1, 1, 1])
		var column := _node(visual, "FlameColumn")
		for i: int in range(12):
			var angle: float = TAU * float(i) / 12.0
			var flame := _mesh(column, "ColumnFlame%d" % i, _leaf(1.8 + (i % 3) * 0.22, 1.1, 0.2), ORANGE if i % 2 == 0 else RED)
			flame.position = Vector3(cos(angle) * 0.48, 0.03, sin(angle) * 0.48)
			flame.rotation.y = angle + PI * 0.5
			_animate_fade(anim, "VisualRoot/FlameColumn/" + str(flame.name), [0, 0.06, 0.2, 0.35], [1.0, 0.1, 0.25, 1.0])
		_track(anim, "VisualRoot/FlameColumn:scale", [0, 0.07, 0.2, 0.35], [Vector3(0.3, 0.2, 0.3), Vector3.ONE, Vector3(1.25, 0.85, 1.25), Vector3(0.9, 0.1, 0.9)])
		for i: int in range(24):
			var ember := _mesh(visual, "BurstFragment%d" % i, _sphere(0.035 + (i % 3) * 0.012), GOLD)
			var angle: float = i * 2.39996
			var end := Vector3(cos(angle) * (1.2 + (i % 4) * 0.4), 0.25 + (i % 5) * 0.27, sin(angle) * (1.2 + (i % 4) * 0.4))
			_track(anim, "VisualRoot/" + str(ember.name) + ":position", [0, 0.08, 0.25, 0.35], [Vector3.UP * 0.1, end * 0.35 + Vector3.UP * 0.3, end, end + Vector3.DOWN * 0.15])
			_animate_fade(anim, "VisualRoot/" + str(ember.name), [0, 0.06, 0.24, 0.35], [1, 0.1, 0.25, 1])
	var library := AnimationLibrary.new()
	library.add_animation("effect", anim)
	player.add_animation_library("", library)
	return _save(root, BASE + str(root.name) + ".tscn")

static func _build_preview(mode: int) -> Error:
	var names := ["CastEffectPreview", "ReleaseEffectPreview", "FlightEffectPreview", "ImpactEffectPreview", "VisualSequencePreview"]
	var root := Node3D.new()
	root.name = "FlameBarrage" + names[mode]
	root.set_script(load(BASE + "FlameBarrageEffectPreview.gd"))
	root.set("preview_mode", mode)
	_node(root, "Transient")
	var caster := (load("res://UnitSystem/Visuals/Ally/CasterVisual.tscn") as PackedScene).instantiate() as Node3D
	caster.name = "CasterVisual"
	root.add_child(caster)
	root.set_editable_instance(caster, true)
	var weapon := (load("res://Item/Weapon/MagicGlobe/MagicGlobeVisual.tscn") as PackedScene).instantiate()
	caster.get_node("CharacterRoot/WeaponSocket").add_child(weapon)
	var animation_player := caster.get_node("CharacterAnimationPlayer") as AnimationPlayer
	if animation_player.has_animation_library("MagicGlobeAnimationLibrary"):
		animation_player.remove_animation_library("MagicGlobeAnimationLibrary")
	animation_player.add_animation_library("MagicGlobeAnimationLibrary", load("res://Item/Weapon/MagicGlobe/MagicGlobeAnimationLibrary.res") as AnimationLibrary)
	# 预览实例只保存引用和局部装配，不保存/改写用户源场景或动画资源。
	var floor_node := _mesh(root, "Ground", PlaneMesh.new(), Color(0.055, 0.069, 0.087, 1), false)
	(floor_node.mesh as PlaneMesh).size = Vector2(25, 25)
	for i: int in range(-12, 13):
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.012, 0.006, 24)
		var x_line := _mesh(root, "GridX%d" % (i + 12), line_mesh, Color(0.12, 0.145, 0.18, 1), false)
		x_line.position = Vector3(i, 0.005, -3)
		var z_line := _mesh(root, "GridZ%d" % (i + 12), line_mesh, Color(0.12, 0.145, 0.18, 1), false)
		z_line.position = Vector3(0, 0.005, i - 3)
		z_line.rotation.y = PI / 2
	var boundary := _mesh(root, "AreaGuide5m", _arc(5, 0.025), Color(0.28, 0.18, 0.075, 0.8), false)
	boundary.position = Vector3(0, 0.018, -6)
	boundary.visible = mode == 4
	for i: int in range(5):
		var marker := _mesh(root, "DummyMarker%d" % i, _sphere(0.16), Color(0.15, 0.22, 0.3, 1), false)
		marker.position = Vector3((i - 2) * 1.2, 0.16, -5.8 - (i % 2) * 1.5)
		marker.visible = mode == 4
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14 if mode == 4 else (4 if mode < 2 else 8)
	root.add_child(camera)
	camera.position = Vector3(8, 9, 11) if mode == 4 else Vector3(4, 3.5, 5)
	var target := Vector3(0, 0, -3) if mode == 4 else Vector3(0, 0.5, 0 if mode == 0 else -3)
	camera.look_at_from_position(camera.position, target)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.light_energy = 1.3
	light.shadow_enabled = false
	root.add_child(light)
	var environment_node := WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.025, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.7, 0.85)
	environment.ambient_light_energy = 0.65
	environment_node.environment = environment
	root.add_child(environment_node)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	root.add_child(ui)
	var panel := VBoxContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(28, 24)
	ui.add_child(panel)
	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	var status := Label.new()
	status.name = "Status"
	status.add_theme_font_size_override("font_size", 16)
	panel.add_child(status)
	var replay := Button.new()
	replay.name = "Replay"
	replay.text = "重新播放"
	panel.add_child(replay)
	var pause := Button.new()
	pause.name = "Pause"
	pause.text = "暂停"
	pause.toggle_mode = true
	panel.add_child(pause)
	return _save(root, BASE + str(root.name) + ".tscn")

static func _assign_owners(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		# 保留场景实例原有内部 owner，避免把继承节点重复序列化成新节点。
		if child.owner == null:
			child.owner = root
		_assign_owners(child, root)

static func _save(root: Node3D, path: String) -> Error:
	if FileAccess.file_exists(path):
		root.free()
		return ERR_ALREADY_EXISTS
	_assign_owners(root, root)
	var packed := PackedScene.new()
	var result := packed.pack(root)
	if result == OK:
		result = ResourceSaver.save(packed, path)
	root.free()
	return result
