extends SceneTree
## 验证独立场景真实输入→动作→聚拢→物理/冷却；E验证真实限时仇恨，不能以log替代Gameplay。
const SCENE_PATH := "res://Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn"
var _failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var world := load(SCENE_PATH).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await process_frame
	await process_frame
	await _frames(3)
	var hero := world.get_node("Hero") as PlayerBase
	var host := hero.get_node("SkillHost") as SkillHostComponent
	var first := host.get_regular_skill(0)
	var second := host.get_regular_skill(1)
	_expect(first != null and first.skill_id==&"player_target_gather" and second != null and second.skill_id==&"player_threat_mark","Q is Gather and E is the real Threat Mark")
	if first == null or first.skill_id!=&"player_target_gather":
		world.free()
		_finish()
		return
	_expect(world.get_node("PlayerSkillBar").skill_source == hero.get_node("PlayerSkillController"),"HUD uses the one local player controller")
	_expect(world.get_node("ValidationActors").get_child_count()==0 and world.get_node_or_null("SquadChainCommandController")==null,"default training removes unused squad before ready")
	_expect(hero.find_children("*","SkillHostComponent",true,false).size()==1,"one SkillHost")
	_expect(hero.find_children("*","AnimationPlayer",true,false).size()==1,"one shared animation executor")
	_expect(not first.automatic_cast_enabled and not second.automatic_cast_enabled,"player skills never autocast")
	_expect(is_equal_approx(first.skill_cooldown,2.0) and is_equal_approx(second.skill_cooldown,2.0),"both test slots keep two-second cooldown")
	_expect(first.get_node("PullTargetSkillEffect") is SkillEffectBase and first.get_node_or_null("ProbeEffect")==null,"Gather composes a real generic PullEffect without fake probe")
	_expect(first.action_animation==null and second.action_animation==null,"both player skills reuse existing weapon cast action")
	_expect(ResourceLoader.get_resource_uid("res://Scenes/Tests/PlayerSkills/PlayerSkillProbeAction.tres")!=ResourceUID.INVALID_ID,"probe Animation has native UID")
	var formal := load("res://UnitSystem/Player/Hero/Hero.tscn").instantiate() as Node
	_expect(formal.get_node_or_null("PlayerSkillController")!=null and formal.get_node_or_null("PlayerSkillInputComponent")!=null,"formal Hero owns its player skill adapters")
	var formal_host := formal.get_node("SkillHost") as SkillHostComponent
	_expect(formal_host.regular_skills[0]!=null and formal_host.regular_skills[1]!=null,"formal Hero has two real skill slots")
	_expect(is_equal_approx(formal_host.regular_skills[0].skill_cooldown,10.0) and is_equal_approx(formal_host.regular_skills[1].skill_cooldown,12.0),"formal cooldowns remain independent of test overrides")
	formal.free()
	await _test_gather_range_display(world,hero,first,second)
	await _test_navigation(world)
	# 只在测试运行实例中走近现有靶子；OutsideRadius原指玩家圆心范围，如今位于目标5米内，应正常拉入。
	hero.position = Vector3(-1,0,2.8)
	# 只调整本次夹具：关闭外力的靶仍在Q/E范围内，但远离落盘，避免普通碰撞散开把它挤动。
	world.get_node("EnemyContainer/Unsupported").position = Vector3(-1,0,-1.8)
	var before_positions: Dictionary = {}
	var before_health: Dictionary = {}
	var before_threat: Dictionary = {}
	var events := [0]
	var pull_ends: Dictionary = {}
	for enemy: EnemyBase in world.get_node("EnemyContainer").get_children():
		before_positions[enemy.name] = enemy.position
		before_health[enemy.name] = enemy.get_current_health()
		before_threat[enemy.name] = enemy.get_threat_component().get_threat_snapshot()
		_expect(enemy.process_mode==Node.PROCESS_MODE_INHERIT and enemy.collision_mask==5,"training physics enabled with local world/enemy collision")
		_expect(not enemy.get_targeting_component().detection_enabled and enemy.get_behavior_state_machine().idle_behavior==0,"stationary training uses real AI config, not disabled physics")
		enemy.damage_resolved.connect(func(_event): events[0]+=1)
		var receiver: UnitBase = enemy if enemy.forced_movement_enabled else null
		if receiver != null:
			receiver.forced_movement_finished.connect(func(_token: int,reason: StringName): pull_ends[enemy.name]={"position":enemy.global_position,"reason":reason})
		_expect(enemy.forced_movement_enabled == (enemy.name!=&"Unsupported"),"root flag explicitly disables the control target")
	var hero_health := hero.get_current_health()
	hero.damage_resolved.connect(func(_event): events[0]+=1)
	_expect(second.get_node_or_null("ProbeEffect")==null and second.get_node_or_null("ThreatChangeSkillEffect")!=null,"E has a real threat Effect and no gameplay probe")
	_expect(hero.get_node("TargetingSystem").request_lock(world.get_node("EnemyContainer/TrainingMelee")),"new Q has actual explicit lock")
	await _tap(&"player_skill_1")
	await _until(func(): return world.get_status_snapshot().slots[0].finished==1,1500)
	var status: Dictionary = world.get_status_snapshot()
	_expect(status.slots[0].accepted==1 and status.slots[0].started==1 and status.slots[0].released==1 and status.slots[0].finished==1,"Q input accepted/start/release/finish exactly once")
	_expect(status.slots[0].affected==3,"five-meter target circle includes anchor, ranged and old caster-radius control")
	_expect(first.get_cooldown_remaining()>1.0 and first.get_cooldown_remaining()<=2.0,"Q release starts two-second cooldown")
	await _tap(&"player_skill_1")
	_expect(world.get_status_snapshot().last_reason==&"skill_unavailable","cooldown rejects duplicate input")
	await _frames(20)
	var enemies := world.get_node("EnemyContainer")
	var center := before_positions[&"TrainingMelee"] as Vector3
	for label: String in ["TrainingRanged","OutsideRadius"]:
		var enemy := enemies.get_node(label) as Node3D
		var terminal: Dictionary = pull_ends.get(enemy.name,{})
		_expect(terminal.get("reason")==&"arrived" and Vector2(terminal.position.x-center.x,terminal.position.z-center.z).length()<0.03,"Q ignores bodies and nearby target arrives at frozen locked-target position")
		_expect(not enemy.is_forced_movement_active() and enemy.get_collision_exceptions().is_empty(),"pull completion restores normal collisions and clears external motion")
	var blocked := enemies.get_node("WallBlocked") as Node3D
	_expect(Vector2(blocked.position.x-before_positions[blocked.name].x,blocked.position.z-before_positions[blocked.name].z).length()<0.01,"wall control is now outside the smaller selection disk and remains unmoved")
	for label: String in ["Unsupported"]:
		var enemy := enemies.get_node(label) as Node3D
		_expect(Vector2(enemy.position.x-before_positions[enemy.name].x,enemy.position.z-before_positions[enemy.name].z).length()<0.01,"outside/unsupported control does not move: %s %s -> %s" % [label,before_positions[enemy.name],enemy.position])
	await _until(func(): return host.is_global_cooldown_ready(),1500)
	await _tap(&"player_skill_2")
	await _until(func(): return world.get_status_snapshot().slots[1].finished==1,1500)
	status = world.get_status_snapshot()
	_expect(status.slots[1].accepted==1 and status.slots[1].released==1 and status.slots[1].finished==1 and status.slots[1].affected==5,"E routes through its real radius delivery exactly once")
	_expect(second.get_cooldown_remaining()>1.0 and second.get_cooldown_remaining()<=2.0,"E has independent two-second cooldown")
	for enemy: EnemyBase in enemies.get_children():
		_expect(is_equal_approx(enemy.get_current_health(),before_health[enemy.name]),"Q and E cause no enemy damage")
		_expect(enemy.get_threat_component().get_threat_for(hero)>1900 and enemy.get_status_effect_component().has_named_status(&"temporary_threat") and enemy.get_targeting_component().get_locked_target()==null,"E creates real temporary threat while training detection stays disabled")
	_expect(events[0]==0 and is_equal_approx(hero.get_current_health(),hero_health),"no damage/focus/chain-generating event")
	await _until(func(): return first.is_ready() and host.is_global_cooldown_ready(),2500)
	await _tap(&"player_skill_1")
	await _until(func(): return world.get_status_snapshot().slots[0].finished==2,1500)
	_expect(world.get_status_snapshot().slots[0].released==2,"Q can be used again after two seconds")
	await _frames(24)
	await _until(func(): return second.is_ready() and host.is_global_cooldown_ready(),2500)
	await _tap(&"player_skill_2")
	await _until(func(): return world.get_status_snapshot().slots[1].finished==2,1500)
	_expect(world.get_status_snapshot().slots[1].released==2,"E repeats after its two-second cooldown")
	for enemy: EnemyBase in enemies.get_children():
		_expect(enemy.get_threat_component().get_threat_for(hero)<2001,"repeated E refresh never doubles the temporary amount")
		enemy.get_status_effect_component().advance_effects(8.1)
		_expect(enemy.get_threat_component().get_threat_for(hero)==0 and not enemy.get_status_effect_component().has_named_status(&"temporary_threat"),"E expires without permanent threat residue")
	# 只在本次临时测试实例开启真实敌人AI，验证外力退出后追击与攻击恢复。
	var melee := enemies.get_node("TrainingMelee") as EnemyBase
	melee.get_targeting_component().detection_enabled = true
	melee.get_targeting_component().refresh_target()
	var health_before := hero.get_current_health()
	await _until(func(): return hero.get_current_health()<health_before,5000)
	_expect(melee.get_targeting_component().get_locked_target()==hero and hero.get_current_health()<health_before,"real enemy AI resumes targeting/attacks after forced movement")
	await _test_target_handoff(world,hero,melee)
	world.free()
	current_scene = null
	await process_frame
	_finish()

# 真实Hero输入、Guardian源实例、敌人感知Area和原resolve_target；只冻结夹具移动/输出，避免击杀污染接管验证。
func _test_target_handoff(world: Node3D, hero: PlayerBase, enemy: EnemyBase) -> void:
	enemy.set_physics_process(false)
	var guardian := load("res://UnitSystem/AI/Ally/Units/Guardian.tscn").instantiate() as AllyBase
	guardian.name = "HandoffGuardian"
	guardian.automatic_skill_cast_enabled = false
	guardian.position = enemy.position+Vector3(1.5,0,0)
	world.add_child(guardian)
	guardian.set_physics_process(false)
	guardian.get_combat_system().set_physics_process(false)
	hero.position = enemy.position+Vector3(-1.5,0,0)
	enemy.get_targeting_component().detection_enabled = true
	await _frames(6)
	var threat := enemy.get_threat_component() as EnemyThreatComponent
	threat.clear_threat()
	threat.submit_threat(ThreatEvent.create_damage(guardian,400))
	enemy.refresh_targeting()
	_expect(enemy.get_targeting_component().get_locked_target()==guardian,"ordinary400 establishes Guardian as current target using real perception: candidates %s / target %s / ratio %s" % [enemy.get_targeting_component().get_perceived_candidates(),enemy.get_targeting_component().get_locked_target(),threat.get_threat_snapshot()])
	var host := hero.get_node("SkillHost") as SkillHostComponent
	var skill := host.get_regular_skill(1)
	await _until(func(): return skill.is_ready() and host.is_global_cooldown_ready(),2500)
	var previous: int = world.get_status_snapshot().slots[1].released
	await _tap(&"player_skill_2")
	await _until(func(): return world.get_status_snapshot().slots[1].released>previous,1500)
	_expect(threat.get_threat_for(hero)>1900 and enemy.get_targeting_component().get_locked_target()==hero,"actual E input makes enemy select player through ordinary threat comparison")
	enemy.get_status_effect_component().advance_effects(8.1)
	_expect(threat.get_threat_for(hero)==0 and threat.get_threat_for(guardian)>390 and enemy.get_targeting_component().get_locked_target()==guardian,"expiry removes E only and real AI returns to Guardian ordinary threat")

# 退回E参数、遗漏偏移或使用动画骨架朝向，都会使可见圆心/半径与真实Q范围不符。
func _test_gather_range_display(world: Node3D, hero: PlayerBase, first: SkillBase, second: SkillBase) -> void:
	var ring := world.get_node("GatherRangeDebug") as MeshInstance3D
	var config := first.delivery as InstantTargetDeliveryConfig
	var radius := config.effect_radius
	var offset := config.center_forward_offset_m
	var target := world.get_node("EnemyContainer/TrainingMelee") as UnitBase
	var target_position := target.position
	_expect(not ring.visible,"no lock hides target-centered preview")
	_expect(hero.get_node("TargetingSystem").request_lock(target),"range preview has a real lock")
	await process_frame
	await process_frame
	_expect(ring.visible and ring.global_position.distance_to(target.global_position+Vector3(0,0.025,0))<0.01,"Q preview centers on actual locked enemy")
	var torus := ring.mesh as TorusMesh
	_expect(absf((torus.inner_radius+torus.outer_radius)*0.5-5.0)<0.001,"new Q visible radius5")
	config.effect_radius = 3.0
	config.center_forward_offset_m = 9.0
	target.position += Vector3(0.3,0,0)
	hero.get_node("Visual").rotation.y=PI/2
	await process_frame
	await process_frame
	_expect(ring.global_position.distance_to(target.global_position+Vector3(0,0.025,0))<0.01,"target mode ignores caster facing/forward offset")
	_expect(absf((torus.inner_radius+torus.outer_radius)*0.5-3.0)<0.001,"Q preview reads its own configured radius")
	_expect(second.delivery.target_collection_mode==InstantTargetDeliveryConfig.TargetCollectionMode.CASTER_RADIUS,"E keeps own caster-centered delivery")
	hero.get_node("TargetingSystem").clear_locked_target()
	await process_frame
	_expect(not ring.visible,"clearing lock hides Q preview")
	config.effect_radius=radius
	config.center_forward_offset_m=offset
	target.position=target_position
	hero.get_node("Visual").rotation=Vector3.ZERO

func _test_navigation(world: Node3D) -> void:
	var region := world.get_node("NavigationRegion3D") as NavigationRegion3D
	_expect(region.navigation_mesh!=null and region.navigation_mesh.get_polygon_count()>0,"navigation is baked")
	await _frames(3)
	var map := region.get_navigation_map()
	var start := NavigationServer3D.map_get_closest_point(map,Vector3(-4,0,-2))
	var goal := NavigationServer3D.map_get_closest_point(map,Vector3(4,0,-2))
	var path := NavigationServer3D.map_get_path(map,start,goal,true)
	_expect(path.size()>1 and path[0].distance_to(start)<0.2 and path[path.size()-1].distance_to(goal)<0.2,"navigation yields traversable path")
	var wall_center := NavigationServer3D.map_get_closest_point(map,Vector3(2,0,0))
	_expect(Vector2(wall_center.x-2.0,wall_center.z).length()>0.7,"wall excluded from navigation")
func _frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame
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
func _until(predicate: Callable, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec()+timeout_ms
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
func _expect(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)
func _finish() -> void:
	for message: String in _failures: printerr("FAIL: ",message)
	print("PlayerSkillTestSceneTest: ","PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)
