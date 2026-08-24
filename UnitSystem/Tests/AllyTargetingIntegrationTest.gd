extends SceneTree

const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const ALLY_SCENE_PATH: String = "res://UnitSystem/AI/Ally/AllyBase.tscn"

var _failures: Array[String] = []
var _world: Node3D
var _forwarded_change_count: int = 0
var _forwarded_target: UnitBase
var _forwarded_state_change_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "AllyTargetingIntegrationTestWorld"
	root.add_child(_world)

	var hero := _create_unit(
		"Hero",
		1,
		1,
		Vector3.ZERO
	)
	hero.faction_id = "Player"
	var ally_scene := load(ALLY_SCENE_PATH) as PackedScene
	var ally := ally_scene.instantiate() as AllyBase
	ally.name = "AllyBase"
	ally.position = Vector3(2.0, 0.0, 0.0)
	ally.targeting_radius = 8.0
	_world.add_child(ally)
	ally.set_physics_process(false)

	var targeting: AITargetingComponent = ally.get_node_or_null(
		^"AITargetingComponent"
	) as AITargetingComponent
	_expect(targeting != null, "AllyBase owns AITargetingComponent")
	_expect(
		ally.get_targeting_component() == targeting,
		"AllyBase getter exposes the installed targeting component"
	)
	_expect(
		is_equal_approx(targeting.get_targeting_radius(), 8.0),
		"AllyBase forwards its per-unit targeting radius"
	)
	_expect(
		is_equal_approx(targeting.get_retention_radius(), 9.0),
		"AllyBase derives retention without a second unit setting"
	)
	var host := ally.get_node_or_null(^"SkillHost") as SkillHostComponent
	_expect(host != null, "AllyBase inherits SkillHost")
	_expect(
		host != null
		and host.get_target_candidate_provider() == targeting,
		"AllyBase injects its existing perception component into SkillHost"
	)
	var behavior := ally.get_node_or_null(
		^"BehaviorStateMachine"
	) as AllyBehaviorStateMachine
	_expect(behavior != null, "AllyBase owns BehaviorStateMachine")
	_expect(
		ally.get_behavior_state_machine() == behavior,
		"AllyBase getter exposes the behavior state machine"
	)

	ally.locked_target_changed.connect(_on_ally_locked_target_changed)
	ally.behavior_state_changed.connect(_on_ally_behavior_state_changed)
	var enemy: UnitBase = _create_unit(
		"Enemy",
		2,
		4,
		Vector3(2.0, 0.0, -3.0)
	)
	await physics_frame
	await physics_frame
	targeting.refresh_target()

	_expect(
		ally.get_locked_target() == enemy,
		"AllyBase exposes the component autonomous lock"
	)
	_expect(
		_forwarded_change_count == 1 and _forwarded_target == enemy,
		"AllyBase forwards the component target change exactly once"
	)
	behavior.physics_tick(0.016)
	_expect(
		behavior.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.COMBAT_APPROACH,
		"target acquisition enters combat approach through the state machine"
	)
	_expect(
		_forwarded_state_change_count == 1,
		"AllyBase forwards behavior state changes exactly once"
	)
	_expect(
		ally.position.is_equal_approx(Vector3(2.0, 0.0, 0.0)),
		"target refresh does not directly change AllyBase movement"
	)

	_finish()


func _create_unit(
	unit_name: String,
	unit_team_id: int,
	unit_collision_layer: int,
	unit_position: Vector3
) -> UnitBase:
	var scene := load(UNIT_SCENE_PATH) as PackedScene
	var unit := scene.instantiate() as UnitBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.collision_layer = unit_collision_layer
	unit.position = unit_position
	_world.add_child(unit)
	return unit


func _on_ally_locked_target_changed(
	_previous_target: UnitBase,
	current_target: UnitBase
) -> void:
	_forwarded_change_count += 1
	_forwarded_target = current_target


func _on_ally_behavior_state_changed(
	_previous_state: AllyBehaviorStateMachine.BehaviorState,
	_current_state: AllyBehaviorStateMachine.BehaviorState
) -> void:
	_forwarded_state_change_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("AllyTargetingIntegrationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print(
		"AllyTargetingIntegrationTest: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
