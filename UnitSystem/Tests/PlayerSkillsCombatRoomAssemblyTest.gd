extends SceneTree
## 正式源/继承装配行为：缺源装配、重复输入、技能实例/CD共享或测试内容泄入都会使本测试失败。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _expect(ok: bool, text: String) -> void:
	if not ok: failures.append(text)
func _run() -> void:
	var hero := load("res://UnitSystem/Player/Hero/Hero.tscn").instantiate() as PlayerBase
	var host := hero.get_node("SkillHost") as SkillHostComponent
	var controller := hero.get_node_or_null("PlayerSkillController") as PlayerSkillController
	var first := host.regular_skills[0]
	var second := host.regular_skills[1]
	_expect(controller != null and hero.get_node_or_null("PlayerSkillInputComponent") != null,"formal Hero has source input/controller")
	_expect(first != null and second != null,"formal Hero equips both real skills")
	var room := load("res://Scenes/CombatRoom.tscn").instantiate() as Node3D
	var bar := room.get_node_or_null("PlayerSkillBar") as PlayerSkillBar
	_expect(bar != null,"production room has HUD")
	if controller == null or first == null or second == null or bar == null:
		hero.free()
		room.free()
		_finish()
		return
	_expect(first == hero.get_node("SkillHost/SkillSocket/Gather") and second == hero.get_node("SkillHost/SkillSocket/ThreatMark"),"slots resolve to original owned nodes")
	_expect(first.skill_id == &"player_target_gather" and second.skill_id == &"player_threat_mark","real skills, not test probes")
	_expect(first.skill_cooldown == 10.0 and second.skill_cooldown == 12.0,"production source cooldowns preserved")
	_expect(not first.automatic_cast_enabled and not second.automatic_cast_enabled,"player skills never auto cast")
	_expect(bar.skill_source == room.get_node("Hero/PlayerSkillController"),"HUD has one local source")
	_expect(room.get_node_or_null("GatherRangeDebug") == null and room.get_script() == null,"test visual/bootstrap never enters production")
	for enemy: Node in room.get_node("EnemyContainer").find_children("*","Node",true,false):
		if enemy is EnemyBase:
			_expect(enemy.forced_movement_enabled and enemy.get_node_or_null("ForcedMovementComponent") == null,"formal enemies accept built-in displacement")
	room.free()
	var other := load("res://UnitSystem/Player/Hero/Hero.tscn").instantiate() as PlayerBase
	var other_host := other.get_node("SkillHost") as SkillHostComponent
	_expect(first != other_host.regular_skills[0],"different heroes own independent skill instances")
	other.free()
	root.add_child(hero)
	current_scene = hero
	await process_frame
	await process_frame
	_expect(host.get_regular_skill(0) == first and host.get_regular_skill(1) == second,"registered slots resolve after ready")
	_expect(_count_script(hero,load("res://SkillSystem/01-Core/SkillHostComponent.gd")) == 1,"one Host")
	_expect(_count_script(hero,load("res://UnitSystem/Components/Combat/PlayerSkillController.gd")) == 1,"one controller")
	_expect(_count_script(hero,load("res://UnitSystem/Components/Combat/PlayerSkillInputComponent.gd")) == 1,"one Input component")
	var packed := PackedScene.new()
	_expect(packed.pack(hero) == OK,"source assembly packs")
	var temporary := "user://player_skills_stage5_roundtrip_%d.tscn" % Time.get_ticks_usec()
	_expect(ResourceSaver.save(packed,temporary) == OK,"source assembly saves natively")
	var restored := (ResourceLoader.load(temporary,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	_expect(restored.get_node("SkillHost").regular_skills[0] == restored.get_node("SkillHost/SkillSocket/Gather"),"roundtrip preserves owned slot reference")
	restored.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	hero.free()
	current_scene = null
	await process_frame
	# 真实独立测试场景保证一次键只一次成功；不伪造释放或重置冷却。
	var scene = load("res://Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var test_hero: PlayerBase = scene.get_node("Hero")
	var test_host: SkillHostComponent = test_hero.get_node("SkillHost")
	_expect(test_host.get_regular_skill(0).skill_cooldown == 2.0 and test_host.get_regular_skill(1).skill_cooldown == 2.0,"local fast cooldown never leaks into Hero")
	_expect(_count_script(test_hero,load("res://UnitSystem/Components/Combat/PlayerSkillInputComponent.gd")) == 1 and _count_script(test_hero,load("res://UnitSystem/Components/Combat/PlayerSkillController.gd")) == 1,"inherited test has no duplicate input/controller")
	test_hero.get_node("TargetingSystem").request_lock(scene.get_node("EnemyContainer/TrainingMelee"))
	await _tap(&"player_skill_1")
	await _until(func(): return scene.get_status_snapshot().slots[0].finished == 1,2.0)
	var counts: Dictionary = scene.get_status_snapshot().slots[0]
	_expect(counts.accepted == 1 and counts.started == 1 and counts.released == 1 and counts.finished == 1,"one Q event produces one actual cast")
	var fresh = load("res://UnitSystem/Player/Hero/Hero.tscn").instantiate()
	root.add_child(fresh)
	_expect(test_host.get_regular_skill(0).get_cooldown_remaining()>0 and fresh.get_node("SkillHost").get_regular_skill(0).is_ready(),"actual cooldown does not leak to another Hero")
	fresh.free()
	await _until(func(): return test_host.is_global_cooldown_ready(),2.0)
	await _tap(&"player_skill_2")
	await _until(func(): return scene.get_status_snapshot().slots[1].finished == 1,2.0)
	counts = scene.get_status_snapshot().slots[1]
	_expect(counts.accepted == 1 and counts.started == 1 and counts.released == 1,"one E event produces one actual cast")
	scene.free()
	current_scene = null
	await process_frame
	_finish()
func _count_script(node: Node, script: Script) -> int:
	var count := 1 if node.get_script() == script else 0
	for child: Node in node.get_children(): count += _count_script(child,script)
	return count
func _tap(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
func _until(predicate: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
func _finish() -> void:
	for message: String in failures: printerr("FAIL: ",message)
	print("PlayerSkillsCombatRoomAssemblyTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
