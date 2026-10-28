extends SceneTree
## 百分比修正须动态作用于基础值与固定修正之和；同来源刷新、到期、死亡均沿旧状态生命周期。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var target := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	target.defense = 80.0
	target.attack_power = 40.0
	world.add_child(target)
	var status := target.get_status_effect_component()
	status.set_physics_process(false)
	var effect := StatModifierSkillEffect.new()
	world.add_child(effect)
	var has_mode: bool = effect.get_property_list().any(func(p): return p.name == &"modifier_mode")
	_expect(has_mode, "stat effect must configure flat or percentage mode")
	_expect(status.has_method("get_modified_value"), "status container must resolve dynamic percentage modifiers")
	if not has_mode or not status.has_method("get_modified_value"):
		world.free()
		_finish()
		return
	effect.target_mode = StatModifierSkillEffect.TargetMode.DELIVERY_TARGET
	effect.modifier_stat = StatModifierSkillEffect.ModifierStat.DEFENSE
	effect.set("modifier_mode",1)
	effect.amount = -25.0
	effect.duration_seconds = 15.0
	var ctx := SkillContext.new()
	ctx.caster = target
	_expect(effect.apply(ctx,SkillDeliveryResult.new(),target), "percentage debuff is accepted through existing effect")
	_expect(is_equal_approx(target.get_defense(),60.0) and target.defense == 80.0, "80 defense becomes60 without rewriting base")
	var flat_source := Node.new()
	world.add_child(flat_source)
	_expect(status.apply_modifier(flat_source,1,20.0,30.0,0), "legacy five-argument flat call remains valid")
	_expect(is_equal_approx(target.get_defense(),75.0), "fixed bonus is included before percentage")
	target.defense = 120.0
	_expect(is_equal_approx(target.get_defense(),105.0), "later base changes remain scaled rather than using a stale snapshot")
	_expect(is_equal_approx(status.get_modifier_total(1),20.0), "legacy additive query excludes percentage points")
	status.advance_effects(10.0)
	_expect(effect.apply(ctx,SkillDeliveryResult.new(),target), "reapplication accepted")
	_expect(status.get_active_modifier_count() == 2 and is_equal_approx(target.get_defense(),105.0), "same source refreshes instead of stacking armor reduction")
	status.advance_effects(14.9)
	_expect(is_equal_approx(target.get_defense(),105.0), "refreshed debuff lasts beyond old expiry")
	status.advance_effects(0.1)
	_expect(is_equal_approx(target.get_defense(),140.0), "15 seconds removes only percentage while longer flat buff remains")
	var power_source := Node.new()
	world.add_child(power_source)
	_expect(status.call("apply_modifier",power_source,0,20.0,10.0,0,1), "same general operation supports attack percentage")
	_expect(is_equal_approx(target.get_attack_power(),48.0), "attack getter shares percentage resolver")
	status.clear_all_modifiers()
	status.call("apply_modifier",power_source,1,-150.0,10.0,0,1)
	_expect(is_zero_approx(target.get_defense()), "over100 percent reduction clamps to zero")
	status.clear_all_modifiers()
	# 同一来源可同时持有固定值和百分比；各自刷新数值而不误覆盖另一种模式。
	status.apply_modifier(flat_source,1,20.0,10.0)
	status.apply_modifier(flat_source,1,15.0,10.0)
	status.apply_modifier(flat_source,1,-25.0,10.0,0,1)
	status.apply_modifier(flat_source,1,-40.0,10.0,0,1)
	_expect(status.get_active_modifier_count() == 2 and is_equal_approx(target.get_defense(),81.0), "flat and percentage refresh update amounts independently for the same source")
	_expect(is_equal_approx(status.get_modifier_total(1),15.0), "legacy flat refresh replaces rather than adds")
	status.clear_all_modifiers()
	for value: float in [NAN,INF]:
		_expect(not status.call("apply_modifier",power_source,1,value,10.0,0,1), "invalid modifier amount rejected")
		_expect(not status.call("apply_modifier",power_source,1,-25.0,value,0,1), "invalid duration rejected")
	_expect(not status.call("apply_modifier",power_source,1,-25.0,10.0,0,99), "unknown mode rejected")
	effect.apply(ctx,SkillDeliveryResult.new(),target)
	target.apply_damage(999999.0,target)
	_expect(status.get_active_modifier_count() == 0 and is_equal_approx(target.get_defense(),120.0), "death clears percentage using existing cleanup")
	world.free()
	await process_frame
	_finish()
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for failure: String in failures: push_error(failure)
	print("PercentageStatModifierTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
