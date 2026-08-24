extends SceneTree

const POLICY_PATH: String = (
	"res://UnitSystem/Components/Targeting/AI/Policies/"
	+ "DefaultNearestEnemy.tres"
)

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "TargetSelectionPolicyTestWorld"
	root.add_child(_world)

	var policy: TargetSelectionPolicy = load(POLICY_PATH) as TargetSelectionPolicy
	_expect(policy != null, "default target selection policy loads")
	if policy == null:
		_finish()
		return

	var owner: UnitBase = _create_unit("Owner", 1, Vector3.ZERO)
	var near_enemy: UnitBase = _create_unit(
		"NearEnemy",
		2,
		Vector3(0.0, 100.0, -2.0)
	)
	var far_enemy: UnitBase = _create_unit(
		"FarEnemy",
		2,
		Vector3(0.0, 0.0, -5.0)
	)
	var ally: UnitBase = _create_unit(
		"Ally",
		1,
		Vector3(0.0, 0.0, -1.0)
	)
	var neutral: UnitBase = _create_unit(
		"Neutral",
		0,
		Vector3(0.0, 0.0, -0.5)
	)
	var dead_enemy: UnitBase = _create_unit(
		"DeadEnemy",
		2,
		Vector3(0.0, 0.0, -0.75)
	)
	dead_enemy.apply_damage(dead_enemy.get_maximum_health())
	var untargetable_enemy: UnitBase = _create_unit(
		"UntargetableEnemy",
		2,
		Vector3(0.0, 0.0, -0.6)
	)
	untargetable_enemy.targetable = false
	var out_of_range_enemy: UnitBase = _create_unit(
		"OutOfRangeEnemy",
		2,
		Vector3(0.0, 0.0, -8.0)
	)

	var candidates: Array[UnitBase] = [
		far_enemy,
		owner,
		ally,
		neutral,
		dead_enemy,
		untargetable_enemy,
		out_of_range_enemy,
		near_enemy,
	]
	var selected: UnitBase = policy.select_target(owner, candidates, 6.0)
	_expect(
		selected == near_enemy,
		"nearest valid hostile target is selected using horizontal distance"
	)
	_expect(
		not policy.is_candidate_valid(owner, owner, 6.0),
		"owner cannot target itself"
	)
	_expect(
		not policy.is_candidate_valid(owner, ally, 6.0),
		"friendly unit is rejected by hostile policy"
	)
	_expect(
		not policy.is_candidate_valid(owner, neutral, 6.0),
		"neutral unit is rejected by hostile policy"
	)
	_expect(
		not policy.is_candidate_valid(owner, dead_enemy, 6.0),
		"dead unit is rejected when require_alive is enabled"
	)
	_expect(
		not policy.is_candidate_valid(owner, untargetable_enemy, 6.0),
		"untargetable unit is rejected when require_targetable is enabled"
	)
	_expect(
		not policy.is_candidate_valid(owner, out_of_range_enemy, 6.0),
		"candidate outside acquisition range is rejected"
	)

	policy.target_relation = TargetSelectionPolicy.TargetRelation.FRIENDLY
	_expect(
		policy.select_target(owner, candidates, 6.0) == ally,
		"the same policy type can select friendly targets through data"
	)

	policy.target_relation = TargetSelectionPolicy.TargetRelation.ANY
	policy.require_alive = false
	policy.require_targetable = false
	_expect(
		policy.select_target(owner, candidates, 6.0) == neutral,
		"ANY relation still excludes self and selects the nearest candidate"
	)
	_finish()


func _create_unit(
	unit_name: String,
	unit_team_id: int,
	unit_position: Vector3
) -> UnitBase:
	var unit := UnitBase.new()
	unit.name = unit_name
	unit.team_id = unit_team_id
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
		print("TargetSelectionPolicyTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print(
		"TargetSelectionPolicyTest: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
