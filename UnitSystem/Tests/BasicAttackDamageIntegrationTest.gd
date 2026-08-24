extends SceneTree

const HERO_SCENE_PATH: String = "res://UnitSystem/Player/Hero/Hero.tscn"
const SABER_SCENE_PATH: String = "res://UnitSystem/AI/Ally/Units/Saber.tscn"
const ARCHER_SCENE_PATH: String = "res://UnitSystem/AI/Ally/Units/Archer.tscn"
const TARGET_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const ENEMY_TARGET_SCENE_PATH: String = "res://UnitSystem/AI/Enemy/EnemyBase.tscn"

var _failures: Array[String] = []
var _world: Node3D
var _player_hit_count: int = 0
var _ai_melee_hit_count: int = 0
var _ai_ranged_hit_count: int = 0
var _player_signal_saw_updated_health: bool = false
var _ai_melee_signal_saw_updated_health: bool = false
var _ai_ranged_signal_saw_updated_health: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "BasicAttackDamageIntegrationTestWorld"
	root.add_child(_world)

	var hero := _instantiate_unit(HERO_SCENE_PATH, "Hero") as PlayerBase
	var saber := _instantiate_unit(SABER_SCENE_PATH, "Saber") as AllyBase
	var archer := _instantiate_unit(ARCHER_SCENE_PATH, "Archer") as AllyBase
	var player_target := _create_target("PlayerTarget")
	var ai_melee_target := _create_target("AIMeleeTarget")
	var ai_ranged_target := _create_enemy_target("AIRangedTarget")
	if (
		hero == null
		or saber == null
		or archer == null
		or player_target == null
		or ai_melee_target == null
		or ai_ranged_target == null
	):
		_finish()
		return

	hero.set_physics_process(false)
	saber.set_physics_process(false)
	archer.set_physics_process(false)
	ai_ranged_target.set_physics_process(false)
	await _wait_for_scene_setup()

	_test_player(hero, player_target)
	_test_ai_melee(saber, ai_melee_target)
	_test_ai_ranged(archer, ai_ranged_target)
	_test_unarmed_player_still_emits(hero, player_target)
	_finish()


func _instantiate_unit(scene_path: String, unit_name: String) -> UnitBase:
	var scene := load(scene_path) as PackedScene
	_expect(scene != null, "%s scene loads" % unit_name)
	if scene == null:
		return null
	var unit := scene.instantiate() as UnitBase
	_expect(unit != null, "%s scene instantiates as UnitBase" % unit_name)
	if unit == null:
		return null
	unit.name = unit_name
	_world.add_child(unit)
	return unit


func _create_target(target_name: String) -> UnitBase:
	var scene := load(TARGET_SCENE_PATH) as PackedScene
	_expect(scene != null, "%s target scene loads" % target_name)
	if scene == null:
		return null
	var target := scene.instantiate() as UnitBase
	_expect(target != null, "%s instantiates as UnitBase" % target_name)
	if target == null:
		return null
	target.name = target_name
	target.maximum_health = 100.0
	target.defense = 0.0
	_world.add_child(target)
	return target


func _create_enemy_target(target_name: String) -> EnemyBase:
	var scene := load(ENEMY_TARGET_SCENE_PATH) as PackedScene
	_expect(scene != null, "%s enemy target scene loads" % target_name)
	if scene == null:
		return null
	var target := scene.instantiate() as EnemyBase
	_expect(target != null, "%s instantiates as EnemyBase" % target_name)
	if target == null:
		return null
	target.name = target_name
	target.maximum_health = 100.0
	target.defense = 0.0
	_world.add_child(target)
	return target


func _wait_for_scene_setup() -> void:
	await process_frame
	await process_frame
	await physics_frame


func _test_player(hero: PlayerBase, target: UnitBase) -> void:
	var controller := hero.get_node_or_null(^"AttackController") as PlayerAttackController
	_expect(controller != null, "Hero exposes PlayerAttackController")
	if controller == null:
		return
	_expect(
		controller.get("_equipped_weapon") != null,
		"Hero equips Iron Sword after deferred scene setup"
	)
	var weapon := controller.get("_equipped_weapon") as WeaponData
	if weapon == null:
		return
	weapon.basic_attack_damage_variance = 0.0
	var health_before: float = target.get_current_health()
	var expected_health := health_before - CombatValueResolver.calculate_damage(
		hero,
		target,
		weapon.basic_attack_base_damage,
		weapon.basic_attack_power_ratio,
		weapon.get_combo_damage_multiplier(1)
	)
	controller.attack_hit.connect(_on_player_attack_hit.bind(target))
	controller.call(
		"_on_melee_hitbox_attack_hit",
		target,
		target.global_position,
		Vector3.FORWARD,
		1
	)
	_assert_approx(
		target.get_current_health(),
		expected_health,
		"Hero first Iron Sword hit follows the current weapon and UnitBase stats"
	)
	_expect(_player_hit_count == 1, "Hero attack_hit emits once per confirmed hit")
	_expect(
		_player_signal_saw_updated_health,
		"Hero attack_hit emits after target health updates"
	)


func _test_ai_melee(saber: AllyBase, target: UnitBase) -> void:
	var combat := saber.get_combat_system()
	_expect(combat != null, "Saber exposes AICombatSystem")
	if combat == null:
		return
	_expect(combat.get_equipped_weapon() != null, "Saber equips Iron Sword")
	var weapon := combat.get_equipped_weapon()
	if weapon == null:
		return
	weapon.basic_attack_damage_variance = 0.0
	var expected_health := target.get_current_health() - CombatValueResolver.calculate_damage(
		saber,
		target,
		weapon.basic_attack_base_damage,
		weapon.basic_attack_power_ratio,
		weapon.get_combo_damage_multiplier(1)
	)
	combat.attack_hit.connect(_on_ai_melee_attack_hit.bind(target))
	combat.report_attack_hit(target, target.global_position, Vector3.FORWARD, 1)
	_assert_approx(
		target.get_current_health(),
		expected_health,
		"Saber first Iron Sword hit follows the current weapon and UnitBase stats"
	)
	_expect(_ai_melee_hit_count == 1, "Saber attack_hit emits once per confirmed hit")
	_expect(
		_ai_melee_signal_saw_updated_health,
		"Saber attack_hit emits after target health updates"
	)


func _test_ai_ranged(archer: AllyBase, target: EnemyBase) -> void:
	var combat := archer.get_combat_system() as AIRangedCombatSystem
	_expect(combat != null, "Archer exposes AIRangedCombatSystem")
	if combat == null:
		return
	_expect(combat.get_equipped_weapon() != null, "Archer equips Bow")
	var weapon := combat.get_equipped_weapon()
	if weapon == null:
		return
	_expect(
		combat.has_method(&"get_attack_movement_speed_multiplier"),
		"AI combat exposes the equipped weapon's attack movement multiplier"
	)
	if combat.has_method(&"get_attack_movement_speed_multiplier"):
		_expect(
			is_zero_approx(float(combat.call("get_attack_movement_speed_multiplier"))),
			"Archer combat resolves Bow's stationary-attack movement setting"
		)
	if not _has_property(weapon, &"basic_attack_damage_variance") or not _has_property(weapon, &"basic_attack_threat_multiplier"):
		_expect(false, "WeaponData exposes basic attack variance and threat multiplier for ranged combat")
		return
	weapon.set("basic_attack_damage_variance", 0.0)
	weapon.set("basic_attack_threat_multiplier", 1.6)
	var health_before: float = target.get_current_health()
	var expected_health := health_before - CombatValueResolver.calculate_damage(
		archer,
		target,
		weapon.basic_attack_base_damage,
		weapon.basic_attack_power_ratio,
		weapon.get_combo_damage_multiplier(1)
	)
	combat.attack_hit.connect(_on_ai_ranged_attack_hit.bind(target))
	combat.call(
		"_on_projectile_hit",
		target,
		target.global_position,
		Vector3.FORWARD,
		1
	)
	_assert_approx(
		target.get_current_health(),
		expected_health,
		"Archer Bow hit follows the current weapon and UnitBase stats"
	)
	_expect(_ai_ranged_hit_count == 1, "Archer attack_hit emits once per confirmed hit")
	_expect(
		_ai_ranged_signal_saw_updated_health,
		"Archer attack_hit emits after target health updates"
	)
	var threat_component := target.get_threat_component()
	_expect(threat_component != null, "Enemy target exposes the local threat component")
	if threat_component != null:
		_expect(
			is_equal_approx(
				float(threat_component.call("get_threat_for", archer)),
				(health_before - target.get_current_health()) * 1.6
			),
			"Ranged basic attack submits actual damage multiplied by its WeaponData threat multiplier"
		)


func _test_unarmed_player_still_emits(hero: PlayerBase, target: UnitBase) -> void:
	var controller := hero.get_node_or_null(^"AttackController") as PlayerAttackController
	if controller == null:
		return
	controller.unequip_weapon()
	var health_before: float = target.get_current_health()
	_player_hit_count = 0
	_player_signal_saw_updated_health = false
	controller.call(
		"_on_melee_hitbox_attack_hit",
		target,
		target.global_position,
		Vector3.FORWARD,
		1
	)
	_assert_approx(
		target.get_current_health(),
		health_before,
		"Unarmed confirmed hit leaves target health unchanged"
	)
	_expect(_player_hit_count == 1, "Unarmed confirmed hit still emits attack_hit once")


func _on_player_attack_hit(
	target: UnitBase,
	_hit_position: Vector3,
	_hit_direction: Vector3,
	_attack_index: int,
	expected_target: UnitBase
) -> void:
	_player_hit_count += 1
	_player_signal_saw_updated_health = (
		target == expected_target
		and target.get_current_health() < target.get_maximum_health()
	)


func _on_ai_melee_attack_hit(
	target: UnitBase,
	_hit_position: Vector3,
	_hit_direction: Vector3,
	_attack_index: int,
	expected_target: UnitBase
) -> void:
	_ai_melee_hit_count += 1
	_ai_melee_signal_saw_updated_health = (
		target == expected_target
		and target.get_current_health() < target.get_maximum_health()
	)


func _on_ai_ranged_attack_hit(
	target: UnitBase,
	_hit_position: Vector3,
	_hit_direction: Vector3,
	_attack_index: int,
	expected_target: UnitBase
) -> void:
	_ai_ranged_hit_count += 1
	_ai_ranged_signal_saw_updated_health = (
		target == expected_target
		and target.get_current_health() < target.get_maximum_health()
	)


func _assert_approx(actual: float, expected: float, message: String) -> void:
	_expect(
		is_equal_approx(actual, expected),
		"%s (expected %s, got %s)" % [message, expected, actual]
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("BasicAttackDamageIntegrationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("BasicAttackDamageIntegrationTest: FAIL (%d)" % _failures.size())
	quit(1)
