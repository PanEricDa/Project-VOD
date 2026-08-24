@tool
class_name SkillHostComponent
extends Node

## 单位级技能插槽和动作请求中介。
##
## Host 管理技能装配、AI 延迟、活动技能和公共冷却，但不播放动画、不读取
## DeliveryConfig，也不依赖任何具体 AI 或角色脚本。

signal skill_registered(skill: SkillBase)
signal skill_unregistered(skill: SkillBase)
signal active_skill_changed(skill: SkillBase)
signal action_requested(
	skill: SkillBase,
	target: Node3D,
	effective_cast_time: float
)
signal approach_requested(context: SkillContext, cast_range: float)
signal facing_requested(context: SkillContext)
signal movement_lock_requested(locked: bool)
signal skill_released(context: SkillContext)
signal global_cooldown_started(duration: float)
signal global_cooldown_finished()

@export_category("Assembly")
## 开启后自动注册固定 SkillSocket 子节点下的全部 SkillBase；关闭时需由外部手动调用 register_skill()。
@export var auto_discover_skills: bool = true
## 开启后将本节点的 Node3D 父节点作为施法者自动注入；关闭用于由外部显式指定施法者的特殊装配。
@export var auto_configure_parent_owner: bool = true

@export_category("Global Cooldown")
@export_range(0.0, 30.0, 0.05, "or_greater")
## Host 独立管理公共冷却时使用的基础时长，单位为秒；由 Ally 行为层接管时该值不会参与实际计时。
var global_cooldown_duration: float = 1.0

var _caster: Node3D
var _delivery_parent: Node
var _registered_skills: Array[SkillBase] = []
var _active_skill: SkillBase
var _pending_context: SkillContext
var _skill_casting_enabled: bool = true
var _cast_blocked: bool = false
var _use_external_global_cooldown: bool = false
var _external_global_cooldown_blocked: bool = false
var _global_cooldown_remaining: float = 0.0
var _movement_locked: bool = false
## 由单位装配层注入的只读感知候选提供者；Host 不依赖具体 AI 组件类型。
var _target_candidate_provider: Node


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if auto_configure_parent_owner:
		var parent := get_parent() as Node3D
		if parent != null:
			configure_owner(parent)
	if auto_discover_skills:
		discover_skills()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _use_external_global_cooldown and _global_cooldown_remaining > 0.0:
		_global_cooldown_remaining = maxf(
			_global_cooldown_remaining - delta,
			0.0
		)
		if _global_cooldown_remaining <= 0.0:
			global_cooldown_finished.emit()

	if (
		is_instance_valid(_active_skill)
		and _active_skill.get_state() == SkillBase.SkillState.QUEUED
	):
		_active_skill.try_request_action()


func configure_owner(caster: Node3D, delivery_parent: Node = null) -> void:
	_caster = caster
	_delivery_parent = delivery_parent
	if not is_instance_valid(_delivery_parent) and is_instance_valid(caster):
		var tree: SceneTree = caster.get_tree()
		if tree != null:
			_delivery_parent = (
				tree.current_scene
				if is_instance_valid(tree.current_scene)
				else tree.root
			)
	for skill: SkillBase in _registered_skills:
		skill.configure_owner(_caster, self, _delivery_parent)


func register_skill(skill: SkillBase) -> bool:
	if skill == null or skill in _registered_skills:
		return false
	for registered: SkillBase in _registered_skills:
		if registered.skill_id == skill.skill_id:
			return false
	_registered_skills.append(skill)
	skill.configure_owner(_caster, self, _delivery_parent)
	_connect_skill(skill)
	skill_registered.emit(skill)
	update_configuration_warnings()
	return true


func unregister_skill(skill: SkillBase) -> bool:
	if skill == null or skill not in _registered_skills:
		return false
	if _active_skill == skill:
		cancel_active_skill(&"skill_unregistered")
	_disconnect_skill(skill)
	_registered_skills.erase(skill)
	skill.configure_owner(null, null, null)
	skill_unregistered.emit(skill)
	update_configuration_warnings()
	return true


func discover_skills() -> void:
	var socket := get_node_or_null(^"SkillSocket")
	if socket == null:
		return
	for child: Node in socket.get_children():
		if child is SkillBase:
			register_skill(child as SkillBase)


func request_skill(
	skill_id: StringName,
	target: Node3D,
	candidate_targets: Array[Node3D] = [],
	target_position: Vector3 = Vector3.INF,
	source: int = 0
) -> bool:
	if not _can_start_request():
		return false
	var skill := _find_skill(skill_id)
	if skill == null:
		return false
	var context := _create_context(
		target,
		candidate_targets,
		target_position,
		source,
		true
	)
	if not skill.can_request(context):
		return false
	# 显式请求已经由外部调用者完成了“何时施放”的决定，因此必须立即进入技能流程。
	# AI 的随机犹豫只属于自动选择入口，不能污染玩家指令、剧情事件或测试调用。
	return _begin_decision(skill, context)


func request_best_skill(target: Node3D) -> bool:
	if not _can_start_request():
		return false
	## 每轮决策只读取一次快照，确保所有候选技能基于相同的感知时刻评估。
	var candidate_targets: Array[Node3D] = _get_candidate_snapshot()
	var selected: SkillBase = null
	var selected_context: SkillContext = null
	for skill: SkillBase in _registered_skills:
		if not skill.automatic_cast_enabled or not skill.is_ready():
			continue
		# Host 只提供未经分类的候选集合。友军、敌军、自身、距离和 Conditions
		# 均由当前 SkillBase 的既有配置统一解析，防止行为层复制技能规则。
		var context := _create_context(
			target,
			candidate_targets,
			Vector3.INF,
			0,
			false
		)
		if not skill.can_request(context):
			continue
		if selected == null or skill.ai_priority > selected.ai_priority:
			selected = skill
			selected_context = context
	if selected == null:
		return false
	return _begin_decision(selected, selected_context)


## 注入只读的技能候选提供者。
##
## Provider 只需实现 get_perceived_candidates(maximum_distance)，无需继承某个
## SkillSystem 类型；传入 null 可安全卸载。
func set_target_candidate_provider(provider: Node) -> void:
	_target_candidate_provider = provider


## 返回当前 Provider，仅用于装配验证和运行时调试，不暴露为 Inspector NodePath。
func get_target_candidate_provider() -> Node:
	return (
		_target_candidate_provider
		if is_instance_valid(_target_candidate_provider)
		else null
	)


func _get_candidate_snapshot() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	if (
		not is_instance_valid(_target_candidate_provider)
		or not _target_candidate_provider.has_method(
			&"get_perceived_candidates"
		)
	):
		return candidates
	var value: Variant = _target_candidate_provider.call(
		&"get_perceived_candidates",
		-1.0
	)
	if not value is Array:
		return candidates
	for candidate_value: Variant in value:
		if (
			is_instance_valid(candidate_value)
			and candidate_value is Node3D
		):
			candidates.append(candidate_value as Node3D)
	return candidates


func confirm_active_action_started(cast_transform: Transform3D) -> bool:
	return (
		is_instance_valid(_active_skill)
		and _active_skill.confirm_action_started(cast_transform)
	)


func release_active_action(launch_transform: Transform3D) -> bool:
	return (
		is_instance_valid(_active_skill)
		and _active_skill.release_action(launch_transform)
	)


func finish_active_action() -> void:
	if not is_instance_valid(_active_skill):
		return
	_active_skill.finish_action()
	_release_active_skill()


func cancel_active_skill(reason: StringName = &"cancelled") -> void:
	if is_instance_valid(_active_skill):
		_active_skill.cancel_skill(reason)
	_release_active_skill()


func set_cast_blocked(blocked: bool) -> void:
	_cast_blocked = blocked


func set_skill_casting_enabled(enabled: bool) -> void:
	_skill_casting_enabled = enabled
	if not enabled:
		cancel_active_skill(&"skill_casting_disabled")


func is_skill_casting_enabled() -> bool:
	return _skill_casting_enabled


func set_use_external_global_cooldown(active: bool) -> void:
	_use_external_global_cooldown = active
	if active:
		_global_cooldown_remaining = 0.0


func set_external_global_cooldown_blocked(blocked: bool) -> void:
	_external_global_cooldown_blocked = blocked


func start_global_cooldown(duration_override: float = -1.0) -> void:
	if _use_external_global_cooldown:
		return
	var duration: float = (
		duration_override
		if duration_override >= 0.0
		else global_cooldown_duration
	)
	_global_cooldown_remaining = maxf(duration, 0.0)
	global_cooldown_started.emit(_global_cooldown_remaining)
	if _global_cooldown_remaining <= 0.0:
		global_cooldown_finished.emit()


func get_global_cooldown_remaining() -> float:
	return _global_cooldown_remaining


func is_global_cooldown_ready() -> bool:
	return (
		not _external_global_cooldown_blocked
		and (
			_use_external_global_cooldown
			or _global_cooldown_remaining <= 0.0
		)
	)


func get_registered_skills() -> Array[SkillBase]:
	return _registered_skills.duplicate()


func get_active_skill() -> SkillBase:
	return _active_skill if is_instance_valid(_active_skill) else null


## 返回当前已激活技能是否仍占用角色的普通攻击链路。
## 只有已排队接近、已请求动作或正在施法的技能会返回 true；成功释放后的犹豫、技能冷却
## 与就绪状态均返回 false，使拥有普攻资格的 AI 能在共享行动冷却结束后继续普攻填充。
func is_active_skill_action_in_progress() -> bool:
	var active_skill := get_active_skill()
	if not is_instance_valid(active_skill):
		return false
	return active_skill.get_state() in [
		SkillBase.SkillState.QUEUED,
		SkillBase.SkillState.ACTION_REQUESTED,
		SkillBase.SkillState.CASTING,
	]


## 返回当前技能是否仅处于 AI 决策等待。
## 当前随机犹豫统一由 SkillBase 在成功释放后维护，因此 Host 不再保留前置等待并始终返回 false。
func is_waiting_for_ai_decision() -> bool:
	return false


## 返回当前被注入的施法者，仅用于装配验证、调试与外部适配层读取。
##
## 该值不是 Inspector 配置项；正常场景装配时始终由 Host 的父 Unit 自动提供。
func get_skill_owner() -> Node3D:
	return _caster if is_instance_valid(_caster) else null


func get_preferred_cast_range() -> float:
	if is_instance_valid(_active_skill):
		return maxf(_active_skill.cast_range, 0.0)
	var selected: SkillBase = null
	for skill: SkillBase in _registered_skills:
		if (
			not skill.automatic_cast_enabled
			or (selected != null and skill.ai_priority <= selected.ai_priority)
		):
			continue
		selected = skill
	# 该接口描述的是当前技能装配所要求的战术站位，而不是“这一帧能否施法”。
	# 技能冷却只由 request_best_skill() 处理；若在这里过滤冷却中的技能，
	# 纯施法 AI 会在每次释放后错误地退回武器的近战距离。
	return maxf(selected.cast_range, 0.0) if selected != null else 0.0


func _can_start_request() -> bool:
	if (
		is_instance_valid(_caster)
		and _caster.has_method(&"is_dead")
		and bool(_caster.call(&"is_dead"))
	):
		# 死亡是运行时资格，不改写用户配置的技能总开关。
		return false
	return (
		_skill_casting_enabled
		and not _cast_blocked
		and is_global_cooldown_ready()
		and not is_instance_valid(_active_skill)
		and is_instance_valid(_caster)
	)


func _begin_decision(
	skill: SkillBase,
	context: SkillContext
) -> bool:
	_active_skill = skill
	_pending_context = context
	active_skill_changed.emit(_active_skill)
	# AI 自动选择只决定“使用哪个技能”，而不是延迟首发动作。
	# 成功释放后的随机犹豫由 SkillBase 自己维护，Host 不保留等待中的 pending skill。
	_activate_pending_request()
	return is_instance_valid(_active_skill)


func _activate_pending_request() -> void:
	if not is_instance_valid(_active_skill) or _pending_context == null:
		_release_active_skill()
		return
	var context: SkillContext = _pending_context
	_pending_context = null
	if not _active_skill.request_skill(context):
		_release_active_skill()


func _create_context(
	target: Node3D,
	candidate_targets: Array[Node3D],
	target_position: Vector3,
	source: int,
	explicit_target_requested: bool
) -> SkillContext:
	var context := SkillContext.new()
	context.caster = _caster
	context.host = self
	context.requested_target = target
	context.candidate_targets.assign(candidate_targets)
	context.target_position = target_position
	context.delivery_parent = _delivery_parent
	context.request_source = source
	context.explicit_target_requested = explicit_target_requested
	return context


func _find_skill(skill_id: StringName) -> SkillBase:
	for skill: SkillBase in _registered_skills:
		if skill.skill_id == skill_id:
			return skill
	return null


func _connect_skill(skill: SkillBase) -> void:
	skill.action_requested.connect(_on_skill_action_requested)
	skill.cast_range_required.connect(_on_skill_cast_range_required)
	skill.delivery_started.connect(_on_skill_delivery_started)
	skill.skill_failed.connect(_on_skill_terminal)
	skill.skill_cancelled.connect(_on_skill_terminal)


func _disconnect_skill(skill: SkillBase) -> void:
	var connections: Array[Array] = [
		[skill.action_requested, Callable(self, &"_on_skill_action_requested")],
		[skill.cast_range_required, Callable(self, &"_on_skill_cast_range_required")],
		[skill.delivery_started, Callable(self, &"_on_skill_delivery_started")],
		[skill.skill_failed, Callable(self, &"_on_skill_terminal")],
		[skill.skill_cancelled, Callable(self, &"_on_skill_terminal")],
	]
	for connection: Array in connections:
		var signal_value: Signal = connection[0] as Signal
		var callback: Callable = connection[1] as Callable
		if signal_value.is_connected(callback):
			signal_value.disconnect(callback)


func _on_skill_action_requested(
	skill: SkillBase,
	target: Node3D,
	effective_cast_time: float
) -> void:
	if skill != _active_skill:
		return
	var context: SkillContext = skill.get_current_context()
	facing_requested.emit(context)
	_set_movement_locked(not skill.can_move_while_casting)
	# 施法时间在 Skill 层计算完成后作为只读请求数据向外传递。
	# 动作控制器不得在播放或回调阶段反向访问 Skill、Host 或 Unit 重新读取该值。
	action_requested.emit(skill, target, effective_cast_time)


func _on_skill_cast_range_required(
	context: SkillContext,
	required_range: float
) -> void:
	if is_instance_valid(_active_skill):
		approach_requested.emit(context, required_range)


func _on_skill_delivery_started(context: SkillContext) -> void:
	skill_released.emit(context)
	if not _use_external_global_cooldown:
		start_global_cooldown()


func _on_skill_terminal(
	_context: SkillContext,
	_reason: StringName
) -> void:
	if (
		is_instance_valid(_active_skill)
		and _active_skill.get_state() == SkillBase.SkillState.READY
	):
		_release_active_skill()


func _release_active_skill() -> void:
	_active_skill = null
	_pending_context = null
	_set_movement_locked(false)
	active_skill_changed.emit(null)


func _set_movement_locked(locked: bool) -> void:
	if _movement_locked == locked:
		return
	_movement_locked = locked
	movement_lock_requested.emit(locked)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if get_node_or_null(^"SkillSocket") == null:
		warnings.append("SkillHostComponent requires its fixed SkillSocket child.")
	var ids: Dictionary = {}
	var socket := get_node_or_null(^"SkillSocket")
	if socket != null:
		for child: Node in socket.get_children():
			if not child is SkillBase:
				continue
			var id: StringName = (child as SkillBase).skill_id
			if ids.has(id):
				warnings.append("Duplicate skill ID: " + String(id))
			ids[id] = true
	return warnings


func _exit_tree() -> void:
	for skill: SkillBase in _registered_skills.duplicate():
		_disconnect_skill(skill)
	_registered_skills.clear()
	_active_skill = null
	_target_candidate_provider = null
