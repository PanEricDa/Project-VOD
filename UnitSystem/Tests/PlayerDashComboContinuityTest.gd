extends SceneTree

## 验证冲刺仅覆盖攻击附加位移，不能中断攻击控制器正在维护的连击状态。


class DashingPlayerStub extends Node:
	func is_player_dashing() -> bool:
		return true

	func cancel_attack_motion() -> void:
		pass


func _initialize() -> void:
	var player := DashingPlayerStub.new()
	var controller := PlayerAttackController.new()
	player.add_child(controller)
	root.add_child(player)

	controller.set("_state", PlayerAttackController.AttackState.CHAIN_WAIT)
	controller.set("_combo_index", 1)
	controller.set("_combo_reset_remaining", 0.5)
	controller._process(0.01)

	var failures: Array[String] = []
	if controller.get("_state") != PlayerAttackController.AttackState.CHAIN_WAIT:
		failures.append("dash must not cancel a pending combo")
	if int(controller.get("_combo_index")) != 1:
		failures.append("dash must preserve the active combo index")
	player.remove_child(controller)
	controller.free()
	root.remove_child(player)
	player.free()

	var player_base := PlayerBase.new()
	var dash_controller := PlayerAttackController.new()
	dash_controller.name = &"AttackController"
	var visual := Node3D.new()
	visual.name = &"Visual"
	player_base.add_child(visual)
	player_base.add_child(dash_controller)
	root.add_child(player_base)
	player_base.dash_distance = 2.5
	player_base.dash_speed = 10.0
	## 此无场景树夹具不会自动等待 UnitBase 的 _ready() 初始化生命值；
	## 使用公开 revive() 建立有效生命，确保后续断言验证真实受伤入口而非初始化时序。
	player_base.revive(100.0)
	dash_controller.combo_reset_duration = 0.3
	dash_controller.set("_state", PlayerAttackController.AttackState.ATTACKING)
	dash_controller.set("_combo_index", 1)
	player_base._start_dash(Vector3.FORWARD)

	if dash_controller.get("_state") != PlayerAttackController.AttackState.CHAIN_WAIT:
		failures.append("Dash must cancel an active attack into chain wait")
	if int(dash_controller.get("_combo_index")) != 1:
		failures.append("Dash cancellation must preserve the next combo index")
	if not is_equal_approx(
		float(dash_controller.get("_combo_reset_remaining")),
		0.425
	):
		failures.append("Dash cancellation must restore half of the expected Dash duration")
	if not player_base.is_dash_invulnerable():
		failures.append("Dash must grant invulnerability during its configured first half")
	if not is_zero_approx(player_base.apply_damage(10.0)):
		failures.append("Damage must be ignored during Dash invulnerability")
	player_base.set("_dash_remaining_distance", player_base.dash_distance * 0.5)
	if player_base.is_dash_invulnerable():
		failures.append("Dash invulnerability must end after the configured first half")
	if not is_equal_approx(player_base.apply_damage(10.0), 10.0):
		failures.append("Damage must apply after Dash invulnerability ends")
	root.remove_child(player_base)
	player_base.free()

	if failures.is_empty():
		print("PlayerDashComboContinuityTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
