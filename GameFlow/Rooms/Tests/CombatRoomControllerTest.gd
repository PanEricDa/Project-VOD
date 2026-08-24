extends SceneTree

const CONTROLLER_SCENE_PATH: String = "res://GameFlow/Rooms/CombatRoomController.tscn"
const ENCOUNTER_SCENE_PATH: String = "res://UnitSystem/Encounter/EncounterController.tscn"
const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const ENEMY_SCENE_PATH: String = "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const CONTROLLER_SCRIPT_PATH: String = "res://GameFlow/Rooms/CombatRoomController.gd"

var _failures: Array[String] = []
var _events: Array[String] = []
var _room: Node3D
var _controller: CombatRoomController
var _player: UnitBase
var _ally: UnitBase
var _enemy: UnitBase
var _pack: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_verify_unique_player_local_is_initialized()
	_verify_default_failure_delay()
	await _create_fixture()
	await _verify_player_revival_cancels_last_stand()
	await _verify_last_stand_room_clear_is_completed()
	_dispose_fixture()
	await _create_fixture()
	await _verify_last_stand_without_any_combat_fails()
	_dispose_fixture()
	await _create_fixture()
	await _verify_all_friendly_death_fails()
	_finish()


func _verify_unique_player_local_is_initialized() -> void:
	var source: String = FileAccess.get_file_as_string(CONTROLLER_SCRIPT_PATH)
	_expect(
		source.contains("var player: UnitBase = null"),
		"unique-player lookup must initialize its nullable local before returning it"
	)


func _verify_default_failure_delay() -> void:
	var controller_scene := load(CONTROLLER_SCENE_PATH) as PackedScene
	var controller := (
		controller_scene.instantiate() as CombatRoomController
		if controller_scene != null
		else null
	)
	_expect(controller != null, "CombatRoomController default-delay fixture instantiates")
	if controller == null:
		return
	_expect(
		is_equal_approx(controller.defeat_resolution_delay, 3.0),
		"failure result must wait three seconds by default"
	)
	controller.free()


func _create_fixture() -> void:
	_events.clear()
	var controller_scene := load(CONTROLLER_SCENE_PATH) as PackedScene
	_expect(controller_scene != null, "CombatRoomController scene exists")
	if controller_scene == null:
		return
	_room = Node3D.new()
	_room.name = "CombatRoomUnderTest"
	root.add_child(_room)
	var container := Node3D.new()
	container.name = "EnemyContainer"
	_room.add_child(container)
	_pack = Node3D.new()
	_pack.name = "Pack_A"
	container.add_child(_pack)
	_player = _create_unit("Player", "Player")
	_ally = _create_unit("Ally", "Ally")
	_enemy = _create_enemy()
	_pack.add_child(_enemy)
	_room.add_child(_player)
	_room.add_child(_ally)
	var encounter_scene := load(ENCOUNTER_SCENE_PATH) as PackedScene
	var encounter := encounter_scene.instantiate() as EncounterController if encounter_scene != null else null
	_expect(encounter != null, "EncounterController fixture instantiates")
	if encounter != null:
		_room.add_child(encounter)
	_controller = controller_scene.instantiate() as CombatRoomController
	_expect(_controller != null, "CombatRoomController instantiates")
	if _controller != null:
		_controller.defeat_resolution_delay = 0.0
		_controller.flow_state_changed.connect(_on_flow_state_changed)
		_controller.room_failed.connect(_on_room_failed)
		_room.add_child(_controller)
	await process_frame
	await process_frame


func _verify_last_stand_room_clear_is_completed() -> void:
	if _controller == null or _player == null or _ally == null or _enemy == null:
		return
	_enemy.enter_combat()
	await process_frame
	_player.apply_damage(_player.get_current_health())
	await process_frame
	_expect(
		_controller.get_flow_state() == CombatRoomController.FlowState.LAST_STAND,
		"a dead Player with a living Ally enters LAST_STAND"
	)
	_enemy.apply_damage(_enemy.get_current_health())
	await process_frame
	await process_frame
	_expect(
		_controller.get_flow_state() == CombatRoomController.FlowState.COMPLETED,
		"clearing every enemy completes the room even while Player remains dead"
	)
	_expect(not _events.has("failed"), "room clear must not emit failure")


func _verify_player_revival_cancels_last_stand() -> void:
	if _controller == null or _player == null:
		return
	_enemy.enter_combat()
	_player.apply_damage(_player.get_current_health())
	await process_frame
	_expect(_player.revive(30.0), "fixture Player revives")
	await process_frame
	_expect(
		_controller.get_flow_state() == CombatRoomController.FlowState.NORMAL,
		"Player revival restores normal room flow"
	)


func _verify_last_stand_without_any_combat_fails() -> void:
	if _controller == null or _player == null or _ally == null or _enemy == null:
		return
	_enemy.enter_combat()
	_ally.enter_combat()
	await process_frame
	_player.apply_damage(_player.get_current_health())
	await process_frame
	_expect(
		_controller.get_flow_state() == CombatRoomController.FlowState.LAST_STAND,
		"a fighting Ally keeps the room in LAST_STAND after Player death"
	)
	_enemy.exit_combat()
	_ally.exit_combat()
	await process_frame
	await process_frame
	_expect(
		_controller.get_flow_state() == CombatRoomController.FlowState.FAILED,
		"a living enemy and no combatants resolve LAST_STAND as failure"
	)


func _verify_all_friendly_death_fails() -> void:
	if _controller == null or _player == null or _ally == null or _enemy == null:
		return
	_enemy.enter_combat()
	await process_frame
	_player.apply_damage(_player.get_current_health())
	_ally.apply_damage(_ally.get_current_health())
	await process_frame
	await process_frame
	_expect(
		_controller.get_flow_state() == CombatRoomController.FlowState.FAILED,
		"all friendly units dead while enemies remain resolves failure"
	)
	_expect(_events.has("failed"), "all-friendly death emits room failure")


func _dispose_fixture() -> void:
	if is_instance_valid(_room):
		_room.queue_free()
	_room = null
	_controller = null
	_player = null
	_ally = null
	_enemy = null
	_pack = null


func _create_unit(unit_name: String, faction: String) -> UnitBase:
	var unit := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	unit.name = unit_name
	unit.faction_id = faction
	return unit


func _create_enemy() -> UnitBase:
	var enemy := (load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	enemy.name = "Enemy"
	return enemy


func _on_flow_state_changed(
	_previous_state: CombatRoomController.FlowState,
	_current_state: CombatRoomController.FlowState
) -> void:
	_events.append("state")


func _on_room_failed() -> void:
	_events.append("failed")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("CombatRoomControllerTest failed: " + message)


func _finish() -> void:
	if is_instance_valid(_room):
		_room.queue_free()
	if _failures.is_empty():
		print("CombatRoomControllerTest: PASS")
		quit(0)
		return
	printerr("CombatRoomControllerTest: FAIL\n- " + "\n- ".join(_failures))
	quit(1)
