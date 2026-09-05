extends SceneTree

## 验证 CombatHUD 的队伍绑定、去重、布局比例、稳定槽位与解绑契约。
## 本测试使用普通 UnitBase 作为玩家与伙伴数据源，不依赖任何 AI 脚本，
## 也不访问 HUD 私有字段，全部断言通过公开方法与稳定节点路径完成。

const HUD_PATH := "res://GameFlow/UI/CombatHUD.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ResourceLoader.exists(HUD_PATH), "CombatHUD scene exists")
	if not ResourceLoader.exists(HUD_PATH):
		_finish()
		return
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as CanvasLayer
	root.add_child(hud)
	var player := _make_unit("玩家", "Player", 300.0)
	var allies: Array[UnitBase] = []
	for index: int in 4:
		allies.append(_make_unit("伙伴%d" % index, "Ally", 100.0))
	await process_frame

	_expect(hud.has_method(&"bind_party"), "bind_party is public")
	_expect(hud.has_method(&"unbind_party"), "unbind_party is public")
	_expect(hud.has_method(&"refresh_party"), "refresh_party is public")
	hud.call(&"bind_party", player, allies)
	await process_frame

	var player_frame := hud.get_node(^"SafeArea/PartyColumn/PlayerFrame") as Control
	var ally_frames := hud.get_node(^"SafeArea/PartyColumn/AllyFrames") as VBoxContainer
	_expect(hud.visible and player_frame.visible, "valid player shows HUD")
	_expect(ally_frames.get_child_count() == 4, "one frame exists per ally")
	_expect(player_frame.custom_minimum_size == Vector2(420, 90), "player size uses default")
	for child: Node in ally_frames.get_children():
		var ally_frame := child as Control
		_expect(ally_frame != null, "ally frame is Control")
		if ally_frame != null:
			_expect(ally_frame.custom_minimum_size == Vector2(280, 60), "ally is two thirds size")
			_expect(is_equal_approx(ally_frame.global_position.x, player_frame.global_position.x), "frames align left")
			_expect(ally_frame.global_position.y < player_frame.global_position.y, "allies appear above player")

	var duplicate_input: Array[UnitBase] = [allies[0], allies[0], player, null]
	hud.call(&"refresh_party", player, duplicate_input)
	await process_frame
	await process_frame
	_expect(ally_frames.get_child_count() == 1, "invalid, duplicate, and player entries are skipped")

	var stable_frame := ally_frames.get_child(0) as Control
	allies[0].apply_damage(9999.0)
	await process_frame
	_expect(stable_frame.visible, "dead ally frame stays in its slot")
	_expect(ally_frames.get_child_count() == 1, "death does not reorder party")

	hud.call(&"unbind_party")
	await process_frame
	await process_frame
	_expect(not hud.visible, "unbind hides HUD")
	_expect(ally_frames.get_child_count() == 0, "unbind removes dynamic ally frames")

	hud.call(&"bind_party", null, allies)
	await process_frame
	_expect(not hud.visible, "invalid player stays safely hidden")
	_cleanup(hud, player, allies)
	await process_frame
	_finish()


## 以指定名称、阵营与生命上限创建一个普通 UnitBase 并加入场景树。
func _make_unit(unit_name: String, faction: String, maximum: float) -> UnitBase:
	var unit := (load(UNIT_PATH) as PackedScene).instantiate() as UnitBase
	unit.name = unit_name
	unit.faction_id = faction
	unit.maximum_health = maximum
	root.add_child(unit)
	return unit


## 只清理本测试创建的节点：HUD 实例与全部单位数据源。
func _cleanup(hud: CanvasLayer, player: UnitBase, allies: Array[UnitBase]) -> void:
	if is_instance_valid(hud):
		hud.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	for ally: UnitBase in allies:
		if is_instance_valid(ally):
			ally.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CombatHUDTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("CombatHUDTest: FAIL (%d)" % _failures.size())
	quit(1)
