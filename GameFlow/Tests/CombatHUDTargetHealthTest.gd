extends SceneTree

## 顶部目标生命 HUD 的真实锁定集成测试。
## 使用 PlayerBase 的现有 locked_target_changed、get_locked_target() 与
## PlayerTargetingComponent.request_lock() 驱动 CombatHUD，不建立测试专用锁定接口。

const HUD_PATH := "res://GameFlow/UI/CombatHUD.tscn"
const PLAYER_PATH := "res://UnitSystem/Player/PlayerBase.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var hud_scene := load(HUD_PATH) as PackedScene
	var player_scene := load(PLAYER_PATH) as PackedScene
	var unit_scene := load(UNIT_PATH) as PackedScene
	_expect(
		hud_scene != null and player_scene != null and unit_scene != null,
		"target HUD fixtures load"
	)
	if hud_scene == null or player_scene == null or unit_scene == null:
		_finish()
		return

	_world = Node3D.new()
	root.add_child(_world)
	var hud := hud_scene.instantiate() as CombatHUD
	var player := player_scene.instantiate() as PlayerBase
	var first := _make_enemy(unit_scene, "目标甲", 200.0, Vector3(1.5, 0.0, 0.0))
	var second := _make_enemy(unit_scene, "目标乙", 80.0, Vector3(-1.5, 0.0, 0.0))
	_world.add_child(player)
	root.add_child(hud)
	await process_frame
	await process_frame

	var allies: Array[UnitBase] = []
	hud.bind_party(player, allies)
	await process_frame
	var target_safe_area := hud.get_node_or_null(^"TargetSafeArea") as MarginContainer
	var target_center := hud.get_node_or_null(^"TargetSafeArea/TargetCenter") as CenterContainer
	var target_frame := hud.get_node_or_null(
		^"TargetSafeArea/TargetCenter/TargetFrame"
	) as UnitHealthFrame
	_expect(
		target_safe_area != null and target_center != null and target_frame != null,
		"top-center target HUD node structure exists"
	)
	if target_safe_area == null or target_center == null or target_frame == null:
		await _cleanup(hud, player, first, second)
		return
	_expect(
		target_safe_area.anchor_left == 0.0
		and target_safe_area.anchor_right == 1.0
		and target_safe_area.anchor_top == 0.0,
		"target safe area spans the top edge"
	)
	_expect(
		target_frame.custom_minimum_size == Vector2(480.0, 64.0),
		"target frame uses the dedicated 480 by 64 size"
	)
	_expect(not target_frame.visible, "target frame starts hidden without a lock")

	var targeting := player.get_node_or_null(^"TargetingSystem") as PlayerTargetingComponent
	_expect(targeting != null, "real PlayerBase exposes its targeting component")
	if targeting == null:
		await _cleanup(hud, player, first, second)
		return
	_expect(targeting.request_lock(first), "first target lock succeeds")
	await process_frame
	var name_label := target_frame.get_node(
		^"FrameContent/CoreInfo/Header/NameLabel"
	) as Label
	var health_value := target_frame.get_node(
		^"FrameContent/CoreInfo/HealthBar/HealthValue"
	) as Label
	var health_bar := target_frame.get_node(
		^"FrameContent/CoreInfo/HealthBar"
	) as ProgressBar
	_expect(
		target_frame.visible and target_frame.is_bound(),
		"locking reveals and binds the target frame"
	)
	_expect(
		name_label.text == "目标甲"
		and name_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"target HUD shows a centered target name"
	)
	_expect(
		health_value.text == "200 / 200" and is_equal_approx(health_bar.value, 1.0),
		"target HUD shows initial target health"
	)

	first.apply_damage(50.0)
	await process_frame
	_expect(
		health_value.text == "150 / 200" and is_equal_approx(health_bar.value, 0.75),
		"target damage updates the reused health presentation"
	)
	_expect(targeting.request_lock(second), "switching to the second target succeeds")
	await process_frame
	_expect(
		name_label.text == "目标乙" and health_value.text == "80 / 80",
		"target switch rebinds the single top frame"
	)
	first.apply_damage(10.0)
	await process_frame
	_expect(
		name_label.text == "目标乙" and health_value.text == "80 / 80",
		"the old target no longer updates the rebound frame"
	)

	targeting.clear_locked_target()
	await process_frame
	_expect(
		not target_frame.visible and not target_frame.is_bound(),
		"clearing the lock immediately hides and unbinds the target frame"
	)
	_expect(targeting.request_lock(second), "lock before target death succeeds")
	second.apply_damage(second.maximum_health)
	await physics_frame
	await physics_frame
	await process_frame
	_expect(
		player.get_locked_target() == null
		and not target_frame.visible
		and not target_frame.is_bound(),
		"target death clears the existing lock and hides the target frame"
	)
	_expect(second.revive(second.maximum_health), "dead target revives for later fixture use")

	_expect(targeting.request_lock(first), "pre-binding lock succeeds")
	hud.unbind_party()
	hud.bind_party(player, allies)
	await process_frame
	_expect(
		target_frame.visible and name_label.text == "目标甲",
		"party binding synchronizes a lock that already exists"
	)
	hud.unbind_party()
	targeting.clear_locked_target()
	_expect(targeting.request_lock(second), "lock changes after HUD unbind still work")
	await process_frame
	_expect(
		not target_frame.visible and not target_frame.is_bound(),
		"unbound HUD no longer responds to the old player signal"
	)

	await _cleanup(hud, player, first, second)


## 创建一名进入现有 enemy_targets 分组、位于默认锁定范围内的 team 2 单位。
func _make_enemy(
	unit_scene: PackedScene,
	unit_name: String,
	maximum: float,
	unit_position: Vector3
) -> UnitBase:
	var unit := unit_scene.instantiate() as UnitBase
	unit.name = unit_name
	unit.team_id = 2
	unit.maximum_health = maximum
	unit.position = unit_position
	unit.add_to_group(&"enemy_targets")
	_world.add_child(unit)
	return unit


## 清理本测试创建的 HUD、玩家、敌人与临时世界，然后结束测试。
func _cleanup(
	hud: CombatHUD,
	player: PlayerBase,
	first: UnitBase,
	second: UnitBase
) -> void:
	for node: Node in [hud, player, first, second]:
		if is_instance_valid(node):
			node.queue_free()
	if is_instance_valid(_world):
		_world.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CombatHUDTargetHealthTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("CombatHUDTargetHealthTest: FAIL (%d)" % _failures.size())
	quit(1)
