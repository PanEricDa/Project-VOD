extends SceneTree

## Formation 落脚点预留算法的确定性测试。
##
## 测试只替换随机候选生成器，真实运行状态机的同队扫描、候选评分、目标提交和
## Combat 分流，避免用随机概率掩盖重叠回归。

const AI_SCENE_PATH: String = "res://UnitSystem/Base/AIUnitBase.tscn"
const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const PLAYER_SCENE_PATH: String = "res://UnitSystem/Player/PlayerBase.tscn"
const TARGETING_SCENE_PATH: String = (
	"res://UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn"
)
const POSITION_PATH: String = (
	"res://UnitSystem/AI/Ally/Formation/Positions/"
	+ "Forward.tres"
)

var _failures: Array[String] = []
var _world: Node3D
var _player: PlayerBase
var _position_data: FormationPositionData


class PredictableFormationStateMachine extends AllyBehaviorStateMachine:
	var candidates: Array[Vector2] = []

	func _generate_formation_local_candidate() -> Vector2:
		if candidates.is_empty():
			return Vector2.ZERO
		return candidates.pop_front()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "FormationTargetReservationTestWorld"
	root.add_child(_world)
	_position_data = load(POSITION_PATH) as FormationPositionData

	_player = (
		load(PLAYER_SCENE_PATH) as PackedScene
	).instantiate() as PlayerBase
	_player.name = "Player"
	_player.position = Vector3.ZERO
	_world.add_child(_player)
	_player.set_physics_process(false)

	var occupied_owner := _create_ai(
		"OccupiedOwner",
		1,
		Vector3(0.0, 0.0, -2.5)
	)
	var first_owner := _create_ai(
		"FirstCandidateOwner",
		1,
		Vector3(0.0, 0.0, 1.0)
	)
	var first_state := _create_predictable_state(
		first_owner,
		[Vector2.ZERO, Vector2(1.0, 0.0)],
		2
	)
	_expect(
		first_state.get_current_movement_target().is_equal_approx(
			Vector3(1.0, 0.0, -2.5)
		),
		"an occupied first candidate is replaced by the clear second candidate"
	)

	first_owner.queue_free()
	await process_frame

	var fallback_owner := _create_ai(
		"FallbackOwner",
		1,
		Vector3(0.0, 0.0, 1.0)
	)
	var fallback_state := _create_predictable_state(
		fallback_owner,
		[Vector2(0.1, 0.0), Vector2(0.4, 0.0)],
		2
	)
	_expect(
		fallback_state.get_current_movement_target().is_equal_approx(
			Vector3(0.4, 0.0, -2.5)
		),
		"all crowded candidates fall back to the greatest clearance"
	)

	fallback_owner.queue_free()
	await process_frame
	occupied_owner.position = Vector3(100.0, 0.0, 100.0)
	var other_team_owner := _create_ai(
		"OtherTeamOwner",
		2,
		Vector3(0.0, 0.0, -2.5)
	)
	var filtered_owner := _create_ai(
		"FilteredOwner",
		1,
		Vector3(0.0, 0.0, 1.0)
	)
	var filtered_state := _create_predictable_state(
		filtered_owner,
		[Vector2.ZERO, Vector2(1.0, 0.0)],
		2
	)
	_expect(
		filtered_state.get_current_movement_target().is_equal_approx(
			Vector3(0.0, 0.0, -2.5)
		),
		"another team does not reserve an Ally formation target"
	)

	filtered_owner.queue_free()
	other_team_owner.queue_free()
	await process_frame
	await _verify_combat_does_not_consume_formation_candidates()
	_finish()


func _verify_combat_does_not_consume_formation_candidates() -> void:
	var combat_owner := _create_ai(
		"CombatOwner",
		1,
		Vector3.ZERO
	)
	var targeting := (
		load(TARGETING_SCENE_PATH) as PackedScene
	).instantiate() as AITargetingComponent
	combat_owner.add_child(targeting)
	_expect(
		targeting.configure(combat_owner, 10.0),
		"combat-isolation targeting configures"
	)
	var combat_state := PredictableFormationStateMachine.new()
	combat_owner.add_child(combat_state)
	combat_state.minimum_target_change_distance = 0.0
	combat_state.minimum_reserved_spacing = 0.65
	combat_state.maximum_candidate_attempts = 2
	combat_state.candidates = [Vector2.ZERO]
	_expect(
		combat_state.set_formation_position(_position_data),
		"combat-isolation state accepts Formation data"
	)
	_expect(
		combat_state.configure(combat_owner, targeting),
		"combat-isolation state configures"
	)

	var enemy := (
		load(UNIT_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	enemy.name = "Enemy"
	enemy.team_id = 2
	enemy.collision_layer = 4
	enemy.position = Vector3(0.0, 0.0, -5.0)
	_world.add_child(enemy)
	await physics_frame
	await physics_frame
	targeting.refresh_target()

	combat_state.candidates = [Vector2(9.0, 9.0)]
	var candidate_count_before: int = combat_state.candidates.size()
	combat_state.physics_tick(0.016)
	_expect(
		combat_state.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.COMBAT_APPROACH,
		"an acquired enemy enters Combat"
	)
	var combat_target: Vector3 = combat_state.get_current_movement_target()
	combat_state.physics_tick(0.016)
	_expect(
		combat_state.candidates.size() == candidate_count_before,
		"Combat does not request a Formation candidate"
	)
	_expect(
		combat_state.get_current_movement_target().is_equal_approx(
			combat_target
		),
		"nearby same-team occupancy does not replace the Combat target"
	)


func _create_predictable_state(
	owner: AIUnitBase,
	candidates: Array[Vector2],
	attempt_count: int
) -> PredictableFormationStateMachine:
	var state := PredictableFormationStateMachine.new()
	owner.add_child(state)
	state.minimum_target_change_distance = 0.0
	state.minimum_reserved_spacing = 0.65
	state.maximum_candidate_attempts = attempt_count
	state.candidates = candidates.duplicate()
	_expect(
		state.set_formation_position(_position_data),
		"predictable state accepts Amy Formation data"
	)
	_expect(
		state.configure(owner, null),
		"predictable Formation state configures"
	)
	return state


func _create_ai(
	unit_name: String,
	unit_team_id: int,
	unit_position: Vector3
) -> AIUnitBase:
	var unit := (
		load(AI_SCENE_PATH) as PackedScene
	).instantiate() as AIUnitBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.position = unit_position
	_world.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("FormationTargetReservationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print(
		"FormationTargetReservationTest: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
