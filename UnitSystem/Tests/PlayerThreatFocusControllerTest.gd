extends SceneTree

## 玩家锁定仇恨提示控制器的真实场景集成测试。
## 使用真实 PlayerBase、EnemyBase、EnemyThreatComponent 与 WorldHealthBar 验证提示层只读取已存在的仇恨和锁定结果，不修改其任何底层状态。
const CONTROLLER_SCENE_PATH := (
	"res://UnitSystem/Components/UI/PlayerThreatFocusController.tscn"
)
const PLAYER_SCENE_PATH := "res://UnitSystem/Player/PlayerBase.tscn"
const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const EVENT_SCRIPT_PATH := "res://UnitSystem/Components/Threat/ThreatEvent.gd"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ResourceLoader.exists(CONTROLLER_SCENE_PATH), "focus controller scene exists")
	var controller_scene := load(CONTROLLER_SCENE_PATH) as PackedScene
	var player_scene := load(PLAYER_SCENE_PATH) as PackedScene
	var enemy_scene := load(ENEMY_SCENE_PATH) as PackedScene
	var unit_scene := load(UNIT_SCENE_PATH) as PackedScene
	var event_script := load(EVENT_SCRIPT_PATH) as Script
	_expect(
		controller_scene != null
		and player_scene != null
		and enemy_scene != null
		and unit_scene != null
		and event_script != null,
		"focus display fixtures load"
	)
	if (
		controller_scene == null
		or player_scene == null
		or enemy_scene == null
		or unit_scene == null
		or event_script == null
	):
		_finish()
		return

	_world = Node3D.new()
	root.add_child(_world)
	var player := player_scene.instantiate() as PlayerBase
	var enemy := enemy_scene.instantiate() as EnemyBase
	var guardian := unit_scene.instantiate() as UnitBase
	var archer := unit_scene.instantiate() as UnitBase
	player.name = "Player"
	enemy.name = "FocusedEnemy"
	guardian.name = "Guardian"
	archer.name = "Archer"
	player.position = Vector3.ZERO
	enemy.position = Vector3(0.0, 0.0, -2.0)
	guardian.position = Vector3(0.5, 0.0, -1.0)
	archer.position = Vector3(-0.5, 0.0, -1.0)
	guardian.team_id = 1
	archer.team_id = 1
	_world.add_child(player)
	_world.add_child(enemy)
	_world.add_child(guardian)
	_world.add_child(archer)
	await process_frame
	await process_frame

	var player_targeting := player.get_node_or_null(^"TargetingSystem") as Node
	var enemy_targeting := enemy.get_targeting_component()
	var threat_component := enemy.get_threat_component()
	_expect(
		player_targeting != null
		and enemy_targeting != null
		and threat_component != null,
		"focus display finds existing player and enemy target interfaces"
	)
	if player_targeting == null or enemy_targeting == null or threat_component == null:
		await _cleanup()
		return

	_expect(
		bool(player_targeting.call(&"request_lock", enemy)),
		"player can lock the enemy providing the displayed local threat table"
	)
	_expect(
		bool(threat_component.call(&"submit_threat", event_script.call("create_damage", guardian, 100.0)))
		and bool(threat_component.call(&"submit_threat", event_script.call("create_damage", archer, 110.0))),
		"two allied sources create current and warning-range threat entries"
	)
	enemy_targeting.call(&"_set_locked_target", guardian)
	await process_frame
	_expect(
		_is_outline_visible(guardian)
		and _get_outline_color(guardian).is_equal_approx(Color(1.0, 0.16, 0.12, 1.0)),
		"current target receives the red-priority outline"
	)
	_expect(
		_is_outline_visible(archer)
		and _get_outline_color(archer).is_equal_approx(Color(1.0, 0.82, 0.12, 1.0)),
		"a non-current ally at 110 percent receives the yellow warning outline"
	)

	_expect(
		bool(threat_component.call(&"submit_threat", event_script.call("create_damage", archer, 20.0))),
		"warning source can exceed the 125 percent target-switch threshold"
	)
	await process_frame
	_expect(
		_is_outline_visible(archer)
		and _get_outline_color(archer).is_equal_approx(Color(1.0, 0.16, 0.12, 1.0))
		and not _is_outline_visible(guardian),
		"above 125 percent the new selected target is red and the old target clears"
	)

	player.clear_locked_target()
	await process_frame
	_expect(
		not _is_outline_visible(guardian) and not _is_outline_visible(archer),
		"player unlock clears all focused threat outlines"
	)
	await _cleanup()


func _is_outline_visible(unit: UnitBase) -> bool:
	var health_bar := unit.get_node_or_null(
		^"WorldUIRoot/WorldHealthBar"
	) as WorldHealthBar
	var outline := health_bar.get_node_or_null(
		^"HealthBarViewport/BarRoot/ThreatOutline"
	) as Control if health_bar != null else null
	return outline != null and outline.visible


func _get_outline_color(unit: UnitBase) -> Color:
	var health_bar := unit.get_node_or_null(
		^"WorldUIRoot/WorldHealthBar"
	) as WorldHealthBar
	var outline := health_bar.get_node_or_null(
		^"HealthBarViewport/BarRoot/ThreatOutline"
	) as Panel if health_bar != null else null
	var style := outline.get_theme_stylebox(&"panel") as StyleBoxFlat if outline != null else null
	return style.border_color if style != null else Color.TRANSPARENT


func _cleanup() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PlayerThreatFocusControllerTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("PlayerThreatFocusControllerTest: FAIL (%d)" % _failures.size())
	quit(1)
