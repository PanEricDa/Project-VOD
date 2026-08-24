extends SceneTree

const CONTROLLER_SCENE_PATH := "res://UnitSystem/Encounter/EncounterController.tscn"
const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const COMBAT_ROOM_SCENE_PATH := "res://Scenes/TestCombatRoom.tscn"

var _failures: Array[String] = []
var _world: Node3D
var _controller: Node
var _pack_a: Node3D
var _pack_b: Node3D
var _events: Array[String] = []
var _room_invalid_events: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "EncounterControllerTestWorld"
	root.add_child(_world)
	_create_test_room()
	await process_frame
	await process_frame
	if _controller == null:
		_finish()
		return
	await _verify_pack_lifecycle()
	await _verify_death_wins_over_reset()
	await _verify_explicit_scene_unload_suppresses_tracking_warning()
	await _verify_test_combat_room_assembly()
	_finish()


func _create_test_room() -> void:
	var enemy_container := Node3D.new()
	enemy_container.name = "EnemyContainer"
	_world.add_child(enemy_container)
	_pack_a = Node3D.new()
	_pack_a.name = "Pack_A"
	enemy_container.add_child(_pack_a)
	_pack_b = Node3D.new()
	_pack_b.name = "Pack_B"
	enemy_container.add_child(_pack_b)
	var empty_pack := Node3D.new()
	empty_pack.name = "EmptyPack"
	enemy_container.add_child(empty_pack)
	_pack_a.add_child(_create_enemy("A_One"))
	_pack_a.add_child(_create_enemy("A_Two"))
	_pack_b.add_child(_create_enemy("B_One"))

	var controller_scene := load(CONTROLLER_SCENE_PATH) as PackedScene
	_expect(controller_scene != null, "EncounterController scene exists")
	if controller_scene == null:
		return
	_controller = controller_scene.instantiate()
	_world.add_child(_controller)
	_controller.set("reset_delay", 0.1)
	_expect(
		_controller.get("debug_log_enabled") == false,
		"encounter debug logging is disabled by default"
	)
	_controller.connect("pack_started", _on_pack_started)
	_controller.connect("pack_reset", _on_pack_reset)
	_controller.connect("pack_cleared", _on_pack_cleared)
	_controller.connect("room_cleared", _on_room_cleared)
	_controller.connect("pack_tracking_invalid", _on_pack_tracking_invalid)


func _verify_pack_lifecycle() -> void:
	_expect(
		int(_controller.call("get_registered_enemy_count", _pack_a)) == 2,
		"Pack A registers all nested enemies"
	)
	_expect(
		int(_controller.call("get_registered_enemy_count", _pack_b)) == 1,
		"Pack B registers its enemy"
	)
	_expect(
		int(_controller.call("get_pack_state", _pack_a)) == 0,
		"a registered Pack starts DORMANT"
	)
	var enemy_a := _pack_a.get_child(0) as EnemyBase
	var enemy_a_two := _pack_a.get_child(1) as EnemyBase
	enemy_a.global_position = Vector3.ZERO
	enemy_a_two.global_position = Vector3(20.0, 0.0, 0.0)
	var assist_target := (load("res://UnitSystem/Base/00_UnitBase.tscn") as PackedScene).instantiate() as UnitBase
	assist_target.name = "PackAssistTarget"
	assist_target.team_id = 1
	_world.add_child(assist_target)
	assist_target.global_position = Vector3.ZERO
	await physics_frame
	# 直接模拟已有本地感知刚刚锁定的目标，避免本测试承担 Area3D 物理同步的职责。
	enemy_a.get_targeting_component().call("_set_locked_target", assist_target)
	_expect(
		enemy_a.get_targeting_component().get_locked_target() == assist_target,
		"initiating enemy provides an existing valid local Pack target"
	)
	enemy_a.enter_combat()
	await process_frame
	_expect(
		enemy_a_two != null and enemy_a_two.get_targeting_component().get_locked_target() == assist_target,
		"a distant Pack member adopts the engaged member target through Pack fallback"
	)
	enemy_a.exit_combat()
	enemy_a_two.get_targeting_component().refresh_target()
	_expect(
		enemy_a_two.get_targeting_component().get_locked_target() == null,
		"a Pack target disappears when no other living combat member still holds it"
	)
	_expect(_events.count("started:Pack_A") == 1, "first combat starts Pack A once")
	_expect(int(_controller.call("get_pack_state", _pack_a)) == 1, "combat enters ENGAGED")

	enemy_a.exit_combat()
	await process_frame
	_expect(int(_controller.call("get_pack_state", _pack_a)) == 2, "all enemies out of combat begin RESETTING")
	enemy_a.enter_combat()
	await process_frame
	_expect(int(_controller.call("get_pack_state", _pack_a)) == 1, "combat during delay cancels reset")
	enemy_a.exit_combat()
	await create_timer(0.12).timeout
	await process_frame
	_expect(_events.count("reset:Pack_A") == 1, "stable disengage emits one Pack reset")
	_expect(int(_controller.call("get_pack_state", _pack_a)) == 0, "reset completion returns Pack to DORMANT")


func _verify_death_wins_over_reset() -> void:
	var enemy_a_one := _pack_a.get_child(0) as EnemyBase
	var enemy_a_two := _pack_a.get_child(1) as EnemyBase
	enemy_a_one.enter_combat()
	enemy_a_two.enter_combat()
	await process_frame
	enemy_a_one.apply_damage(9999.0)
	enemy_a_two.apply_damage(9999.0)
	await process_frame
	await process_frame
	_expect(_events.count("cleared:Pack_A") == 1, "all deaths clear Pack A once")
	_expect(_events.count("reset:Pack_A") == 1, "death does not create an extra Pack reset")
	_expect(int(_controller.call("get_pack_state", _pack_a)) == 3, "cleared Pack is terminal")
	var late_removed_enemy := _create_enemy("A_LateRemoved")
	_pack_a.add_child(late_removed_enemy)
	_controller.call("_on_enemy_tree_exiting", _pack_a, late_removed_enemy)
	_expect(
		int(_controller.call("get_pack_state", _pack_a)) == 3,
		"a delayed enemy tree-exit cannot revert a cleared Pack to tracking invalid"
	)
	_expect(_events.count("invalid") == 0, "a cleared Pack does not emit tracking invalid")
	late_removed_enemy.queue_free()
	enemy_a_one.queue_free()
	enemy_a_two.queue_free()
	await process_frame
	_expect(
		int(_controller.call("get_alive_enemy_count", _pack_a)) == 0,
		"a cleared Pack safely queries alive count after its enemy nodes are freed"
	)

	var enemy_b := _pack_b.get_child(0) as EnemyBase
	enemy_b.apply_damage(9999.0)
	await process_frame
	await process_frame
	_expect(_events.count("cleared:Pack_B") == 1, "all deaths clear Pack B once")
	_expect(_events.count("room") == 1, "all non-empty Packs clear the room once")


func _verify_test_combat_room_assembly() -> void:
	var room_scene := load(COMBAT_ROOM_SCENE_PATH) as PackedScene
	_expect(room_scene != null, "TestCombatRoom scene loads")
	if room_scene == null:
		return
	var room := room_scene.instantiate() as Node3D
	_expect(room != null, "TestCombatRoom instantiates")
	if room == null:
		return
	_world.add_child(room)
	await process_frame
	await process_frame
	var room_controller: Node = room.get_node_or_null(^"EncounterController")
	_expect(room_controller != null, "TestCombatRoom equips EncounterController")
	_expect(room.get_node_or_null(^"EnemyContainer/Pack_A") != null, "existing user Pack A remains present")
	if room_controller != null:
		room_controller.connect("pack_tracking_invalid", _on_room_tracking_invalid)
		_expect(
			room_controller.get("debug_log_enabled") == true,
			"TestCombatRoom enables encounter debug logging for manual testing"
		)
		_expect(
			int(room_controller.call("get_registered_enemy_count", room.get_node(^"EnemyContainer/Pack_A"))) == 3,
			"room controller registers the existing Pack A enemies"
		)
		_expect(
			int(room_controller.call("get_registered_enemy_count", room.get_node(^"EnemyContainer/Pack_B"))) == 4,
			"room controller registers the existing Pack B enemies"
		)
		_expect(
			int(room_controller.call("get_registered_enemy_count", room.get_node(^"EnemyContainer/Pack_C"))) == 5,
			"room controller registers the existing Pack C enemies"
		)
	var invalid_event_count: int = _room_invalid_events
	room.queue_free()
	await process_frame
	_expect(
		_room_invalid_events == invalid_event_count,
		"normal room teardown does not report enemy tracking invalid"
	)


## 主动场景重载会让存活敌人正常离树；此时控制器必须保留异常监测能力，但不得把卸载误标记为 Pack 失效。
func _verify_explicit_scene_unload_suppresses_tracking_warning() -> void:
	var reload_room := Node3D.new()
	reload_room.name = "ExplicitUnloadRoom"
	_world.add_child(reload_room)
	var enemy_container := Node3D.new()
	enemy_container.name = "EnemyContainer"
	reload_room.add_child(enemy_container)
	var reload_pack := Node3D.new()
	reload_pack.name = "ReloadPack"
	enemy_container.add_child(reload_pack)
	var reload_enemy := _create_enemy("ReloadEnemy")
	reload_pack.add_child(reload_enemy)
	var controller_scene := load(CONTROLLER_SCENE_PATH) as PackedScene
	if controller_scene == null:
		_expect(false, "EncounterController scene loads for explicit unload test")
		return
	var reload_controller: Node = controller_scene.instantiate()
	reload_room.add_child(reload_controller)
	var invalid_events: Array[int] = [0]
	reload_controller.connect(
		"pack_tracking_invalid",
		func(_pack: Node3D, _enemy: EnemyBase) -> void:
			invalid_events[0] += 1
	)
	await process_frame
	await process_frame
	_expect(
		reload_controller.has_method(&"begin_scene_unload"),
		"EncounterController exposes an explicit scene-unload guard"
	)
	if not reload_controller.has_method(&"begin_scene_unload"):
		reload_room.queue_free()
		await process_frame
		return
	reload_controller.call("begin_scene_unload")
	reload_enemy.queue_free()
	await process_frame
	_expect(
		invalid_events[0] == 0,
		"explicit scene unload does not emit pack tracking invalid for a living enemy"
	)
	reload_room.queue_free()
	await process_frame


func _create_enemy(enemy_name: String) -> EnemyBase:
	var enemy := (load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as EnemyBase
	enemy.name = enemy_name
	enemy.set_physics_process(false)
	return enemy


func _on_pack_started(pack: Node3D, _count: int) -> void:
	_events.append("started:" + pack.name)


func _on_pack_reset(pack: Node3D, _count: int) -> void:
	_events.append("reset:" + pack.name)


func _on_pack_cleared(pack: Node3D, _count: int) -> void:
	_events.append("cleared:" + pack.name)


func _on_room_cleared() -> void:
	_events.append("room")


func _on_pack_tracking_invalid(_pack: Node3D, _enemy: EnemyBase) -> void:
	_events.append("invalid")


func _on_room_tracking_invalid(_pack: Node3D, _enemy: EnemyBase) -> void:
	_room_invalid_events += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("EncounterControllerTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("EncounterControllerTest: FAIL (%d)" % _failures.size())
	quit(1)
