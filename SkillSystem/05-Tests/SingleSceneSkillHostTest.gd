extends SceneTree

## SkillHost 的装配、选择和动作路由契约测试。

const HOST_SCENE_PATH := \
	"res://SkillSystem/01-Core/SkillHostComponent.tscn"
const SKILL_SCENE_PATH := \
	"res://SkillSystem/01-Core/SkillBase.tscn"

var _failures: Array[String] = []
var _world: Node3D


class TestUnit:
	extends Node3D

	var faction: StringName = &"ally"

	func is_targetable() -> bool:
		return true

	func is_dead() -> bool:
		return false

	func is_hostile_to(other: Node) -> bool:
		return other != null and other.get("faction") != faction

	func is_friendly_to(other: Node) -> bool:
		return other != null and other.get("faction") == faction

	func is_neutral_to(other: Node) -> bool:
		return other != null and other.get("faction") == &"neutral"


class CandidateProvider:
	extends Node

	var candidates: Array[Node3D] = []
	var query_count: int = 0

	func get_perceived_candidates(
		_maximum_distance: float = -1.0
	) -> Array[Node3D]:
		query_count += 1
		return candidates.duplicate()


class RecordingEffect:
	extends SkillEffectBase

	func apply(
		_context: SkillContext,
		_result: SkillDeliveryResult,
		_target: Node3D
	) -> bool:
		return true


func _initialize() -> void:
	_world = Node3D.new()
	get_root().add_child(_world)
	call_deferred(&"_run_test")


func _run_test() -> void:
	if not ResourceLoader.exists(HOST_SCENE_PATH):
		_failures.append("Single-scene SkillHost scene does not exist")
		_finish()
		return
	var host_scene := load(HOST_SCENE_PATH) as PackedScene
	var skill_scene := load(SKILL_SCENE_PATH) as PackedScene
	_expect(host_scene != null, "SkillHost scene loads")
	_expect(skill_scene != null, "SkillBase scene remains available")
	if host_scene == null or skill_scene == null:
		_finish()
		return

	var caster := TestUnit.new()
	var friendly := TestUnit.new()
	var enemy := TestUnit.new()
	enemy.faction = &"enemy"
	_world.add_child(caster)
	_world.add_child(friendly)
	_world.add_child(enemy)
	friendly.global_position = Vector3(2.0, 0.0, 0.0)
	enemy.global_position = Vector3(3.0, 0.0, 0.0)
	var provider := CandidateProvider.new()
	provider.candidates.assign([friendly, enemy])
	caster.add_child(provider)
	var host: Node = host_scene.instantiate()
	caster.add_child(host)
	var socket: Node = host.get_node_or_null(^"SkillSocket")
	_expect(socket != null, "SkillHost owns fixed SkillSocket")

	var skill: Node = skill_scene.instantiate()
	skill.name = "TestSkill"
	skill.set("skill_id", &"test_skill")
	skill.set(
		"target_relations",
		TargetResolver.TargetRelationFlag.HOSTILE
	)
	skill.set("cast_range", 5.0)
	skill.set("decision_delay_min", 0.0)
	skill.set("decision_delay_max", 0.0)
	# 显式指定技能是外部确定性请求，不应受到仅供 AI 自动决策使用的额外拖延影响。
	# 将额外拖延设为必定触发，可稳定验证 Host 正确区分两种请求入口。
	skill.set("extra_hesitation_chance", 1.0)
	skill.set("extra_hesitation_min", 5.0)
	skill.set("extra_hesitation_max", 5.0)
	skill.set("skill_cooldown", 1.0)
	skill.set("base_cast_time", 0.8)
	skill.set("delivery", InstantTargetDeliveryConfig.new())
	skill.add_child(RecordingEffect.new())
	socket.add_child(skill)
	host.call("discover_skills")

	_expect(
		(host.call("get_registered_skills") as Array).size() == 1,
		"Host discovers one direct SkillSocket child"
	)
	_expect(
		is_equal_approx(float(host.call("get_preferred_cast_range")), 5.0),
		"Host exposes preferred cast range"
	)
	# 技能冷却只限制“是否能够再次释放”，不能改变 AI 的战术站位距离。
	# 否则纯施法单位会在每次释放结束后回退到武器的近战距离并向目标冲刺。
	skill.call("_start_cooldown")
	_expect(
		is_equal_approx(float(host.call("get_preferred_cast_range")), 5.0),
		"Cooling skill continues to define the host positioning range"
	)
	skill.call("reset_skill")
	var action_count: Array[int] = [0]
	var requested_cast_time: Array[float] = [-1.0]
	var released_count: Array[int] = [0]
	host.action_requested.connect(
		func(
			_skill: SkillBase,
			_target: Node3D,
			effective_cast_time: float
		) -> void:
			action_count[0] += 1
			requested_cast_time[0] = effective_cast_time
	)
	host.skill_released.connect(
		func(_context: SkillContext) -> void:
			released_count[0] += 1
	)

	_expect(
		bool(host.call("request_skill", &"test_skill", enemy)),
		"Host accepts explicit skill request"
	)
	var explicit_context := skill.call("get_current_context") as SkillContext
	_expect(
		explicit_context != null
		and explicit_context.explicit_target_requested,
		"explicit Host request marks its target authoritative"
	)
	_expect(action_count[0] == 1, "Host forwards one action request")
	_expect(
		bool(host.call("is_active_skill_action_in_progress")),
		"Queued or action-requested active skill occupies the basic attack chain"
	)
	_expect(
		is_equal_approx(requested_cast_time[0], 0.8),
		"Host forwards the already computed effective cast time as request data"
	)
	_expect(host.call("get_active_skill") == skill, "Host stores active skill")
	var cast_transform := Transform3D(Basis.IDENTITY, Vector3(5.0, 1.0, 2.0))
	_expect(
		bool(host.call("confirm_active_action_started", cast_transform)),
		"Host confirms active action"
	)
	_expect(
		bool(host.call("release_active_action", cast_transform)),
		"Host routes release to active skill"
	)
	_expect(
		not bool(host.call("is_active_skill_action_in_progress")),
		"Released skill hesitation does not occupy the basic attack chain"
	)
	_expect(released_count[0] == 1, "Host reports successful skill release")
	host.call("finish_active_action")
	_expect(host.call("get_active_skill") == null, "Action finish releases active slot")

	# 自动请求只能读取注入的感知 Provider，不能再次扫描隐藏的全场景分组。
	skill.call("reset_skill")
	skill.set(
		"target_relations",
		TargetResolver.TargetRelationFlag.FRIENDLY
	)
	skill.set(
		"target_selection_mode",
		TargetResolver.TargetSelectionMode.NEAREST
	)
	# 自动技能的首发不应等待随机犹豫；该数值应在成功释放后由 SkillBase 结算。
	skill.set("decision_delay_min", 5.0)
	skill.set("decision_delay_max", 5.0)
	skill.set("extra_hesitation_chance", 0.0)
	host.call("start_global_cooldown", 0.0)
	host.call("set_target_candidate_provider", provider)
	var hidden_group_candidate := TestUnit.new()
	_world.add_child(hidden_group_candidate)
	hidden_group_candidate.global_position = Vector3(0.1, 0.0, 0.0)
	hidden_group_candidate.add_to_group(&"skill_target_candidates")
	_expect(
		bool(host.call("request_best_skill", null)),
		"Host supplies injected perception candidates to an automatic skill"
	)
	_expect(
		action_count[0] == 2,
		"Automatic skill requests its cast action immediately despite configured post-release hesitation"
	)
	var automatic_context := skill.call("get_current_context") as SkillContext
	_expect(
		automatic_context != null
		and automatic_context.resolved_target == friendly,
		"automatic request ignores a nearer hidden-group-only candidate"
	)
	_expect(
		automatic_context != null
		and not automatic_context.explicit_target_requested,
		"automatic Host request leaves target selection to the skill"
	)
	_expect(
		provider.query_count == 1,
		"one automatic decision reads exactly one candidate snapshot"
	)
	host.call("cancel_active_skill", &"test_cleanup")
	host.call("set_target_candidate_provider", null)
	_expect(
		not bool(host.call("request_best_skill", null)),
		"automatic request without a Provider fails safely"
	)

	# 排队技能的目标可能在动作尚未开始前死亡、移除或失去有效性。
	# 失败信号返回后，Host 必须立即释放 active_skill，不能永久占用自动施法入口。
	skill.call("reset_skill")
	skill.set(
		"target_relations",
		TargetResolver.TargetRelationFlag.HOSTILE
	)
	skill.set(
		"target_selection_mode",
		TargetResolver.TargetSelectionMode.CURRENT_COMBAT_TARGET
	)
	skill.set("cast_range", 1.0)
	var invalidated_enemy := TestUnit.new()
	invalidated_enemy.faction = &"enemy"
	_world.add_child(invalidated_enemy)
	invalidated_enemy.global_position = Vector3(10.0, 0.0, 0.0)
	_expect(
		bool(host.call("request_skill", &"test_skill", invalidated_enemy)),
		"Host queues an out-of-range skill before target invalidation"
	)
	_expect(
		host.call("get_active_skill") == skill,
		"Queued skill initially owns the active slot"
	)
	invalidated_enemy.queue_free()
	## queue_free() 在当前帧末尾真正移除节点；随后 Host 需要一个物理帧重新验证
	## 已排队请求。等待少量确定帧数，验证最终状态而不依赖 SceneTree 回调顺序。
	for _frame: int in range(3):
		await physics_frame
		if host.call("get_active_skill") == null:
			break
	_expect(
		host.call("get_active_skill") == null,
		(
			"Target invalidation releases the queued active skill; "
			+ "skill_state=%s, target_valid=%s, target_inside_tree=%s"
		) % [
			str(skill.call("get_state")),
			str(is_instance_valid(invalidated_enemy)),
			str(
				invalidated_enemy.is_inside_tree()
				if is_instance_valid(invalidated_enemy)
				else false
			),
		]
	)

	host.call("set_skill_casting_enabled", false)
	_expect(
		not bool(host.call("request_skill", &"test_skill", enemy)),
		"Disabled host rejects skill request"
	)

	caster.queue_free()
	friendly.queue_free()
	enemy.queue_free()
	hidden_group_candidate.queue_free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("SingleSceneSkillHostTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
