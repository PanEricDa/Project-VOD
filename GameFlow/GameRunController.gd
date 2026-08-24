extends Node

## 跨房间的最小游戏流程控制器。
## 它自动监听当前场景中的 CombatRoomController，负责显示结果界面、禁止玩家新输入和重新载入当前场景。
## 它不裁决战斗结果、不暂停世界，也不管理敌人生成、奖励或检查点。

const RESULT_OVERLAY_SCENE: PackedScene = preload(
	"res://GameFlow/UI/RunResultOverlay.tscn"
)

var _result_overlay: CanvasLayer
var _observed_scene: Node
var _room_controller: CombatRoomController


func _ready() -> void:
	_result_overlay = RESULT_OVERLAY_SCENE.instantiate() as CanvasLayer
	if not is_instance_valid(_result_overlay):
		push_error("GameRunController: RunResultOverlay could not be instantiated.")
		return
	add_child(_result_overlay)
	if not _result_overlay.has_signal(&"restart_requested"):
		push_error("GameRunController: RunResultOverlay is missing restart_requested.")
		return
	_result_overlay.connect(&"restart_requested", _on_restart_requested)
	call_deferred(&"_refresh_room_binding")


func _process(_delta: float) -> void:
	var active_scene: Node = get_tree().current_scene
	if active_scene == _observed_scene:
		return
	_observed_scene = active_scene
	_disconnect_room_controller()
	if is_instance_valid(_result_overlay):
		_result_overlay.call(&"hide_result")
	call_deferred(&"_refresh_room_binding")


func _exit_tree() -> void:
	_disconnect_room_controller()


func _refresh_room_binding() -> void:
	var active_scene: Node = get_tree().current_scene
	if active_scene != _observed_scene:
		_observed_scene = active_scene
	_disconnect_room_controller()
	var discovered_room := _find_combat_room_controller(active_scene)
	if discovered_room == _room_controller:
		return
	_disconnect_room_controller()
	_room_controller = discovered_room
	if not is_instance_valid(_room_controller):
		return
	if not _room_controller.room_failed.is_connected(_on_room_failed):
		_room_controller.room_failed.connect(_on_room_failed)
	if not _room_controller.room_completed.is_connected(_on_room_completed):
		_room_controller.room_completed.connect(_on_room_completed)


func _on_room_failed() -> void:
	_set_current_player_input_enabled(false)
	if is_instance_valid(_result_overlay):
		_result_overlay.call(&"show_failure")


func _on_room_completed() -> void:
	_set_current_player_input_enabled(false)
	if is_instance_valid(_result_overlay):
		_result_overlay.call(&"show_success")


func _on_restart_requested() -> void:
	if is_instance_valid(_result_overlay):
		_result_overlay.call(&"hide_result")
	_set_current_player_input_enabled(true)
	var encounter_controller := _find_encounter_controller(get_tree().current_scene)
	if is_instance_valid(encounter_controller):
		encounter_controller.begin_scene_unload()
	get_tree().reload_current_scene()


func _disconnect_room_controller() -> void:
	if not is_instance_valid(_room_controller):
		_room_controller = null
		return
	if _room_controller.room_failed.is_connected(_on_room_failed):
		_room_controller.room_failed.disconnect(_on_room_failed)
	if _room_controller.room_completed.is_connected(_on_room_completed):
		_room_controller.room_completed.disconnect(_on_room_completed)
	_room_controller = null


func _find_combat_room_controller(node: Node) -> CombatRoomController:
	if node == null:
		return null
	if node is CombatRoomController:
		return node as CombatRoomController
	for child: Node in node.get_children():
		var found := _find_combat_room_controller(child)
		if is_instance_valid(found):
			return found
	return null


## 在当前房间场景中查找唯一的 EncounterController。
## 重新开始前仅用于发送正常卸载通知；不会参与房间胜负、敌群登记或单位 AI 决策。
func _find_encounter_controller(node: Node) -> EncounterController:
	if node == null:
		return null
	if node is EncounterController:
		return node as EncounterController
	for child: Node in node.get_children():
		var found := _find_encounter_controller(child)
		if is_instance_valid(found):
			return found
	return null


func _set_current_player_input_enabled(enabled: bool) -> void:
	var player := _find_player_base(get_tree().current_scene)
	if is_instance_valid(player):
		player.set_player_input_enabled(enabled)


func _find_player_base(node: Node) -> PlayerBase:
	if node == null:
		return null
	if node is PlayerBase:
		return node as PlayerBase
	for child: Node in node.get_children():
		var found := _find_player_base(child)
		if is_instance_valid(found):
			return found
	return null
