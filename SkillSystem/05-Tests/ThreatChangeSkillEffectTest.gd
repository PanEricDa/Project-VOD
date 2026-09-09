extends SceneTree

## 隔离验证 ThreatChangeSkillEffect 的固定值 SKILL_BONUS 契约：
## 精确固定值、可累加、不受 context.threat_multiplier 影响、
## 友方/无仇恨组件目标、无效施法者与非正数值全部安全拒绝且不改动仇恨表。
## 实施前脚本尚不存在，测试以脚本加载守卫保证 RED 阶段无解析错误。

const EFFECT_SCRIPT_PATH := (
	"res://SkillSystem/03-Extensions/ThreatChangeSkillEffect.gd"
)
const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var effect_script := load(EFFECT_SCRIPT_PATH) as GDScript
	_expect(effect_script != null, "ThreatChangeSkillEffect script exists")
	if effect_script == null:
		_finish()
		return

	var world := Node3D.new()
	world.name = "ThreatEffectTestWorld"
	root.add_child(world)
	var guardian := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	guardian.team_id = 1
	world.add_child(guardian)
	var enemy := (load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as EnemyBase
	enemy.team_id = 2
	world.add_child(enemy)
	var friendly := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	friendly.team_id = 1
	world.add_child(friendly)
	var plain_unit := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	plain_unit.team_id = 2
	world.add_child(plain_unit)
	await process_frame

	var threat_component := enemy.get_threat_component()
	_expect(
		threat_component != null and threat_component.has_method(&"submit_threat"),
		"EnemyBase fixture exposes its threat component"
	)
	if threat_component == null:
		_world_cleanup(world)
		return

	var effect: Node = effect_script.new()
	world.add_child(effect)
	effect.set("threat_amount", 200.0)
	var context := SkillContext.new()
	context.caster = guardian
	context.delivery_parent = world
	var result := SkillDeliveryResult.new()

	_expect(
		bool(effect.call(&"apply", context, SkillDeliveryResult.new(), enemy)),
		"fixed threat effect accepts a hostile unit with a threat component"
	)
	_expect(
		is_equal_approx(
			float(threat_component.call(&"get_threat_for", guardian)),
			200.0
		),
		"first application stores exactly 200 threat"
	)
	_expect(
		bool(effect.call(&"apply", context, SkillDeliveryResult.new(), enemy))
			and is_equal_approx(
				float(threat_component.call(&"get_threat_for", guardian)),
				400.0
			),
		"repeated application adds the same fixed amount"
	)
	context.threat_multiplier = 50.0
	_expect(
		bool(effect.call(&"apply", context, SkillDeliveryResult.new(), enemy))
			and is_equal_approx(
				float(threat_component.call(&"get_threat_for", guardian)),
				600.0
			),
		"the fixed amount ignores the request threat multiplier"
	)
	context.threat_multiplier = 1.0

	_expect(
		not bool(effect.call(&"apply", context, SkillDeliveryResult.new(), friendly)),
		"a friendly target is rejected"
	)
	_expect(
		not bool(effect.call(&"apply", context, SkillDeliveryResult.new(), plain_unit)),
		"a target without a threat component is rejected"
	)
	var invalid_context := SkillContext.new()
	invalid_context.caster = null
	invalid_context.delivery_parent = world
	_expect(
		not bool(
			effect.call(&"apply", invalid_context, SkillDeliveryResult.new(), enemy)
		),
		"an invalid caster is rejected"
	)
	effect.set("threat_amount", 0.0)
	_expect(
		not bool(effect.call(&"apply", context, SkillDeliveryResult.new(), enemy)),
		"a non-positive threat amount is rejected"
	)
	_expect(
		is_equal_approx(
			float(threat_component.call(&"get_threat_for", guardian)),
			600.0
		),
		"rejected applications never modify the threat table"
	)
	_expect(result.affected_targets.is_empty(), "the effect never mutates the result")

	_world_cleanup(world)


func _world_cleanup(world: Node3D) -> void:
	world.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ThreatChangeSkillEffectTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("ThreatChangeSkillEffectTest: FAIL (%d)" % _failures.size())
	quit(1)
