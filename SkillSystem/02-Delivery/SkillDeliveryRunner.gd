class_name SkillDeliveryRunner
extends Node

## 所有 SkillBase 共用的运行时交付执行器。
##
## 具体技能只提供一个强类型 SkillDeliveryConfig。本节点集中保存当前运行状态，
## 负责把配置转换为一次真实交付，不持有任何 Firebolt、HolyLight 或职业依赖。

signal delivery_started(context: SkillContext)
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


## 按配置真实类型执行一次交付。
##
## Resource 只作为只读参数来源；投射物、区域和计时状态全部留在运行实例中。
func execute(
	config: SkillDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool:
	if _busy or config == null or context == null:
		return false
	if not launch_transform.is_finite():
		return false
	if not config.validate_configuration().is_empty():
		return false
	if not _is_context_base_valid(context):
		return false

	if config is TrackingProjectileDeliveryConfig:
		return _execute_tracking_projectile(
			config as TrackingProjectileDeliveryConfig,
			context,
			launch_transform,
			effects
		)
	if config is InstantTargetDeliveryConfig:
		return _execute_instant_target(context, launch_transform, effects)
	if config is GroundAreaDeliveryConfig:
		return _execute_ground_area(
			config as GroundAreaDeliveryConfig,
			context,
			launch_transform
		)
	return false


## 取消当前仍在飞行的交付。
##
## 瞬发和地面区域在 execute() 内已经完成，因此只有追踪投射物会长期占用 Runner。
func cancel(reason: StringName = &"cancelled") -> void:
	if not _busy:
		return
	var context: SkillContext = _current_context
	if is_instance_valid(_active_projectile):
		_disconnect_projectile(_active_projectile)
		_active_projectile.queue_free()
	_active_projectile = null
	_clear_runtime_state()
	delivery_failed.emit(context, reason)


func is_busy() -> bool:
	return _busy


func _execute_instant_target(
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool:
	if not is_instance_valid(context.resolved_target) or effects.is_empty():
		return false
	_begin_delivery(context, launch_transform.origin, context.resolved_target.global_position)
	var result := _make_success_result(context.resolved_target.global_position)
	for effect: SkillEffectBase in effects:
		if not is_instance_valid(effect) or not effect.apply(
			context,
			result,
			context.resolved_target
		):
			_finish_failure(&"instant_effect_failed")
			return false
		result.affected_targets.append(context.resolved_target)
	var finished_context: SkillContext = _current_context
	_clear_runtime_state()
	delivery_finished.emit(finished_context, result)
	return true


func _execute_tracking_projectile(
	config: TrackingProjectileDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool:
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
	delivery_started.emit(context)
	if _pending_terminal != PENDING_TERMINAL_NONE:
		call_deferred(&"_flush_pending_terminal")
	return true


func _execute_ground_area(
	config: GroundAreaDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D
) -> bool:
	var destination: Vector3 = context.target_position
	if not destination.is_finite():
		if not is_instance_valid(context.resolved_target):
			return false
		destination = context.resolved_target.global_position
	destination += config.ground_offset

	var instance: Node = config.area_scene.instantiate()
	if not instance is Node3D:
		if is_instance_valid(instance):
			instance.free()
		return false
	var area := instance as Node3D
	if not area.has_method(&"launch"):
		area.free()
		return false
	context.delivery_parent.add_child(area)
	area.global_position = destination
	var launch_result: Variant = area.call(&"launch", context)
	if not (launch_result is bool) or not bool(launch_result):
		area.queue_free()
		return false

	_begin_delivery(context, launch_transform.origin, destination)
	var result := _make_success_result(destination)
	var finished_context: SkillContext = _current_context
	_clear_runtime_state()
	delivery_finished.emit(finished_context, result)
	return true


func _begin_delivery(
	context: SkillContext,
	origin_position: Vector3,
	intended_position: Vector3
) -> void:
	_arm_delivery(context, origin_position, intended_position)
	delivery_started.emit(context)


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
		result.affected_targets.append(target)
		for effect: SkillEffectBase in _active_effects:
			if not is_instance_valid(effect) or not effect.apply(
				_current_context,
				result,
				target
			):
				_finish_failure(&"projectile_effect_failed")
				return
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


func _clear_runtime_state() -> void:
	_busy = false
	_current_context = null
	_origin_position = Vector3.ZERO
	_intended_position = Vector3.ZERO
	_active_effects.clear()
	_resolved_projectile_targets.clear()
	_launch_in_progress = false
	_clear_pending_terminal()


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
	if is_instance_valid(_active_projectile):
		_disconnect_projectile(_active_projectile)
	_active_projectile = null
	_clear_runtime_state()
