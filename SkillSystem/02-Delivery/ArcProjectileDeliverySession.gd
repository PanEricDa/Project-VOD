class_name ArcProjectileDeliverySession
extends Node

## 一次弧线交付的运行会话；单箭、连射和预选多目标齐射共用投射物契约与效果管线。

## 全部箭矢完成且至少一次有效命中后发出；result 保留每次独立命中的实际结果。
signal delivery_finished(context: SkillContext, result: SkillDeliveryResult)
## 全部箭矢未能命中或效果执行失败时发出；reason 标识交付失败原因。
signal delivery_failed(context: SkillContext, reason: StringName)

var _config: ArcProjectileDeliveryConfig
var _context: SkillContext
var _effects: Array[SkillEffectBase] = []
var _projectiles: Array[Node3D] = []
var _targets: Array[UnitBase] = []
var _projectile_targets: Dictionary = {}
var _origin: Vector3 = Vector3.ZERO
var _intended: Vector3 = Vector3.ZERO
var _result: SkillDeliveryResult
var _launched_count: int = 0
var _settled_count: int = 0
var _issued_count: int = 0
var _total_shots: int = 0
var _next_shot_elapsed: float = 0.0
var _launching: bool = false
var _terminal: bool = false
var _pending_hits: Array[Array] = []


func _ready() -> void:
	set_physics_process(false)


## 启动一次交付；配置、施法者、目标、世界父节点和发射变换都必须有效。
## 成功返回 true，随后以完成或失败信号终结；第一支箭无法启动时返回 false 且不发信号。
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
	if not target.is_inside_tree() or target.is_dead():
		return false
	_config = config
	_context = context
	_targets.clear()
	if config.target_expansion != null:
		_targets.assign(config.target_expansion.select_targets(context, target))
	else:
		_targets.append(target)
	if _targets.is_empty():
		return false
	_total_shots = _targets.size() * config.shot_count
	_origin = launch_transform.origin
	_intended = target.global_position
	_effects.assign(effects)
	_result = SkillDeliveryResult.new()
	_result.succeeded = true
	_result.original_target = target
	_result.origin_position = _origin
	_result.intended_position = _intended
	while _can_issue_next() and not _launch_next():
		pass
	if _launched_count == 0:
		_cleanup_projectiles()
		return false
	if _terminal:
		return true
	if _config.shot_interval_seconds == 0.0:
		while _can_issue_next() and not _terminal:
			_launch_next()
		_check_finished()
	else:
		set_physics_process(_issued_count < _total_shots)
	return true


func _physics_process(delta: float) -> void:
	if _terminal or _context == null:
		set_physics_process(false)
		return
	if not _can_issue_next():
		set_physics_process(false)
		_check_finished()
		return
	_next_shot_elapsed += maxf(delta, 0.0)
	while _next_shot_elapsed >= _config.shot_interval_seconds and not _terminal:
		_next_shot_elapsed -= _config.shot_interval_seconds
		if not _can_issue_next():
			break
		_launch_next()
	if _issued_count >= _total_shots:
		set_physics_process(false)
	_check_finished()


## 中止本次交付的全部未完成箭矢；reason 为取消原因，不影响其他交付会话。
func cancel(reason: StringName = &"cancelled") -> void:
	if not _terminal and _context != null:
		_finish_failure(reason)


func _can_issue_next() -> bool:
	return _issued_count < _total_shots


func _launch_next() -> bool:
	var target := _targets[floori(float(_issued_count) / float(_config.shot_count))]
	_issued_count += 1
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_dead():
		return false
	var instance: Node = _config.projectile_scene.instantiate()
	if not instance is Node3D:
		if is_instance_valid(instance):
			instance.free()
		return false
	var projectile := instance as Node3D
	if not _has_arc_contract(projectile):
		projectile.free()
		return false
	_context.delivery_parent.add_child(projectile)
	_projectiles.append(projectile)
	_projectile_targets[projectile.get_instance_id()] = target
	projectile.connect(&"projectile_hit", _on_projectile_hit.bind(projectile))
	projectile.tree_exiting.connect(_on_projectile_tree_exiting.bind(projectile))
	_launched_count += 1
	_launching = true
	var accepted: Variant = projectile.call(&"launch", target, _origin)
	_launching = false
	if not (accepted is bool) or not bool(accepted):
		_disconnect_projectile(projectile)
		_projectiles.erase(projectile)
		_projectile_targets.erase(projectile.get_instance_id())
		_launched_count -= 1
		projectile.queue_free()
		return false
	if not _pending_hits.is_empty():
		call_deferred(&"_finish_pending_hits")
	return true


func _on_projectile_hit(target: UnitBase, position: Vector3, direction: Vector3, projectile: Node3D) -> void:
	if _terminal or not _projectiles.has(projectile):
		return
	if _launching:
		_pending_hits.append([target, position, direction, projectile])
		return
	_finish_hit(target, position, direction, projectile)


func _finish_pending_hits() -> void:
	var pending := _pending_hits.duplicate()
	_pending_hits.clear()
	for entry: Array in pending:
		if not _terminal:
			_finish_hit(entry[0] as UnitBase, entry[1] as Vector3, entry[2] as Vector3, entry[3] as Node3D)


func _finish_hit(target: UnitBase, position: Vector3, direction: Vector3, projectile: Node3D) -> void:
	if _terminal or not _projectiles.has(projectile):
		return
	_disconnect_projectile(projectile)
	_projectiles.erase(projectile)
	var expected_target := _projectile_targets.get(projectile.get_instance_id()) as UnitBase
	_projectile_targets.erase(projectile.get_instance_id())
	_settled_count += 1
	if not is_instance_valid(target) or not target.is_inside_tree() or target != expected_target:
		_check_finished()
		return
	if not position.is_finite() or not direction.is_finite():
		_finish_failure(&"arc_hit_invalid")
		return
	var hit := SkillHitOutcome.new()
	hit.target = target
	hit.impact_position = position
	var status := target.get_status_effect_component()
	if is_instance_valid(status):
		hit.statuses_before_hit.assign(status.get_active_status_ids())
	_result.current_hit = hit
	_result.impact_position = position
	_result.impact_direction = direction
	for effect: SkillEffectBase in _effects:
		if not is_instance_valid(effect) or not effect.apply(_context, _result, target):
			_finish_failure(&"arc_effect_failed")
			return
	_result.affected_targets.append(target)
	_result.hit_outcomes.append(hit)
	_check_finished()


func _on_projectile_tree_exiting(projectile: Node3D) -> void:
	if _terminal or not _projectiles.has(projectile):
		return
	if _launching:
		call_deferred(&"_on_projectile_tree_exiting", projectile)
		return
	_disconnect_projectile(projectile)
	_projectiles.erase(projectile)
	_projectile_targets.erase(projectile.get_instance_id())
	_settled_count += 1
	_check_finished()


func _check_finished() -> void:
	if _terminal or _context == null:
		return
	if _issued_count < _total_shots:
		return
	if _settled_count < _launched_count:
		return
	if _result.hit_outcomes.is_empty():
		_finish_failure(&"arc_projectile_ended_without_hit")
		return
	_terminal = true
	set_physics_process(false)
	var completed_context := _context
	var completed_result := _result
	_cleanup_projectiles()
	delivery_finished.emit(completed_context, completed_result)
	queue_free()


func _finish_failure(reason: StringName) -> void:
	if _terminal or _context == null:
		return
	_terminal = true
	set_physics_process(false)
	var failed_context := _context
	_cleanup_projectiles()
	delivery_failed.emit(failed_context, reason)
	queue_free()


func _cleanup_projectiles() -> void:
	for projectile: Node3D in _projectiles.duplicate():
		if not is_instance_valid(projectile):
			continue
		_disconnect_projectile(projectile)
		if not projectile.is_queued_for_deletion():
			projectile.queue_free()
	_projectiles.clear()
	_projectile_targets.clear()
	_targets.clear()
	_context = null
	_config = null
	_result = null
	_effects.clear()
	_pending_hits.clear()


func _disconnect_projectile(projectile: Node3D) -> void:
	if not is_instance_valid(projectile):
		return
	var hit_callback := Callable(self, &"_on_projectile_hit").bind(projectile)
	if projectile.is_connected(&"projectile_hit", hit_callback):
		projectile.disconnect(&"projectile_hit", hit_callback)
	var exit_callback := Callable(self, &"_on_projectile_tree_exiting").bind(projectile)
	if projectile.is_connected(&"tree_exiting", exit_callback):
		projectile.disconnect(&"tree_exiting", exit_callback)


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
	_cleanup_projectiles()
