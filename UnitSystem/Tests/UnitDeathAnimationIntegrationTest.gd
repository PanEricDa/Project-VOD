extends SceneTree

const UNIT_SCENE_PATH: String = "res://UnitSystem/Player/Hero/Hero.tscn"
const BASIC_LIBRARY_PATH: String = "res://UnitSystem/Visuals/Base/BasicAnimationLibrary.res"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_test_animation_resource_contract()
	await _test_unit_death_playback()
	_finish()


func _test_animation_resource_contract() -> void:
	var library := load(BASIC_LIBRARY_PATH) as AnimationLibrary
	_expect(library != null, "BasicAnimationLibrary loads")
	if library == null:
		return
	var animation := library.get_animation(&"Die")
	_expect(animation != null, "BasicAnimationLibrary contains Die")
	if animation == null:
		return
	var has_finish_marker := false
	for track_index: int in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_METHOD:
			continue
		for key_index: int in range(animation.track_get_key_count(track_index)):
			var key_value: Variant = animation.track_get_key_value(track_index, key_index)
			if key_value is Dictionary and key_value.get("method") == &"finish_death_animation":
				has_finish_marker = true
	_expect(has_finish_marker, "Die calls finish_death_animation")


func _test_unit_death_playback() -> void:
	var scene := load(UNIT_SCENE_PATH) as PackedScene
	_expect(scene != null, "UnitBase scene loads")
	if scene == null:
		return
	var unit := scene.instantiate() as UnitBase
	_expect(unit != null, "UnitBase instantiates")
	if unit == null:
		return
	_world.add_child(unit)
	await process_frame
	var state := unit.get_node_or_null(^"UnitState") as UnitStateComponent
	var visual_root := unit.get_node_or_null(^"Visual")
	var animation_player := (
		visual_root.find_child(&"CharacterAnimationPlayer", true, false)
		if visual_root != null
		else null
	) as CharacterAnimationEventPlayer
	_expect(state != null, "UnitBase exposes UnitState")
	_expect(animation_player != null, "UnitBase exposes CharacterAnimationEventPlayer")
	if state == null or animation_player == null:
		return
	unit.apply_damage(unit.maximum_health)
	await process_frame
	_expect(state.is_dead_state(), "death enters UnitState dead state")
	_expect(
		animation_player.current_animation == &"unit/Die",
		"death starts unit/Die animation"
	)
	_expect(unit.revive(1.0), "unit revives during animation")
	await process_frame
	_expect(
		animation_player.current_animation != &"unit/Die",
		"revive stops death animation"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("UnitDeathAnimationIntegrationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("UnitDeathAnimationIntegrationTest: FAIL (%d)" % _failures.size())
	quit(1)
