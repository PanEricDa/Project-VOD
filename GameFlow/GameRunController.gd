extends Node

## 跨房间的最小游戏流程控制器。
## 它自动监听当前场景中的 CombatRoomController，负责显示结果界面、禁止玩家新输入和重新载入当前场景。
## 它同时在本控制器下独立创建屏幕空间队伍生命 HUD（CombatHUD），并在当前场景变化时按 faction_id
## 收集恰好一名玩家与全部友方单位重新绑定；结果界面与 HUD 互为独立子系统，任一初始化失败不影响另一个。
## 它不裁决战斗结果、不暂停世界，也不管理敌人生成、奖励或检查点。

const RESULT_OVERLAY_SCENE: PackedScene = preload(
	"res://GameFlow/UI/RunResultOverlay.tscn"
)
const COMBAT_HUD_SCENE: PackedScene = preload(
	"res://GameFlow/UI/CombatHUD.tscn"
)

var _result_overlay: CanvasLayer
var _combat_hud: CombatHUD
var _observed_scene: Node
var _room_controller: CombatRoomController


func _ready() -> void:
	_initialize_result_overlay()
	_initialize_combat_hud()
	call_deferred(&"_refresh_scene_bindings")


## 独立初始化结果界面并连接重开请求信号。
## 本方法与 _initialize_combat_hud() 互不依赖：任一错误分支只跳过自身后续步骤，
## 绝不阻止 HUD 创建或 call_deferred 的场景绑定刷新。
func _initialize_result_overlay() -> void:
	_result_overlay = RESULT_OVERLAY_SCENE.instantiate() as CanvasLayer
	if not is_instance_valid(_result_overlay):
		push_error("GameRunController: RunResultOverlay could not be instantiated.")
		return
	add_child(_result_overlay)
	if not _result_overlay.has_signal(&"restart_requested"):
		push_error("GameRunController: RunResultOverlay is missing restart_requested.")
		return
	_result_overlay.connect(&"restart_requested", _on_restart_requested)


## 独立初始化队伍生命 HUD。实例化失败只输出错误并保留 _combat_hud 为无效引用，
## 不影响结果界面与房间绑定逻辑；后续场景刷新会对无效 HUD 安全跳过。
func _initialize_combat_hud() -> void:
	_combat_hud = COMBAT_HUD_SCENE.instantiate() as CombatHUD
	if not is_instance_valid(_combat_hud):
		push_error("GameRunController: CombatHUD could not be instantiated.")
		return
	add_child(_combat_hud)


func _process(_delta: float) -> void:
	var active_scene: Node = get_tree().current_scene
	if active_scene == _observed_scene:
		return
	_observed_scene = active_scene
	_disconnect_room_controller()
	_unbind_combat_hud()
	if is_instance_valid(_result_overlay):
		_result_overlay.call(&"hide_result")
	call_deferred(&"_refresh_scene_bindings")


func _exit_tree() -> void:
	_disconnect_room_controller()
	_unbind_combat_hud()


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


## 场景切换后的统一延迟刷新入口：先刷新房间控制器绑定，再刷新 HUD 队伍绑定。
## 即使当前场景没有 CombatRoomController 或 HUD 不可用，两者各自独立尝试，不互为前置条件。
func _refresh_scene_bindings() -> void:
	_refresh_room_binding()
	_refresh_combat_hud_binding()


## 在当前场景中收集队伍并绑定 HUD。无玩家时安静隐藏；玩家数量不为一时不猜测主角，
## 隐藏 HUD 并在每次绑定尝试时最多输出一次警告，不在 _process() 每帧刷屏。
func _refresh_combat_hud_binding() -> void:
	if not is_instance_valid(_combat_hud):
		return
	var players: Array[UnitBase] = []
	var allies: Array[UnitBase] = []
	_collect_party_units(get_tree().current_scene, players, allies)
	if players.is_empty():
		_combat_hud.unbind_party()
		return
	if players.size() != 1:
		push_warning(
			"GameRunController: CombatHUD requires exactly one Player; found %d."
			% players.size()
		)
		_combat_hud.unbind_party()
		return
	_combat_hud.bind_party(players[0], allies)


## 深度优先遍历场景树，按 faction_id 把单位分入玩家与友方集合。
## 保留场景树发现顺序，不按名字排序、不读取 AI 子组件；玩家唯一性按 faction_id 判定，
## 不使用 PlayerBase 类型，以便未来其他玩家职业仍只依赖通用单位协议。
func _collect_party_units(
	node: Node,
	players: Array[UnitBase],
	allies: Array[UnitBase]
) -> void:
	if node == null:
		return
	if node is UnitBase:
		var unit := node as UnitBase
		if unit.faction_id == "Player":
			players.append(unit)
		elif unit.faction_id == "Ally":
			allies.append(unit)
	for child: Node in node.get_children():
		_collect_party_units(child, players, allies)


## 解绑当前 HUD 队伍显示；HUD 未初始化时安全跳过。
func _unbind_combat_hud() -> void:
	if is_instance_valid(_combat_hud):
		_combat_hud.unbind_party()


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
