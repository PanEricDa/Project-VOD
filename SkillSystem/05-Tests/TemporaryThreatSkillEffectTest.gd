extends SceneTree
## 测真实Effect与正式内容；duration分支、失败回退或来源归属改变应触发失败。
class RejectingStatus:
	extends StatusEffectComponent
	var reject: bool = false
	func prepare_bound_status(id: StringName, source: UnitBase, key: StringName, duration: float, cleanup: Callable) -> int:
		return 0 if reject else super.prepare_bound_status(id,source,key,duration,cleanup)

var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := UnitBase.new()
	caster.team_id = 1
	world.add_child(caster)
	var enemy := load("res://UnitSystem/AI/Enemy/EnemyBase.tscn").instantiate() as EnemyBase
	enemy.team_id = 2
	world.add_child(enemy)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	var threat := enemy.get_threat_component() as EnemyThreatComponent
	threat.threat_half_life = 0
	var status := enemy.get_status_effect_component() as StatusEffectComponent
	var context := SkillContext.new()
	context.caster = caster
	context.delivery_parent = world
	var effect := ThreatChangeSkillEffect.new()
	world.add_child(effect)
	_check(effect.get("duration_seconds")!=null,"effect exposes optional duration")
	if effect.get("duration_seconds")!=null:
		effect.threat_amount = 200
		_check(effect.apply(context,SkillDeliveryResult.new(),enemy) and effect.apply(context,SkillDeliveryResult.new(),enemy) and threat.get_threat_for(caster)==400,"duration0 preserves ordinary repeated fixed contribution")
		effect.set("duration_seconds",8)
		effect.threat_amount = 2000
		_check(effect.apply(context,SkillDeliveryResult.new(),enemy),"positive duration binds state")
		effect.apply(context,SkillDeliveryResult.new(),enemy)
		_check(threat.get_threat_for(caster)==2400 and status.has_named_status(&"temporary_threat"),"repeated timed effect refreshes instead of stacking")
		effect.free()
		status.advance_effects(8.1)
		_check(threat.get_threat_for(caster)==400 and not status.has_named_status(&"temporary_threat"),"binding survives effect deletion and expires independently")
		effect = ThreatChangeSkillEffect.new()
		world.add_child(effect)
		# 可预期的接收方拒绝：不伪造仇恨结果，只拒绝一次状态prepare，验证真实Effect的事务回退。
		status.free()
		var rejecting := RejectingStatus.new()
		rejecting.name = "StatusEffect"
		enemy.add_child(rejecting)
		rejecting.configure_owner(enemy)
		status = rejecting
		effect.threat_amount = 2000
		effect.duration_seconds = 8
		_check(effect.apply(context,SkillDeliveryResult.new(),enemy),"initial timed binding is accepted before rejection")
		rejecting.reject = true
		_check(not effect.apply(context,SkillDeliveryResult.new(),enemy) and threat.get_threat_for(caster)==2400 and status.has_named_status(&"temporary_threat"),"state creation rejection preserves old contribution and state")
		status.advance_effects(8.1)
		rejecting.reject = false
		_check(threat.get_threat_for(caster)==400,"rejected application leaves no hidden pending contribution")
		effect.set("duration_seconds",-1)
		_check(not effect.apply(context,SkillDeliveryResult.new(),enemy) and threat.get_threat_for(caster)==400,"negative duration never silently adds ordinary threat")
		effect.set("duration_seconds",NAN)
		_check(not effect.apply(context,SkillDeliveryResult.new(),enemy),"nonfinite duration rejected")
		var no_receiver := UnitBase.new()
		no_receiver.team_id=2
		world.add_child(no_receiver)
		_check(not effect.can_apply_to(context,SkillDeliveryResult.new(),no_receiver),"unsupported target is inapplicable")
		var path := "res://SkillSystem/00-Skills/Player_ThreatMark/ThreatMarkSkill.tscn"
		_check(FileAccess.file_exists(path),"formal Threat Mark exists")
		if FileAccess.file_exists(path):
			var packed := load(path) as PackedScene
			_check(packed.get_state().get_base_scene_state()!=null,"formal content is native inherited scene")
			_check(ResourceLoader.get_resource_uid(path)!=ResourceUID.INVALID_ID,"formal content has UID")
			var skill := packed.instantiate() as SkillBase
			world.add_child(skill)
			skill.configure_owner(caster,null,world)
			context.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
			context.activation_transform = caster.global_transform
			context.requested_target = caster
			context.resolved_target = caster
			context.explicit_target_requested = true
			_check(skill.activate(context) and threat.get_threat_for(caster)==2400,"formal skill uses normal SkillBase and skips unsupported targets without losing enemy")
			_check(is_equal_approx(skill.get_cooldown_remaining(),12.0),"formal successful E starts configured12s cooldown")
	world.free()
	await process_frame
	for message: String in failures: printerr("FAIL: ",message)
	print("TemporaryThreatSkillEffectTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
