class_name SkillModuleBase
extends Node3D

const SkillProfileType = preload("res://Scripts/Combat/Skills/SkillProfile.gd")

## 技能请求和施法生命周期信号。
## 所有目标均使用通用 Node3D，避免父模块依赖 AllyBase 或具体战斗单位类型。
signal skill_requested(target: Node3D)
signal decision_wait_started(target: Node3D, duration: float, used_extra_hesitation: bool)
signal skill_queued(target: Node3D)
signal cast_range_required(target: Node3D, cast_range: float, tolerance: float)
signal cast_started(target: Node3D)
signal delivery_requested(target: Node3D, target_position: Vector3)
signal skill_delivered(target: Node3D, target_position: Vector3)
signal cast_failed(target: Node3D, reason: StringName)
signal cast_cancelled(target: Node3D)
signal cooldown_started(duration: float)
signal cooldown_finished()
signal module_reset()

## 技能父模块只维护技能自身状态；移动、普攻和公共冷却由宿主决定。
enum SkillState {
	READY,
	DECISION_WAIT,
	QUEUED,
	CASTING,
	COOLDOWN
}

const RESET_ANIMATION_NAME: StringName = &"RESET"

@export_category("Skill Profile")
## 当前技能使用的可复用静态配置资源。
@export var skill_profile: SkillProfileType

@export_category("Animation")
## 继承技能共用的 AnimationPlayer；父场景提供 RESET 与可覆盖的空 cast 动画。
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = ^"SkillAnimationPlayer"
## 子技能可覆盖动画名称；缺少该动画不会阻止技能流程。
@export var cast_animation_name: StringName = &"cast"

@export_category("Debug")
## 原型阶段输出状态、目标、等待时间、交付和冷却日志；正式版本可在 Inspector 关闭。
@export var debug_logging_enabled: bool = true

@onready var skill_animation_player: AnimationPlayer = get_node_or_null(
	animation_player_path
) as AnimationPlayer

## 当前技能自身状态。
var skill_state: SkillState = SkillState.READY

## 由宿主通过开放接口注入的通用持有者。
var skill_owner: Node3D

## 当前请求绑定的目标；完成、取消或复位时清空。
var current_target: Node3D

## 地面或目标位置交付使用的世界坐标；默认跟随目标的当前坐标。
var current_target_position: Vector3 = Vector3.INF

## 当前决策等待、施法和技能冷却剩余时间。
var decision_wait_remaining: float = 0.0
var cast_time_remaining: float = 0.0
var skill_cooldown_remaining: float = 0.0

## 当前请求是否触发了单次额外犹豫判定。
var current_request_used_extra_hesitation: bool = false

## 每个模块拥有独立随机源，避免多个单位共享完全相同的释放节奏。
var random_generator := RandomNumberGenerator.new()


## 初始化随机源和 RESET 姿态；模块不主动搜索目标或请求施法。
func _ready() -> void:
	random_generator.randomize()
	_reset_animation()


## 固定物理帧只更新技能自己的计时器，不读取宿主行为状态。
func _physics_process(delta: float) -> void:
	match skill_state:
		SkillState.DECISION_WAIT:
			_process_decision_wait(delta)
		SkillState.CASTING:
			_process_casting(delta)
		SkillState.COOLDOWN:
			_process_cooldown(delta)


## 注入或清除技能持有者。
## 更换持有者前会取消尚未交付的请求，但不会通过具体宿主类型执行任何操作。
func configure_skill_owner(skill_owner_node: Node3D) -> void:
	if skill_owner == skill_owner_node:
		return
	if skill_state in [SkillState.DECISION_WAIT, SkillState.QUEUED, SkillState.CASTING]:
		cancel_skill()
	skill_owner = skill_owner_node
	_debug_log("Owner configured: " + _node_label(skill_owner))


## 请求一次技能决策。
## 该方法允许目标暂时位于射程外，因为接近移动属于外部宿主职责。
func request_skill(target: Node3D, target_position: Vector3 = Vector3.INF) -> bool:
	if not can_request_skill():
		return false

	var resolved_target: Node3D = _resolve_requested_target(target)
	var validation_reason: StringName = _get_structural_validation_failure(resolved_target)
	if not validation_reason.is_empty():
		_debug_log("Request rejected: " + str(validation_reason))
		return false

	current_target = resolved_target
	current_target_position = (
		current_target.global_position
		if target_position == Vector3.INF
		else target_position
	)
	skill_requested.emit(current_target)
	_start_decision_wait()
	return true


## 外部宿主在公共冷却、动作占用和移动条件均允许时调用。
## 父模块会自行重新检查目标和距离，但不会判断宿主的公共冷却。
func begin_cast() -> bool:
	if skill_state != SkillState.QUEUED:
		return false

	var validation_reason: StringName = _get_cast_validation_failure()
	if validation_reason == &"out_of_range":
		_emit_cast_range_required()
		return false
	if not validation_reason.is_empty():
		_fail_cast(validation_reason, false)
		return false

	skill_state = SkillState.CASTING
	cast_time_remaining = max(skill_profile.cast_time, 0.0)
	_play_cast_animation()
	cast_started.emit(current_target)
	_debug_log("Cast started: target=" + _node_label(current_target))
	if cast_time_remaining <= 0.0:
		_complete_cast()
	return true


## 取消当前未完成请求；已经开始的技能冷却不会被取消或刷新。
func cancel_skill() -> void:
	if skill_state == SkillState.COOLDOWN:
		return
	if skill_state == SkillState.READY and not is_instance_valid(current_target):
		return

	var cancelled_target: Node3D = current_target if is_instance_valid(current_target) else null
	_clear_active_request()
	skill_state = SkillState.READY
	_reset_animation()
	cast_cancelled.emit(cancelled_target)
	_debug_log("Cast cancelled: target=" + _node_label(cancelled_target))


## 完整复位模块，包括技能冷却；用于卸装、测试和场景重置。
func reset_module() -> void:
	_clear_active_request()
	skill_cooldown_remaining = 0.0
	skill_state = SkillState.READY
	_reset_animation()
	module_reset.emit()
	_debug_log("Module reset")


## 返回模块是否可以接受新的技能请求。
func can_request_skill() -> bool:
	return (
		skill_state == SkillState.READY
		and skill_profile != null
		and is_instance_valid(skill_owner)
		and skill_owner.is_inside_tree()
	)


## 返回已经排队的技能是否满足父模块自身的施法条件。
func can_begin_cast() -> bool:
	return skill_state == SkillState.QUEUED and _get_cast_validation_failure().is_empty()


## 当前是否处于施法计时阶段。
func is_casting() -> bool:
	return skill_state == SkillState.CASTING


## 当前是否已经完成随机决策并等待宿主允许施法。
func is_queued() -> bool:
	return skill_state == SkillState.QUEUED


## 返回当前技能状态，供宿主、测试或调试界面读取。
func get_skill_state() -> SkillState:
	return skill_state


## 返回技能专属冷却剩余秒数。
func get_skill_cooldown_remaining() -> float:
	return skill_cooldown_remaining


## 返回当前请求目标；不存在有效请求时返回 null。
func get_current_target() -> Node3D:
	return current_target if is_instance_valid(current_target) else null


## 返回 Profile 施法距离；缺少配置时返回 0。
func get_cast_range() -> float:
	return max(skill_profile.cast_range, 0.0) if skill_profile != null else 0.0


## 返回 Profile 施法距离容差；缺少配置时返回 0。
func get_cast_range_tolerance() -> float:
	return max(skill_profile.cast_range_tolerance, 0.0) if skill_profile != null else 0.0


## 返回 Profile 的通用 AI 选择优先级；缺少配置时使用最低影响的默认值。
func get_ai_priority() -> int:
	return skill_profile.ai_priority if skill_profile != null else 0


## 返回 Profile 期望的目标阵营；缺少配置时返回无效枚举值供宿主安全跳过。
func get_target_faction() -> int:
	return int(skill_profile.target_faction) if skill_profile != null else -1


## 返回宿主是否可在施法计时阶段继续执行自己的移动策略。
func can_move_during_cast() -> bool:
	return skill_profile != null and skill_profile.can_move_while_casting


## 子技能覆盖该方法来生成投射物、地面 AOE 或目标瞬时效果。
## 父类仅输出占位交付日志并返回成功，用于验证信号和组装路径。
func deliver_skill(caster: Node3D, target: Node3D, target_position: Vector3) -> bool:
	_debug_log(
		"Delivery successful: owner=" + _node_label(caster)
		+ ", target=" + _node_label(target)
		+ ", position=" + str(target_position)
		+ ", delivery_type=" + _delivery_type_label()
	)
	return true


## 更新普通与额外犹豫共同组成的单次决策等待。
func _process_decision_wait(delta: float) -> void:
	var validation_reason: StringName = _get_structural_validation_failure(current_target)
	if not validation_reason.is_empty():
		_fail_cast(validation_reason, false)
		return
	decision_wait_remaining = max(decision_wait_remaining - delta, 0.0)
	if decision_wait_remaining <= 0.0:
		_finish_decision_wait()


## 更新单一施法计时器；目标是否仍在范围只在结束点再次检查。
func _process_casting(delta: float) -> void:
	cast_time_remaining = max(cast_time_remaining - delta, 0.0)
	if cast_time_remaining <= 0.0:
		_complete_cast()


## 更新技能专属冷却并在结束时恢复 READY。
func _process_cooldown(delta: float) -> void:
	skill_cooldown_remaining = max(skill_cooldown_remaining - delta, 0.0)
	if skill_cooldown_remaining > 0.0:
		return
	skill_state = SkillState.READY
	cooldown_finished.emit()
	_debug_log("Skill cooldown finished")


## 每个请求只在此处选择一次普通等待和一次额外犹豫结果。
func _start_decision_wait() -> void:
	skill_state = SkillState.DECISION_WAIT
	var normal_min: float = min(skill_profile.decision_delay_min, skill_profile.decision_delay_max)
	var normal_max: float = max(skill_profile.decision_delay_min, skill_profile.decision_delay_max)
	decision_wait_remaining = random_generator.randf_range(normal_min, normal_max)
	current_request_used_extra_hesitation = (
		random_generator.randf() < clamp(skill_profile.extra_hesitation_chance, 0.0, 1.0)
	)
	if current_request_used_extra_hesitation:
		var extra_min: float = min(
			skill_profile.extra_hesitation_min,
			skill_profile.extra_hesitation_max
		)
		var extra_max: float = max(
			skill_profile.extra_hesitation_min,
			skill_profile.extra_hesitation_max
		)
		decision_wait_remaining += random_generator.randf_range(extra_min, extra_max)

	decision_wait_started.emit(
		current_target,
		decision_wait_remaining,
		current_request_used_extra_hesitation
	)
	_debug_log(
		"Decision wait started: duration=" + str(decision_wait_remaining)
		+ ", extra_hesitation=" + str(current_request_used_extra_hesitation)
	)
	if decision_wait_remaining <= 0.0:
		_finish_decision_wait()


## 决策完成后进入队列；范围不足只通知宿主，不主动移动持有者。
func _finish_decision_wait() -> void:
	decision_wait_remaining = 0.0
	skill_state = SkillState.QUEUED
	skill_queued.emit(current_target)
	_debug_log("Skill queued: target=" + _node_label(current_target))
	if not _is_target_in_cast_range():
		_emit_cast_range_required()


## 施法结束点执行唯一一次最终验证和交付。
func _complete_cast() -> void:
	var validation_reason: StringName = _get_cast_validation_failure()
	if not validation_reason.is_empty():
		var can_retry: bool = (
			validation_reason == &"out_of_range"
			and _get_structural_validation_failure(current_target).is_empty()
		)
		_fail_cast(validation_reason, can_retry)
		return

	current_target_position = (
		current_target.global_position
		if skill_profile.delivery_type != SkillProfileType.SkillDeliveryType.GROUND_AOE
		else current_target_position
	)
	delivery_requested.emit(current_target, current_target_position)
	if not deliver_skill(skill_owner, current_target, current_target_position):
		_fail_cast(&"delivery_failed", false)
		return

	var delivered_target: Node3D = current_target
	var delivered_position: Vector3 = current_target_position
	_reset_animation()
	_clear_active_request()
	_start_skill_cooldown()
	skill_delivered.emit(delivered_target, delivered_position)


## 统一发送失败原因，并按调用方要求选择重试决策或完全回到 READY。
func _fail_cast(reason: StringName, retry_same_target: bool) -> void:
	var failed_target: Node3D = current_target if is_instance_valid(current_target) else null
	cast_time_remaining = 0.0
	_reset_animation()
	cast_failed.emit(failed_target, reason)
	_debug_log("Cast failed: reason=" + str(reason) + ", target=" + _node_label(failed_target))
	if retry_same_target and is_instance_valid(current_target):
		_start_decision_wait()
		return
	_clear_active_request()
	skill_state = SkillState.READY


## 成功交付后启动技能专属冷却；零冷却会在同一调用内完成。
func _start_skill_cooldown() -> void:
	skill_cooldown_remaining = max(skill_profile.skill_cooldown, 0.0)
	skill_state = SkillState.COOLDOWN
	cooldown_started.emit(skill_cooldown_remaining)
	_debug_log("Skill cooldown started: duration=" + str(skill_cooldown_remaining))
	if skill_cooldown_remaining <= 0.0:
		skill_state = SkillState.READY
		cooldown_finished.emit()


## SELF 技能始终把已注入的持有者作为目标。
func _resolve_requested_target(target: Node3D) -> Node3D:
	if skill_profile != null and skill_profile.target_faction == SkillProfileType.SkillTargetFaction.SELF:
		return skill_owner
	return target


## 返回结构性失败原因；该检查不包含距离，允许宿主先进行接近移动。
func _get_structural_validation_failure(target: Node3D) -> StringName:
	if not is_instance_valid(skill_owner) or not skill_owner.is_inside_tree():
		return &"invalid_owner"
	if not is_instance_valid(target) or not target.is_inside_tree():
		return &"invalid_target"
	if (
		skill_profile != null
		and not skill_profile.required_target_group.is_empty()
		and not target.is_in_group(skill_profile.required_target_group)
	):
		return &"wrong_target_group"
	return &""


## 返回正式开始或完成施法时的完整失败原因。
func _get_cast_validation_failure() -> StringName:
	var structural_reason: StringName = _get_structural_validation_failure(current_target)
	if not structural_reason.is_empty():
		return structural_reason
	if not _is_target_in_cast_range():
		return &"out_of_range"
	return &""


## 使用水平距离判断施法范围；SELF 技能不受距离限制。
func _is_target_in_cast_range() -> bool:
	if skill_profile == null:
		return false
	if skill_profile.target_faction == SkillProfileType.SkillTargetFaction.SELF:
		return true
	if not is_instance_valid(skill_owner) or not is_instance_valid(current_target):
		return false
	var offset: Vector3 = current_target.global_position - skill_owner.global_position
	offset.y = 0.0
	return offset.length() <= get_cast_range() + get_cast_range_tolerance()


## 通知宿主需要把持有者移动进施法范围。
func _emit_cast_range_required() -> void:
	cast_range_required.emit(current_target, get_cast_range(), get_cast_range_tolerance())
	_debug_log(
		"Cast range required: range=" + str(get_cast_range())
		+ ", tolerance=" + str(get_cast_range_tolerance())
	)


## 清除单次请求数据，但不修改技能专属冷却。
func _clear_active_request() -> void:
	decision_wait_remaining = 0.0
	cast_time_remaining = 0.0
	current_target = null
	current_target_position = Vector3.INF
	current_request_used_extra_hesitation = false


## 播放当前技能配置的施法动画；播放器、名称或动画缺失时安全跳过而不中断施法。
func _play_cast_animation() -> void:
	if not is_instance_valid(skill_animation_player):
		return
	if cast_animation_name.is_empty():
		return
	if skill_animation_player.has_animation(cast_animation_name):
		skill_animation_player.play(cast_animation_name)


## 将未来继承动画恢复到 RESET；缺少动画时保持安全无操作。
func _reset_animation() -> void:
	if not is_instance_valid(skill_animation_player):
		return
	skill_animation_player.stop()
	if skill_animation_player.has_animation(RESET_ANIMATION_NAME):
		skill_animation_player.play(RESET_ANIMATION_NAME)


## 输出统一格式的原型诊断日志。
func _debug_log(message: String) -> void:
	if not debug_logging_enabled:
		return
	var profile_name: String = skill_profile.display_name if skill_profile != null else "No Profile"
	print("[SkillModuleBase][", name, "][", profile_name, "] ", message)


## 安全生成节点日志标签。
func _node_label(node: Node) -> String:
	return str(node.name) if is_instance_valid(node) else "<null>"


## 把交付枚举转换为稳定日志文本。
func _delivery_type_label() -> String:
	if skill_profile == null:
		return "UNKNOWN"
	match skill_profile.delivery_type:
		SkillProfileType.SkillDeliveryType.GROUND_AOE:
			return "GROUND_AOE"
		SkillProfileType.SkillDeliveryType.INSTANT_TARGET:
			return "INSTANT_TARGET"
		_:
			return "PROJECTILE"


## 离开场景树时清理请求和持有者引用，避免重装同一实例时残留状态。
func _exit_tree() -> void:
	_reset_animation()
	_clear_active_request()
	skill_cooldown_remaining = 0.0
	skill_state = SkillState.READY
	skill_owner = null
