extends SceneTree

## AI 灼烧数量门槛不限制显式请求，也不把死亡或过期目标计入数量。

const CONDITION_PATH := "res://SkillSystem/03-Extensions/Conditions/MarkedHostileCountCondition.gd"
const UNIT_SCENE := preload("res://UnitSystem/Base/00_UnitBase.tscn")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ResourceLoader.exists(CONDITION_PATH):
		_expect(false, "marked-hostile count condition exists")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world, 1)
	var first := _unit(world, 2)
	var second := _unit(world, 2)
	var query := MarkedHostileTargetExpansion.new()
	query.status_id = &"burning"
	var condition := (load(CONDITION_PATH) as Script).new() as SkillConditionBase
	world.add_child(condition)
	condition.set("target_query", query)
	condition.set("minimum_count", 2)
	var context := SkillContext.new()
	context.caster = caster
	context.delivery_parent = world
	context.request_source = SkillContext.RequestSource.AI_AUTOMATIC
	_expect(condition.applies_to(context), "AI request checks the soft condition")
	_expect(not condition.evaluate(context), "zero burning enemies reject automatic use")
	first.get_status_effect_component().apply_named_status(&"burning", 8.0)
	_expect(not condition.evaluate(context), "one burning enemy is insufficient")
	second.get_status_effect_component().apply_named_status(&"burning", 8.0)
	_expect(condition.evaluate(context), "two burning enemies permit automatic use")
	context.request_source = SkillContext.RequestSource.EXPLICIT
	_expect(not condition.applies_to(context), "explicit request bypasses the AI soft condition")
	second.apply_damage(9999.0, caster)
	context.request_source = SkillContext.RequestSource.AI_AUTOMATIC
	_expect(not condition.evaluate(context), "dead burning enemy no longer counts")
	world.free()
	_finish()


func _unit(world: Node3D, team: int) -> UnitBase:
	var unit := UNIT_SCENE.instantiate() as UnitBase
	unit.team_id = team
	world.add_child(unit)
	if team == 2:
		unit.add_to_group(&"enemy_targets")
	return unit


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("MarkedHostileCountConditionTest: PASS")
	quit(0 if failures.is_empty() else 1)
