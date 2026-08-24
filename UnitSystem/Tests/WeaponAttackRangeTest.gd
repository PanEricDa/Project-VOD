extends SceneTree

const IRON_SWORD_PATH: String = (
	"res://Item/Weapon/Sword/IronSwordData.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	var sword := load(IRON_SWORD_PATH) as WeaponData
	_expect(sword != null, "IronSwordData loads as WeaponData")
	if sword != null:
		_expect(
			is_equal_approx(sword.attack_range, 1.1),
			"IronSword attack range is 1.1m"
		)
		_expect(
			is_equal_approx(sword.attack_range_tolerance, 0.1),
			"IronSword attack range tolerance is 0.1m"
		)
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("WeaponAttackRangeTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("WeaponAttackRangeTest: FAIL (%d)" % _failures.size())
	quit(1)
