extends SceneTree

## 通用状态效果只使用 Inspector 配置的 ID，不认识特定的灼烧技能。

const EFFECT_PATH := "res://SkillSystem/03-Extensions/ApplyNamedStatusSkillEffect.gd"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	if not ResourceLoader.exists(EFFECT_PATH):
		_expect(false, "generic named-status skill effect exists")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := (load("res://UnitSystem/Base/00_UnitBase.tscn") as PackedScene).instantiate() as UnitBase
	var target := (load("res://UnitSystem/Base/00_UnitBase.tscn") as PackedScene).instantiate() as UnitBase
	world.add_child(caster)
	world.add_child(target)
	var effect := (load(EFFECT_PATH) as Script).new() as SkillEffectBase
	world.add_child(effect)
	effect.set("status_id", &"frostbite")
	effect.set("duration_seconds", 4.0)
	var context := SkillContext.new()
	context.caster = caster
	var result := SkillDeliveryResult.new()
	_expect(effect.apply(context, result, target), "configured status effect applies to UnitBase")
	var statuses := target.get_status_effect_component()
	_expect(bool(statuses.call(&"has_named_status", &"frostbite")), "effect applies configured ID")
	_expect(not bool(statuses.call(&"has_named_status", &"burning")), "effect does not hard-code burning")
	world.free()
	_finish()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("ApplyNamedStatusSkillEffectTest: PASS")
	quit(0 if failures.is_empty() else 1)
