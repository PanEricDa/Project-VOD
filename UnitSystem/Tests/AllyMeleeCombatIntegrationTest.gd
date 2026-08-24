extends SceneTree

const PLAYER_SCENE_PATH: String = "res://UnitSystem/Player/PlayerBase.tscn"
const ALLY_SCENE_PATH: String = \
	"res://UnitSystem/AI/Ally/Units/Saber.tscn"
const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const IRON_SWORD_PATH: String = (
	"res://Item/Weapon/Sword/IronSwordData.tres"
)

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "AllyMeleeCombatIntegrationTestWorld"
	root.add_child(_world)

	var player := (
		load(PLAYER_SCENE_PATH) as PackedScene
	).instantiate() as PlayerBase
	player.name = "Player"
	player.position = Vector3.ZERO
	_world.add_child(player)
	player.set_physics_process(false)

	var saber := (load(ALLY_SCENE_PATH) as PackedScene).instantiate() as AllyBase
	saber.name = "Saber"
	saber.position = Vector3.ZERO
	saber.gravity_multiplier = 0.0
	_world.add_child(saber)
	saber.set_physics_process(false)

	var enemy := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	enemy.name = "Enemy"
	enemy.team_id = 2
	enemy.collision_layer = 4
	enemy.collision_mask = 0
	## 0.89m 会落入旧实现的轻微径向修正分支：修正距离小于 arrival_distance，
	## 因而能够稳定复现“有移动目标但实际速度永远为零”的问题。
	enemy.position = Vector3(0.0, 0.0, -0.89)
	_world.add_child(enemy)

	var combat: AICombatSystem = saber.get_combat_system()
	var behavior: AllyBehaviorStateMachine = saber.get_behavior_state_machine()
	var targeting: AITargetingComponent = saber.get_targeting_component()
	var sword := load(IRON_SWORD_PATH) as WeaponData
	_expect(combat != null, "Saber exposes AICombatSystem")
	_expect(behavior != null, "Saber exposes AllyBehaviorStateMachine")
	_expect(targeting != null, "Saber exposes AITargetingComponent")
	if combat == null or behavior == null or targeting == null:
		_finish()
		return

	_expect(
		combat.get_equipped_weapon() == sword,
		"Saber equips IronSword through the inherited CombatSystem"
	)
	_expect(
		is_equal_approx(behavior.get_effective_combat_distance(), 1.1),
		"behavior reads the equipped sword attack range"
	)

	await _wait_for_physics()
	targeting.refresh_target()
	_expect(targeting.get_locked_target() == enemy, "Saber acquires the enemy")
	behavior.physics_tick(0.016)
	behavior.physics_tick(0.016)
	_expect(
		behavior.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.COMBAT_ATTACK,
		"Saber enters COMBAT_ATTACK after reaching sword range"
	)
	_expect(combat.is_attacking(), "Saber starts one sword animation")
	behavior.physics_tick(0.016)
	_expect(
		saber.has_movement_target(),
		"Saber keeps a combat-orbit movement target during the attack animation"
	)
	var position_before_orbit: Vector3 = saber.global_position
	saber.set_physics_process(true)
	await _wait_physics_frames(12)
	saber.set_physics_process(false)
	var horizontal_displacement := Vector2(
		saber.global_position.x - position_before_orbit.x,
		saber.global_position.z - position_before_orbit.z
	).length()
	_expect(
		horizontal_displacement > 0.02,
		"combat orbit produces real horizontal movement above arrival threshold"
	)
	_expect(
		combat.is_global_cooldown_ready(),
		"behavior owns the shared cooldown while CombatSystem remains ready"
	)
	_expect(
		not combat.request_basic_attack(enemy),
		"GCD and active animation prevent overlapping attacks"
	)

	var cooldown_before_cancel: float = (
		combat.get_global_cooldown_remaining()
	)
	enemy.targetable = false
	targeting.refresh_target()
	behavior.physics_tick(0.016)
	_expect(
		behavior.get_current_state()
			== AllyBehaviorStateMachine.BehaviorState.RETURN,
		"invalidating the target exits combat through RETURN"
	)
	_expect(not combat.is_attacking(), "target loss cancels the active animation")
	_expect(
		is_equal_approx(
			combat.get_global_cooldown_remaining(),
			cooldown_before_cancel
		),
		"target loss does not clear the already-started GCD"
	)
	_finish()


func _wait_for_physics() -> void:
	await physics_frame
	await physics_frame


func _wait_physics_frames(frame_count: int) -> void:
	for _frame_index: int in range(frame_count):
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("AllyMeleeCombatIntegrationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print(
		"AllyMeleeCombatIntegrationTest: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
