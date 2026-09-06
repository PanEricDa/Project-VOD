extends SceneTree

## 验证 GameRunController Autoload 对 CombatHUD 的创建、场景级队伍发现、
## 场景切换重绑与异常场景（无玩家/多玩家）的安全契约。
## 本测试使用真实 Autoload 实例，不手工创建第二个控制器。

const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const PLAYER_BASE_PATH := "res://UnitSystem/Player/PlayerBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var game_run := root.get_node_or_null(^"GameRunController")
	_expect(game_run != null, "GameRunController autoload exists")
	if game_run == null:
		_finish()
		return
	var hud := game_run.get_node_or_null(^"CombatHUD") as CanvasLayer
	_expect(hud != null, "GameRunController creates CombatHUD")
	if hud == null:
		_finish()
		return

	var first_scene := Node3D.new()
	first_scene.name = "FirstHUDScene"
	root.add_child(first_scene)
	current_scene = first_scene
	var first_player := _add_player(first_scene, "玩家A", 200.0)
	var ally_a := _add_unit(first_scene, "守卫", "Ally", 300.0)
	var ally_b := _add_unit(first_scene, "牧师", "Ally", 100.0)
	_add_unit(first_scene, "敌人", "Enemy", 100.0)
	_expect(is_instance_valid(ally_a) and is_instance_valid(ally_b), "ally fixtures stay valid")
	await process_frame
	await process_frame
	await process_frame

	var ally_frames := hud.get_node(^"SafeArea/PartyColumn/AllyFrames") as VBoxContainer
	var player_frame := hud.get_node(^"SafeArea/PartyColumn/PlayerFrame") as Control
	_expect(hud.visible and player_frame.visible, "one player binds automatically")
	_expect(ally_frames.get_child_count() == 2, "only Ally units receive compact frames")
	var first_name := player_frame.get_node(^"FrameContent/CoreInfo/Header/NameLabel") as Label
	_expect(first_name.text == "玩家A", "first scene player is bound")
	if ally_frames.get_child_count() == 2:
		var first_ally_name := ally_frames.get_child(0).get_node(
			^"FrameContent/CoreInfo/Header/NameLabel"
		) as Label
		var second_ally_name := ally_frames.get_child(1).get_node(
			^"FrameContent/CoreInfo/Header/NameLabel"
		) as Label
		_expect(first_ally_name != null and second_ally_name != null, "ally labels exist")
		if first_ally_name != null and second_ally_name != null:
			_expect(
				first_ally_name.text == "守卫" and second_ally_name.text == "牧师",
				"ally frames preserve scene-tree discovery order"
			)

	var second_scene := Node3D.new()
	second_scene.name = "SecondHUDScene"
	root.add_child(second_scene)
	var second_player := _add_player(second_scene, "玩家B", 500.0)
	_expect(is_instance_valid(second_player), "second scene player stays valid")
	_add_unit(second_scene, "新伙伴", "Ally", 120.0)
	current_scene = second_scene
	await process_frame
	await process_frame
	await process_frame
	_expect(first_name.text == "玩家B", "scene change rebinds player frame")
	_expect(ally_frames.get_child_count() == 1, "old ally frames are cleared")
	var dash_bar := _find_dash_bar(hud)
	_expect(
		dash_bar != null and dash_bar.is_bound(),
		"combat hud keeps the dash bar bound to the active player"
	)
	if dash_bar != null:
		_expect(
			is_equal_approx(dash_bar.value, second_player.get_dash_charge_progress()),
			"dash bar follows the new player's business progress"
		)
	first_player.apply_damage(10.0)
	await process_frame
	_expect(first_name.text == "玩家B", "old scene signals cannot update new binding")
	if dash_bar != null:
		first_player._start_dash(Vector3.FORWARD)
		first_player._finish_dash(Vector3.ZERO)
		await process_frame
		_expect(
			is_equal_approx(dash_bar.value, second_player.get_dash_charge_progress()),
			"old player dash activity cannot move the rebound dash bar"
		)

	var no_player_scene := Node3D.new()
	root.add_child(no_player_scene)
	current_scene = no_player_scene
	await process_frame
	await process_frame
	_expect(not hud.visible, "scene without player hides HUD")

	var ambiguous_scene := Node3D.new()
	root.add_child(ambiguous_scene)
	_add_unit(ambiguous_scene, "玩家一", "Player", 100.0)
	_add_unit(ambiguous_scene, "玩家二", "Player", 100.0)
	current_scene = ambiguous_scene
	await process_frame
	await process_frame
	_expect(not hud.visible, "multiple players are not guessed")

	current_scene = null
	for scene: Node in [first_scene, second_scene, no_player_scene, ambiguous_scene]:
		if is_instance_valid(scene):
			scene.queue_free()
	await process_frame
	_finish()


## 在加入父节点前完成名称、阵营与生命上限配置，返回已入树的普通 UnitBase。
func _add_unit(
	parent: Node,
	unit_name: String,
	faction: String,
	maximum: float
) -> UnitBase:
	var unit := (load(UNIT_PATH) as PackedScene).instantiate() as UnitBase
	unit.name = unit_name
	unit.faction_id = faction
	unit.maximum_health = maximum
	parent.add_child(unit)
	return unit


## 以 PlayerBase 创建场景玩家，供 Dash 监控条的真实数据源契约使用。
func _add_player(parent: Node, player_name: String, maximum: float) -> PlayerBase:
	var player := (load(PLAYER_BASE_PATH) as PackedScene).instantiate() as PlayerBase
	player.name = player_name
	player.maximum_health = maximum
	parent.add_child(player)
	return player


## 在 HUD 子树中查找唯一 Dash 监控条；未装配时返回 null。
func _find_dash_bar(node: Node) -> PlayerDashStatusBar:
	if node is PlayerDashStatusBar:
		return node as PlayerDashStatusBar
	for child: Node in node.get_children():
		var found := _find_dash_bar(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CombatHUDBindingIntegrationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("CombatHUDBindingIntegrationTest: FAIL (%d)" % _failures.size())
	quit(1)
