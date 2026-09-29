extends SceneTree

## 验证单位临时属性效果只由通用 StatusEffectComponent 管理。

const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var unit := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	_expect(unit != null, "UnitBase scene instantiates")
	if unit == null:
		_finish()
		return
	unit.defense = 35.0
	_world.add_child(unit)
	await process_frame

	var status_effects := unit.get_node_or_null(^"StatusEffect")
	_expect(status_effects != null, "UnitBase mounts StatusEffectComponent")
	_expect(unit.has_method(&"get_status_effect_component"), "UnitBase exposes its status component")
	if status_effects == null:
		_finish()
		return

	_expect(
		bool(status_effects.call(&"apply_modifier", self, 1, 20.0, 5.0, 0)),
		"a temporary defense modifier is accepted"
	)
	_expect(is_equal_approx(unit.get_defense(), 55.0), "temporary defense increases effective defense")
	_expect(
		bool(status_effects.call(&"apply_modifier", self, 1, 20.0, 5.0, 0)),
		"the same modifier source refreshes"
	)
	_expect(
		int(status_effects.call(&"get_active_modifier_count")) == 1,
		"refreshing a modifier does not stack a duplicate"
	)
	status_effects.call(&"advance_effects", 5.1)
	_expect(is_equal_approx(unit.get_defense(), 35.0), "expired modifier restores base defense")
	if not status_effects.has_method(&"apply_named_status"):
		_expect(false, "StatusEffectComponent accepts a generic named status")
		_finish()
		return
	_expect(bool(status_effects.call(&"apply_named_status", &"burning", 4.0)), "burning status is accepted")
	_expect(bool(status_effects.call(&"has_named_status", &"burning")), "burning is queryable")
	_expect((status_effects.call(&"get_active_status_ids") as Array).has(&"burning"), "status IDs are available for a pre-hit snapshot")
	status_effects.call(&"advance_effects", 2.0)
	_expect(bool(status_effects.call(&"apply_named_status", &"burning", 4.0)), "reapplying refreshes the status")
	status_effects.call(&"advance_effects", 3.9)
	_expect(bool(status_effects.call(&"has_named_status", &"burning")), "refreshed status survives old expiry")
	status_effects.call(&"advance_effects", 0.2)
	_expect(not bool(status_effects.call(&"has_named_status", &"burning")), "named status expires")
	_expect(not bool(status_effects.call(&"apply_named_status", &"", 4.0)), "empty status ID is rejected")
	_expect(not bool(status_effects.call(&"apply_named_status", &"burning", 0.0)), "zero duration is rejected")
	_expect(not bool(status_effects.call(&"apply_named_status", &"burning", INF)), "non-finite duration is rejected")
	_expect(bool(status_effects.call(&"apply_named_status", &"burning", 4.0)), "status can be reapplied")
	status_effects.call(&"clear_all_modifiers")
	_expect(bool(status_effects.call(&"has_named_status", &"burning")), "clearing modifiers does not erase named status")
	unit.apply_damage(9999.0, unit)
	_expect(not bool(status_effects.call(&"has_named_status", &"burning")), "death clears named status")

	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("StatusEffectComponentTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("StatusEffectComponentTest: FAIL (%d)" % _failures.size())
	quit(1)
