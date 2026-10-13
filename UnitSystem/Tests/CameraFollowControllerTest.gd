extends SceneTree

const CAMERA_CONTROLLER_SCRIPT_PATH := (
	"res://UnitSystem/Components/Camera/CameraFollowController.gd"
)
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const COMBAT_ROOM_SCENE_PATH := "res://Scenes/TestCombatRoom.tscn"

var _failures: Array[String] = []
var _world: Node3D
var _camera_rig: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "CameraFollowControllerTestWorld"
	root.add_child(_world)

	await _verify_stepped_zoom()
	await _verify_unique_player_resolution()
	await _verify_resolution_recovers_after_player_is_removed()
	await _verify_living_focus_falls_back_from_player_to_ally_then_enemy()
	await _verify_multiple_players_are_not_bound()
	_verify_combat_room_structure()
	_finish()


## 真实输入管线验证档位边界、按键重绑定、独立平滑和焦点切换保留档位。
func _verify_stepped_zoom() -> void:
	var rig := Node3D.new()
	rig.set_script(load(CAMERA_CONTROLLER_SCRIPT_PATH))
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.rotation_degrees.x = -50.0
	camera.position = Vector3(0.2, 0.1, 0.0)
	camera.fov = 45.0
	var baseline := camera.position
	rig.add_child(camera)
	_world.add_child(rig)
	rig.set_process(false)
	camera.make_current()
	_expect(rig.get("zoom_distances") != null, "Camera has configured zoom steps")
	_expect(InputMap.has_action(&"camera_zoom_in") and InputMap.has_action(&"camera_zoom_out"), "Zoom bindings exist in project InputMap")
	if rig.get("zoom_distances") == null or not InputMap.has_action(&"camera_zoom_in") or not InputMap.has_action(&"camera_zoom_out"):
		rig.free()
		return
	_expect(camera.position.is_equal_approx(baseline + camera.basis.z * 3.0), "Standard step initially moves camera along its viewing axis")
	var has_wheel_up := false
	var has_wheel_down := false
	for event: InputEvent in InputMap.action_get_events(&"camera_zoom_in"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			has_wheel_up = true
	for event: InputEvent in InputMap.action_get_events(&"camera_zoom_out"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			has_wheel_down = true
	_expect(has_wheel_up and has_wheel_down, "Project binds both wheel directions")
	await _send_zoom_action(&"camera_zoom_out")
	var before := camera.position
	rig.call("_process", 0.05)
	_expect(camera.position.distance_to(before) > 0.0 and camera.position.distance_to(baseline) < 6.0, "Zoom interpolates instead of jumping")
	rig.call("_process", 2.0)
	_expect(camera.position.is_equal_approx(baseline + camera.basis.z * 6.0), "One action advances exactly one step")
	for _index: int in range(6):
		await _send_zoom_action(&"camera_zoom_out")
	rig.call("_process", 2.0)
	_expect(camera.position.is_equal_approx(baseline + camera.basis.z * 9.0), "Zoom stops at farthest step")
	_expect(is_equal_approx(camera.fov, 45.0), "Zoom preserves projection FOV")
	var player := _create_unit("ZoomPlayer", "Player")
	var ally := _create_unit("ZoomAlly", "Ally")
	_world.add_child(player)
	_world.add_child(ally)
	rig.call("_resolve_follow_target")
	player.apply_damage(player.get_current_health())
	rig.call("_resolve_follow_target")
	_expect(rig.call("get_resolved_target") == ally, "Death still switches to ally")
	_expect(camera.position.is_equal_approx(baseline + camera.basis.z * 9.0), "Focus switch retains current zoom")
	player.free()
	ally.free()
	for _index: int in range(6):
		await _send_zoom_action(&"camera_zoom_in")
	rig.call("_process", 2.0)
	_expect(camera.position.is_equal_approx(baseline), "Zoom stops at closest step")
	var original_events := InputMap.action_get_events(&"camera_zoom_out")
	InputMap.action_erase_events(&"camera_zoom_out")
	var key_binding := InputEventKey.new()
	key_binding.physical_keycode = KEY_Z
	InputMap.action_add_event(&"camera_zoom_out", key_binding)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Z
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key = InputEventKey.new()
	key.physical_keycode = KEY_Z
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	rig.call("_process", 2.0)
	_expect(camera.position.is_equal_approx(baseline + camera.basis.z * 3.0), "Rebinding works without changing camera code")
	InputMap.action_erase_events(&"camera_zoom_out")
	for event: InputEvent in original_events:
		InputMap.action_add_event(&"camera_zoom_out", event)
	var wheel := InputEventMouseButton.new()
	wheel.device = 0
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await process_frame
	wheel = InputEventMouseButton.new()
	wheel.device = 0
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = false
	Input.parse_input_event(wheel)
	await process_frame
	rig.call("_process", 2.0)
	_expect(camera.position.is_equal_approx(baseline + camera.basis.z * 6.0), "Physical mouse wheel matches project binding")
	var other := Camera3D.new()
	_world.add_child(other)
	other.make_current()
	await _send_zoom_action(&"camera_zoom_out")
	rig.call("_process", 2.0)
	_expect(camera.position.is_equal_approx(baseline + camera.basis.z * 6.0), "Inactive camera ignores zoom input")
	other.free()
	rig.free()


func _send_zoom_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _verify_unique_player_resolution() -> void:
	_camera_rig = _create_camera_rig()
	var nested_parent := Node3D.new()
	nested_parent.name = "RenamedContainer"
	_world.add_child(nested_parent)
	var player := _create_unit("RenamedHero", "Player")
	nested_parent.add_child(player)
	await process_frame

	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == player,
		"a renamed nested Player unit is resolved automatically"
	)

	_camera_rig.queue_free()
	nested_parent.queue_free()
	await process_frame


func _verify_resolution_recovers_after_player_is_removed() -> void:
	_camera_rig = _create_camera_rig()
	var player := _create_unit("InitialPlayer", "Player")
	_world.add_child(player)
	await process_frame
	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == player,
		"the first unique Player is resolved"
	)

	player.queue_free()
	await process_frame
	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == null,
		"a removed Player clears the cached camera target"
	)

	var replacement := _create_unit("LatePlayer", "Player")
	_world.add_child(replacement)
	await process_frame
	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == replacement,
		"a Player added after the camera is resolved automatically"
	)

	_camera_rig.queue_free()
	replacement.queue_free()
	await process_frame


func _verify_living_focus_falls_back_from_player_to_ally_then_enemy() -> void:
	_camera_rig = _create_camera_rig()
	var player := _create_unit("Player", "Player")
	var nearby_ally := _create_unit("NearbyAlly", "Ally")
	var distant_ally := _create_unit("DistantAlly", "Ally")
	var nearby_enemy := _create_unit("NearbyEnemy", "Enemy")
	var distant_enemy := _create_unit("DistantEnemy", "Enemy")
	player.position = Vector3.ZERO
	nearby_ally.position = Vector3(2.0, 0.0, 0.0)
	distant_ally.position = Vector3(6.0, 0.0, 0.0)
	nearby_enemy.position = Vector3(1.0, 0.0, 0.0)
	distant_enemy.position = Vector3(4.0, 0.0, 0.0)
	_world.add_child(player)
	_world.add_child(nearby_ally)
	_world.add_child(distant_ally)
	_world.add_child(nearby_enemy)
	_world.add_child(distant_enemy)
	await process_frame

	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == player,
		"a living Player remains the highest-priority camera focus"
	)
	player.apply_damage(player.get_current_health())
	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == nearby_ally,
		"a dead Player immediately falls back to the nearest living Ally"
	)
	nearby_ally.apply_damage(nearby_ally.get_current_health())
	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == distant_ally,
		"a dead current Ally falls back to the remaining nearest Ally"
	)
	distant_ally.apply_damage(distant_ally.get_current_health())
	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == nearby_enemy,
		"all friendlies dead falls back to the nearest living Enemy"
	)
	nearby_enemy.apply_damage(nearby_enemy.get_current_health())
	distant_enemy.apply_damage(distant_enemy.get_current_health())
	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == null,
		"no living unit leaves the camera without an active focus"
	)
	_expect(player.revive(25.0), "the dead Player can be revived for focus recovery")
	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == player,
		"a revived Player immediately recovers highest-priority camera focus"
	)

	_camera_rig.queue_free()
	player.queue_free()
	nearby_ally.queue_free()
	distant_ally.queue_free()
	nearby_enemy.queue_free()
	distant_enemy.queue_free()
	await process_frame


func _verify_multiple_players_are_not_bound() -> void:
	_camera_rig = _create_camera_rig()
	var player_a := _create_unit("PlayerA", "Player")
	var player_b := _create_unit("PlayerB", "Player")
	_world.add_child(player_a)
	_world.add_child(player_b)
	await process_frame

	_camera_rig._resolve_follow_target()
	_expect(
		_camera_rig.get_resolved_target() == null,
		"multiple Player candidates intentionally leave the camera unbound"
	)

	_camera_rig.queue_free()
	player_a.queue_free()
	player_b.queue_free()
	await process_frame


func _verify_combat_room_structure() -> void:
	var room_scene := load(COMBAT_ROOM_SCENE_PATH) as PackedScene
	_expect(room_scene != null, "TestCombatRoom scene loads")
	if room_scene == null:
		return
	var room := room_scene.instantiate() as Node3D
	_expect(room != null, "TestCombatRoom instantiates")
	if room == null:
		return
	_world.add_child(room)

	_expect(room.get_node_or_null(^"PlayerSpawn") is Marker3D, "room has PlayerSpawn marker")
	_expect(room.get_node_or_null(^"PartySpawn") is Marker3D, "room has PartySpawn marker")
	_expect(room.get_node_or_null(^"EnemyContainer/Pack_A") is Node3D, "room has Pack_A container")
	_expect(room.get_node_or_null(^"EnemyContainer/Pack_B") is Node3D, "room has Pack_B container")
	_expect(room.get_node_or_null(^"EnemyContainer/Pack_C") is Node3D, "room has Pack_C container")
	var navigation_region := room.get_node_or_null(^"NavigationRegion3D") as NavigationRegion3D
	_expect(navigation_region != null, "room has NavigationRegion3D")
	if navigation_region != null:
		var navigation_mesh := navigation_region.navigation_mesh
		_expect(
			navigation_mesh != null and navigation_mesh.get_polygon_count() > 0,
			"room navigation mesh is baked"
		)
	var camera := room.get_node_or_null(^"CameraRig")
	_expect(camera != null and camera.get("target_path") == null, "room has no manual camera target path")

	room.queue_free()


func _create_camera_rig() -> Node3D:
	var controller_script := load(CAMERA_CONTROLLER_SCRIPT_PATH) as Script
	var camera_rig := Node3D.new()
	camera_rig.set_script(controller_script)
	camera_rig.name = "CameraRigUnderTest"
	_world.add_child(camera_rig)
	return camera_rig


func _create_unit(unit_name: String, faction: String) -> UnitBase:
	var unit := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	unit.name = unit_name
	unit.faction_id = faction
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("CameraFollowControllerTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("CameraFollowControllerTest: FAIL (%d)" % _failures.size())
	quit(1)
