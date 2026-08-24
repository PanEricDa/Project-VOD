extends SceneTree

## EnemyBase 与本地仇恨组件的装配契约测试。
## 验证任何经 EnemyBase.apply_damage() 实际结算的伤害，都只通过统一仇恨入口写入本地表。

const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "EnemyThreatIntegrationTestWorld"
	root.add_child(_world)

	var enemy_scene := load(ENEMY_SCENE_PATH) as PackedScene
	_expect(enemy_scene != null, "EnemyBase scene loads")
	if enemy_scene == null:
		_finish()
		return
	var enemy := enemy_scene.instantiate() as EnemyBase
	enemy.name = "ThreatEnemy"
	_world.add_child(enemy)
	var attacker := _create_friendly("ThreatAttacker", Vector3(0.0, 0.0, -3.0))
	await physics_frame

	_expect(
		enemy.has_method(&"get_threat_component"),
		"EnemyBase exposes its assembled local threat component"
	)
	if not enemy.has_method(&"get_threat_component"):
		_finish()
		return
	var threat_component: Node = enemy.call("get_threat_component") as Node
	_expect(threat_component != null, "EnemyBase owns a configured ThreatComponent")
	if threat_component == null:
		_finish()
		return

	var first_applied := enemy.apply_damage(15.0, attacker)
	_expect(is_equal_approx(first_applied, 15.0), "EnemyBase still applies actual damage")
	_expect(
		is_equal_approx(float(threat_component.call("get_threat_for", attacker)), first_applied),
		"actual applied damage is submitted once as baseline local threat"
	)
	var second_applied := enemy.apply_damage(5.0, attacker)
	_expect(is_equal_approx(second_applied, 5.0), "later damage remains independently resolved")
	_expect(
		is_equal_approx(float(threat_component.call("get_threat_for", attacker)), 20.0),
		"EnemyBase routes later damage through the same local threat entry"
	)
	var behavior := enemy.get_behavior_state_machine()
	_expect(behavior != null, "EnemyBase exposes its configured behavior state machine")
	if behavior != null:
		behavior.state_changed.emit(
			EnemyBehaviorStateMachine.State.CHASE,
			EnemyBehaviorStateMachine.State.RETURN_HOME
		)
		_expect(
			is_zero_approx(float(threat_component.call("get_threat_for", attacker))),
			"enemy return-home transition clears local threat records"
		)
		enemy.apply_damage(4.0, attacker)
	enemy.apply_damage(enemy.get_current_health(), attacker)
	_expect(
		is_zero_approx(float(threat_component.call("get_threat_for", attacker))),
		"enemy death clears local threat records"
	)

	_finish()


func _create_friendly(unit_name: String, unit_position: Vector3) -> UnitBase:
	var scene := load(UNIT_SCENE_PATH) as PackedScene
	var unit := scene.instantiate() as UnitBase
	unit.name = unit_name
	unit.faction_id = "Ally"
	unit.team_id = 1
	unit.position = unit_position
	_world.add_child(unit)
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("EnemyThreatIntegrationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("EnemyThreatIntegrationTest: FAIL (%d)" % _failures.size())
	quit(1)
