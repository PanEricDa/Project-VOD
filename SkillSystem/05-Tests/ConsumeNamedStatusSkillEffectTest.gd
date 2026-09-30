extends SceneTree

## 通用命名状态消耗效果只移除配置的状态 ID。

const EFFECT_PATH := "res://SkillSystem/03-Extensions/ConsumeNamedStatusSkillEffect.gd"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ResourceLoader.exists(EFFECT_PATH):
		_expect(false, "generic named-status consume effect exists")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := (load("res://UnitSystem/Base/00_UnitBase.tscn") as PackedScene).instantiate() as UnitBase
	var target := (load("res://UnitSystem/Base/00_UnitBase.tscn") as PackedScene).instantiate() as UnitBase
	world.add_child(caster)
	world.add_child(target)
	var status := target.get_status_effect_component()
	status.apply_named_status(&"burning", 8.0)
	status.apply_named_status(&"frostbite", 8.0)
	var effect := (load(EFFECT_PATH) as Script).new() as SkillEffectBase
	world.add_child(effect)
	effect.set("status_id", &"burning")
	var context := SkillContext.new()
	context.caster = caster
	var result := SkillDeliveryResult.new()
	_expect(effect.apply(context, result, target), "valid hit accepts configured status consumption")
	_expect(not status.has_named_status(&"burning"), "configured status is consumed")
	_expect(status.has_named_status(&"frostbite"), "unrelated status remains")
	_expect(effect.apply(context, result, target), "missing status does not fail the delivery")
	world.free()
	_finish()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("ConsumeNamedStatusSkillEffectTest: PASS")
	quit(0 if failures.is_empty() else 1)
