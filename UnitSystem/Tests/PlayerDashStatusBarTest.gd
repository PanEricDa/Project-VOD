extends SceneTree

## 验证 PlayerDashStatusBar 的只读监控契约：最大值与数值直接镜像业务权威查询，
## 显示更新不改变玩家 Dash 状态，解绑安全隐藏。
## 实施前 PlayerDashStatusBar 类尚不存在，因此测试以 ProgressBar 基类加鸭子调用交互，
## 保证 RED 阶段无脚本解析错误；玩家物理处理被显式关闭，断言间不产生额外业务推进。

const BAR_PATH := "res://UnitSystem/Components/UI/PlayerDashStatusBar.tscn"
const PLAYER_PATH := "res://UnitSystem/Player/PlayerBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ResourceLoader.exists(BAR_PATH), "dash status bar scene exists")
	if not ResourceLoader.exists(BAR_PATH):
		_finish()
		return
	var bar_scene := load(BAR_PATH) as PackedScene
	var player_scene := load(PLAYER_PATH) as PackedScene
	_expect(bar_scene != null and player_scene != null, "dash HUD fixtures load")
	if bar_scene == null or player_scene == null:
		_finish()
		return

	var bar := bar_scene.instantiate() as ProgressBar
	var player := player_scene.instantiate() as PlayerBase
	player.maximum_consecutive_dashes = 2
	player.dash_cooldown_duration = 2.0
	player.set_physics_process(false)
	root.add_child(player)
	root.add_child(bar)
	await process_frame

	var fill_style := bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	_expect(bar.custom_minimum_size.y == 8.0, "dash bar uses the specified thin height")
	_expect(
		fill_style != null
		and fill_style.bg_color.is_equal_approx(Color(1.0, 0.88, 0.42, 0.95)),
		"dash bar uses the approved pale yellow fill"
	)
	_expect(not bar.show_percentage, "dash bar does not display text")

	_expect(bar.has_method(&"bind_player"), "bind_player is public")
	_expect(bar.has_method(&"unbind_player"), "unbind_player is public")
	_expect(bar.has_method(&"is_bound"), "binding query is public")
	_expect(not bar.visible and not bool(bar.call(&"is_bound")), "unbound dash bar stays hidden")
	bar.call(&"bind_player", player)
	await process_frame
	_expect(bar.visible and bool(bar.call(&"is_bound")), "valid player reveals dash bar")
	_expect(is_equal_approx(bar.max_value, float(player.get_dash_charge_capacity())), "bar maximum directly mirrors business capacity")
	_expect(is_equal_approx(bar.value, player.get_dash_charge_progress()), "bar directly mirrors final business progress")

	player._start_dash(Vector3.FORWARD)
	player._finish_dash(Vector3.ZERO)
	player._update_dash_cooldown(0.5)
	var count_before := player.get_available_dash_count()
	var cooldown_before := player.get_dash_cooldown_remaining()
	await process_frame
	_expect(is_equal_approx(bar.value, player.get_dash_charge_progress()), "partial recharge is mirrored without HUD interpolation")
	_expect(player.get_available_dash_count() == count_before, "HUD update does not change dash count")
	_expect(is_equal_approx(player.get_dash_cooldown_remaining(), cooldown_before), "HUD update does not advance cooldown")

	bar.call(&"unbind_player")
	_expect(not bar.visible and not bool(bar.call(&"is_bound")), "unbind clears and hides dash bar")
	player.queue_free()
	bar.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PlayerDashStatusBarTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("PlayerDashStatusBarTest: FAIL (%d)" % _failures.size())
	quit(1)
