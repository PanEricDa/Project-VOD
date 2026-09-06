extends SceneTree

## 验证玩家 Dash 逐层恢复的业务契约：首次消耗即启动恢复、再次消耗保留进度、
## 逐层结算、满层停止、大 delta 连续恢复与零冷却收束。
## 测试只断言公开查询的确定结果，不复制恢复公式；主体在初始帧等待后为单一同步块，
## 通过 Dash 系统的推进入口手动驱动，物理帧不会插入断言之间。

const PLAYER_PATH := "res://UnitSystem/Player/PlayerBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var player_scene := load(PLAYER_PATH) as PackedScene
	_expect(player_scene != null, "PlayerBase scene loads")
	if player_scene == null:
		_finish()
		return
	var player := player_scene.instantiate() as PlayerBase
	player.maximum_consecutive_dashes = 2
	player.dash_cooldown_duration = 2.0
	root.add_child(player)
	await process_frame

	_expect(player.get_available_dash_count() == 2, "player starts with two dash charges")
	_expect(player.has_method(&"get_dash_charge_capacity"), "dash exposes sanitized read-only capacity")
	_expect(player.has_method(&"get_dash_charge_progress"), "dash exposes final read-only progress")
	if not player.has_method(&"get_dash_charge_capacity") or not player.has_method(&"get_dash_charge_progress"):
		player.queue_free()
		await process_frame
		_finish()
		return
	_expect(player.get_dash_charge_capacity() == 2, "configured capacity is exposed by the business layer")
	_expect(is_equal_approx(player.get_dash_charge_progress(), 2.0), "full charges report full progress")

	player._start_dash(Vector3.FORWARD)
	player._finish_dash(Vector3.ZERO)
	_expect(player.get_available_dash_count() == 1, "first dash consumes one charge")
	_expect(is_equal_approx(player.get_dash_cooldown_remaining(), 2.0), "first spent charge immediately starts recharge")
	_expect(is_equal_approx(player.get_dash_charge_progress(), 1.0), "progress falls by exactly one charge")

	player._update_dash_cooldown(0.75)
	var preserved_remaining := player.get_dash_cooldown_remaining()
	_expect(is_equal_approx(preserved_remaining, 1.25), "recharge advances before second dash")
	_expect(is_equal_approx(player.get_dash_charge_progress(), 1.375), "business layer reports partial charge")

	player._start_dash(Vector3.FORWARD)
	player._finish_dash(Vector3.ZERO)
	_expect(player.get_available_dash_count() == 0, "second dash consumes the remaining full charge")
	_expect(is_equal_approx(player.get_dash_cooldown_remaining(), preserved_remaining), "second dash does not reset recharge")
	_expect(is_equal_approx(player.get_dash_charge_progress(), 0.375), "second dash preserves partial recharge and removes exactly one")

	player._update_dash_cooldown(1.25)
	_expect(player.get_available_dash_count() == 1, "one cooldown restores one charge")
	_expect(is_equal_approx(player.get_dash_cooldown_remaining(), 2.0), "missing second charge starts the next cooldown")
	player._update_dash_cooldown(2.0)
	_expect(player.get_available_dash_count() == 2, "second cooldown restores full charges")
	_expect(is_zero_approx(player.get_dash_cooldown_remaining()), "full charges stop recharge")

	var large_delta_player := _make_player("LargeDeltaPlayer")
	large_delta_player._start_dash(Vector3.FORWARD)
	large_delta_player._finish_dash(Vector3.ZERO)
	large_delta_player._start_dash(Vector3.FORWARD)
	large_delta_player._finish_dash(Vector3.ZERO)
	large_delta_player._update_dash_cooldown(4.5)
	_expect(large_delta_player.get_available_dash_count() == 2, "large delta restores every elapsed layer")
	_expect(is_zero_approx(large_delta_player.get_dash_cooldown_remaining()), "full result discards unused overflow")

	var zero_cooldown_player := _make_player("ZeroCooldownPlayer")
	zero_cooldown_player.dash_cooldown_duration = 0.0
	zero_cooldown_player._start_dash(Vector3.FORWARD)
	_expect(zero_cooldown_player.get_available_dash_count() == 2, "zero cooldown immediately restores all missing charges")
	_expect(is_zero_approx(zero_cooldown_player.get_dash_cooldown_remaining()), "zero cooldown has no active timer")

	player.queue_free()
	large_delta_player.queue_free()
	zero_cooldown_player.queue_free()
	await process_frame
	_finish()


## 以两层、2 秒冷却的标准配置创建独立玩家夹具并加入场景树。
func _make_player(player_name: String) -> PlayerBase:
	var player := (load(PLAYER_PATH) as PackedScene).instantiate() as PlayerBase
	player.name = player_name
	player.maximum_consecutive_dashes = 2
	player.dash_cooldown_duration = 2.0
	root.add_child(player)
	return player


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PlayerDashRechargeTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("PlayerDashRechargeTest: FAIL (%d)" % _failures.size())
	quit(1)
