extends SceneTree

const AI_SCENE_PATH := "res://UnitSystem/Base/AIUnitBase.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const ENEMY_VISUAL_SCENE_PATH := "res://UnitSystem/Visuals/Enemy/EnemyVisual.tscn"
const STATE_MACHINE_SCENE_PATH := (
	"res://UnitSystem/Components/Behavior/EnemyBehaviorStateMachine.tscn"
)
const TARGETING_SCENE_PATH := (
	"res://UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn"
)
const COMBAT_SCENE_PATH := (
	"res://UnitSystem/Components/Combat/AI/AICombatSystem.tscn"
)
const IRON_SWORD_PATH := "res://Item/Weapon/Sword/IronSwordData.tres"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "EnemyAttackEntryDelayTestWorld"
	root.add_child(_world)
	await _verify_direct_attack_entry_is_not_delayed()
	await _verify_chase_attack_entry_is_delayed_once()
	_finish()


func _verify_direct_attack_entry_is_not_delayed() -> void:
	var target := _create_target()
	var owner := _create_owner(Vector3(0.0, 0.0, 1.0))
	var targeting := _create_targeting(owner)
	var combat := _create_combat(owner)
	var state := _create_state(owner, targeting, combat)
	await physics_frame
	await physics_frame
	targeting.refresh_target()

	state.physics_tick(0.016)
	_expect(
		combat.is_attacking(),
		"a direct IDLE to ATTACK transition keeps the existing immediate attack"
	)

	owner.queue_free()
	target.queue_free()
	await process_frame



func _verify_chase_attack_entry_is_delayed_once() -> void:
	var target := _create_target()
	var owner := _create_owner(Vector3(0.0, 0.0, 2.0))
	var targeting := _create_targeting(owner)
	var combat := _create_combat(owner)
	var state := _create_state(owner, targeting, combat)
	await physics_frame
	await physics_frame
	targeting.refresh_target()
	state.physics_tick(0.016)
	_expect(
		state.get_current_state() == EnemyBehaviorStateMachine.State.CHASE,
		"a distant target first enters chase"
	)

	owner.global_position = Vector3(0.0, 0.0, 1.0)
	state.physics_tick(0.016)
	_expect(
		state.get_current_state() == EnemyBehaviorStateMachine.State.ATTACK,
		"entering weapon range transitions into attack before the delayed action"
	)
	_expect(
		not combat.is_attacking(),
		"entering attack starts the configured delay instead of attacking immediately"
	)
	_expect(
		is_equal_approx(combat.get_global_cooldown_remaining(), 0.4),
		"attack entry writes the deterministic delay into the existing global cooldown"
	)

	combat.call(&"_process", 0.2)
	state.physics_tick(0.016)
	_expect(
		combat.get_global_cooldown_remaining() < 0.3,
		"remaining in attack does not refresh the entry delay"
	)

	combat.call(&"_process", 0.3)
	state.physics_tick(0.016)
	_expect(
		combat.is_attacking(),
		"the existing basic-attack chain starts after the entry delay expires"
	)

	owner.queue_free()
	target.queue_free()
	await process_frame


func _create_owner(unit_position: Vector3) -> AIUnitBase:
	var owner := (
		load(AI_SCENE_PATH) as PackedScene
	).instantiate() as AIUnitBase
	owner.name = "EntryDelayOwner"
	owner.team_id = 2
	owner.collision_layer = 4
	owner.position = unit_position
	_world.add_child(owner)
	owner.set_physics_process(false)
	return owner


func _create_target() -> UnitBase:
	var target := (
		load(UNIT_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	target.name = "EntryDelayTarget"
	target.team_id = 1
	target.collision_layer = 2
	target.position = Vector3.ZERO
	_world.add_child(target)
	return target


func _create_targeting(owner: AIUnitBase) -> AITargetingComponent:
	var targeting := (
		load(TARGETING_SCENE_PATH) as PackedScene
	).instantiate() as AITargetingComponent
	owner.add_child(targeting)
	_expect(targeting.configure(owner, 10.0), "targeting configures")
	return targeting


func _create_combat(owner: AIUnitBase) -> AICombatSystem:
	var visual := (
		load(ENEMY_VISUAL_SCENE_PATH) as PackedScene
	).instantiate() as Node3D
	owner.get_node(^"Visual").add_child(visual)

	var combat := (
		load(COMBAT_SCENE_PATH) as PackedScene
	).instantiate() as AICombatSystem
	combat.name = "CombatSystemUnderTest"
	combat.starting_weapon = load(IRON_SWORD_PATH) as WeaponData
	owner.add_child(combat)
	_expect(combat.configure(owner), "combat system configures")
	return combat


func _create_state(
	owner: AIUnitBase,
	targeting: AITargetingComponent,
	combat: AICombatSystem
) -> EnemyBehaviorStateMachine:
	var state := (
		load(STATE_MACHINE_SCENE_PATH) as PackedScene
	).instantiate() as EnemyBehaviorStateMachine
	state.attack_entry_delay_min = 0.4
	state.attack_entry_delay_max = 0.4
	state.combat_wander_radius = 0.0
	owner.add_child(state)
	_expect(state.configure(owner, targeting, combat), "state machine configures")
	return state


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("EnemyAttackEntryDelayTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("EnemyAttackEntryDelayTest: FAIL (%d)" % _failures.size())
	quit(1)
