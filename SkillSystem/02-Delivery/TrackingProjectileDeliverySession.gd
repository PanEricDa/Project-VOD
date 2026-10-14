class_name TrackingProjectileDeliverySession
extends Node
## 单次追踪交付会话，保存自身投射物/context/Effects；同一技能的多次在途互不覆盖。
## 命中或失败都携带最初context；启动失败不发终态，启动同步回调在接受后延迟结算。
signal delivery_finished(context: SkillContext, result: SkillDeliveryResult)
signal delivery_failed(context: SkillContext, reason: StringName)
const DIRECTION_EPSILON_SQUARED: float = 0.000001
const PROJECTILE_LAUNCH_ARGUMENT_COUNT: int = 8
const PENDING_TERMINAL_NONE: int = 0
const PENDING_TERMINAL_SUCCESS: int = 1
const PENDING_TERMINAL_FAILURE: int = 2
var _busy: bool = false
var _current_context: SkillContext
var _active_projectile: Node3D
var _origin_position: Vector3 = Vector3.ZERO
var _intended_position: Vector3 = Vector3.ZERO
var _active_effects: Array[SkillEffectBase] = []
var _resolved_projectile_targets: Array[Node3D] = []
var _launch_in_progress: bool = false
var _pending_terminal: int = PENDING_TERMINAL_NONE
var _pending_impact_position: Vector3 = Vector3.ZERO
var _pending_failure_reason: StringName

## 配置/context/发射变换/效果是本次只读输入；true仅表示launch接受，结果通过终态信号返回。
func start(
	config: TrackingProjectileDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool:
	if _busy or config == null or context == null or not launch_transform.is_finite() or not _is_context_base_valid(context):
		return false
	if not config.validate_configuration().is_empty():
		return false
	if not context.resolved_target is CharacterBody3D:
		return false
	var target := context.resolved_target as CharacterBody3D
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false

	var intended_position: Vector3 = (
		target.global_position + Vector3.UP * config.aim_height
	)
	var initial_direction: Vector3 = intended_position - launch_transform.origin
	if (
		not initial_direction.is_finite()
		or initial_direction.length_squared() <= DIRECTION_EPSILON_SQUARED
	):
		return false
	initial_direction = initial_direction.normalized()

	var instance: Node = config.projectile_scene.instantiate()
	if not instance is Node3D:
		if is_instance_valid(instance):
			instance.free()
		return false
	var projectile := instance as Node3D
	if not _has_compatible_projectile_contract(projectile):
		projectile.free()
		return false

	context.delivery_parent.add_child(projectile)
	_connect_projectile(projectile)
	# 必须在 launch 前完整武装运行时状态，兼容同步命中或退出的投射物回调。
	_active_effects.clear()
	_active_effects.append_array(effects)
	_resolved_projectile_targets.clear()
	_active_projectile = projectile
	_arm_delivery(context, launch_transform.origin, intended_position)
	_launch_in_progress = true
	var launch_result: Variant = projectile.callv(&"launch", [
		context.caster,
		target,
		launch_transform.origin,
		initial_direction,
		config.projectile_speed,
		config.turn_speed_degrees,
		config.maximum_lifetime,
		config.impact_radius,
	])
	_launch_in_progress = false
	if not (launch_result is bool) or not bool(launch_result):
		_clear_pending_terminal()
		# launch 内已终结时回调会先清理状态；此处只回滚仍在运行的本轮。
		if _busy and _active_projectile == projectile:
			_disconnect_projectile(projectile)
			_active_projectile = null
			_clear_runtime_state()
			if is_instance_valid(projectile):
				projectile.queue_free()
		return false

	# launch 可能已在同步回调中完成或退出；禁止重新武装已终结的交付。
	if _pending_terminal != PENDING_TERMINAL_NONE:
		call_deferred(&"_flush_pending_terminal")
	return true

## 取消本会话并结束一次；reason为诊断标识，不取消其他请求的会话。
func cancel(reason: StringName = &"cancelled") -> void:
	if not _busy: return
	_finish_failure(reason)

func _arm_delivery(
	context: SkillContext,
	origin_position: Vector3,
	intended_position: Vector3
) -> void:
	_busy = true
	_current_context = context
	_origin_position = origin_position
	_intended_position = intended_position

func _on_projectile_impacted(impact_position: Vector3) -> void:
	if not _busy or not is_instance_valid(_active_projectile):
		return
	if _launch_in_progress:
		_record_pending_success(impact_position)
		return
	_complete_projectile_impact(impact_position)

func _complete_projectile_impact(impact_position: Vector3) -> void:
	if not _busy or not is_instance_valid(_active_projectile):
		return
	var projectile: Node3D = _active_projectile
	_disconnect_projectile(projectile)
	_active_projectile = null
	var result := _make_success_result(impact_position)
	var effect_targets: Array[Node3D] = []
	# 投射物可能先上报命中候选，再延迟到下一帧才上报最终命中。
	# 因此最终结算必须重新验证生命周期，不能信任之前缓存时的有效状态。
	for target: Node3D in _resolved_projectile_targets:
		if is_instance_valid(target) and target.is_inside_tree():
			effect_targets.append(target)
	var original_target := result.original_target as Node3D
	if (
		effect_targets.is_empty()
		and is_instance_valid(original_target)
		and original_target.is_inside_tree()
	):
		effect_targets.append(original_target)
	for target: Node3D in effect_targets:
		result.current_hit = _make_hit_outcome(target, impact_position)
		result.affected_targets.append(target)
		for effect: SkillEffectBase in _active_effects:
			if not is_instance_valid(effect) or not effect.apply(
				_current_context,
				result,
				target
			):
				_finish_failure(&"projectile_effect_failed")
				return
	if is_instance_valid(projectile): projectile.queue_free()
	var finished_context: SkillContext = _current_context
	_clear_runtime_state()
	delivery_finished.emit(finished_context, result)

func _on_projectile_targets_resolved(
	targets: Array[CharacterBody3D]
) -> void:
	if not _busy:
		return
	_resolved_projectile_targets.clear()
	for target: CharacterBody3D in targets:
		if is_instance_valid(target) and not _resolved_projectile_targets.has(target):
			_resolved_projectile_targets.append(target)

func _on_projectile_tree_exiting() -> void:
	if not _busy:
		return
	if _launch_in_progress:
		_record_pending_failure(&"projectile_ended_without_impact")
		return
	_active_projectile = null
	_finish_failure(&"projectile_ended_without_impact")

func _record_pending_success(impact_position: Vector3) -> void:
	if _pending_terminal != PENDING_TERMINAL_NONE:
		return
	_pending_terminal = PENDING_TERMINAL_SUCCESS
	_pending_impact_position = impact_position

func _record_pending_failure(reason: StringName) -> void:
	if _pending_terminal != PENDING_TERMINAL_NONE:
		return
	_pending_terminal = PENDING_TERMINAL_FAILURE
	_pending_failure_reason = reason

func _flush_pending_terminal() -> void:
	if not _busy or _pending_terminal == PENDING_TERMINAL_NONE:
		return
	var pending_terminal := _pending_terminal
	var impact_position := _pending_impact_position
	var failure_reason := _pending_failure_reason
	_clear_pending_terminal()
	if pending_terminal == PENDING_TERMINAL_SUCCESS:
		_complete_projectile_impact(impact_position)
	else:
		if is_instance_valid(_active_projectile):
			_disconnect_projectile(_active_projectile)
		_active_projectile = null
		_finish_failure(failure_reason)

func _finish_failure(reason: StringName) -> void:
	var failed_context: SkillContext = _current_context
	_clear_runtime_state()
	delivery_failed.emit(failed_context, reason)

func _make_success_result(impact_position: Vector3) -> SkillDeliveryResult:
	var result := SkillDeliveryResult.new()
	result.succeeded = true
	result.original_target = (
		_current_context.resolved_target
		if is_instance_valid(_current_context)
		else null
	)
	result.origin_position = _origin_position
	result.intended_position = _intended_position
	result.impact_position = impact_position
	var direction: Vector3 = impact_position - _origin_position
	if direction.length_squared() > DIRECTION_EPSILON_SQUARED:
		result.impact_direction = direction.normalized()
	return result


## 在任何效果执行前读取本目标状态，构成一次命中的独立结果；非 UnitBase 目标保持空状态快照。

func _make_hit_outcome(target: Node3D, impact_position: Vector3) -> SkillHitOutcome:
	var outcome := SkillHitOutcome.new()
	outcome.target = target
	outcome.impact_position = impact_position
	if target is UnitBase:
		var status_component := (target as UnitBase).get_status_effect_component()
		if is_instance_valid(status_component):
			outcome.statuses_before_hit.assign(status_component.get_active_status_ids())
	return outcome

func _clear_runtime_state() -> void:
	if is_instance_valid(_active_projectile):
		_disconnect_projectile(_active_projectile)
		_active_projectile.queue_free()
	_active_projectile = null
	_busy = false
	_current_context = null
	_origin_position = Vector3.ZERO
	_intended_position = Vector3.ZERO
	_active_effects.clear()
	_resolved_projectile_targets.clear()
	_launch_in_progress = false
	_clear_pending_terminal()
	queue_free()

func _clear_pending_terminal() -> void:
	_pending_terminal = PENDING_TERMINAL_NONE
	_pending_impact_position = Vector3.ZERO
	_pending_failure_reason = &""

func _is_context_base_valid(context: SkillContext) -> bool:
	return (
		is_instance_valid(context.caster)
		and context.caster.is_inside_tree()
		and is_instance_valid(context.delivery_parent)
		and context.delivery_parent.is_inside_tree()
	)

func _has_compatible_projectile_contract(projectile: Node3D) -> bool:
	if not projectile.has_signal(&"projectile_impacted"):
		return false
	var launch_method: Dictionary = _find_named_entry(
		projectile.get_method_list(),
		&"launch"
	)
	if launch_method.is_empty():
		return false
	var arguments: Array = launch_method.get("args", []) as Array
	var return_info: Dictionary = launch_method.get("return", {}) as Dictionary
	return (
		arguments.size() == PROJECTILE_LAUNCH_ARGUMENT_COUNT
		and int(return_info.get("type", TYPE_NIL)) == TYPE_BOOL
	)

func _connect_projectile(projectile: Node3D) -> void:
	projectile.projectile_impacted.connect(_on_projectile_impacted)
	if projectile.has_signal(&"projectile_targets_resolved"):
		projectile.connect(
			&"projectile_targets_resolved",
			_on_projectile_targets_resolved
		)
	projectile.tree_exiting.connect(_on_projectile_tree_exiting)

func _disconnect_projectile(projectile: Node3D) -> void:
	var impact_callback := Callable(self, &"_on_projectile_impacted")
	if projectile.is_connected(&"projectile_impacted", impact_callback):
		projectile.disconnect(&"projectile_impacted", impact_callback)
	var targets_callback := Callable(self, &"_on_projectile_targets_resolved")
	if (
		projectile.has_signal(&"projectile_targets_resolved")
		and projectile.is_connected(
			&"projectile_targets_resolved",
			targets_callback
		)
	):
		projectile.disconnect(&"projectile_targets_resolved", targets_callback)
	var exit_callback := Callable(self, &"_on_projectile_tree_exiting")
	if projectile.is_connected(&"tree_exiting", exit_callback):
		projectile.disconnect(&"tree_exiting", exit_callback)

func _find_named_entry(
	entries: Array[Dictionary],
	entry_name: StringName
) -> Dictionary:
	for entry: Dictionary in entries:
		if StringName(entry.get("name", &"")) == entry_name:
			return entry
	return {}

func _exit_tree() -> void:
	if _busy: cancel(&"session_exiting")
