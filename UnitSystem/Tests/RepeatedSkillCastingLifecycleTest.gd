extends SceneTree

## 回归验证：同一个 AI 单位连续释放超过七次技能后，动作占用与移动锁必须正常归还。
const PLAYER_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const CASTER_SCENE_PATH := "res://UnitSystem/AI/Ally/Units/Caster.tscn"
const PRIEST_SCENE_PATH := "res://UnitSystem/AI/Ally/Units/Priest.tscn"
const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const REQUIRED_RELEASE_COUNT: int = 20

var _failures: Array[String] = []
var _caster_release_count: int = 0
var _priest_release_count: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var player := (
		load(PLAYER_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	var caster := (
		load(CASTER_SCENE_PATH) as PackedScene
	).instantiate() as AllyBase
	var priest := (
		load(PRIEST_SCENE_PATH) as PackedScene
	).instantiate() as AllyBase
	var enemy := (
		load(ENEMY_SCENE_PATH) as PackedScene
	).instantiate() as AIUnitBase
	var friendly := (
		load(PLAYER_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	if (
		player == null
		or caster == null
		or priest == null
		or enemy == null
		or friendly == null
	):
		_failures.append("repeated casting fixtures instantiate")
		_finish()
		return

	player.name = &"RuntimePlayer"
	player.faction_id = "Player"
	player.team_id = 1
	friendly.name = &"RuntimeFriendly"
	friendly.faction_id = "Ally"
	friendly.team_id = 1
	caster.team_id = 1
	priest.team_id = 1
	enemy.team_id = 2
	# 该测试验证长期动作归还，不应让真实伤害闭环在第 5 次释放后终止压力循环。
	# 必须在进入场景树、执行 UnitBase._ready() 前设置生命配置。
	enemy.maximum_health = 10000.0
	enemy.starting_health_percentage = 100.0
	caster.gravity_multiplier = 0.0
	priest.gravity_multiplier = 0.0
	enemy.gravity_multiplier = 0.0

	player.position = Vector3(0.0, 0.0, 4.0)
	caster.position = Vector3(-1.0, 0.0, 1.0)
	priest.position = Vector3(1.0, 0.0, 1.0)
	enemy.position = Vector3(-1.0, 0.0, -1.0)
	friendly.position = Vector3(1.0, 0.0, 2.0)
	root.add_child(player)
	root.add_child(caster)
	root.add_child(priest)
	root.add_child(enemy)
	root.add_child(friendly)
	await physics_frame

	var caster_host := caster.get_node(^"SkillHost") as SkillHostComponent
	var priest_host := priest.get_node(^"SkillHost") as SkillHostComponent
	var firebolt := caster.get_node(
		^"SkillHost/SkillSocket/FireboltSkill"
	) as SkillBase
	var holy_light := priest.get_node(
		^"SkillHost/SkillSocket/HolyLightSkill"
	) as SkillBase
	caster_host.configure_owner(caster, root)
	priest_host.configure_owner(priest, root)
	_configure_stress_timing(caster, firebolt)
	_configure_stress_timing(priest, holy_light)
	firebolt.delivery.set(&"projectile_speed", 40.0)
	firebolt.delivery.set(&"maximum_lifetime", 0.5)
	friendly.apply_damage(50.0, priest)

	var targeting: AITargetingComponent = caster.get_targeting_component()
	targeting.call(&"_set_locked_target", enemy)
	targeting.set_physics_process(false)
	firebolt.delivery_started.connect(
		func(_context: SkillContext) -> void:
			_caster_release_count += 1
	)
	holy_light.delivery_started.connect(
		func(_context: SkillContext) -> void:
			_priest_release_count += 1
	)

	var previous_total: int = 0
	var frames_without_progress: int = 0
	for _frame: int in range(3600):
		var current_total: int = (
			_caster_release_count + _priest_release_count
		)
		if current_total == previous_total:
			frames_without_progress += 1
		else:
			previous_total = current_total
			frames_without_progress = 0
		if (
			_caster_release_count >= REQUIRED_RELEASE_COUNT
			and _priest_release_count >= REQUIRED_RELEASE_COUNT
		):
			break
		if frames_without_progress >= 600:
			break
		await physics_frame

	_expect(
		_caster_release_count >= REQUIRED_RELEASE_COUNT,
		"Caster repeated casting stalled: "
			+ _describe_runtime_state(caster, caster_host, firebolt)
	)
	_expect(
		_priest_release_count >= REQUIRED_RELEASE_COUNT,
		"Priest repeated casting stalled: "
			+ _describe_runtime_state(priest, priest_host, holy_light)
	)

	caster.set_automatic_skill_cast_enabled(false)
	priest.set_automatic_skill_cast_enabled(false)
	for _frame: int in range(120):
		await physics_frame

	_assert_action_released(caster, caster_host, "Caster")
	_assert_action_released(priest, priest_host, "Priest")

	for node: Node in [player, caster, priest, enemy, friendly]:
		node.queue_free()
	await process_frame
	_finish()


func _configure_stress_timing(unit: AllyBase, skill: SkillBase) -> void:
	unit.shared_action_cooldown_duration = 0.1
	skill.skill_cooldown = 0.2
	skill.base_cast_time = 0.15
	skill.decision_delay_min = 0.0
	skill.decision_delay_max = 0.3
	skill.extra_hesitation_chance = 0.1
	skill.extra_hesitation_min = 0.2
	skill.extra_hesitation_max = 0.5


func _describe_runtime_state(
	unit: AllyBase,
	host: SkillHostComponent,
	skill: SkillBase
) -> String:
	var behavior := unit.get_behavior_state_machine()
	var controller := unit.get_node_or_null(
		^"CombatSystem/AttackController"
	)
	var runner := skill.get_node_or_null(^"DeliveryRunner")
	return (
		"releases=%d, skill_state=%s, cooldown=%.3f, "
		+ "host_active=%s, movement_locked=%s, "
		+ "controller_state=%s, runner_busy=%s, behavior_state=%s, "
		+ "shared_cooldown=%.3f, auto_enabled=%s, casting_enabled=%s, "
		+ "locked_target=%s, target_position=%s, unit_position=%s, "
		+ "movement_target=%s, velocity=%s, policy=%s, "
		+ "effective_distance=%.3f, effective_tolerance=%.3f"
	) % [
		(
			_caster_release_count
			if unit.name == &"Caster"
			else _priest_release_count
		),
		str(skill.get_state()),
		skill.get_cooldown_remaining(),
		str(host.get_active_skill()),
		str(behavior.get("_skill_movement_locked")),
		str(controller.get("_state") if controller != null else "missing"),
		str(runner.call("is_busy") if runner != null else "missing"),
		str(behavior.call("get_current_state_name")),
		float(behavior.get("_shared_action_cooldown_remaining")),
		str(behavior.get("automatic_skill_cast_enabled")),
		str(host.is_skill_casting_enabled()),
		str(unit.get_locked_target()),
		str(
			unit.get_locked_target().global_position
			if unit.get_locked_target() != null
			else Vector3.INF
		),
		str(unit.global_position),
		str(behavior.call("get_current_movement_target")),
		str(unit.velocity),
		str(behavior.get("combat_action_policy")),
		float(behavior.call("get_effective_combat_distance")),
		float(behavior.call("get_effective_combat_distance_tolerance")),
	]


func _assert_action_released(
	unit: AllyBase,
	host: SkillHostComponent,
	label: String
) -> void:
	var behavior := unit.get_behavior_state_machine()
	_expect(
		host.get_active_skill() == null,
		label + " releases the active skill slot"
	)
	_expect(
		not bool(behavior.get("_skill_movement_locked")),
		label + " releases the movement lock"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("RepeatedSkillCastingLifecycleTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
