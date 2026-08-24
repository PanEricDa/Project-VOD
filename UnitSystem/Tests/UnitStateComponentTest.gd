extends SceneTree

const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const MAX_FRAMES: int = 5

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	await _test_hit_movement_lock_lifecycle()
	await _test_keep_root_lifecycle()
	await _test_destroy_cancel()
	_finish()


func _test_hit_movement_lock_lifecycle() -> void:
	var unit := _create_unit("HitMovementLock")
	if unit == null:
		return
	_expect(
		unit.has_method(&"is_hit_movement_locked")
		and unit.has_method(&"advance_hit_movement_lock"),
		"UnitBase exposes the common hit movement lock interface"
	)
	if (
		not unit.has_method(&"is_hit_movement_locked")
		or not unit.has_method(&"advance_hit_movement_lock")
	):
		return
	_expect(
		is_equal_approx(unit.hit_movement_lock_duration, 0.07),
		"units default to a 0.07-second hit movement lock"
	)
	_expect(is_equal_approx(unit.apply_damage(1.0), 1.0), "nonlethal damage applies")
	_expect(unit.is_hit_movement_locked(), "effective damage starts the movement lock")
	unit.advance_hit_movement_lock(0.03)
	_expect(unit.is_hit_movement_locked(), "movement lock persists before its duration elapses")
	unit.advance_hit_movement_lock(0.05)
	_expect(not unit.is_hit_movement_locked(), "movement lock ends after its duration elapses")


func _test_keep_root_lifecycle() -> void:
	var unit := _create_unit("StateKeepRoot")
	var state := unit.get_node_or_null(^"UnitState") as UnitStateComponent
	_expect(state != null, "UnitBase exposes UnitStateComponent")
	if state == null:
		return
	_expect(state.death_mode == UnitStateComponent.DeathMode.KEEP_FOR_REVIVE, "default death mode keeps unit")
	unit.apply_damage(unit.maximum_health)
	await process_frame
	_expect(state.is_dead_state(), "state enters dead state")
	var visual := unit.get_node_or_null(^"Visual") as Node3D
	_expect(visual != null and visual.visible, "death keeps visual visible until cleanup")
	_expect(not state.is_pending_destroy(), "keep-root does not schedule destroy")
	_expect(unit.is_inside_tree(), "keep-root unit remains in tree")
	_expect(unit.revive(1.0), "unit revives")
	_expect(not state.is_dead_state(), "revive clears state")
	_expect(visual != null and visual.visible, "revive keeps visual visible")


func _test_destroy_cancel() -> void:
	var unit := _create_unit("StateDestroyCancel")
	var state := unit.get_node_or_null(^"UnitState") as UnitStateComponent
	if state == null:
		return
	state.death_mode = UnitStateComponent.DeathMode.REMOVE_AFTER_DELAY
	state.remove_after_seconds = 0.2
	unit.apply_damage(unit.maximum_health)
	await process_frame
	_expect(state.is_pending_destroy(), "destroy mode schedules pending destroy")
	state.cancel_pending_destroy()
	_expect(not state.is_pending_destroy(), "pending destroy can be cancelled")
	_expect(unit.is_inside_tree(), "cancelled unit remains in tree")
	_expect(unit.revive(1.0), "cancelled unit can revive")
	_expect(not state.is_dead_state(), "cancelled revive restores state")
	await _wait_frames(MAX_FRAMES)
	_expect(unit.is_inside_tree(), "cancelled timer cannot destroy revived unit")


func _create_unit(node_name: String) -> UnitBase:
	var scene := load(UNIT_SCENE_PATH) as PackedScene
	_expect(scene != null, "UnitBase scene loads")
	if scene == null:
		return null
	var unit := scene.instantiate() as UnitBase
	_expect(unit != null, "UnitBase scene instantiates")
	if unit == null:
		return null
	unit.name = node_name
	_world.add_child(unit)
	return unit


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("UnitStateComponentTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("UnitStateComponentTest: FAIL (%d)" % _failures.size())
	quit(1)
