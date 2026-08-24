extends SceneTree

const AI_SCENE_PATH: String = "res://UnitSystem/Base/AIUnitBase.tscn"
const ALLY_SCENE_PATH: String = "res://UnitSystem/AI/Ally/AllyBase.tscn"
const ENEMY_SCENE_PATH: String = "res://UnitSystem/AI/Enemy/EnemyBase.tscn"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "AIUnitBaseLocomotionMigrationTestWorld"
	root.add_child(_world)

	var ai_scene := load(AI_SCENE_PATH) as PackedScene
	_expect(ai_scene != null, "AIUnitBase scene loads")
	if ai_scene == null:
		_finish()
		return
	var ai := ai_scene.instantiate() as AIUnitBase
	_expect(ai != null, "AIUnitBase scene instantiates with its typed script")
	if ai == null:
		_finish()
		return
	_world.add_child(ai)
	ai.set_physics_process(false)

	_expect(
		ai.get_node_or_null(^"MovementSystem/LocomotionComponent") == null,
		"AIUnitBase no longer mounts a LocomotionComponent node"
	)
	_expect(
		not ai.has_method("get_locomotion_component"),
		"AIUnitBase no longer exposes the removed component getter"
	)
	_expect(
		is_equal_approx(ai.movement_speed, 4.2),
		"movement speed moved to the AIUnitBase root"
	)
	_expect(
		is_equal_approx(ai.movement_acceleration, 20.0),
		"movement acceleration moved to the AIUnitBase root"
	)
	_expect(
		is_equal_approx(ai.dash_speed, 9.0),
		"dash speed moved to the AIUnitBase root"
	)
	_expect(
		is_equal_approx(ai.rotation_speed, 7.0),
		"facing speed moved to the AIUnitBase root"
	)
	_expect(
		is_equal_approx(ai.gravity_multiplier, 1.0),
		"gravity multiplier moved to the AIUnitBase root"
	)
	_expect(
		ai.get_node_or_null(^"CombatSystem") == null,
		"AIUnitBase does not preinstall a combat implementation"
	)
	_expect(
		ai.get_combat_system() == null,
		"AIUnitBase safely supports units without a CombatSystem component"
	)

	ai.set_movement_target(Vector3(2.0, 0.0, 0.0))
	_expect(ai.has_movement_target(), "AIUnitBase accepts movement targets")
	_expect(
		ai.should_face_movement_direction(),
		"movement faces its travel direction by default"
	)
	ai.set_movement_target(Vector3(2.0, 0.0, 0.0), 2.0, false)
	_expect(
		not ai.should_face_movement_direction(),
		"combat movement can preserve an explicit facing direction"
	)
	ai.clear_movement_target()
	_expect(
		not ai.has_movement_target(),
		"AIUnitBase clears movement targets"
	)
	_expect(
		ai.should_face_movement_direction(),
		"clearing movement restores the default facing policy"
	)
	_expect(
		ai.request_attack_motion(Vector3.FORWARD, 0.5, 2.0),
		"AIUnitBase accepts valid collision-aware attack motion"
	)
	_expect(
		ai.is_attack_motion_active(),
		"accepted attack motion becomes active"
	)
	ai.set_attack_motion_suspended(true)
	_expect(
		ai.is_attack_motion_suspended(),
		"attack motion can be locally suspended for hit stop"
	)
	ai.cancel_attack_motion()
	_expect(
		not ai.is_attack_motion_active(),
		"attack motion cancels without affecting the unit"
	)
	_expect(
		not ai.request_attack_motion(Vector3.ZERO, 0.5, 2.0),
		"zero-direction attack motion is rejected"
	)
	_expect(
		ai.request_dash(Vector3(2.0, 0.0, 0.0)),
		"AIUnitBase starts a valid dash"
	)
	_expect(ai.is_dashing(), "dash state is owned by AIUnitBase")

	var ally_scene := load(ALLY_SCENE_PATH) as PackedScene
	var ally := ally_scene.instantiate() as AllyBase
	_expect(ally != null, "AllyBase still instantiates from AIUnitBase")
	if ally != null:
		_world.add_child(ally)
		ally.set_physics_process(false)
		_expect(
			ally.get_node_or_null(^"MovementSystem/LocomotionComponent") == null,
			"AllyBase inherits the flattened locomotion structure"
		)
		_expect(
			ally.get_node_or_null(^"MovementSystem/FormationComponent") == null,
			"AllyBase no longer mounts the legacy FormationComponent"
		)
		_expect(
			ally.get_node_or_null(^"BehaviorStateMachine")
				is AllyBehaviorStateMachine,
			"AllyBase installs the unified behavior state machine"
		)

	var enemy_scene := load(ENEMY_SCENE_PATH) as PackedScene
	var enemy := enemy_scene.instantiate() as EnemyBase
	_expect(enemy != null, "EnemyBase still instantiates from AIUnitBase")
	if enemy != null:
		_world.add_child(enemy)
		enemy.set_physics_process(false)
		_expect(
			enemy.get_node_or_null(^"MovementSystem/LocomotionComponent") == null,
			"EnemyBase inherits the flattened locomotion structure"
		)

	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("AIUnitBaseLocomotionMigrationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print(
		"AIUnitBaseLocomotionMigrationTest: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
