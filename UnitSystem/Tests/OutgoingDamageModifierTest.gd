extends SceneTree

## 防止增伤漏掉基础伤害、重复放大，或误增强治疗；验证状态刷新、到期和死亡清理。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	if not StatusEffectComponent.ModifierStat.has("OUTGOING_DAMAGE"):
		printerr("FAIL: generic outgoing damage modifier is missing")
		quit(1)
		return
	var world := Node3D.new()
	root.add_child(world)
	var source := _unit(world)
	var target := _unit(world)
	source.attack_power = 20
	target.defense = 100
	var status: StatusEffectComponent = source.get_status_effect_component()
	status.set_physics_process(false)
	var effect := StatModifierSkillEffect.new()
	effect.modifier_stat = 3
	effect.modifier_mode = 1
	effect.amount = 30
	effect.duration_seconds = 15
	effect.target_mode = 1
	world.add_child(effect)
	var context := SkillContext.new()
	context.caster = source
	var visual_setting := false
	for property: Dictionary in effect.get_property_list():
		if property.name == "status_visual_scene": visual_setting = true
	_check(visual_setting, "shared modifier supports optional state-owned visual")
	if visual_setting:
		var visual := Node3D.new()
		var packed := PackedScene.new()
		packed.pack(visual)
		visual.free()
		effect.set("status_visual_scene",packed)
	_check(effect.apply(context, null, source), "shared effect accepts outgoing damage modifier")
	_check(is_equal_approx(CombatValueResolver.calculate_damage(source, target, 80, 1),65), "base80 and attack20 both increased30 percent with defense100")
	_check(is_equal_approx(CombatValueResolver.apply_damage(source, target, 80, 1),65), "damage application amplifies exactly once")
	_check(is_equal_approx(source.get_attack_power(),20), "damage buff does not modify attack stat")
	_check(is_equal_approx(CombatValueResolver.calculate_healing(source,80,1),100), "healing is unaffected")
	_check(is_equal_approx(CombatValueResolver.calculate_damage(null,target,100,0),50), "sourceless damage remains unchanged")
	status.advance_effects(10)
	_check(effect.apply(context,null,source), "same effect refresh succeeds")
	_check(status.get_active_modifier_count() == 1, "refresh does not stack")
	status.advance_effects(14.9)
	_check(is_equal_approx(CombatValueResolver.calculate_damage(source,target,100,0),65), "buff survives until refreshed duration")
	status.advance_effects(0.1)
	_check(is_equal_approx(CombatValueResolver.calculate_damage(source,target,100,0),50), "expiry restores original damage")
	effect.apply(context,null,source)
	source.apply_damage(100000)
	_check(status.get_active_modifier_count() == 0, "death clears modifier")
	await process_frame
	if visual_setting:
		var visuals := source.get_node_or_null(^"StatusModifierVisuals")
		_check(visuals != null and visuals.get_child_count() == 0, "death clears state-owned visual")
	world.free()
	await process_frame
	for failure: String in failures: printerr("FAIL: ",failure)
	print("OutgoingDamageModifierTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _unit(world: Node) -> UnitBase:
	var unit := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	unit.maximum_health = 10000
	world.add_child(unit)
	return unit
func _check(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
