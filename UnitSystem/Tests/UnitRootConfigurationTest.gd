extends SceneTree

const AI_SCENE_PATH: String = "res://UnitSystem/AI/Ally/Units/Guardian.tscn"
const PLAYER_SCENE_PATH: String = "res://UnitSystem/Player/Hero/Hero.tscn"
const PREVIEW_SCRIPT_PATH: String = (
	"res://UnitSystem/Components/Combat/EditorWeaponPreview.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var unit_scene := load(
		"res://UnitSystem/Base/00_UnitBase.tscn"
	) as PackedScene
	var unit := unit_scene.instantiate() as UnitBase
	var unrelated_node := Node3D.new()
	root.add_child(unit)
	root.add_child(unrelated_node)
	_assert_true(
		unit.get_node_or_null(^"WorldUIRoot") is Node3D,
		"UnitBase provides the shared WorldUIRoot slot"
	)
	_assert_true(
		unit.get_node_or_null(^"WorldUIRoot/WorldHealthBar")
			is WorldHealthBar,
		"UnitBase assembles the removable WorldHealthBar component"
	)
	unit.attack_power = -3.0
	unit.defense = -7.0
	_assert_true(
		is_equal_approx(unit.get_attack_power(), 0.0),
		"attack getter clamps negative runtime values to zero"
	)
	_assert_true(
		is_equal_approx(unit.get_defense(), 0.0),
		"defense getter clamps negative runtime values to zero"
	)
	var has_default_suppression_property := _has_editor_property(
		unit,
		&"threat_action_suppression_at_125"
	)
	var default_suppression_at_125: float = (
		float(unit.get("threat_action_suppression_at_125"))
		if has_default_suppression_property
		else -1.0
	)
	_assert_true(
		has_default_suppression_property
		and is_equal_approx(default_suppression_at_125, 0.7),
		"UnitBase exposes a 70-percent-at-125 default threat action suppression setting"
	)
	_assert_true(
		unit.has_method(&"enter_combat")
		and unit.has_method(&"exit_combat")
		and unit.has_method(&"is_in_combat"),
		"UnitBase exposes non-exported combat lifecycle methods"
	)
	_assert_true(
		not _has_editor_property(unit, &"combat_state"),
		"combat lifecycle state is not an Inspector configuration field"
	)
	_assert_true(
		not bool(unit.call(&"is_in_combat")),
		"UnitBase starts outside combat"
	)
	unit.call(&"enter_combat")
	_assert_true(
		bool(unit.call(&"is_in_combat")),
		"UnitBase enters combat through its runtime interface"
	)
	unit.apply_damage(unit.get_current_health())
	_assert_true(unit.is_dead(), "lethal damage marks the unit dead")
	_assert_true(
		not bool(unit.call(&"is_in_combat")),
		"death always leaves the shared combat lifecycle"
	)
	_assert_true(not unit.is_targetable(), "dead units are not targetable")
	_assert_true(
		not bool(unit.call(&"is_friendly_to", unrelated_node)),
		"friendly relation safely rejects a non-UnitBase node"
	)
	_assert_true(
		not bool(unit.call(&"is_hostile_to", unrelated_node)),
		"hostile relation safely rejects a non-UnitBase node"
	)
	_assert_true(
		not bool(unit.call(&"is_neutral_to", unrelated_node)),
		"neutral relation safely rejects a non-UnitBase node"
	)
	unit.queue_free()
	var protected_unit := unit_scene.instantiate() as UnitBase
	root.add_child(protected_unit)
	var death_signal_count := 0
	protected_unit.died.connect(
		func(_source: Node) -> void:
			death_signal_count += 1
	)
	protected_unit.set("can_die", false)
	protected_unit.apply_damage(1000000.0)
	_assert_true(
		_has_editor_property(protected_unit, &"can_die"),
		"UnitBase exposes can_die as an Inspector configuration field"
	)
	_assert_true(
		is_equal_approx(protected_unit.get_current_health(), 1.0),
		"non-killable units retain one health after lethal damage"
	)
	_assert_true(
		not protected_unit.is_dead() and death_signal_count == 0,
		"non-killable units never enter the death lifecycle"
	)
	protected_unit.queue_free()
	unrelated_node.queue_free()
	_verify_role_stat_baselines()

	_assert_true(
		ResourceLoader.exists(PREVIEW_SCRIPT_PATH),
		"editor weapon preview script exists"
	)
	var guardian := load(AI_SCENE_PATH).instantiate() as Node
	_assert_true(guardian != null, "Guardian scene instantiates")
	if guardian != null:
		_assert_true(
			_has_property(guardian, &"starting_weapon"),
			"AI unit exposes starting_weapon on its root"
		)
		_assert_true(
			_has_property(guardian, &"formation_position"),
			"Ally unit exposes formation_position on its root"
		)
		_assert_true(
			is_equal_approx(float(guardian.get("threat_takeover_ratio")), 1.05),
			"Guardian overrides the default threat takeover ratio to 1.05"
		)
		var has_guardian_suppression_property := _has_property(
			guardian,
			&"threat_action_suppression_at_125"
		)
		var guardian_suppression_at_125: float = (
			float(guardian.get("threat_action_suppression_at_125"))
			if has_guardian_suppression_property
			else -1.0
		)
		_assert_true(
			has_guardian_suppression_property
			and is_equal_approx(guardian_suppression_at_125, 0.0),
			"Guardian disables threat action suppression as the tank role"
		)
		_assert_true(
			guardian.get_node_or_null(^"EditorWeaponPreview") != null,
			"AI unit contains the editor-only weapon preview component"
		)
		var combat: Node = guardian.get_node_or_null(^"CombatSystem")
		var behavior: Node = guardian.get_node_or_null(^"BehaviorStateMachine")
		_assert_true(combat != null, "AI unit retains CombatSystem")
		_assert_true(behavior != null, "Ally unit retains BehaviorStateMachine")
		if combat != null:
			_assert_true(
				not _has_editor_property(combat, &"starting_weapon"),
				"CombatSystem does not duplicate starting_weapon in Inspector"
			)
		if behavior != null:
			_assert_true(
				not _has_editor_property(behavior, &"formation_position"),
				"BehaviorStateMachine does not duplicate formation_position in Inspector"
			)
		guardian.free()

	var hero := load(PLAYER_SCENE_PATH).instantiate() as Node
	_assert_true(hero != null, "Hero scene instantiates")
	if hero != null:
		_assert_true(
			_has_property(hero, &"starting_weapon"),
			"Player unit exposes starting_weapon on its root"
		)
		_assert_true(
			hero.get_node_or_null(^"EditorWeaponPreview") != null,
			"Player unit contains the editor-only weapon preview component"
		)
		hero.free()
	_finish()


func _has_property(node: Object, property_name: StringName) -> bool:
	for property_info: Dictionary in node.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			return true
	return false


## 验证各角色将基础三维直接配置在继承场景根节点，而非依赖额外数值资源。
func _verify_role_stat_baselines() -> void:
	var expected_roles: Array[Dictionary] = [
		{
			"path": "res://UnitSystem/Player/Hero/Hero.tscn",
			"health": 120.0, "attack": 12.0, "defense": 8.0,
		},
		{
			"path": "res://UnitSystem/AI/Ally/Units/Guardian.tscn",
			"health": 200.0, "attack": 8.0, "defense": 35.0,
		},
		{
			"path": "res://UnitSystem/AI/Ally/Units/Saber.tscn",
			"health": 125.0, "attack": 16.0, "defense": 8.0,
		},
		{
			"path": "res://UnitSystem/AI/Ally/Units/Archer.tscn",
			"health": 95.0, "attack": 15.0, "defense": 3.0,
		},
		{
			"path": "res://UnitSystem/AI/Ally/Units/Caster.tscn",
			"health": 90.0, "attack": 16.0, "defense": 2.0,
		},
		{
			"path": "res://UnitSystem/AI/Ally/Units/Priest.tscn",
			"health": 105.0, "attack": 11.0, "defense": 5.0,
		},
		{
			"path": "res://UnitSystem/AI/Enemy/EnemyBase.tscn",
			"health": 100.0, "attack": 10.0, "defense": 0.0,
		},
	]
	for expected: Dictionary in expected_roles:
		var scene := load(expected.path) as PackedScene
		var role := scene.instantiate() as UnitBase if scene != null else null
		_assert_true(role != null, "Role stat fixture instantiates: " + str(expected.path))
		if role == null:
			continue
		_assert_true(
			is_equal_approx(role.maximum_health, float(expected.health)),
			"Role root config sets health: " + str(expected.path)
		)
		_assert_true(
			is_equal_approx(role.attack_power, float(expected.attack)),
			"Role root config sets attack: " + str(expected.path)
		)
		_assert_true(
			is_equal_approx(role.defense, float(expected.defense)),
			"Role root config sets defense: " + str(expected.path)
		)
		role.free()


func _has_editor_property(node: Object, property_name: StringName) -> bool:
	for property_info: Dictionary in node.get_property_list():
		if StringName(property_info.get("name", "")) != property_name:
			continue
		var usage: int = int(property_info.get("usage", 0))
		return (usage & PROPERTY_USAGE_EDITOR) != 0
	return false


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("UnitRootConfigurationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("UnitRootConfigurationTest: FAIL (%d)" % _failures.size())
	quit(1)
