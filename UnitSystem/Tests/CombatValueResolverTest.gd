extends SceneTree

const RESOLVER_PATH: String = "res://UnitSystem/Combat/CombatValueResolver.gd"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := UnitBase.new()
	var target := UnitBase.new()
	root.add_child(source)
	root.add_child(target)
	await process_frame

	var resolver: Script = load(RESOLVER_PATH) as Script
	_assert_true(resolver != null, "CombatValueResolver script loads")
	if resolver == null:
		_finish()
		return

	source.attack_power = 20.0
	target.defense = 100.0
	_assert_approx(
		float(resolver.calculate_damage(source, target, 10.0, 1.0, 1.5)),
		22.5,
		"damage includes source attack, target defense, and multiplier"
	)
	for _roll_index: int in range(24):
		var varied_damage: float = float(
			resolver.calculate_damage(source, target, 10.0, 1.0, 1.0, 0.2)
		)
		_assert_true(
			varied_damage >= 12.0 and varied_damage <= 18.0,
			"20 percent damage variance remains within the expected resolved-damage range"
		)
	_assert_approx(
		float(resolver.calculate_healing(source, 5.0, 0.5, 2.0)),
		30.0,
		"healing includes source attack and multiplier"
	)
	_assert_approx(
		float(resolver.calculate_damage(source, target, -10.0, 1.0, 1.0)),
		10.0,
		"negative damage base value clamps to zero while attack scaling remains"
	)
	_assert_approx(
		float(resolver.calculate_damage(source, target, 10.0, -1.0, 1.0)),
		5.0,
		"negative damage power ratio clamps to zero"
	)
	_assert_approx(
		float(resolver.calculate_healing(source, -5.0, 0.5, 1.0)),
		10.0,
		"negative healing base amount clamps to zero while attack scaling remains"
	)
	_assert_approx(
		float(resolver.calculate_healing(source, 5.0, -0.5, 1.0)),
		5.0,
		"negative healing power ratio clamps to zero"
	)
	_assert_approx(
		float(resolver.calculate_damage(null, target, 10.0, 1.0, 1.0)),
		5.0,
		"null source uses only base damage"
	)
	_assert_approx(
		float(resolver.calculate_healing(null, 5.0, 0.5, 2.0)),
		10.0,
		"null source uses only base healing"
	)
	_assert_approx(
		float(resolver.apply_damage(source, null, 10.0)),
		0.0,
		"damage application rejects a null target"
	)
	_assert_approx(
		float(resolver.apply_healing(source, null, 10.0)),
		0.0,
		"healing application rejects a null target"
	)
	target.apply_damage(target.get_current_health())
	_assert_approx(
		float(resolver.apply_damage(source, target, 10.0)),
		0.0,
		"damage application rejects a dead target"
	)
	_assert_approx(
		float(resolver.apply_healing(source, target, 10.0)),
		0.0,
		"healing application rejects a dead target"
	)

	var wounded_target := UnitBase.new()
	wounded_target.maximum_health = 25.0
	root.add_child(wounded_target)
	await process_frame
	_assert_approx(
		float(resolver.apply_damage(source, wounded_target, 100.0)),
		25.0,
		"damage application returns only the health actually removed"
	)
	wounded_target.revive(20.0)
	_assert_approx(
		float(resolver.apply_healing(source, wounded_target, 100.0)),
		5.0,
		"healing application returns only the health actually restored"
	)
	_finish()


func _assert_approx(actual: float, expected: float, message: String) -> void:
	_assert_true(is_equal_approx(actual, expected), "%s (expected %s, got %s)" % [message, expected, actual])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CombatValueResolverTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("CombatValueResolverTest: FAIL (%d)" % _failures.size())
	quit(1)
