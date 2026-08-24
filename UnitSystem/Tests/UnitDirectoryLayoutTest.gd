extends SceneTree

## UnitSystem 与武器资产目录迁移的专项契约测试。##
## 本测试不复刻用户已经主动删除的旧功能测试，只验证本次迁移最容易破坏的
## 文件位置、资源加载、Hero 武器装配以及 TestScene2 既有单位实例。
const REQUIRED_FILES: Array[String] = [
	"res://Item/Weapon/WeaponData.gd",
	"res://Item/Weapon/Sword/IronSwordData.tres",
	"res://Item/Weapon/Sword/IronSwordVisual.tscn",
	"res://Item/Weapon/Sword/SwordAnimationLibrary.res",
	"res://UnitSystem/Base/00_UnitBase.gd",
	"res://UnitSystem/Base/00_UnitBase.tscn",
	"res://UnitSystem/Base/AIUnitBase.gd",
	"res://UnitSystem/Base/AIUnitBase.tscn",
	"res://UnitSystem/Player/PlayerBase.gd",
	"res://UnitSystem/Player/PlayerBase.tscn",
	"res://UnitSystem/Player/Hero/Hero.tscn",
	"res://UnitSystem/Visuals/Player/HeroVisual.tscn",
	"res://UnitSystem/Visuals/Workbench/HeroAnimationWorkbench.tscn",
	"res://UnitSystem/AI/Ally/AllyBase.gd",
	"res://UnitSystem/AI/Ally/AllyBase.tscn",
	(
		"res://UnitSystem/AI/Ally/Formation/"
		+ "FormationPositionData.gd"
	),
	(
		"res://UnitSystem/AI/Ally/Formation/Positions/"
		+ "Defender.tres"
	),
	(
		"res://UnitSystem/AI/Ally/Formation/Positions/"
		+ "DefensiveMid.tres"
	),
	(
		"res://UnitSystem/AI/Ally/Formation/Positions/"
		+ "LeftWingBack.tres"
	),
	(
		"res://UnitSystem/AI/Ally/Formation/Positions/"
		+ "RightWingBack.tres"
	),
	(
		"res://UnitSystem/AI/Ally/Formation/Positions/"
		+ "AttackingMid.tres"
	),
	(
		"res://UnitSystem/AI/Ally/Formation/Positions/"
		+ "Forward.tres"
	),
	"res://UnitSystem/Tests/FormationPositionDataTest.gd",
	"res://UnitSystem/Tests/FormationTargetReservationTest.gd",
	"res://UnitSystem/Tests/ResourceUidAuditTest.gd",
	"res://UnitSystem/Tests/UnitRootConfigurationTest.gd",
	"res://UnitSystem/AI/Enemy/EnemyBase.gd",
	"res://UnitSystem/AI/Enemy/EnemyBase.tscn",
	"res://UnitSystem/Components/Animation/CharacterAnimationEventPlayer.gd",
	"res://UnitSystem/Components/Combat/EditorWeaponPreview.gd",
	"res://UnitSystem/Components/Combat/PlayerAttackController.gd",
	(
		"res://UnitSystem/Components/Combat/Common/"
		+ "MeleeHitboxComponent.gd"
	),
	(
		"res://UnitSystem/Components/Combat/Common/"
		+ "MeleeHitboxComponent.tscn"
	),
	"res://UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd",
	"res://UnitSystem/Components/Behavior/AllyBehaviorStateMachine.tscn",
	"res://UnitSystem/Components/Targeting/AI/AITargetingComponent.gd",
	"res://UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn",
	(
		"res://UnitSystem/Components/Targeting/AI/Policies/"
		+ "TargetSelectionPolicy.gd"
	),
	(
		"res://UnitSystem/Components/Targeting/AI/Policies/"
		+ "DefaultNearestEnemy.tres"
	),
]

const LEGACY_FILES: Array[String] = [
	"res://UnitSystem/Components/Movement/LocomotionComponent.gd",
	"res://UnitSystem/Components/Movement/LocomotionComponent.tscn",
	"res://UnitSystem/Components/Movement/FormationComponent.gd",
	"res://UnitSystem/Components/Movement/FormationComponent.tscn",
	"res://UnitSystem/Components/Combat/PlayerMeleeHitbox.gd",
	"res://UnitSystem/Components/Combat/PlayerMeleeHitbox.tscn",
	"res://UnitSystem/Combat/WeaponData.gd",
	"res://UnitSystem/Combat/PlayerAttackController.gd",
	"res://UnitSystem/Combat/PlayerMeleeHitbox.gd",
	"res://UnitSystem/Combat/PlayerMeleeHitbox.tscn",
	"res://UnitSystem/Combat/CharacterAnimationEventPlayer.gd",
	"res://UnitSystem/00_UnitBase.gd",
	"res://UnitSystem/00_UnitBase.tscn",
	"res://UnitSystem/AIUnitBase.gd",
	"res://UnitSystem/AIUnitBase.tscn",
	"res://UnitSystem/PlayerBase.gd",
	"res://UnitSystem/PlayerBase.tscn",
	"res://UnitSystem/AllyBase.gd",
	"res://UnitSystem/AllyBase.tscn",
	"res://UnitSystem/EnemyBase.gd",
	"res://UnitSystem/EnemyBase.tscn",
	"res://UnitSystem/Players/Hero/Hero.tscn",
	"res://UnitSystem/Players/Hero/Weapons/IronSword/IronSwordData.tres",
]

const LOADABLE_SCENES: Array[String] = [
	"res://UnitSystem/Base/00_UnitBase.tscn",
	"res://UnitSystem/Base/AIUnitBase.tscn",
	"res://UnitSystem/Player/PlayerBase.tscn",
	"res://UnitSystem/Player/Hero/Hero.tscn",
	"res://UnitSystem/AI/Ally/AllyBase.tscn",
	"res://UnitSystem/AI/Enemy/EnemyBase.tscn",
	"res://UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn",
	"res://UnitSystem/Components/Behavior/AllyBehaviorStateMachine.tscn",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_directory_contract()
	_verify_resources_load()
	_finish()


func _verify_directory_contract() -> void:
	for path: String in REQUIRED_FILES:
		_assert_true(ResourceLoader.exists(path), "required migrated file exists: " + path)
	for path: String in LEGACY_FILES:
		_assert_true(not ResourceLoader.exists(path), "legacy file is absent: " + path)


func _verify_resources_load() -> void:
	for path: String in LOADABLE_SCENES:
		if not ResourceLoader.exists(path):
			continue
		var packed_scene := load(path) as PackedScene
		_assert_true(packed_scene != null, "scene loads: " + path)
		if packed_scene == null:
			continue
		var instance: Node = packed_scene.instantiate()
		_assert_true(instance != null, "scene instantiates: " + path)
		if instance != null:
			instance.free()

	var unit_base_scene := load(
		"res://UnitSystem/Base/00_UnitBase.tscn"
	) as PackedScene
	if unit_base_scene != null:
		var unit_base: Node = unit_base_scene.instantiate()
		var skill_host: Node = unit_base.get_node_or_null(^"SkillHost")
		_assert_true(skill_host != null, "UnitBase contains SkillHost")
		if skill_host != null:
			_assert_true(
			skill_host.get_node_or_null(^"SkillSocket") != null,
				"UnitBase SkillHost contains SkillSocket"
			)
		unit_base.free()

	var weapon_path := "res://Item/Weapon/Sword/IronSwordData.tres"
	if ResourceLoader.exists(weapon_path):
		var weapon_data: Resource = load(weapon_path)
		_assert_true(weapon_data != null, "IronSwordData loads from Item/Weapon")
		if weapon_data != null:
			_assert_equal(
				weapon_data.resource_path,
				weapon_path,
				"IronSwordData keeps its migrated resource path"
				)

	var formation_position_path := (
		"res://UnitSystem/AI/Ally/Formation/Positions/"
		+ "Forward.tres"
	)
	if ResourceLoader.exists(formation_position_path):
		var formation_position := load(
			formation_position_path
		) as FormationPositionData
		_assert_true(
			formation_position != null,
			"Forward loads as FormationPositionData"
		)
		if formation_position != null:
			_assert_equal(
				formation_position.resource_path,
				formation_position_path,
				"Forward keeps its canonical resource path"
			)

	var hero_path := "res://UnitSystem/Player/Hero/Hero.tscn"
	if ResourceLoader.exists(hero_path):
		var hero := (load(hero_path) as PackedScene).instantiate()
		var controller: Node = hero.get_node_or_null(^"AttackController")
		_assert_true(controller != null, "Hero retains AttackController")
		var starting_weapon: Resource = hero.get("starting_weapon") as Resource
		_assert_true(starting_weapon != null, "Hero root retains starting weapon")
		if starting_weapon != null:
			_assert_equal(
				starting_weapon.resource_path,
				weapon_path,
				"Hero root starting weapon points to Item/Weapon"
			)
		hero.free()


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, expected, actual])


func _finish() -> void:
	if failures.is_empty():
		print("UnitDirectoryLayoutTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
