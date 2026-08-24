extends SceneTree

## 回归验证：技能已经进入范围外排队，但施法者持续无法缩短距离时，
## 行为状态机必须主动结束本次请求，不能让 SkillHost 永久占用 active_skill。

const PLAYER_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const CASTER_SCENE_PATH := "res://UnitSystem/AI/Ally/Units/Caster.tscn"
const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const MAXIMUM_WAIT_FRAMES: int = 240

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var player := (
		load(PLAYER_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	var caster := (
		load(CASTER_SCENE_PATH) as PackedScene
	).instantiate() as AllyBase
	var enemy := (
		load(ENEMY_SCENE_PATH) as PackedScene
	).instantiate() as AIUnitBase
	if player == null or caster == null or enemy == null:
		_failures.append("skill approach fixtures instantiate")
		_finish()
		return

	player.name = &"RuntimePlayer"
	player.faction_id = "Player"
	player.team_id = 1
	caster.team_id = 1
	enemy.team_id = 2
	caster.gravity_multiplier = 0.0
	enemy.gravity_multiplier = 0.0
	## 使用零移动速度稳定模拟“存在目标，但导航接近没有任何进展”的情况。
	caster.movement_speed = 0.0
	player.position = Vector3.ZERO
	caster.position = Vector3.ZERO
	enemy.position = Vector3(8.0, 0.0, 0.0)

	root.add_child(player)
	root.add_child(caster)
	root.add_child(enemy)
	await physics_frame

	var skill := caster.get_node(
		^"SkillHost/SkillSocket/FireboltSkill"
	) as SkillBase
	var host := caster.get_node(^"SkillHost") as SkillHostComponent
	var targeting: AITargetingComponent = caster.get_targeting_component()
	_expect(skill != null, "Caster provides FireboltSkill")
	_expect(host != null, "Caster provides SkillHostComponent")
	_expect(targeting != null, "Caster provides AITargetingComponent")
	if skill == null or host == null or targeting == null:
		_cleanup([player, caster, enemy])
		_finish()
		return

	skill.cast_range = 1.0
	skill.decision_delay_min = 0.0
	skill.decision_delay_max = 0.0
	skill.extra_hesitation_chance = 0.0
	var cancellation_reasons: Array[StringName] = []
	var failure_reasons: Array[StringName] = []
	var release_count: Array[int] = [0]
	skill.skill_cancelled.connect(
		func(_context: SkillContext, reason: StringName) -> void:
			cancellation_reasons.append(reason)
	)
	skill.skill_failed.connect(
		func(_context: SkillContext, reason: StringName) -> void:
			failure_reasons.append(reason)
	)
	skill.delivery_started.connect(
		func(_context: SkillContext) -> void:
			release_count[0] += 1
	)

	targeting.call(&"_set_locked_target", enemy)
	targeting.set_physics_process(false)
	## 本测试直接请求一次范围外技能，隔离普通 COMBAT_APPROACH 与技能自身
	## QUEUED/approach_requested 链路；自动技能决策关闭后不会在取消后立即重试。
	caster.set_automatic_skill_cast_enabled(false)
	_expect(
		host.request_skill(&"firebolt", enemy),
		"Explicit out-of-range Firebolt request enters the queued approach"
	)

	for _frame: int in range(MAXIMUM_WAIT_FRAMES):
		if &"approach_stalled" in cancellation_reasons:
			break
		await physics_frame

	var behavior := caster.get_behavior_state_machine()
	var no_progress_value: Variant = behavior.get(
		"_skill_approach_no_progress_elapsed"
	)
	_expect(
		&"approach_stalled" in cancellation_reasons,
		(
			"Stalled skill approach cancels the active request; "
			+ "skill_state=%s, active=%s, behavior=%s, "
			+ "approach_target=%s, no_progress=%.3f, "
			+ "cancel_reasons=%s, failure_reasons=%s, releases=%d"
		) % [
			str(skill.get_state()),
			str(host.get_active_skill()),
			str(behavior.get_current_state_name()),
			str(behavior.get("_skill_approach_target")),
			float(no_progress_value) if no_progress_value != null else -1.0,
			str(cancellation_reasons),
			str(failure_reasons),
			release_count[0],
		]
	)

	_cleanup([player, caster, enemy])
	await process_frame
	_finish()


func _cleanup(nodes: Array[Node]) -> void:
	for node: Node in nodes:
		if is_instance_valid(node):
			node.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SkillApproachRecoveryTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
