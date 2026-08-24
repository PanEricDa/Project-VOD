extends SceneTree

const AI_SCENE_PATH: String = "res://UnitSystem/Base/AIUnitBase.tscn"
const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const ENEMY_SCENE_PATH: String = "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const ENEMY_VISUAL_SCENE_PATH: String = (
	"res://UnitSystem/Visuals/Enemy/EnemyVisual.tscn"
)
const STATE_MACHINE_SCENE_PATH := (
	"res://UnitSystem/Components/Behavior/EnemyBehaviorStateMachine.tscn"
)
const TARGETING_SCENE_PATH: String = (
	"res://UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn"
)
const COMBAT_SCENE_PATH: String = (
	"res://UnitSystem/Components/Combat/AI/AICombatSystem.tscn"
)
const IRON_SWORD_PATH: String = (
	"res://Item/Weapon/Sword/IronSwordData.tres"
)

var _failures: Array[String] = []
var _world: Node3D


class PredictableEnemyStateMachine extends EnemyBehaviorStateMachine:
	var candidates: Array[Vector3] = []
	var idle_candidates: Array[Vector3] = []

	func _generate_combat_wander_candidate(
		_target: UnitBase
	) -> Vector3:
		if candidates.is_empty():
			return Vector3.ZERO
		return candidates.pop_front()


	func _generate_idle_wander_candidate() -> Vector3:
		if idle_candidates.is_empty():
			return Vector3.ZERO
		return idle_candidates.pop_front()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state_machine_scene := load(STATE_MACHINE_SCENE_PATH) as PackedScene
	_expect(state_machine_scene != null, "enemy behavior state-machine scene loads")
	if state_machine_scene != null:
		var state_machine := state_machine_scene.instantiate()
		_expect(
			state_machine is EnemyBehaviorStateMachine,
			"enemy behavior state-machine exposes its concrete component type"
		)
		if state_machine is EnemyBehaviorStateMachine:
			_expect(
				state_machine.get_current_state()
				== EnemyBehaviorStateMachine.State.IDLE,
				"enemy behavior state-machine starts in idle"
			)
			_expect(
				state_machine.has_method(&"configure"),
				"enemy behavior state-machine exposes configure"
			)
			_expect(
				state_machine.has_method(&"physics_tick"),
				"enemy behavior state-machine exposes physics_tick"
			)
			state_machine.free()

	_world = Node3D.new()
	_world.name = "EnemyBehaviorStateMachineTestWorld"
	root.add_child(_world)

	await _verify_combat_wander()
	await _verify_idle_behavior()
	await _verify_attack_animation_clears_movement()
	await _verify_combat_reservation()
	_finish()


func _verify_idle_behavior() -> void:
	var owner := _create_owner("IdleOwner", 2, Vector3.ZERO)
	var targeting := _create_targeting(owner)
	var combat := _create_combat(owner)
	var state := _create_predictable_state(owner, targeting, combat, [])
	state.idle_behavior = EnemyBehaviorStateMachine.IdleBehavior.STATIONARY
	state.physics_tick(0.016)
	_expect(
		not owner.has_movement_target(),
		"stationary idle does not submit a movement target"
	)

	state.idle_behavior = EnemyBehaviorStateMachine.IdleBehavior.WANDER_AROUND_HOME
	state.idle_wander_radius = 0.8
	state.idle_wander_interval_min = 1.5
	state.idle_wander_interval_max = 3.0
	state.idle_candidates = [Vector3(0.4, 0.0, 0.2)]
	state.physics_tick(0.016)
	_expect(owner.has_movement_target(), "wander idle submits a movement target")
	_expect(
		owner.get_current_movement_target().distance_to(state.get_home_position())
			<= state.idle_wander_radius,
		"idle wander target remains inside the configured home radius"
	)

	var target := _create_target("IdleTarget", Vector3(0.0, 0.0, -4.0))
	await _wait_for_physics()
	targeting.refresh_target()
	state.physics_tick(0.016)
	_expect(
		state.get_current_state() == EnemyBehaviorStateMachine.State.CHASE,
		"a locked target exits idle into chase"
	)
	_expect(
		not owner.get_current_movement_target().is_equal_approx(Vector3(0.4, 0.0, 0.2)),
		"chase replaces the idle wander target"
	)

	owner.queue_free()
	target.queue_free()
	await process_frame


func _verify_combat_wander() -> void:
	var target := _create_target("Target", Vector3.ZERO)
	var owner := _create_owner(
		"WanderOwner",
		2,
		Vector3(0.0, 0.0, 2.0)
	)
	var targeting := _create_targeting(owner)
	var combat := _create_combat(owner)
	var state := _create_predictable_state(owner, targeting, combat, [])
	await _wait_for_physics()
	targeting.refresh_target()
	_expect(
		targeting.get_locked_target() == target,
		"enemy test target is acquired"
	)

	state.physics_tick(0.016)
	_expect(
		state.get_current_state() == EnemyBehaviorStateMachine.State.CHASE,
		"a distant target enters chase"
	)
	_expect(
		owner.is_in_combat(),
		"chase synchronizes owner into UnitBase combat state"
	)
	_expect(
		owner.get_current_movement_target().is_equal_approx(
			Vector3(0.0, owner.global_position.y, 1.1)
		),
		"chase targets the attack ring from the incoming direction"
	)

	owner.global_position = target.global_position + Vector3(0.0, 0.0, 1.0)
	state.candidates = [
		Vector3(0.0, owner.global_position.y, -1.1)
	]
	state.physics_tick(0.016)
	_expect(
		state.get_current_state() == EnemyBehaviorStateMachine.State.ATTACK,
		"weapon range enters attack"
	)
	var wander_target: Vector3 = owner.get_current_movement_target()
	_expect(
		owner.has_movement_target(),
		"attack cooldown keeps a movement target for combat wander"
	)
	_expect(
		wander_target.is_equal_approx(
			Vector3(0.0, owner.global_position.y, -1.1)
		),
		"attack uses the selected wander candidate"
	)
	_expect(
		not owner.should_face_movement_direction(),
		"attack wander does not face the movement direction"
	)

	owner.global_position = wander_target
	state.candidates = [
		Vector3(9.0, owner.global_position.y, 9.0)
	]
	state.physics_tick(0.1)
	_expect(
		owner.get_current_movement_target().is_equal_approx(wander_target),
		"attack wander waits for its interval after reaching a point"
	)

	target.queue_free()
	await process_frame
	state.physics_tick(0.016)
	state.physics_tick(0.016)
	_expect(
		not owner.is_in_combat(),
		"return home synchronizes owner out of UnitBase combat state"
	)

	owner.queue_free()
	await process_frame


func _verify_attack_animation_clears_movement() -> void:
	var target := _create_target("AnimationTarget", Vector3.ZERO)
	var owner := _create_owner(
		"AnimationOwner",
		2,
		Vector3(0.0, 0.0, 1.0)
	)
	var targeting := _create_targeting(owner)
	var combat := _create_combat(owner, false)
	var state := _create_predictable_state(
		owner,
		targeting,
		combat,
		[Vector3(0.0, owner.global_position.y, -1.1)]
	)
	await _wait_for_physics()
	targeting.refresh_target()
	state.physics_tick(0.016)
	_expect(
		state.get_current_state() == EnemyBehaviorStateMachine.State.ATTACK,
		"animation test enters attack"
	)
	_expect(
		combat.is_attacking(),
		"a ready enemy starts its attack animation"
	)
	_expect(
		not owner.has_movement_target(),
		"attack animation clears the wander movement target"
	)

	owner.queue_free()
	target.queue_free()
	await process_frame


func _verify_combat_reservation() -> void:
	var target := _create_target("ReservationTarget", Vector3.ZERO)
	var owner := _create_owner(
		"ReservationOwner",
		2,
		Vector3(0.0, 0.0, 1.0)
	)
	var targeting := _create_targeting(owner)
	var combat := _create_combat(owner)
	var state := _create_predictable_state(
		owner,
		targeting,
		combat,
		[
			Vector3(1.1, 0.0, 0.0),
			Vector3(0.0, 0.0, -1.1),
		]
	)

	var occupied_enemy := (
		load(ENEMY_SCENE_PATH) as PackedScene
	).instantiate() as EnemyBase
	occupied_enemy.name = "OccupiedEnemy"
	occupied_enemy.team_id = 2
	occupied_enemy.position = Vector3(9.0, 0.0, 9.0)
	_world.add_child(occupied_enemy)
	occupied_enemy.set_physics_process(false)
	occupied_enemy.set_movement_target(Vector3(1.1, 0.0, 0.0))

	var other_team_unit := _create_owner(
		"OtherTeamUnit",
		1,
		Vector3(9.0, 0.0, -9.0)
	)
	other_team_unit.set_movement_target(Vector3(0.0, 0.0, -1.1))

	await _wait_for_physics()
	targeting.refresh_target()
	state.physics_tick(0.016)
	_expect(
		state.get_current_state() == EnemyBehaviorStateMachine.State.ATTACK,
		"reservation owner enters attack"
	)
	_expect(
		owner.get_current_movement_target().is_equal_approx(
			Vector3(0.0, owner.global_position.y, -1.1)
		),
		"same-team movement intent reserves the first attack candidate"
	)

	occupied_enemy.queue_free()
	await process_frame
	owner.global_position = target.global_position + Vector3(4.0, 0.0, 0.0)
	state.physics_tick(0.016)
	owner.global_position = target.global_position + Vector3(0.0, 0.0, 1.0)
	state.candidates = [
		Vector3(1.1, 0.0, 0.0),
		Vector3(0.0, 0.0, -1.1),
	]
	state.physics_tick(0.016)
	_expect(
		owner.get_current_movement_target().is_equal_approx(
			Vector3(1.1, owner.global_position.y, 0.0)
		),
		"another team does not reserve an enemy attack candidate"
	)

	owner.queue_free()
	target.queue_free()
	other_team_unit.queue_free()
	await process_frame


func _create_predictable_state(
	owner: AIUnitBase,
	targeting: AITargetingComponent,
	combat: AICombatSystem,
	candidates: Array[Vector3]
) -> PredictableEnemyStateMachine:
	var state := PredictableEnemyStateMachine.new()
	owner.add_child(state)
	state.minimum_reserved_spacing = 0.45
	state.combat_wander_radius = 1.1
	state.attack_entry_delay_min = 0.0
	state.attack_entry_delay_max = 0.0
	state.candidates = candidates.duplicate()
	_expect(
		state.configure(owner, targeting, combat),
		"predictable enemy state configures"
	)
	return state


func _create_owner(
	unit_name: String,
	unit_team_id: int,
	unit_position: Vector3
) -> AIUnitBase:
	var unit := (
		load(AI_SCENE_PATH) as PackedScene
	).instantiate() as AIUnitBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.collision_layer = 4 if unit_team_id == 2 else 2
	unit.position = unit_position
	_world.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _create_target(unit_name: String, unit_position: Vector3) -> UnitBase:
	var unit := (
		load(UNIT_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	unit.name = unit_name
	unit.team_id = 1
	unit.collision_layer = 2
	unit.position = unit_position
	_world.add_child(unit)
	return unit


func _create_targeting(owner: AIUnitBase) -> AITargetingComponent:
	var targeting := (
		load(TARGETING_SCENE_PATH) as PackedScene
	).instantiate() as AITargetingComponent
	owner.add_child(targeting)
	_expect(
		targeting.configure(owner, 10.0),
		"targeting configures for test owner"
	)
	return targeting


func _create_combat(
	owner: AIUnitBase,
	block_attack: bool = true
) -> AICombatSystem:
	var visual := (
		load(ENEMY_VISUAL_SCENE_PATH) as PackedScene
	).instantiate() as Node3D
	owner.get_node(^"Visual").add_child(visual)

	var sword := load(IRON_SWORD_PATH) as WeaponData
	var combat := (
		load(COMBAT_SCENE_PATH) as PackedScene
	).instantiate() as AICombatSystem
	combat.name = "CombatSystemUnderTest"
	combat.starting_weapon = sword
	owner.add_child(combat)
	_expect(
		combat.configure(owner),
		"combat system configures for test owner"
	)
	if block_attack:
		combat.start_global_cooldown(10.0)
	return combat


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
		print("EnemyBehaviorStateMachineTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print(
		"EnemyBehaviorStateMachineTest: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
