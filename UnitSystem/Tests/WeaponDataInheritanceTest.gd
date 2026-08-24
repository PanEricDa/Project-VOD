extends SceneTree

## 验证武器数据按普攻交付方式分层：近战数据保存 Hitbox，远程数据保存投射物参数。
const SWORD_PATH := "res://Item/Weapon/Sword/IronSwordData.tres"
const IRON_SWORD_UID := "uid://bu388bdhai45r"
const MELEE_WEAPON_DATA_SCRIPT := preload("res://Item/Weapon/MeleeWeaponData.gd")
const SHIELD_PATH := "res://Item/Weapon/Shield/IronShieldData.tres"
const IRON_SHIELD_UID := "uid://dfvy0ic06ufm"
const STAFF_PATH := "res://Item/Weapon/Staff/StaffData.tres"
const GLOBE_PATH := "res://Item/Weapon/MagicGlobe/MagicGlobeData.tres"
const BOW_PATH := "res://Item/Weapon/Bow/BowData.tres"
const BOW_UID := "uid://d1ufbct3qqslr"

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_expect(load(SWORD_PATH) is MeleeWeaponData, "Iron Sword uses MeleeWeaponData")
	_expect(load(SHIELD_PATH) is MeleeWeaponData, "Iron Shield uses MeleeWeaponData")
	_expect(load(STAFF_PATH) is MeleeWeaponData, "Staff uses MeleeWeaponData as its fallback attack")
	_expect(load(GLOBE_PATH) is MeleeWeaponData, "Magic Globe uses MeleeWeaponData as its fallback attack")
	_expect(load(BOW_PATH) is RangedWeaponData, "Bow uses RangedWeaponData")

	var sword := load(SWORD_PATH) as MeleeWeaponData
	_expect(sword != null and not sword.hitbox_sizes.is_empty(), "Melee data owns Hitbox profiles")
	if sword != null:
		_expect(
			_has_property(sword, &"basic_attack_damage_variance"),
			"WeaponData exposes a basic attack damage variance setting"
		)
		_expect(
			_has_property(sword, &"basic_attack_threat_multiplier"),
			"WeaponData exposes a basic attack threat multiplier setting"
		)
		_expect(
			_has_property(sword, &"attack_movement_speed_multiplier"),
			"WeaponData exposes an attack movement speed multiplier setting"
		)
		if _has_property(sword, &"attack_movement_speed_multiplier"):
			_expect(
				is_equal_approx(float(sword.get("attack_movement_speed_multiplier")), 1.0),
				"Melee weapons keep full movement during basic attacks by default"
			)
		_expect(sword.get("basic_attack_base_damage") == 5.0, "Iron Sword basic attack base damage is 5.0")
		_expect(sword.get("basic_attack_power_ratio") == 1.0, "Iron Sword basic attack power ratio is 1.0")
		_expect(sword.call("get_combo_damage_multiplier", 1) == 1.0, "Iron Sword uses the default combo multiplier when no per-step multiplier is configured")
		_expect(sword.call("get_combo_damage_multiplier", 2) == 1.0, "Iron Sword combo step 2 multiplier is 1.0")
		_expect(sword.call("get_combo_damage_multiplier", 3) == 1.0, "Iron Sword uses the default multiplier for all unconfigured combo steps")
		_expect(sword.call("get_combo_damage_multiplier", 0) == 1.0, "Combo step 0 uses the fallback multiplier")
		_expect(sword.call("get_combo_damage_multiplier", 4) == 1.0, "Missing combo step uses the fallback multiplier")
		_expect(
			ResourceLoader.get_resource_uid(SWORD_PATH) == ResourceUID.text_to_id(IRON_SWORD_UID),
			"Iron Sword keeps its established resource UID"
		)
		_expect(sword.get_script() == MELEE_WEAPON_DATA_SCRIPT, "Iron Sword has the MeleeWeaponData script class")

		# 负倍率在运行时会被钳制为零，避免反向伤害。
		var negative_multipliers: Array[float] = [-0.5]
		sword.combo_damage_multipliers = negative_multipliers
		_expect(sword.call("get_combo_damage_multiplier", 1) == 0.0, "Negative combo multiplier is clamped to 0.0")

	var bow := load(BOW_PATH) as RangedWeaponData
	_expect(bow != null, "Ranged data loads")
	if bow != null:
		_expect(bow.projectile_scene != null, "Bow has a projectile configuration")
		if _has_property(bow, &"basic_attack_damage_variance") and _has_property(bow, &"basic_attack_threat_multiplier") and _has_property(bow, &"attack_movement_speed_multiplier"):
			_expect(
				is_equal_approx(float(bow.get("basic_attack_damage_variance")), 0.2),
				"Bow uses 20 percent basic attack damage variance"
			)
			_expect(
				is_equal_approx(float(bow.get("basic_attack_threat_multiplier")), 1.0),
				"Bow keeps one-to-one basic attack threat"
			)
			_expect(
				is_zero_approx(float(bow.get("attack_movement_speed_multiplier"))),
				"Bow prevents horizontal movement while its basic attack is active"
			)
		else:
			_expect(false, "Bow inherits all basic attack balance and movement fields")
	var shield := load(SHIELD_PATH) as MeleeWeaponData
	if shield != null:
		_expect(
			ResourceLoader.get_resource_uid(SHIELD_PATH) == ResourceUID.text_to_id(IRON_SHIELD_UID),
			"Iron Shield keeps a valid registered external resource UID"
		)
		if _has_property(shield, &"basic_attack_damage_variance") and _has_property(shield, &"basic_attack_threat_multiplier"):
			_expect(
				is_equal_approx(float(shield.get("basic_attack_damage_variance")), 0.05),
				"Iron Shield uses 5 percent basic attack damage variance"
			)
			_expect(
				is_equal_approx(float(shield.get("basic_attack_threat_multiplier")), 1.6),
				"Iron Shield uses 1.6 basic attack threat multiplier"
			)
		else:
			_expect(false, "Iron Shield inherits both basic attack balance fields")
		
	if bow != null:
		_expect(
			ResourceLoader.get_resource_uid(BOW_PATH) == ResourceUID.text_to_id(BOW_UID),
			"Bow keeps a valid registered external resource UID"
		)

	if _failures.is_empty():
		print("WeaponDataInheritanceTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("WeaponDataInheritanceTest: FAIL (%d)" % _failures.size())
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false
