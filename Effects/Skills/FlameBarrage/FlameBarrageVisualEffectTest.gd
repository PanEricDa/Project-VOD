extends SceneTree

## 验证新终结技视觉的生命周期、五发完整性、独立资源与 UID；不执行战斗伤害。
var failures: Array[String] = []
var checks: int = 0
const BASE := "res://Effects/Skills/FlameBarrage/"
const PARTS := ["Cast", "Release", "Flight", "Impact"]
var _completed: int = 0
var _shots: Array[int] = []
var _impacts: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var paths: Array[String] = []
	for part: String in PARTS:
		paths.append(BASE + "FlameBarrage" + part + "Effect.tscn")
		paths.append(BASE + "FlameBarrage" + part + "EffectPreview.tscn")
	paths.append(BASE + "FlameBarrageVisualSequencePreview.tscn")
	for path: String in paths:
		_expect(ResourceLoader.exists(path), "可用视觉资产：" + path)
	if not failures.is_empty():
		_finish()
		return
	for path: String in paths:
		_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "原生保存 UID：" + path)
		_check_dependencies(path, {})
	var orphan_baseline: int = Node.get_orphan_node_ids().size()
	var world := Node3D.new()
	root.add_child(world)
	for part: String in PARTS:
		var fx := load(BASE + "FlameBarrage" + part + "Effect.tscn").instantiate() as Node3D
		fx.set("autoplay", false)
		fx.set("auto_free_on_finished", false)
		world.add_child(fx)
		fx.set_process(false)
		_completed = 0
		fx.connect("effect_finished", func() -> void: _completed += 1)
		fx.call("play")
		_expect(fx.visible and fx.call("is_playing"), part + "开始可见")
		fx.call("advance_effect", 0.1)
		fx.call("stop")
		_expect(not fx.visible and not fx.call("is_playing") and _completed == 0, part + "取消不冒充完成")
		fx.call("play")
		if part == "Flight":
			fx.call("advance_effect", 1.5)
			_expect(fx.call("is_playing") and _completed == 0, "飞行循环不提前完成")
		else:
			fx.call("advance_effect", 1.0)
			_expect(not fx.call("is_playing") and _completed == 1, part + "自然结束仅通知一次")
			fx.call("advance_effect", 1.0)
			_expect(_completed == 1, part + "结束后推进不重复通知")
		fx.free()
	var source := Node3D.new()
	world.add_child(source)
	var charge := load(BASE + "FlameBarrageCastEffect.tscn").instantiate() as Node3D
	charge.set("autoplay", false)
	world.add_child(charge)
	charge.set_process(false)
	charge.call("configure_cast", source, Transform3D(Basis.IDENTITY, Vector3(0.3, 0.7, -0.5)), 0.6)
	charge.call("play")
	source.position = Vector3(2, 0, 1)
	source.rotation.y = PI
	charge.call("advance_effect", 0.4)
	_expect(charge.call("is_playing"), "蓄力适配外部施法时间而非固定帧数")
	_expect(charge.global_position.is_equal_approx(source.global_position), "蓄力跟随角色位置")
	_expect(charge.global_basis.is_equal_approx(Basis.IDENTITY), "蓄力不跟随角色旋转一圈")
	charge.call("advance_effect", 0.21)
	_expect(not charge.call("is_playing"), "蓄力在传入时长结束")
	source.free()
	charge.call("play")
	charge.call("advance_effect", 0.1)
	charge.free()
	var relocated := load(BASE + "FlameBarrageCastEffect.tscn").instantiate() as Node3D
	relocated.set("autoplay", false)
	world.add_child(relocated)
	relocated.set_process(false)
	var relocated_origin := Vector3(1.3, 1.1, -0.2)
	relocated.call("configure_cast", null, Transform3D(Basis.IDENTITY, relocated_origin), 1.0)
	relocated.call("play")
	relocated.call("advance_effect", 0.94)
	for spark: Node in relocated.find_children("GatherSpark*", "MeshInstance3D", true, false):
		_expect(spark.global_position.distance_to(relocated_origin) < 0.001, "重新配置发射点后火星和核心汇聚到同一点")
	relocated.free()
	_test_builder_no_overwrite()
	var impact := load(BASE + "FlameBarrageImpactEffect.tscn").instantiate() as Node3D
	world.add_child(impact)
	impact.set_process(false)
	_completed = 0
	impact.connect("effect_finished", func() -> void: _completed += 1)
	impact.call("advance_effect", 0.34)
	_expect(_completed == 0, "主爆炸未结束不能提前通知")
	impact.call("advance_effect", 0.02)
	_expect(_completed == 1, "主爆炸约0.35秒结束")
	await process_frame
	_expect(not is_instance_valid(impact), "独立命中效果自动清理")
	for i: int in range(5):
		var preview_path: String = BASE + "FlameBarrage" + PARTS[i] + "EffectPreview.tscn" if i < 4 else paths.back()
		var preview: Node = load(preview_path).instantiate()
		root.add_child(preview)
		preview.set_process(false)
		_shots.clear()
		_impacts.clear()
		_completed = 0
		preview.connect("shot_emitted", func(index: int, _point: Vector3) -> void: _shots.append(index))
		preview.connect("impact_completed", func(index: int) -> void: _impacts.append(index))
		preview.connect("preview_finished", func() -> void: _completed += 1)
		preview.call("restart_preview")
		for step: int in range(210):
			preview.call("advance_preview", 0.01)
		if i == 4:
			_expect(_shots == [0, 1, 2, 3, 4], "动作提前结束仍依序发出全部五颗")
			_expect(_impacts.size() == 5, "五颗均完成主爆炸")
		_expect(_completed == 1, "预览完整结束：" + str(i))
		if i < 4:
			_expect(not preview.get_node("UI/Panel/Status").text.contains("/ 5"), "单项预览不显示虚假的五发计数")
		preview.call("restart_preview")
		_expect(preview.get_node("Transient").get_child_count() <= 1, "重播清理上一轮临时视觉：" + str(i))
		preview.free()
	var coarse := load(BASE + "FlameBarrageVisualSequencePreview.tscn").instantiate() as Node
	root.add_child(coarse)
	coarse.set_process(false)
	coarse.set("auto_repeat", false)
	coarse.call("restart_preview")
	coarse.call("advance_preview", 0.4)
	coarse.call("advance_preview", 0.36666667)
	var live_shots := coarse.get("_flights") as Array
	_expect(live_shots.size() == 2, "0.767秒时前两发仍在飞行，不能出生当帧直接命中")
	if live_shots.size() == 2:
		_expect(absf(float(live_shots[0].age) - 0.16666666) < 0.00001, "第一发只消费释放后的0.166667秒")
		_expect(absf(float(live_shots[1].age) - 0.04666666) < 0.00001, "第二发保留0.12秒发射间隔")
	coarse.call("advance_preview", 0.66)
	_expect(int(coarse.get("_finished_impacts")) == 0, "1.427秒时第一发主爆炸尚未完成")
	coarse.call("advance_preview", 0.03)
	_expect(int(coarse.get("_finished_impacts")) == 1, "1.457秒时只有第一发主爆炸完成")
	coarse.call("advance_preview", 0.48)
	_expect(bool(coarse.get("_done")) and int(coarse.get("_finished_impacts")) == 5, "大步长仍按真实发射飞行和爆炸时间完成五发")
	coarse.free()
	world.free()
	# 最后一发：0.6 + 4*0.12 + 0.5 + 0.35 = 1.93秒；等待延迟销毁队列清空。
	await process_frame
	await process_frame
	_expect(Node.get_orphan_node_ids().size() == orphan_baseline, "全部预览销毁后不遗留孤儿节点")
	_finish()

func _test_builder_no_overwrite() -> void:
	# 仅操作自己的临时样例，不用正式视觉资产作破坏性测试。
	var path := "user://flame_barrage_visual_guard_test.tscn"
	var original := Node3D.new()
	original.name = "KeepOriginal"
	var fixture := PackedScene.new()
	fixture.pack(original)
	_expect(ResourceSaver.save(fixture, path) == OK, "防覆盖测试样例原生保存")
	original.free()
	var before := FileAccess.get_sha256(path)
	var candidate := Node3D.new()
	candidate.name = "MustNotOverwrite"
	var builder: GDScript = load("res://Tools/Effects/BuildFlameBarrageAssets.gd")
	var result: Error = builder._save(candidate, path)
	_expect(result == ERR_ALREADY_EXISTS and FileAccess.get_sha256(path) == before, "生成工具拒绝覆盖已有场景，保留原始内容")
	DirAccess.remove_absolute(path)

func _check_dependencies(path: String, seen: Dictionary) -> void:
	if seen.has(path):
		return
	seen[path] = true
	for dep: String in ResourceLoader.get_dependencies(path):
		var actual: String = dep.get_slice("::", dep.get_slice_count("::") - 1)
		_expect(not actual.contains("Effects/Skills/Pyroblast/") and not actual.contains("Effects/Skills/Fireball/"), "独立新特效、不引用旧技能内容：" + actual)
		if actual.ends_with(".tscn") or actual.ends_with(".tres"):
			_check_dependencies(actual, seen)

func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func _finish() -> void:
	print("FlameBarrageVisualEffectTest: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
