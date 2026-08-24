extends SceneTree

const AI_SCENE_PATH: String = "res://UnitSystem/Base/AIUnitBase.tscn"
const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const PLAYER_SCENE_PATH: String = "res://UnitSystem/Player/PlayerBase.tscn"
const ALLY_SCENE_PATH: String = \
	"res://UnitSystem/AI/Ally/Units/Saber.tscn"
const ALLY_FORMATION_POSITION_PATH: String = (
	"res://UnitSystem/AI/Ally/Formation/Positions/AttackingMid.tres"
)
const TARGETING_SCENE_PATH: String = (
	"res://UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn"
)
const STATE_MACHINE_SCENE_PATH: String = (
	"res://UnitSystem/Components/Behavior/AllyBehaviorStateMachine.tscn"
)

var _failures: Array[String] = []
var _world: Node3D


class CustomBehaviorStateMachine extends AllyBehaviorStateMachine:
	var enter_count: int = 0
	var update_count: int = 0
	var exit_count: int = 0
	var received_context_value: String = ""

	func _supports_custom_state(custom_state_id: StringName) -> bool:
		return custom_state_id == &"rest"

	func _enter_custom_state(
		_custom_state_id: StringName,
		context: Dictionary
	) -> void:
		enter_count += 1
		received_context_value = str(context.get("reason", ""))

	func _update_custom_state(
		_custom_state_id: StringName,
		_delta: float
	) -> void:
		update_count += 1

	func _exit_custom_state(_custom_state_id: StringName) -> void:
		exit_count += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "AllyBehaviorStateMachineTestWorld"
	root.add_child(_world)

	var state_machine_scene := load(STATE_MACHINE_SCENE_PATH) as PackedScene
	_expect(state_machine_scene != null, "behavior state-machine scene loads")
	if state_machine_scene == null:
		_finish()
		return

	var owner := (load(AI_SCENE_PATH) as PackedScene).instantiate() as AIUnitBase
	owner.name = "Owner"
	owner.team_id = 1
	owner.collision_layer = 2
	owner.position = Vector3(0.0, 0.0, 2.0)
	_world.add_child(owner)
	owner.set_physics_process(false)

	var player := _create_player("PlayerRenamed", Vector3.ZERO)
	_expect(
		player.faction_id == "Player",
		"PlayerBase keeps the unique Player faction identity"
	)
	var targeting_scene := load(TARGETING_SCENE_PATH) as PackedScene
	var targeting := targeting_scene.instantiate() as AITargetingComponent
	owner.add_child(targeting)
	_expect(targeting.configure(owner, 10.0), "targeting configures for test owner")

	var state_machine := (
		state_machine_scene.instantiate() as AllyBehaviorStateMachine
	)
	owner.add_child(state_machine)
	_expect(
		state_machine.configure(owner, targeting),
		"state machine accepts movement owner and targeting component"
	)
	var has_threat_suppression_probability := state_machine.has_method(
		&"get_threat_action_suppression_probability"
	)
	_expect(
		has_threat_suppression_probability,
		"state machine exposes one shared threat action suppression probability"
	)
	if has_threat_suppression_probability:
		_expect(
			is_zero_approx(
				float(
					state_machine.call(
						"get_threat_action_suppression_probability",
						1.0
					)
				)
			),
			"equal threat has no action suppression probability"
		)
		_expect(
			is_equal_approx(
				float(
					state_machine.call(
						"get_threat_action_suppression_probability",
						1.25
					)
				),
				0.7
			),
			"125-percent threat returns the UnitBase configured 70-percent suppression probability"
		)
		var high_threat_probability: float = float(
			state_machine.call(
				"get_threat_action_suppression_probability",
				1.5
			)
		)
		_expect(
			high_threat_probability > 0.7 and high_threat_probability < 0.9,
			"threat above 125 percent rises toward but never reaches 90 percent"
		)
		owner.threat_action_suppression_at_125 = 0.0
		_expect(
			is_zero_approx(
				float(
					state_machine.call(
						"get_threat_action_suppression_probability",
						1.5
					)
				)
			),
			"a zero suppression configuration disables the shared action throttle"
		)
		owner.threat_action_suppression_at_125 = 0.7
	_expect(
		"COMBAT_ATTACK"
			in AllyBehaviorStateMachine.BehaviorState.keys(),
		"behavior state enum exposes COMBAT_ATTACK"
	)
	_expect(
		is_equal_approx(
			state_machine.get_effective_combat_distance(),
			state_machine.preferred_combat_distance
		),
		"an unarmed state machine keeps its configured fallback distance"
	)
	state_machine.physics_tick(0.016)
	_expect(
		state_machine.get_follow_target() == player,
		"state machine automatically resolves the renamed Player-faction unit"
	)
	var follow_debug_property: Dictionary = _find_property_definition(
		state_machine,
		&"debug_current_follow_target"
	)
	_expect(
		not follow_debug_property.is_empty(),
		"Inspector exposes the current follow target debug property"
	)
	if not follow_debug_property.is_empty():
		var follow_debug_usage: int = int(
			follow_debug_property.get("usage", 0)
		)
		_expect(
			(follow_debug_usage & PROPERTY_USAGE_READ_ONLY) != 0,
			"follow target debug property is read-only"
		)
		_expect(
			(follow_debug_usage & PROPERTY_USAGE_STORAGE) == 0,
			"follow target debug property is not stored in the scene"
		)
		_expect(
			state_machine.get(&"debug_current_follow_target") == player,
			"follow target debug property displays the resolved Player unit"
		)
	_expect(
		state_machine.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.FORMATION_WANDER,
		"state machine starts in formation wander"
	)
	_expect(
		state_machine.get_current_state_name() == &"FORMATION_WANDER",
		"state machine exposes a readable initial state name"
	)
	_expect(not state_machine.is_in_combat(), "formation state is not combat")
	var runtime_position := FormationPositionData.new()
	runtime_position.display_name = "Runtime Test Position"
	runtime_position.center_offset = Vector2(2.0, 4.0)
	runtime_position.lateral_radius = 0.0
	runtime_position.lateral_minimum = 0.0
	runtime_position.forward_radius = 0.0
	runtime_position.side_mode = (
		FormationPositionData.SideMode.FREE_CROSSING
	)
	_expect(
		state_machine.set_formation_position(runtime_position),
		"formation position can be replaced through the public interface"
	)
	_expect(
		state_machine.get_formation_position() == runtime_position,
		"state machine exposes the selected shared resource"
	)
	var invalid_position := FormationPositionData.new()
	invalid_position.lateral_radius = -1.0
	_expect(
		not state_machine.set_formation_position(invalid_position),
		"invalid position data is rejected"
	)
	_expect(
		state_machine.get_formation_position() == runtime_position,
		"invalid data does not replace the current formation position"
	)
	state_machine.physics_tick(0.016)
	_expect(
		state_machine.get_current_movement_target().is_equal_approx(
			Vector3(2.0, player.global_position.y, -4.0)
		),
		"center offset is converted through player right and forward"
	)
	var ally_position := load(
		ALLY_FORMATION_POSITION_PATH
	) as FormationPositionData
	_expect(
		state_machine.set_formation_position(ally_position),
		"state machine restores Saber's migrated formation position"
	)
	var saber_scene_instance := (
		load(ALLY_SCENE_PATH) as PackedScene
	).instantiate() as AllyBase
	_expect(
		saber_scene_instance.formation_position != null
		and saber_scene_instance.formation_position.resource_path
			== ALLY_FORMATION_POSITION_PATH,
		"Saber explicitly selects the migrated position resource"
	)
	saber_scene_instance.free()
	_expect(
		not state_machine.request_custom_state(&"unsupported"),
		"unknown custom state is rejected safely"
	)

	var enemy := _create_unit(
		"Enemy",
		2,
		4,
		Vector3(0.0, 0.0, -5.0)
	)
	await _wait_for_physics()
	targeting.refresh_target()
	_expect(targeting.get_locked_target() == enemy, "test enemy is acquired")

	state_machine.physics_tick(0.016)
	_expect(
		state_machine.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.COMBAT_APPROACH,
		"acquiring a distant target enters combat approach"
	)
	_expect(state_machine.is_in_combat(), "combat approach reports combat")
	_expect(
		owner.is_in_combat(),
		"combat approach synchronizes the Ally owner into UnitBase combat state"
	)
	_expect(
		not owner.should_face_movement_direction(),
		"combat approach preserves target-facing movement"
	)
	var combat_movement_target: Vector3 = (
		state_machine.get_current_movement_target()
	)
	var combat_only_position := FormationPositionData.new()
	combat_only_position.center_offset = Vector2(9.0, 9.0)
	combat_only_position.lateral_radius = 0.0
	combat_only_position.forward_radius = 0.0
	_expect(
		state_machine.set_formation_position(combat_only_position),
		"Combat accepts a future Formation selection without applying it"
	)
	_expect(
		state_machine.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.COMBAT_APPROACH
		and state_machine.get_current_movement_target().is_equal_approx(
			combat_movement_target
		),
		"changing Formation data does not replace a Combat movement target"
	)
	_expect(
		state_machine.set_formation_position(ally_position),
		"Saber's Formation selection can be restored while Combat remains active"
	)

	owner.global_position = enemy.global_position + Vector3(0.0, 0.0, 2.0)
	state_machine.physics_tick(0.016)
	_expect(
		state_machine.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.COMBAT_HOLD,
		"entering the preferred distance band enters combat hold"
	)
	state_machine.physics_tick(0.016)
	var first_combat_wander_target: Vector3 = (
		state_machine.get_current_movement_target()
	)
	owner.global_position = first_combat_wander_target
	state_machine.physics_tick(0.1)
	_expect(
		state_machine.get_current_movement_target().is_equal_approx(
			first_combat_wander_target
		),
		"combat wander waits for its shared interval after reaching a point"
	)

	owner.global_position = enemy.global_position + Vector3(0.0, 0.0, 4.0)
	state_machine.physics_tick(0.016)
	_expect(
		state_machine.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.COMBAT_APPROACH,
		"a target beyond the distance band returns to combat approach"
	)

	enemy.targetable = false
	targeting.refresh_target()
	state_machine.physics_tick(0.016)
	_expect(
		state_machine.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.RETURN,
		"losing the target enters return"
	)
	_expect(not state_machine.is_in_combat(), "return is not a combat state")
	_expect(
		not owner.is_in_combat(),
		"return synchronizes the Ally owner out of UnitBase combat state"
	)

	owner.global_position = player.global_position + Vector3.FORWARD * 2.5
	state_machine.physics_tick(0.016)
	_expect(
		state_machine.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.FORMATION_WANDER,
		"reaching the formation region returns to formation wander"
	)

	player.global_position = Vector3.ZERO
	enemy.global_position = Vector3(0.0, 0.0, -2.0)
	owner.global_position = Vector3(0.0, 0.0, 13.0)
	_expect(
		bool(state_machine.call("_should_force_disengage", enemy)),
		"an ally forced beyond the player combat boundary disengages even when its target remains nearby"
	)
	owner.global_position = player.global_position + Vector3.FORWARD * 2.5

	enemy.targetable = true
	enemy.global_position = Vector3(0.0, 0.0, -5.0)
	player.global_position = Vector3(0.0, 0.0, 20.0)
	await _wait_for_physics()
	targeting.refresh_target()
	state_machine.physics_tick(0.016)
	_expect(
		state_machine.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.FORMATION_REPOSITION,
		"forced disengagement returns through the existing formation flow"
	)
	_expect(
		targeting.is_detection_suspended(),
		"forced disengagement temporarily suspends targeting"
	)
	_expect(
		owner.is_dashing(),
		"the existing emergency follow rule can dash after forced disengagement"
	)

	var custom_state_machine := CustomBehaviorStateMachine.new()
	owner.add_child(custom_state_machine)
	custom_state_machine.set_player(player)
	_expect(
		custom_state_machine.configure(owner, null),
		"custom behavior extension can run without a targeting component"
	)
	_expect(
		custom_state_machine.request_custom_state(
			&"rest",
			{"reason": "camp"}
		),
		"supported custom behavior enters through the open interface"
	)
	_expect(
		custom_state_machine.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.CUSTOM,
		"supported custom behavior enters CUSTOM"
	)
	custom_state_machine.physics_tick(0.016)
	_expect(
		custom_state_machine.enter_count == 1
		and custom_state_machine.update_count == 1
		and custom_state_machine.received_context_value == "camp",
		"custom enter and update hooks receive the request context"
	)
	custom_state_machine.exit_custom_state()
	_expect(
		custom_state_machine.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.RETURN
		and custom_state_machine.exit_count == 1,
		"custom exit hook returns control through RETURN"
	)
	var follow_proxy := _create_unit(
		"FollowProxy",
		1,
		2,
		Vector3(3.0, 0.0, 0.0)
	)
	state_machine.set_follow_target(follow_proxy)
	_expect(
		state_machine.get_follow_target() == follow_proxy,
		"explicit follow target overrides automatic player resolution"
	)
	_expect(
		state_machine.get(&"debug_current_follow_target") == follow_proxy,
		"follow target debug property updates for an explicit target"
	)
	state_machine.set_follow_target(null)
	_expect(
		state_machine.get_follow_target() == player,
		"clearing explicit follow target restores automatic player resolution"
	)
	_expect(
		state_machine.get(&"debug_current_follow_target") == player,
		"follow target debug property restores the Player unit"
	)

	_finish()


func _create_unit(
	unit_name: String,
	unit_team_id: int,
	unit_collision_layer: int,
	unit_position: Vector3
) -> UnitBase:
	var unit := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.collision_layer = unit_collision_layer
	unit.position = unit_position
	_world.add_child(unit)
	return unit


func _create_player(
	player_name: String,
	player_position: Vector3
) -> PlayerBase:
	var player := (
		load(PLAYER_SCENE_PATH) as PackedScene
	).instantiate() as PlayerBase
	player.name = player_name
	player.position = player_position
	_world.add_child(player)
	player.set_physics_process(false)
	return player


func _wait_for_physics() -> void:
	await physics_frame
	await physics_frame


func _find_property_definition(
	object: Object,
	property_name: StringName
) -> Dictionary:
	for property_definition: Dictionary in object.get_property_list():
		if StringName(property_definition.get("name", "")) == property_name:
			return property_definition
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("AllyBehaviorStateMachineTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print(
		"AllyBehaviorStateMachineTest: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
