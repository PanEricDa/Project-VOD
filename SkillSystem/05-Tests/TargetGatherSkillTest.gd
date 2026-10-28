extends SceneTree
## 错中心/朝向、无锁定回退、重新锁定串目标、释放后追踪、遗漏远端AoE或污染旧技能均会破坏本用例。
const NEW_SKILL := "res://SkillSystem/00-Skills/Player_TargetGather/TargetGatherSkill.tscn"
var failures: Array[String] = []
var world: Node3D
var hero: PlayerBase
var host: SkillHostComponent
var controller: PlayerSkillController
var targets: Dictionary = {}
var accepts := [0,0]
var releases := [0,0]
var ends: Dictionary = {}
var release_position := Vector3.INF
var fx: Node3D
var damage_events := 0

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	if not ResourceLoader.exists(NEW_SKILL):
		_expect(false,"independent target-centered Gather skill exists while old Gather remains available")
		_finish()
		return
	await _test_out_of_range_rejects_without_queue()
	await _setup()
	_expect(host.get_regular_skill(0).scene_file_path == NEW_SKILL,"formal Hero equips new skill, not old Gather")
	_expect(ResourceLoader.get_resource_uid(NEW_SKILL) != ResourceUID.INVALID_ID,"new scene has native valid UID")
	await _tap(&"player_skill_1")
	_expect(accepts[0] == 0 and releases[0] == 0 and host.get_active_skill() == null and host.get_regular_skill(0).is_ready(),"no lock rejects before action/cooldown")
	_expect(not controller.get_slot_status(0).can_request,"no lock is visibly unavailable")
	await _tap(&"player_skill_2")
	await _until(func(): return releases[1] == 1 and host.get_active_skill() == null,2.0)
	_expect(accepts[1] == 1 and releases[1] == 1,"self E still works without lock")
	var anchor: UnitBase = targets.anchor
	_expect(hero.get_node("TargetingSystem").request_lock(anchor),"real player lock selects anchor")
	var visual := hero.get_node("Visual") as Node3D
	visual.rotation.y = PI/2.0
	await _tap(&"player_skill_1")
	_expect(accepts[0] == 1,"targeted Q accepts once")
	# 在施法期间移动原目标并切换锁定：本次技能仍使用原目标，中心取释放时新位置。
	anchor.position = Vector3(0,0,-2.5)
	_expect(hero.get_node("TargetingSystem").request_lock(targets.near),"player may change lock after request")
	await _until(func(): return releases[0] == 1,2.0)
	_expect(release_position.distance_to(Vector3(0,0,-2.5)) < 0.001,"release freezes original requested target position, not caster/new lock")
	anchor.position = Vector3(1,0,-2.5)
	await _until(func(): return ends.size() >= 3,1.0)
	for label: String in ["near","edge","far_from_caster"]:
		var result: Dictionary = ends.get(label,{})
		_expect(result.get("reason") == &"arrived" and result.get("position",Vector3.INF).distance_to(Vector3(0,0,-2.5))<0.03,"actual physics ends at frozen target center: "+label)
	_expect(targets.outside.position.distance_to(Vector3(5.2,0,-3))<0.01,"outside target radius remains untouched")
	_expect(targets.behind.position.distance_to(Vector3(0,0,3))<0.01,"near caster but outside target circle is not pulled")
	_expect(targets.disabled.position.distance_to(Vector3(-1,0,-3))<0.01,"root disabled target still rejects external motion")
	_expect(not targets.friendly.is_forced_movement_active() and not ends.has("friendly") and targets.friendly.position.distance_to(Vector3(-2,0,-3))<0.01,"friendly never receives pull or moves")
	_expect(anchor.position.distance_to(Vector3(1,0,-2.5))<0.01 and not ends.has("anchor"),"anchor itself is not displaced")
	for label: String in ["near","edge","far_from_caster"]:
		var status := targets[label].get_status_effect_component() as StatusEffectComponent
		_expect(status.get_active_modifier_count()==1 and is_equal_approx(status.get_modified_value(2,4.2),0.42),"formal Q applies composed slow after real arrival: "+label)
	for label: String in ["anchor","outside","behind","disabled","friendly"]:
		_expect(targets[label].get_status_effect_component().get_active_modifier_count()==0,"unpulled target receives no slow: "+label)
	_expect(damage_events == 0,"new Gather has no damage side effect")
	if is_instance_valid(fx):
		fx.set_process(false)
		_expect(fx.global_position.distance_to(Vector3(0,0,-2.5))<0.001,"FX anchored to same frozen target center")
		_expect(fx.get_node("VisualRoot/Boundary").global_position.distance_to(Vector3(0,0.04,-2.5))<0.001,"FX selection ring centered at target")
		_expect(is_equal_approx(fx.get_node("VisualRoot/Boundary").scale.x,5.0),"FX reads actual5m radius")
	else:
		_expect(false,"real target Gather release creates reusable convergence FX")
	for label: String in targets:
		_expect(targets[label].get_collision_exceptions().is_empty(),"pull restores own exceptions: "+label)
	_cleanup()
	await _setup()
	anchor = targets.anchor
	hero.get_node("TargetingSystem").request_lock(anchor)
	await _tap(&"player_skill_1")
	anchor.apply_damage(100000)
	await _until(func(): return host.get_active_skill() == null,2.0)
	_expect(accepts[0] == 1 and releases[0] == 0 and host.get_regular_skill(0).is_ready(),"target death during cast cancels without release/cooldown")
	_cleanup()
	await _test_composed_visual_centers()
	var old := load("res://SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn").instantiate() as SkillBase
	_expect(old.target_relations == TargetResolver.TargetRelationFlag.SELF and old.skill_id == &"player_gather","old skill remains independent self-centered content")
	old.free()
	var preview: Node = load("res://Effects/Skills/TargetGather/TargetGatherEffectPreview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	_expect(preview.get_node_or_null("Target") != null,"target Gather preview exposes independent target")
	preview.free()
	await process_frame
	_finish()

# 选怪圆心与拉拽落点是可独立组装的职责；表现不能把两者强制绑定为同一种模式。
func _test_composed_visual_centers() -> void:
	var scope := Node3D.new()
	root.add_child(scope)
	var caster := Node3D.new()
	scope.add_child(caster)
	caster.position=Vector3(4,0,2)
	var target := Node3D.new()
	scope.add_child(target)
	target.position=Vector3(0,0,-2)
	var skill := load("res://SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn").instantiate() as SkillBase
	caster.add_child(skill)
	skill.delivery=skill.delivery.duplicate()
	var pull := skill.get_node("PullTargetSkillEffect") as PullTargetSkillEffect
	pull.front_distance_m=1.5
	skill.delivery.center_forward_offset_m=3
	var player := SkillReleasePresentationPlayer.new()
	scope.add_child(player)
	var visuals: Array[Node3D]=[]
	player.release_instance_prepared.connect(func(_fact,visual): visuals.append(visual))
	for index: int in range(2):
		skill.delivery.target_collection_mode=2 if index==0 else 1
		pull.center_mode=0 if index==0 else 1
		var context := SkillContext.new()
		context.caster=caster
		context.resolved_target=target
		context.target_position=Vector3(0,0,-2)
		context.release_caster_position=Vector3(4,0,2)
		context.release_facing_direction=Vector3.RIGHT
		context.delivery_parent=scope
		var fact := SkillPresentationContext.create(skill,context,Transform3D.IDENTITY)
		var snapshot := player.prepare_release(context,Transform3D.IDENTITY,skill.release_effect_scene,0,null,null,fact)
		player.play_release(snapshot)
		var visual: Node3D=visuals.back()
		visual.set_process(false)
		var expected_boundary := Vector3(0,0.04,-2) if index==0 else Vector3(7,0.04,2)
		var expected_destination := Vector3(5.5,0.06,2) if index==0 else Vector3(0,0.06,-2)
		_expect(visual.get_node("VisualRoot/Boundary").global_position.distance_to(expected_boundary)<0.001,"mixed components preserve independently configured selection center "+str(index))
		_expect(visual.get_node("VisualRoot/Destination").global_position.distance_to(expected_destination)<0.001,"mixed components preserve independently configured pull center "+str(index))
		visual.free()
	scope.free()
	await process_frame

# 玩家没有自动接近：合法锁定但超出技能射程必须立即拒绝，不能悄悄占槽等待。
func _test_out_of_range_rejects_without_queue() -> void:
	await _setup()
	host.get_regular_skill(0).cast_range=1.0
	_expect(hero.get_node("TargetingSystem").request_lock(targets.anchor),"out-of-range fixture still has legal player lock")
	_expect(not controller.request_slot(0),"out-of-range player request rejects rather than queues")
	_expect(accepts[0]==0 and host.get_active_skill()==null and host.get_regular_skill(0).is_ready(),"range rejection leaves no action slot/cooldown")
	hero.position=Vector3(0,0,-2.2)
	hero.get_node("TargetingSystem").clear_locked_target()
	await _until(func(): return releases[0]>0,0.5)
	_expect(releases[0]==0 and host.get_active_skill()==null,"moving close after clearing lock cannot revive rejected request")
	await _tap(&"player_skill_2")
	_expect(accepts[1]==1,"range rejection does not block independent self E")
	_cleanup()

func _setup() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	hero = load("res://UnitSystem/Player/Hero/Hero.tscn").instantiate()
	world.add_child(hero)
	hero.set_physics_process(false)
	hero.gravity_multiplier = 0
	host = hero.get_node("SkillHost")
	host.global_cooldown_duration = 0
	controller = hero.get_node("PlayerSkillController")
	accepts = [0,0]
	releases = [0,0]
	ends.clear()
	targets.clear()
	damage_events = 0
	release_position = Vector3.INF
	fx = null
	var points := {"anchor":Vector3(0,0,-3),"near":Vector3(2,0,-3),"edge":Vector3(4.95,0,-3),"outside":Vector3(5.2,0,-3),"behind":Vector3(0,0,3),"far_from_caster":Vector3(0,0,-6),"disabled":Vector3(-1,0,-3),"friendly":Vector3(-2,0,-3)}
	for label: String in points:
		var body := load("res://UnitSystem/Base/AIUnitBase.tscn").instantiate() as AIUnitBase
		body.name = label
		body.position = points[label]
		body.team_id = 1 if label == "friendly" else 2
		body.collision_mask = 0
		body.gravity_multiplier = 0
		body.forced_movement_enabled = label != "disabled"
		world.add_child(body)
		body.add_to_group(&"enemy_targets")
		body.forced_movement_finished.connect(func(_token,reason): ends[label]={"reason":reason,"position":body.global_position})
		body.damage_resolved.connect(func(_event): damage_events+=1)
		targets[label] = body
	await process_frame
	await process_frame
	controller.slot_accepted.connect(func(slot,_skill): accepts[slot]+=1)
	for slot: int in range(2):
		host.get_regular_skill(slot).release_started.connect(func(context):
			releases[slot]+=1
			if slot == 0: release_position=context.target_position)
	host.get_regular_skill(0).release_instance_prepared.connect(func(_fact,visual): fx=visual)

func _cleanup() -> void:
	world.free()
	current_scene = null
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
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _finish() -> void:
	for label: String in failures: printerr("FAIL: ",label)
	print("TargetGatherSkillTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
