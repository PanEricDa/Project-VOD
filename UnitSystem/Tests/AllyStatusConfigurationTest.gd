extends SceneTree

const ALLY_SCENE_PATH: String = "res://UnitSystem/AI/Ally/AllyBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_verify_source_scene_defaults()
	await _verify_runtime_health_and_death_lifecycle()
	_finish()


func _verify_source_scene_defaults() -> void:
	var source_text: String = FileAccess.get_file_as_string(ALLY_SCENE_PATH)
	_expect(
		source_text.contains("maximum_health = 100.0"),
		"AllyBase explicitly declares its inherited maximum health default"
	)
	_expect(
		source_text.contains("starting_health_percentage = 100.0"),
		"AllyBase explicitly declares its inherited full-health start"
	)
	_expect(
		source_text.contains("death_mode = 0"),
		"AllyBase explicitly keeps dead allies for future revival"
	)


func _verify_runtime_health_and_death_lifecycle() -> void:
	var scene: PackedScene = load(ALLY_SCENE_PATH) as PackedScene
	var ally: AllyBase = scene.instantiate() as AllyBase if scene != null else null
	_expect(ally != null, "AllyBase scene instantiates")
	if ally == null:
		return
	root.add_child(ally)
	await process_frame

	var health_bar := ally.get_node_or_null(^"WorldUIRoot/WorldHealthBar") as WorldHealthBar
	var unit_state := ally.get_node_or_null(^"UnitState") as UnitStateComponent
	_expect(health_bar != null, "AllyBase inherits the shared WorldHealthBar")
	_expect(unit_state != null, "AllyBase inherits the shared UnitState component")
	_expect(
		is_equal_approx(ally.get_health_ratio(), 1.0),
		"AllyBase starts at full configured health"
	)

	ally.apply_damage(20.0)
	await process_frame
	_expect(
		health_bar != null and health_bar.visible,
		"ally damage displays the inherited world health bar"
	)

	ally.apply_damage(ally.get_current_health())
	await process_frame
	_expect(ally.is_dead(), "lethal damage enters the ally dead state")
	_expect(
		is_instance_valid(ally) and unit_state != null
		and unit_state.death_mode == UnitStateComponent.DeathMode.KEEP_FOR_REVIVE,
		"dead allies remain in the scene under the revive-oriented death policy"
	)
	_expect(ally.revive(25.0), "an ally can be explicitly revived")
	_expect(ally.is_targetable(), "revived ally becomes targetable again")
	ally.queue_free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("AllyStatusConfigurationTest failed: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("AllyStatusConfigurationTest: PASS")
		quit(0)
		return
	printerr("AllyStatusConfigurationTest: FAIL\n- " + "\n- ".join(_failures))
	quit(1)
