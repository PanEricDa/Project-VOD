extends SceneTree

## 验证技能只经公开状态效果接口提交临时属性数值，而不直接改写 UnitBase 基础属性。

const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const EFFECT_SCRIPT_PATH := "res://SkillSystem/03-Extensions/StatModifierSkillEffect.gd"
const CONTEXT_SCRIPT_PATH := "res://SkillSystem/01-Core/SkillContext.gd"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var unit := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	var effect_script := load(EFFECT_SCRIPT_PATH) as Script
	var context_script := load(CONTEXT_SCRIPT_PATH) as Script
	_expect(unit != null, "UnitBase scene instantiates")
	_expect(effect_script != null, "stat modifier skill effect script exists")
	if unit == null or effect_script == null or context_script == null:
		_finish()
		return
	unit.defense = 35.0
	_world.add_child(unit)
	await process_frame

	var effect := effect_script.new() as Node
	effect.set("target_mode", 0)
	effect.set("modifier_stat", 1)
	effect.set("amount", 20.0)
	effect.set("duration_seconds", 5.0)
	var context := context_script.new() as SkillContext
	context.caster = unit
	_expect(bool(effect.call(&"apply", context, null, null)), "self-defense skill effect applies")
	_expect(is_equal_approx(unit.defense, 35.0), "skill effect preserves base defense")
	_expect(is_equal_approx(unit.get_defense(), 55.0), "skill effect contributes effective defense")

	var status_effects := unit.get_status_effect_component()
	status_effects.call(&"advance_effects", 5.1)
	_expect(is_equal_approx(unit.get_defense(), 35.0), "skill defense modifier expires")
	effect.free()

	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("StatModifierSkillEffectTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("StatModifierSkillEffectTest: FAIL (%d)" % _failures.size())
	quit(1)
