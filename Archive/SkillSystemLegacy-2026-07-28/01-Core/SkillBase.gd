class_name IndependentSkillBase
extends Node3D

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")
const SkillDefinitionType = preload("res://SkillSystem/01-Core/SkillDefinition.gd")
const DELIVERY_AGENT_BASE_PATH := "res://SkillSystem/07-Delivery/00-Agents/SkillDeliveryAgentBase.gd"

signal request_accepted(context: RefCounted)
signal decision_wait_started(context: RefCounted, duration: float)
signal skill_queued(context: RefCounted)
signal cast_range_required(context: RefCounted, cast_range: float, tolerance: float)
signal cast_started(context: RefCounted)
signal delivery_launched(context: RefCounted, agent: Node3D)
signal cast_failed(context: RefCounted, reason: StringName)
signal cast_cancelled(context: RefCounted, reason: StringName)
signal cooldown_started(duration: float)
signal cooldown_finished()

enum SkillState {
	READY,
	DECISION_WAIT,
	QUEUED,
	CASTING,
	COOLDOWN,
}

const RESET_ANIMATION: StringName = &"RESET"

@export_category("Skill Assembly")
@export var skill_definition: SkillDefinitionType
@export var delivery_agent_scene: PackedScene

@export_category("Node Paths")
@export_node_path("Marker3D") var cast_origin_path: NodePath = ^"CastOrigin"
@export_node_path("Node3D") var presentation_root_path: NodePath = ^"PresentationRoot"
@export_node_path("Marker3D") var delivery_socket_path: NodePath = ^"DeliverySocket"
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = ^"SkillAnimationPlayer"
@export var cast_animation_name: StringName = &"cast"

@onready var cast_origin: Marker3D = get_node_or_null(cast_origin_path) as Marker3D
@onready var presentation_root: Node3D = get_node_or_null(presentation_root_path) as Node3D
@onready var delivery_socket: Marker3D = get_node_or_null(delivery_socket_path) as Marker3D
@onready var animation_player: AnimationPlayer = get_node_or_null(animation_player_path) as AnimationPlayer

var skill_state: SkillState = SkillState.READY
var skill_owner: Node3D
var skill_host: Node
var current_context: SkillContextType
var decision_wait_remaining: float = 0.0
var cast_time_remaining: float = 0.0
var cooldown_remaining: float = 0.0
var random_generator := RandomNumberGenerator.new()


func _ready() -> void:
	random_generator.randomize()
	_reset_animation()


func _physics_process(delta: float) -> void:
	match skill_state:
		SkillState.DECISION_WAIT:
			decision_wait_remaining = maxf(decision_wait_remaining - delta, 0.0)
			if decision_wait_remaining <= 0.0:
				_queue_current_request()
		SkillState.CASTING:
			cast_time_remaining = maxf(cast_time_remaining - delta, 0.0)
			if cast_time_remaining <= 0.0:
				_complete_cast()
		SkillState.COOLDOWN:
			cooldown_remaining = maxf(cooldown_remaining - delta, 0.0)
			if cooldown_remaining <= 0.0:
				skill_state = SkillState.READY
				cooldown_finished.emit()


## 注入施法者与可选宿主。技能不读取宿主内部字段。
func configure_owner(caster: Node3D, host: Node = null) -> void:
	if skill_owner == caster and skill_host == host:
		return
	if skill_state in [SkillState.DECISION_WAIT, SkillState.QUEUED, SkillState.CASTING]:
		cancel_skill(&"owner_changed")
	skill_owner = caster
	skill_host = host


## 接受一次请求并创建独立上下文副本。
func request_skill(context: SkillContextType) -> bool:
	if skill_state != SkillState.READY:
		return false
	var prepared: SkillContextType = _prepare_context(context)
	if prepared == null:
		return false
	current_context = prepared
	request_accepted.emit(current_context)
	var delay: float = 0.0
	if skill_definition.decision_policy != null:
		delay = maxf(float(skill_definition.decision_policy.call(
			"get_decision_delay", current_context, random_generator
		)), 0.0)
	if delay > 0.0:
		skill_state = SkillState.DECISION_WAIT
		decision_wait_remaining = delay
		decision_wait_started.emit(current_context, delay)
	else:
		_queue_current_request()
	return true


## 开始已经排队且满足最终开施法条件的请求。
func begin_cast() -> bool:
	if not can_begin_cast():
		if skill_state == SkillState.QUEUED and not is_target_in_cast_range():
			cast_range_required.emit(current_context, get_cast_range(), get_cast_range_tolerance())
		return false
	skill_state = SkillState.CASTING
	cast_time_remaining = maxf(skill_definition.cast_time, 0.0)
	_play_cast_animation()
	_play_cast_presentation()
	cast_started.emit(current_context)
	if cast_time_remaining <= 0.0:
		_complete_cast()
	return true


func cancel_skill(reason: StringName = &"cancelled") -> void:
	if skill_state not in [SkillState.DECISION_WAIT, SkillState.QUEUED, SkillState.CASTING]:
		return
	var cancelled_context: SkillContextType = current_context
	_clear_active_request()
	skill_state = SkillState.READY
	_reset_animation()
	cast_cancelled.emit(cancelled_context, reason)


func reset_skill() -> void:
	_clear_active_request()
	cooldown_remaining = 0.0
	skill_state = SkillState.READY
	_reset_animation()


## 无副作用检查一个请求当前是否具备进入技能状态机的条件。
func can_request(context: SkillContextType) -> bool:
	return skill_state == SkillState.READY and _prepare_context(context) != null


func can_begin_cast() -> bool:
	if skill_state != SkillState.QUEUED or current_context == null:
		return false
	return _get_validation_failure(current_context, true).is_empty() and is_target_in_cast_range()


## 使用 X/Z 水平距离判断射程，保持与项目 top-down 移动平面一致。
func is_target_in_cast_range() -> bool:
	if current_context == null or not is_instance_valid(skill_owner):
		return false
	if not is_instance_valid(current_context.resolved_target):
		return false
	var offset: Vector3 = current_context.resolved_target.global_position - skill_owner.global_position
	offset.y = 0.0
	return offset.length() <= get_cast_range() + get_cast_range_tolerance()


func is_ready() -> bool:
	return skill_state == SkillState.READY


func is_casting() -> bool:
	return skill_state == SkillState.CASTING


func get_state() -> SkillState:
	return skill_state


func get_current_context() -> SkillContextType:
	return current_context


func get_cooldown_remaining() -> float:
	return cooldown_remaining


func get_skill_id() -> StringName:
	return skill_definition.skill_id if skill_definition != null else &""


func get_ai_priority() -> int:
	return skill_definition.ai_priority if skill_definition != null else 0


func get_cast_range() -> float:
	return maxf(skill_definition.cast_range, 0.0) if skill_definition != null else 0.0


func get_cast_range_tolerance() -> float:
	return maxf(skill_definition.cast_range_tolerance, 0.0) if skill_definition != null else 0.0


func can_move_during_cast() -> bool:
	return skill_definition != null and skill_definition.can_move_while_casting


func _prepare_context(source_context: SkillContextType) -> SkillContextType:
	if skill_definition == null or not is_instance_valid(skill_owner) or not skill_owner.is_inside_tree():
		return null
	if source_context == null or skill_definition.target_selector == null:
		return null
	var prepared: SkillContextType = source_context.duplicate_context() as SkillContextType
	prepared.caster = skill_owner
	prepared.host = skill_host
	_apply_targeting_snapshot(prepared)
	if not bool(skill_definition.target_selector.call("resolve_target", prepared)):
		return null
	if not _get_validation_failure(prepared, false).is_empty():
		return null
	return prepared


func _get_validation_failure(context: SkillContextType, include_range: bool) -> StringName:
	if context == null or not is_instance_valid(context.resolved_target):
		return &"target_resolution_failed"
	if not context.resolved_target.is_inside_tree():
		return &"target_resolution_failed"
	if not skill_definition.target_selector.is_candidate_valid(context, context.resolved_target, false):
		return &"invalid_target_relation"
	if skill_definition.condition == null or not bool(skill_definition.condition.call("evaluate", context)):
		return &"condition_failed"
	if skill_definition.cost == null or not bool(skill_definition.cost.call("can_pay", context)):
		return &"cost_unavailable"
	if include_range:
		var offset: Vector3 = context.resolved_target.global_position - skill_owner.global_position
		offset.y = 0.0
		if offset.length() > get_cast_range() + get_cast_range_tolerance():
			return &"out_of_range"
	return &""


## 将本次请求使用的目标规则复制到上下文，使选择器不需要反向读取 SkillBase 或某个具体角色。
## 这些值在请求期间保持稳定，而最终施法检查仍会重新验证目标当前的节点与阵营状态。
func _apply_targeting_snapshot(context: SkillContextType) -> void:
	context.target_relation = int(skill_definition.target_relation)
	context.require_targetable = skill_definition.require_targetable
	context.cast_range = get_cast_range()
	context.cast_range_tolerance = get_cast_range_tolerance()


func _queue_current_request() -> void:
	decision_wait_remaining = 0.0
	skill_state = SkillState.QUEUED
	skill_queued.emit(current_context)
	if not is_target_in_cast_range():
		cast_range_required.emit(current_context, get_cast_range(), get_cast_range_tolerance())


func _complete_cast() -> void:
	if current_context == null:
		_fail_active(&"invalid_context", false)
		return
	if is_instance_valid(current_context.resolved_target):
		current_context.target_position = current_context.resolved_target.global_position
	var failure: StringName = _get_validation_failure(current_context, true)
	if not failure.is_empty():
		_fail_active(failure, false)
		return
	if not bool(skill_definition.cost.call("commit", current_context)):
		_fail_active(&"cost_commit_failed", false)
		return
	var committed_cost: bool = true
	var delivery_failure: StringName = &""
	var agent: Node3D
	if delivery_agent_scene == null:
		delivery_failure = &"missing_delivery_scene"
	elif not is_instance_valid(current_context.delivery_parent):
		delivery_failure = &"invalid_delivery_parent"
	else:
		var instance: Node = delivery_agent_scene.instantiate()
		if not instance is Node3D:
			instance.free()
			delivery_failure = &"invalid_delivery_agent"
		else:
			agent = instance as Node3D
			var agent_script: Script = agent.get_script() as Script
			if agent_script == null or not _script_inherits_path(
				agent_script, DELIVERY_AGENT_BASE_PATH
			):
				agent.free()
				agent = null
				delivery_failure = &"invalid_delivery_agent"
	if delivery_failure.is_empty():
		current_context.delivery_parent.add_child(agent)
		var launch_transform: Transform3D = _get_skill_origin_transform()
		if not bool(agent.call("launch", current_context, launch_transform)):
			agent.queue_free()
			delivery_failure = &"delivery_launch_failed"
	if not delivery_failure.is_empty():
		if committed_cost:
			skill_definition.cost.call("refund", current_context)
		_fail_active(delivery_failure, true)
		return
	var launched_context: SkillContextType = current_context
	delivery_launched.emit(launched_context, agent)
	_clear_active_request()
	_start_cooldown()


func _fail_active(reason: StringName, delivery_failure: bool) -> void:
	var failed_context: SkillContextType = current_context
	_clear_active_request()
	_reset_animation()
	cast_failed.emit(failed_context, reason)
	if delivery_failure and skill_definition != null and skill_definition.cooldown_on_failed_delivery:
		_start_cooldown()
	else:
		skill_state = SkillState.READY


func _start_cooldown() -> void:
	cooldown_remaining = maxf(skill_definition.skill_cooldown, 0.0)
	skill_state = SkillState.COOLDOWN
	cooldown_started.emit(cooldown_remaining)
	if cooldown_remaining <= 0.0:
		skill_state = SkillState.READY
		cooldown_finished.emit()


func _clear_active_request() -> void:
	current_context = null
	decision_wait_remaining = 0.0
	cast_time_remaining = 0.0


func _play_cast_animation() -> void:
	if is_instance_valid(animation_player) and animation_player.has_animation(cast_animation_name):
		animation_player.play(cast_animation_name)


func _reset_animation() -> void:
	if not is_instance_valid(animation_player):
		return
	animation_player.stop()
	if animation_player.has_animation(RESET_ANIMATION):
		animation_player.play(RESET_ANIMATION)


func _play_cast_presentation() -> void:
	if skill_definition.cast_presentation == null or not is_instance_valid(presentation_root):
		return
	var transform_value: Transform3D = _get_skill_origin_transform()
	skill_definition.cast_presentation.call(
		"play", presentation_root, transform_value, current_context, null
	)


## 统一读取 SkillHost 提供的角色级发射点；旧 SkillHost 或旧场景缺少该接口时，
## 保持原有内部 DeliverySocket / CastOrigin 回退，避免破坏仍在归档中的旧技能。
func _get_skill_origin_transform() -> Transform3D:
	var fallback_transform: Transform3D = (
		delivery_socket.global_transform
		if is_instance_valid(delivery_socket)
		else (
			cast_origin.global_transform
			if is_instance_valid(cast_origin)
			else global_transform
		)
	)
	if is_instance_valid(skill_host) and skill_host.has_method(
		&"get_skill_origin_transform"
	):
		var resolved_transform: Variant = skill_host.call(
			&"get_skill_origin_transform",
			fallback_transform
		)
		if resolved_transform is Transform3D and (resolved_transform as Transform3D).is_finite():
			return resolved_transform as Transform3D
	return fallback_transform


## 沿脚本继承链检查 Agent 类型，避免依赖编辑器全局 class_name 缓存的刷新时机。
func _script_inherits_path(script: Script, expected_path: String) -> bool:
	var cursor: Script = script
	while cursor != null:
		if cursor.resource_path == expected_path:
			return true
		cursor = cursor.get_base_script()
	return false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if skill_definition == null:
		warnings.append("SkillBase requires a SkillDefinition Resource.")
	if delivery_agent_scene == null:
		warnings.append("SkillBase requires a delivery_agent_scene PackedScene.")
	return warnings


func _exit_tree() -> void:
	_clear_active_request()
	cooldown_remaining = 0.0
	skill_state = SkillState.READY
