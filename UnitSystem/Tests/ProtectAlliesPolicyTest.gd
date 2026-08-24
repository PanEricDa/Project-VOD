extends SceneTree

const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const THREAT_EVENT_PATH := "res://UnitSystem/Components/Threat/ThreatEvent.gd"
const NEAREST_POLICY_PATH := "res://UnitSystem/Components/Targeting/AI/Policies/DefaultNearestEnemy.tres"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "ProtectAlliesPolicyTestWorld"
	root.add_child(_world)

	var event_script := load(THREAT_EVENT_PATH) as Script
	var nearest_policy := load(NEAREST_POLICY_PATH) as TargetSelectionPolicy
	var protect_policy := _create_protect_policy(0.3)
	var neutral_policy := _create_protect_policy(1.0)

	var owner := _create_unit("Owner", 1, Vector3.ZERO)
	var ally := _create_unit("Ally", 1, Vector3(1.0, 0.0, 0.0))
	var enemy_near := _create_enemy("ENear", 2, Vector3(0.0, 0.0, 3.0))
	var enemy_far := _create_enemy("EFar", 2, Vector3(0.0, 0.0, 6.0))

	_submit_threat(event_script, enemy_near, owner, 120.0)
	_submit_threat(event_script, enemy_far, owner, 100.0)

	await _wait_for_physics()
	enemy_near.get_targeting_component().refresh_target()
	enemy_far.get_targeting_component().refresh_target()

	var candidates: Array[UnitBase] = [enemy_near, enemy_far]

	var nearest_result := nearest_policy.select_target(owner, candidates, 10.0)
	_expect(nearest_result == enemy_near, "NEAREST picks the closer enemy")

	var both_on_owner := protect_policy.select_target(owner, candidates, 10.0)
	_expect(both_on_owner == enemy_near, "PROTECT_ALLIES with IR=0.3 and both on owner picks nearest")

	_submit_threat(event_script, enemy_far, ally, 200.0)
	enemy_far.get_targeting_component().refresh_target()
	_submit_threat(event_script, enemy_near, ally, 200.0)
	enemy_near.get_targeting_component().refresh_target()
	var both_on_ally := protect_policy.select_target(owner, candidates, 10.0)
	_expect(both_on_ally == enemy_near, "PROTECT_ALLIES with both on ally still picks nearest")

	var neutral_result := neutral_policy.select_target(owner, candidates, 10.0)
	_expect(neutral_result == enemy_near, "PROTECT_ALLIES IR=1.0 acts like NEAREST")

	var bare_enemy := _create_unit("BareEnemy", 2, Vector3(0.0, 0.0, 4.0)) as UnitBase
	bare_enemy.set("team_id", 2)
	bare_enemy.set("collision_layer", 4)
	var bare_candidates: Array[UnitBase] = [bare_enemy]
	var bare_result := protect_policy.select_target(owner, bare_candidates, 10.0)
	_expect(bare_result == bare_enemy, "PROTECT_ALLIES selects enemy without ThreatComponent via binary check")

	_finish()


func _submit_threat(event_script: Script, enemy: Node, source: Node, amount: float) -> void:
	var threat_component: Node = enemy.get_node_or_null(^"ThreatComponent")
	if not is_instance_valid(threat_component):
		return
	var event: Variant = event_script.call("create_damage", source, amount)
	threat_component.call("submit_threat", event)


func _create_protect_policy(ir: float) -> TargetSelectionPolicy:
	var policy := TargetSelectionPolicy.new()
	policy.priority_mode = TargetSelectionPolicy.PriorityMode.PROTECT_ALLIES
	policy.intervention_response = ir
	return policy


func _create_enemy(unit_name: String, unit_team_id: int, unit_position: Vector3) -> Node:
	var unit := (load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as Node
	unit.name = unit_name
	unit.set("team_id", unit_team_id)
	unit.set("position", unit_position)
	_world.add_child(unit)
	unit.call("set_physics_process", false)
	return unit


func _create_unit(unit_name: String, unit_team_id: int, unit_position: Vector3) -> Node:
	var unit := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as Node
	unit.name = unit_name
	unit.set("team_id", unit_team_id)
	unit.set("collision_layer", 2 if unit_team_id == 1 else 4)
	unit.set("position", unit_position)
	_world.add_child(unit)
	return unit


func _wait_for_physics() -> void:
	await physics_frame
	await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("ProtectAlliesPolicyTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("ProtectAlliesPolicyTest: FAIL (%d)" % _failures.size())
	quit(1)
