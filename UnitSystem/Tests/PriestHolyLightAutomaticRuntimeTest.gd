extends SceneTree

## 回归“自动治疗错误依赖敌方锁定”的根因。
##
## 场景中刻意不创建任何敌人：Priest 必须在 Formation 行为期间，使用
## HolyLight 已有的 FRIENDLY + NEAREST 配置发现并治疗范围内友方。
const PRIEST_SCENE_PATH := "res://UnitSystem/AI/Ally/Units/Priest.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []
var _delivery_started: bool = false
var _delivery_target: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var priest := (
		load(PRIEST_SCENE_PATH) as PackedScene
	).instantiate() as AllyBase
	var player := (
		load(UNIT_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	var friendly_target := (
		load(UNIT_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	_expect(
		priest != null and player != null and friendly_target != null,
		"automatic HolyLight fixtures instantiate"
	)
	if priest == null or player == null or friendly_target == null:
		_finish()
		return

	player.name = &"RuntimePlayer"
	player.faction_id = "Player"
	player.team_id = 1
	friendly_target.faction_id = "Ally"
	friendly_target.team_id = 1
	priest.team_id = 1
	priest.gravity_multiplier = 0.0
	priest.movement_speed = 0.0
	# 在进入树前禁用自动施法，避免未完成候选、配置和受伤状态时先进入冷却。
	priest.automatic_skill_cast_enabled = false
	priest.position = Vector3.ZERO
	friendly_target.position = Vector3(1.0, 0.0, 0.0)
	player.position = Vector3(2.0, 0.0, 0.0)

	root.add_child(player)
	root.add_child(priest)
	root.add_child(friendly_target)
	await physics_frame
	await physics_frame

	var host := priest.get_node_or_null(^"SkillHost") as SkillHostComponent
	var holy_light := priest.get_node_or_null(
		^"SkillHost/SkillSocket/HolyLightSkill"
	) as SkillBase
	_expect(host != null and holy_light != null, "Priest owns configured HolyLight")
	if host == null or holy_light == null:
		await _cleanup(player, priest, friendly_target)
		return
	host.configure_owner(priest, root)
	# 消除随机决策等待，只验证通用自动机会检查、目标解析和真实动画交付。
	holy_light.decision_delay_min = 0.0
	holy_light.decision_delay_max = 0.0
	holy_light.extra_hesitation_chance = 0.0
	holy_light.base_cast_time = 0.1
	holy_light.delivery_started.connect(
		func(context: SkillContext) -> void:
			_delivery_started = true
			_delivery_target = context.resolved_target
	)

	friendly_target.apply_damage(50.0, priest)
	priest.set_automatic_skill_cast_enabled(true)
	for _frame: int in range(180):
		if _delivery_started:
			break
		await physics_frame

	_expect(
		priest.get_locked_target() == null,
		"Priest has no hostile combat target during automatic healing"
	)
	_expect(
		_delivery_started,
		"Priest automatically releases HolyLight without an enemy lock"
	)
	_expect(
		_delivery_target == friendly_target,
		"HolyLight resolves the nearest damaged friendly target"
	)
	_expect(
		is_equal_approx(friendly_target.get_current_health(), 75.0),
		"HolyLight selects and heals the nearby friendly target"
	)
	await _cleanup(player, priest, friendly_target)


func _cleanup(player: Node, priest: Node, target: Node) -> void:
	player.queue_free()
	priest.queue_free()
	target.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PriestHolyLightAutomaticRuntimeTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
