class_name ArcProjectileDeliverySession
extends Node

## 每次弧线技能发射独立创建的运行会话；与普通弓普攻共享投射物契约但不共享运行状态。

## 投射物命中且全部效果成功时发出；context 为本次发射上下文，result 含单目标实际命中结果。
signal delivery_finished(context: SkillContext, result: SkillDeliveryResult)
## 投射物无命中退出、目标失效或效果失败时发出；reason 为失败原因标识。
signal delivery_failed(context: SkillContext, reason: StringName)

var _context: SkillContext
var _effects: Array[SkillEffectBase] = []
var _projectile: Node3D
var _origin: Vector3 = Vector3.ZERO
var _intended: Vector3 = Vector3.ZERO
var _launching: bool = false
var _terminal: bool = false
var _pending_hit: Array = []


## 启动一次交付；调用方需提供已通过配置验证的 Arc 配置、有效施法者/目标/世界父节点、有限世界发射变换及效果列表。
## 返回 false 表示发射前失败，且不会发出完成/失败信号；成功后所有异步终结由本会话信号报告。
func start(
	config: ArcProjectileDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool:
	if _context != null or config == null or context == null or not launch_transform.is_finite():
		return false
	if not config.validate_configuration().is_empty():
		return false
	if not context.resolved_target is UnitBase or not is_instance_valid(context.caster):
		return false
	if not is_instance_valid(context.delivery_parent) or not context.delivery_parent.is_inside_tree():
		return false
	var target := context.resolved_target as UnitBase
	if not target.is_inside_tree():
		return false
	var instance: Node = config.projectile_scene.instantiate()
	if not instance is Node3D:
		if is_instance_valid(instance):
			instance.free()
		return false
	var projectile := instance as Node3D
	if not _has_arc_contract(projectile):
		projectile.free()
		return false
	_context = context
	_origin = launch_transform.origin
	_intended = target.global_position
	_effects.assign(effects)
	_projectile = projectile
	context.delivery_parent.add_child(projectile)
	projectile.connect(&"projectile_hit", _on_projectile_hit)
	projectile.tree_exiting.connect(_on_projectile_tree_exiting)
	_launching = true
	var accepted: Variant = projectile.call(&"launch", target, _origin)
	_launching = false
	if not (accepted is bool) or not bool(accepted):
		_disconnect_projectile()
		projectile.queue_free()
		_projectile = null
		_context = null
		_effects.clear()
		_pending_hit.clear()
		return false
	if not _pending_hit.is_empty():
		call_deferred(&"_finish_pending_hit")
	return true


## 主动中止本会话；只影响这一次发射，不影响同一 Runner 的其他弧线会话。
func cancel(reason: StringName = &"cancelled") -> void:
	if _terminal or _context == null:
		return
	_finish_failure(reason)


func _on_projectile_hit(target: UnitBase, position: Vector3, direction: Vector3) -> void:
	if _terminal or _context == null:
		return
	if _launching:
		_pending_hit = [target, position, direction]
		return
	_finish_hit(target, position, direction)


func _finish_pending_hit() -> void:
	if _terminal or _pending_hit.is_empty():
		return
	var hit := _pending_hit.duplicate()
	_pending_hit.clear()
	_finish_hit(hit[0] as UnitBase, hit[1] as Vector3, hit[2] as Vector3)


func _finish_hit(target: UnitBase, position: Vector3, direction: Vector3) -> void:
	if _terminal or _context == null:
		return
	if not is_instance_valid(target) or not target.is_inside_tree() or target != _context.resolved_target:
		_finish_failure(&"arc_target_invalid")
		return
	if not position.is_finite() or not direction.is_finite():
		_finish_failure(&"arc_hit_invalid")
		return
	var result := SkillDeliveryResult.new()
	result.succeeded = true
	result.original_target = target
	result.origin_position = _origin
	result.intended_position = _intended
	result.impact_position = position
	result.impact_direction = direction
	var hit := SkillHitOutcome.new()
	hit.target = target
	hit.impact_position = position
	var status := target.get_status_effect_component()
	if is_instance_valid(status):
		hit.statuses_before_hit.assign(status.get_active_status_ids())
	result.current_hit = hit
	for effect: SkillEffectBase in _effects:
		if not is_instance_valid(effect) or not effect.apply(_context, result, target):
			_finish_failure(&"arc_effect_failed")
			return
	result.affected_targets.append(target)
	_terminal = true
	var completed_context := _context
	_cleanup_projectile()
	delivery_finished.emit(completed_context, result)
	queue_free()


func _on_projectile_tree_exiting() -> void:
	if _terminal or _context == null:
		return
	if _launching:
		call_deferred(&"_finish_failure", &"arc_projectile_ended_without_hit")
	else:
		_finish_failure(&"arc_projectile_ended_without_hit")


func _finish_failure(reason: StringName) -> void:
	if _terminal or _context == null:
		return
	_terminal = true
	var failed_context := _context
	_cleanup_projectile()
	delivery_failed.emit(failed_context, reason)
	queue_free()


func _cleanup_projectile() -> void:
	_disconnect_projectile()
	if is_instance_valid(_projectile) and not _projectile.is_queued_for_deletion():
		_projectile.queue_free()
	_projectile = null
	_context = null
	_effects.clear()
	_pending_hit.clear()


func _disconnect_projectile() -> void:
	if not is_instance_valid(_projectile):
		return
	var hit_callback := Callable(self, &"_on_projectile_hit")
	if _projectile.is_connected(&"projectile_hit", hit_callback):
		_projectile.disconnect(&"projectile_hit", hit_callback)
	var exit_callback := Callable(self, &"_on_projectile_tree_exiting")
	if _projectile.is_connected(&"tree_exiting", exit_callback):
		_projectile.disconnect(&"tree_exiting", exit_callback)


func _has_arc_contract(projectile: Node3D) -> bool:
	if not projectile.has_signal(&"projectile_hit") or not projectile.has_method(&"launch"):
		return false
	for method: Dictionary in projectile.get_method_list():
		if StringName(method.get("name", &"")) != &"launch":
			continue
		var args: Array = method.get("args", []) as Array
		var return_info: Dictionary = method.get("return", {}) as Dictionary
		return args.size() == 2 and int(return_info.get("type", TYPE_NIL)) == TYPE_BOOL
	return false


func _exit_tree() -> void:
	_cleanup_projectile()
