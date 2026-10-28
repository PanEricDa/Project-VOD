extends SceneTree
## 快照、逐Effect适用性和真实聚拢验证；不以源码文本替代行为。
const PULL_PATH := "res://SkillSystem/03-Extensions/PullTargetSkillEffect.gd"
var failures: Array[String] = []
class RecordingEffect:
	extends SkillEffectBase
	var targets: Array[Node3D] = []
	var contexts: Array[SkillContext] = []
	var fail: bool = false
	func apply(context: SkillContext, _result: SkillDeliveryResult, target: Node3D) -> bool:
		targets.append(target)
		contexts.append(context.duplicate_context())
		return not fail
class SkipEffect:
	extends SkillEffectBase
	var calls := 0
	func can_apply_to(_context: SkillContext, _result: SkillDeliveryResult, _target: Node3D) -> bool: return false
	func apply(_context: SkillContext, _result: SkillDeliveryResult, _target: Node3D) -> bool:
		calls += 1
		return true
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _unit(world: Node, at: Vector3, team: int) -> UnitBase:
	var unit := UnitBase.new()
	unit.position = at
	unit.team_id = team
	world.add_child(unit)
	return unit
func _ai(world: Node, at: Vector3, receiver_enabled: bool = true):
	var unit = load("res://UnitSystem/Base/AIUnitBase.tscn").instantiate()
	unit.position = at
	unit.team_id = 2
	unit.gravity_multiplier = 0
	unit.collision_mask = 0
	unit.forced_movement_enabled = receiver_enabled
	world.add_child(unit)
	return unit
func _context(caster: Node3D, world: Node, target: Node3D = null) -> SkillContext:
	var ctx := SkillContext.new()
	ctx.caster = caster
	ctx.requested_target = caster if target == null else target
	ctx.resolved_target = ctx.requested_target
	ctx.explicit_target_requested = true
	ctx.delivery_parent = world
	ctx.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
	ctx.activation_transform = caster.global_transform
	return ctx
func _config() -> InstantTargetDeliveryConfig:
	var config := InstantTargetDeliveryConfig.new()
	config.target_collection_mode = InstantTargetDeliveryConfig.TargetCollectionMode.CASTER_RADIUS
	config.candidate_source = InstantTargetDeliveryConfig.CandidateSource.WORLD_SCOPE
	config.effect_radius = 5
	return config
func _skill(world: Node, caster: UnitBase, effect: SkillEffectBase) -> SkillBase:
	var skill := load("res://SkillSystem/01-Core/SkillBase.tscn").instantiate() as SkillBase
	skill.skill_cooldown = 0
	skill.target_relations = TargetResolver.TargetRelationFlag.SELF
	skill.delivery = _config()
	skill.add_child(effect)
	world.add_child(skill)
	skill.configure_owner(caster,null,world)
	return skill
func _frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world,Vector3(0,0,4),1)
	var visual := Node3D.new()
	visual.name = "Visual"
	caster.add_child(visual)
	var animated := Node3D.new()
	animated.name = "CharacterRoot"
	visual.add_child(animated)
	var socket := Node3D.new()
	socket.name = "WeaponSocket"
	animated.add_child(socket)
	_check(caster.has_method("get_facing_direction"),"UnitBase exposes stable facing")
	if caster.has_method("get_facing_direction"):
		animated.rotation.y = PI
		socket.rotation.y = PI/2
		_check(caster.call("get_facing_direction").dot(Vector3.FORWARD)>0.999,"weapon/CharacterRoot animation cannot rotate gather facing")
		visual.rotation.y = PI/2
		_check(caster.call("get_facing_direction").dot(Vector3.LEFT)>0.999,"Visual rotation controls actual facing")
		visual.rotation.y = 0
	var target := _unit(world,Vector3(-2,0,1),2)
	var recorder := RecordingEffect.new()
	var skill := _skill(world,caster,recorder)
	skill.delivery_started.connect(func(_ctx: SkillContext):
		caster.position = Vector3(20,0,4)
		visual.rotation.y = PI/2
	)
	_check(skill.activate(_context(caster,world)),"direct release uses common pipeline")
	_check(recorder.contexts.size()==1,"snapshot delivered to effect")
	if not recorder.contexts.is_empty():
		var captured := recorder.contexts[0]
		_check(captured.get("release_caster_position")==Vector3(0,0,4),"delivery callbacks cannot change captured release origin")
		_check(captured.get("release_facing_direction")==Vector3.FORWARD,"copied context preserves frozen facing")
	caster.position = Vector3(2,0,4)
	target.position = Vector3(1,0,1)
	skill.activate(_context(caster,world))
	if recorder.contexts.size()==2:
		_check(recorder.contexts[1].get("release_caster_position")==Vector3(2,0,4) and recorder.contexts[1].get("release_facing_direction").is_equal_approx(Vector3.LEFT),"each DIRECT_TRIGGER release recaptures instead of inheriting old snapshot")
	skill.free()
	caster.position = Vector3(0,0,4)
	visual.rotation.y = 0
	var runner := SkillDeliveryRunner.new()
	world.add_child(runner)
	var skipped := SkipEffect.new()
	var applied := RecordingEffect.new()
	world.add_child(skipped)
	world.add_child(applied)
	var results: Array[SkillDeliveryResult] = []
	var failed: Array[StringName] = []
	runner.delivery_finished.connect(func(_ctx: SkillContext,result: SkillDeliveryResult): results.append(result))
	runner.delivery_failed.connect(func(_ctx: SkillContext,reason: StringName): failed.append(reason))
	var effects: Array[SkillEffectBase] = [skipped,applied]
	runner.execute(_config(),_context(caster,world),caster.global_transform,effects)
	_check(skipped.calls==0 and applied.targets.size()==1,"inapplicable effect skips only itself, not other effects")
	_check(results.size()==1 and results[0].affected_targets==[target],"affected targets count successful application once")
	effects = [skipped]
	_check(not runner.execute(_config(),_context(caster,world),caster.global_transform,effects),"all inapplicable effects reject before acceptance")
	_check(results.size()==1,"rejected all-inapplicable batch emits no successful delivery")
	applied.fail = true
	effects = [applied]
	runner.execute(_config(),_context(caster,world),caster.global_transform,effects)
	_check(failed==[&"instant_effect_failed"],"genuine apply=false retains fail-fast contract")
	applied.fail = false
	var second_target := _unit(world,Vector3(2,0,1),2)
	var deletion: Callable = func(_ctx: SkillContext): target.free()
	runner.delivery_started.connect(deletion,CONNECT_ONE_SHOT)
	applied.targets.clear()
	runner.execute(_config(),_context(caster,world),caster.global_transform,effects)
	_check(applied.targets==[second_target],"target freed in delivery notification skips safely without losing later targets")
	second_target.free()
	_check(not runner.execute(_config(),_context(caster,world),caster.global_transform,effects),"empty radius retains rejected-delivery contract")
	_check(FileAccess.file_exists(PULL_PATH),"generic PullTargetSkillEffect exists")
	if FileAccess.file_exists(PULL_PATH):
		await _test_pull(world,caster,visual)
	await _test_release_callback_lifecycle()
	_test_alive_policy()
	_test_content_empty_and_unsupported()
	_test_forward_radius_selection()
	await _test_mixed_pull_effects()
	world.free()
	await process_frame
	for message: String in failures: printerr("FAIL: ",message)
	print("PullTargetSkillEffectTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _test_pull(world: Node3D, caster: UnitBase, visual: Node3D) -> void:
	caster.position = Vector3(0,0,4)
	visual.rotation.y = 0
	var a = _ai(world,Vector3(-2,0,1))
	var b = _ai(world,Vector3(-3,0,2))
	var outside = _ai(world,Vector3(-5.1,0,4))
	var unsupported = _ai(world,Vector3(1,0,1),false)
	var settled = _ai(world,Vector3(0,0,2.5))
	var pull = load(PULL_PATH).new()
	var skill := _skill(world,caster,pull)
	var affected: Array[Node3D] = []
	var started := [0]
	var damage := [0]
	settled.forced_movement_started.connect(func(_token: int): started[0]+=1)
	for unit: UnitBase in [a,b,outside,unsupported,settled]:
		unit.damage_resolved.connect(func(_event): damage[0]+=1)
	skill.delivery_started.connect(func(_ctx: SkillContext):
		caster.position = Vector3(20,0,4)
		visual.rotation.y = PI/2
	)
	skill.delivery_finished.connect(func(_ctx: SkillContext,result: SkillDeliveryResult): affected.assign(result.affected_targets))
	_check(skill.activate(_context(caster,world)),"gather release accepted")
	_check(affected.size()==3 and affected.has(a) and affected.has(b) and affected.has(settled),"mixed receivers skip only unsupported/out-of-radius targets")
	await _frames(24)
	var center := Vector3(0,0,2.5)
	_check(a.position.distance_to(center)<=0.68 and b.position.distance_to(center)<=0.68,"all targets converge to same frozen front disk despite caster callback movement")
	_check(outside.position==Vector3(-5.1,0,4) and unsupported.position==Vector3(1,0,1),"5.1m/unsupported control targets remain unmoved")
	_check(settled.position==center and started[0]==0,"already gathered target succeeds without a new movement request")
	_check(damage[0]==0 and is_equal_approx(a.get_current_health(),a.get_maximum_health()),"pull creates no damage or focus-generating damage event")
	# 真实CHARACTER_ACTION也必须在release帧取当前位置，而不是请求时。
	caster.position = Vector3.ZERO
	visual.rotation.y = PI/2
	skill.delivery_started.disconnect(skill.delivery_started.get_connections()[0].callable)
	var recording := RecordingEffect.new()
	skill.add_child(recording)
	_check(skill.activate(_ordinary_context(caster,world)),"ordinary action request accepted")
	_check(skill.confirm_action_started(caster.global_transform),"ordinary action confirmed")
	caster.position = Vector3(1,0,0)
	_check(skill.release_action(caster.global_transform),"ordinary release accepted")
	_check(not recording.contexts.is_empty() and recording.contexts[0].get("release_caster_position")==Vector3(1,0,0),"ordinary cast snapshots actual release position instead of request position")
	# 无效参数属于真正执行失败，不误装为“不支持目标”。
	pull.duration_seconds = 0
	var ctx := _context(caster,world)
	ctx.set("release_caster_position",caster.position)
	ctx.set("release_facing_direction",Vector3.LEFT)
	_check(pull.can_apply_to(ctx,SkillDeliveryResult.new(),a) and not pull.apply(ctx,SkillDeliveryResult.new(),a),"invalid pull parameters remain a real apply failure")

# 实际Pull与另一Effect同批：禁用外力仅跳过Pull；已经在盘内合法完成，其他效果不丢失。
func _test_mixed_pull_effects() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world,Vector3.ZERO,1)
	var movable = _ai(world,Vector3(-2,0,-1))
	var unsupported = _ai(world,Vector3(2,0,-1),false)
	var duplicate = _ai(world,Vector3(0,0,-1.5))
	var pull = load(PULL_PATH).new()
	var skill := _skill(world,caster,pull)
	var recording := RecordingEffect.new()
	skill.add_child(recording)
	var affected: Array[Node3D] = []
	skill.delivery_finished.connect(func(_ctx,result):affected.assign(result.affected_targets))
	_check(skill.activate(_context(caster,world)),"mixed pull/other-effect batch accepts")
	_check(recording.targets.size()==3 and affected.size()==3 and recording.targets.has(unsupported) and recording.targets.has(duplicate),"skipping Pull still applies other effect once to each unsupported target")
	await _frames(24)
	_check(movable.position.distance_to(Vector3(0,0,-1.5))<0.68,"mixed batch still moves supported target")
	_check(unsupported.position==Vector3(2,0,-1) and duplicate.position==Vector3(0,0,-1.5),"disabled target is skipped and already settled target stays in place")
	world.free()

# 正式聚拢场景保留继承/通用装配；无人可拉时不能伪报成功并启动成功释放冷却。
func _test_content_empty_and_unsupported() -> void:
	var packed := load("res://SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn") as PackedScene
	_check(packed.get_state().get_base_scene_state()!=null,"Gather is a native inherited SkillBase scene")
	_check(ResourceLoader.get_resource_uid("res://SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn")!=ResourceUID.INVALID_ID,"native Gather scene has registered UID")
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world,Vector3.ZERO,1)
	var unsupported := _unit(world,Vector3(0,0,-2),2)
	unsupported.forced_movement_enabled = false
	var gather := packed.instantiate() as SkillBase
	world.add_child(gather)
	gather.configure_owner(caster,null,world)
	var accepted := [0]
	gather.delivery_started.connect(func(_ctx): accepted[0]+=1)
	_check(not gather.activate(_context(caster,world)) and gather.is_ready() and accepted[0]==0,"only unsupported targets reject without successful cooldown/acceptance")
	unsupported.free()
	_check(not gather.activate(_context(caster,world)) and gather.is_ready() and accepted[0]==0,"empty radius rejects without successful cooldown/acceptance")
	world.free()

# 通用瞬发保留SkillBase显式尸体目标合法性；普通存活要求仍跳过通知中刚死亡的目标。
func _test_alive_policy() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world,Vector3.ZERO,1)
	var corpse := _unit(world,Vector3(0,0,-2),2)
	corpse.apply_damage(1000)
	var record := RecordingEffect.new()
	var skill := _skill(world,caster,record)
	skill.target_relations = TargetResolver.TargetRelationFlag.HOSTILE
	skill.delivery = InstantTargetDeliveryConfig.new()
	_check(not skill.activate(_context(caster,world,corpse)),"normal require-alive skill rejects corpse")
	skill.require_alive = false
	skill.require_targetable = false
	_check(skill.activate(_context(caster,world,corpse)) and record.targets==[corpse],"authorized SINGLE corpse effect is applied when require_alive=false")
	skill.require_alive = true
	var living := _unit(world,Vector3(0,0,-2),2)
	record.targets.clear()
	skill.delivery_started.connect(func(_ctx): living.apply_damage(1000),CONNECT_ONE_SHOT)
	_check(skill.activate(_context(caster,world,living)) and record.targets.is_empty(),"require-alive target dying after acceptance is safely skipped")
	world.free()

# 释放前通知属于公开边界：删除施法者或同步取消/重入不得读取失效快照或清掉新请求。
func _test_release_callback_lifecycle() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world,Vector3.ZERO,1)
	_unit(world,Vector3(0,0,-2),2)
	var skill := _skill(world,caster,RecordingEffect.new())
	skill.release_started.connect(func(_ctx): caster.free(),CONNECT_ONE_SHOT)
	_check(not skill.activate(_context(caster,world)),"caster removed in release callback rejects safely before snapshot")
	world.free()
	world = Node3D.new()
	root.add_child(world)
	caster = _unit(world,Vector3.ZERO,1)
	_unit(world,Vector3(0,0,-2),2)
	var record := RecordingEffect.new()
	skill = _skill(world,caster,record)
	var entered := [false]
	skill.release_started.connect(func(_ctx):
		if entered[0]: return
		entered[0] = true
		skill.cancel_skill()
		skill.activate(_ordinary_context(caster,world))
	)
	_check(not skill.activate(_context(caster,world)),"cancelled old release stops before delivery")
	_check(skill.get_state()==SkillBase.SkillState.ACTION_REQUESTED and record.targets.is_empty(),"old release cannot consume/clear reentrant new ordinary action")
	skill.cancel_skill()
	world.free()

# 真实交付验证前移圆心、转向及释放快照；忽略偏移/朝向或改回玩家圆心都会漏选或误选。
func _test_forward_radius_selection() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world,Vector3.ZERO,1)
	var front := _unit(world,Vector3(0,0,-2.7),2)
	var rear := _unit(world,Vector3(0,0,1.5),2)
	var left := _unit(world,Vector3(-2.7,0,0),2)
	var record := RecordingEffect.new()
	world.add_child(record)
	var runner := SkillDeliveryRunner.new()
	world.add_child(runner)
	var config := _config()
	config.effect_radius = 2.0
	config.set("center_forward_offset_m",0.8)
	var effects: Array[SkillEffectBase] = [record]
	var ctx := _context(caster,world)
	ctx.release_caster_position = Vector3.ZERO
	ctx.release_facing_direction = Vector3.FORWARD
	caster.position = Vector3(10,0,0)
	_check(runner.execute(config,ctx,caster.global_transform,effects),"offset radius uses frozen release center after caster moves")
	_check(record.targets==[front],"front 2.7m is included; rear 1.5m and left 2.7m are excluded")
	record.targets.clear()
	ctx.release_facing_direction = Vector3.LEFT
	runner.execute(config,ctx,caster.global_transform,effects)
	_check(record.targets==[rear,left],"forward offset rotates with frozen facing; the rear fixture is also inside the left-centered disk")
	caster.position = Vector3.ZERO
	record.targets.clear()
	runner.execute(config,_context(caster,world),caster.global_transform,effects)
	_check(record.targets==[front],"contexts without release snapshot use current stable unit facing")
	config.set("center_forward_offset_m",0.0)
	record.targets.clear()
	runner.execute(config,_context(caster,world),caster.global_transform,effects)
	_check(record.targets==[rear],"zero default preserves caster-centered radius")
	var gather := load("res://SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn").instantiate() as SkillBase
	var gather_record := RecordingEffect.new()
	gather.add_child(gather_record)
	world.add_child(gather)
	gather.configure_owner(caster,null,world)
	var movable = _ai(world,Vector3(0,0,-2.7))
	_check(gather.activate(_context(caster,world)) and gather_record.targets.has(movable) and not gather_record.targets.has(rear),"configured Gather selects forward radius, not old 5m caster radius")
	world.free()

func _ordinary_context(caster: UnitBase, world: Node) -> SkillContext:
	var ctx := _context(caster,world)
	ctx.execution_mode = SkillContext.ExecutionMode.CHARACTER_ACTION
	return ctx
