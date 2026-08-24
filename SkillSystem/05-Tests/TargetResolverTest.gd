extends SceneTree

## 技能临时目标解析器的纯算法契约测试。
##
## 每个断言都验证外部可观察行为：关系复选、有效性过滤和选择结果。
## 测试不读取脚本源码，也不依赖具体 UnitBase 类型。

var _failures: Array[String] = []
var _world: Node3D


class TestUnit:
	extends Node3D

	var team_id: int = 0
	var targetable: bool = true
	var dead: bool = false
	var health_ratio: float = 1.0

	func is_targetable() -> bool:
		return targetable

	func is_dead() -> bool:
		return dead

	func get_health_ratio() -> float:
		return health_ratio

	func is_friendly_to(other_value: Variant) -> bool:
		if not is_instance_valid(other_value) or not other_value is TestUnit:
			return false
		var other := other_value as TestUnit
		return team_id != 0 and other.team_id != 0 and team_id == other.team_id

	func is_hostile_to(other_value: Variant) -> bool:
		if not is_instance_valid(other_value) or not other_value is TestUnit:
			return false
		var other := other_value as TestUnit
		return team_id != 0 and other.team_id != 0 and team_id != other.team_id

	func is_neutral_to(other_value: Variant) -> bool:
		if not is_instance_valid(other_value) or not other_value is TestUnit:
			return false
		var other := other_value as TestUnit
		return team_id == 0 or other.team_id == 0


func _initialize() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	call_deferred(&"_run")


func _run() -> void:
	var owner := _create_unit("Owner", 1, Vector3.ZERO, 0.75)
	var friendly := _create_unit("Friendly", 1, Vector3(3.0, 8.0, 0.0), 0.5)
	var hostile_near := _create_unit(
		"HostileNear",
		2,
		Vector3(1.0, 20.0, 0.0),
		0.8
	)
	var hostile_low := _create_unit(
		"HostileLow",
		2,
		Vector3(4.0, 0.0, 0.0),
		0.2
	)
	var neutral := _create_unit("Neutral", 0, Vector3(2.0, 0.0, 0.0), 0.4)

	_expect(
		TargetResolver.is_candidate_valid(
			owner,
			owner,
			TargetResolver.TargetRelationFlag.SELF,
			true,
			true
		),
		"SELF accepts the owner"
	)
	_expect(
		not TargetResolver.is_candidate_valid(
			owner,
			friendly,
			TargetResolver.TargetRelationFlag.SELF,
			true,
			true
		),
		"SELF rejects another friendly"
	)
	_expect(
		TargetResolver.is_candidate_valid(
			owner,
			friendly,
			TargetResolver.TargetRelationFlag.FRIENDLY,
			true,
			true
		),
		"FRIENDLY accepts another same-team unit"
	)
	_expect(
		TargetResolver.is_candidate_valid(
			owner,
			hostile_near,
			TargetResolver.TargetRelationFlag.HOSTILE,
			true,
			true
		),
		"HOSTILE accepts a different non-zero team"
	)
	_expect(
		TargetResolver.is_candidate_valid(
			owner,
			neutral,
			TargetResolver.TargetRelationFlag.NEUTRAL,
			true,
			true
		),
		"NEUTRAL accepts a unit involving team zero"
	)
	_expect(
		TargetResolver.is_candidate_valid(
			owner,
			owner,
			(
				TargetResolver.TargetRelationFlag.SELF
				| TargetResolver.TargetRelationFlag.FRIENDLY
			),
			true,
			true
		),
		"relation flags support combined Self and Friendly"
	)

	friendly.targetable = false
	_expect(
		not TargetResolver.is_candidate_valid(
			owner,
			friendly,
			TargetResolver.TargetRelationFlag.FRIENDLY,
			true,
			true
		),
		"Require Targetable rejects an untargetable unit"
	)
	_expect(
		TargetResolver.is_candidate_valid(
			owner,
			friendly,
			TargetResolver.TargetRelationFlag.FRIENDLY,
			false,
			true
		),
		"disabled Require Targetable accepts the same unit"
	)
	friendly.targetable = true
	friendly.dead = true
	_expect(
		not TargetResolver.is_candidate_valid(
			owner,
			friendly,
			TargetResolver.TargetRelationFlag.FRIENDLY,
			true,
			true
		),
		"Require Alive rejects a dead unit"
	)
	_expect(
		TargetResolver.is_candidate_valid(
			owner,
			friendly,
			TargetResolver.TargetRelationFlag.FRIENDLY,
			true,
			false
		),
		"disabled Require Alive accepts the same unit"
	)
	friendly.dead = false

	var unrelated := Node3D.new()
	_world.add_child(unrelated)
	_expect(
		not TargetResolver.is_candidate_valid(
			owner,
			unrelated,
			TargetResolver.TargetRelationFlag.FRIENDLY,
			true,
			true
		),
		"candidate missing target capabilities is rejected safely"
	)

	var hostile_candidates: Array[Node3D] = [
		hostile_low,
		hostile_near,
		hostile_near,
	]
	_expect(
		TargetResolver.resolve_target(
			owner,
			hostile_candidates,
			hostile_low,
			TargetResolver.TargetRelationFlag.HOSTILE,
			TargetResolver.TargetSelectionMode.CURRENT_COMBAT_TARGET,
			true,
			true
		) == hostile_low,
		"Current Combat Target returns the valid supplied lock"
	)
	_expect(
		TargetResolver.resolve_target(
			owner,
			hostile_candidates,
			friendly,
			TargetResolver.TargetRelationFlag.HOSTILE,
			TargetResolver.TargetSelectionMode.CURRENT_COMBAT_TARGET,
			true,
			true
		) == null,
		"Current Combat Target does not silently fall back"
	)
	_expect(
		TargetResolver.resolve_target(
			owner,
			hostile_candidates,
			null,
			TargetResolver.TargetRelationFlag.HOSTILE,
			TargetResolver.TargetSelectionMode.NEAREST,
			true,
			true
		) == hostile_near,
		"Nearest uses horizontal distance and ignores vertical offset"
	)
	_expect(
		TargetResolver.resolve_target(
			owner,
			hostile_candidates,
			null,
			TargetResolver.TargetRelationFlag.HOSTILE,
			TargetResolver.TargetSelectionMode.LOWEST_HEALTH_RATIO,
			true,
			true
		) == hostile_low,
		"Lowest Health Ratio selects the lowest valid ratio"
	)

	var seeded_random := RandomNumberGenerator.new()
	seeded_random.seed = 42
	var random_result := TargetResolver.resolve_target(
		owner,
		hostile_candidates,
		null,
		TargetResolver.TargetRelationFlag.HOSTILE,
		TargetResolver.TargetSelectionMode.RANDOM,
		true,
		true,
		seeded_random
	)
	_expect(
		random_result in [hostile_near, hostile_low],
		"Random returns one filtered unique candidate"
	)
	_expect(
		TargetResolver.resolve_target(
			owner,
			[unrelated],
			null,
			TargetResolver.TargetRelationFlag.HOSTILE,
			TargetResolver.TargetSelectionMode.NEAREST,
			true,
			true
		) == null,
		"empty valid candidate set returns null"
	)

	var freed_candidate := TestUnit.new()
	freed_candidate.free()
	_expect(
		not TargetResolver.is_candidate_valid(
			owner,
			freed_candidate,
			TargetResolver.TargetRelationFlag.HOSTILE,
			true,
			true
		),
		"freed candidate is rejected before typed conversion"
	)
	_finish()


func _create_unit(
	unit_name: String,
	unit_team_id: int,
	unit_position: Vector3,
	unit_health_ratio: float
) -> TestUnit:
	var unit := TestUnit.new()
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.position = unit_position
	unit.health_ratio = unit_health_ratio
	_world.add_child(unit)
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("TargetResolverTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
