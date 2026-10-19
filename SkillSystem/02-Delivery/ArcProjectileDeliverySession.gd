class_name ArcProjectileDeliverySession
extends Node

## 一次弧线交付的运行会话；单箭、连射和预选多目标齐射共用投射物契约与效果管线。

## 全部箭矢完成且至少一次有效命中后发出；result 保留每次独立命中的实际结果。
signal delivery_finished(context: SkillContext, result: SkillDeliveryResult)
## 全部箭矢未能命中或效果执行失败时发出；reason 标识交付失败原因。
signal delivery_failed(context: SkillContext, reason: StringName)

## 全部待发项目已结束，不表示在途或视觉结束；每会话仅通知一次。
signal emission_finished(context: SkillContext)
## 独立命中表现进树前的准备通知，允许登记时钟和结束监听。
signal impact_presentation_prepared(context: SkillContext, instance: Node3D)
## 第index颗已成功创建并发射，point为冻结的世界落点/单位位置。
signal projectile_launched(context: SkillContext, index: int, point: Vector3)
## 第index颗已抵达；数值在本通知前完成，不等于主要视觉已结束。
signal projectile_landed(context: SkillContext, index: int, point: Vector3)
var _ground_points: PackedVector3Array = PackedVector3Array()
var _ground_mode: bool = false
var _emission_notified: bool = false
var _projectile_indices: Dictionary = {}
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
## 地面模式必须在物理帧调用，以安全采样真实地形；SkillBase负责将渲染来源的释放转入物理帧。
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
	_ground_mode = config.destination_mode == ArcProjectileDeliveryConfig.DestinationMode.RANDOM_GROUND_CIRCLE
	if _ground_mode:
		if not Engine.is_in_physics_frame(): return false
		_ground_points = _sample_ground_points(config, context, target.global_position)
		if _ground_points.size() != config.shot_count: return false
		context.target_position = target.global_position
	_config = config.duplicate() as ArcProjectileDeliveryConfig
	_context = context
	_targets.clear()
	if config.target_expansion != null and not _ground_mode:
		_targets.assign(config.target_expansion.select_targets(context, target))
	else:
		_targets.append(target)
	if _targets.is_empty() and not _ground_mode:
		return false
	_total_shots = config.shot_count if _ground_mode else _targets.size() * config.shot_count
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
		if not _pending_hits.is_empty(): set_physics_process(true)
	else:
		set_physics_process(_issued_count < _total_shots or not _pending_hits.is_empty())
	return true


func _physics_process(delta: float) -> void:
	if _ground_mode and not _pending_hits.is_empty(): _finish_pending_hits()
	if _terminal or _context == null:
		set_physics_process(false)
		return
	if _context != null and _context.execution_clock != null:
		delta = _context.execution_clock.get_delta(delta)
	if _context != null and (not is_instance_valid(_context.caster) or not _context.caster.is_inside_tree()):
		_finish_failure(&"source_exited")
		return
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
		_notify_emission_finished()
		set_physics_process(false)
	_check_finished()


## 中止本次交付的全部未完成箭矢；reason 为取消原因，不影响其他交付会话。
func cancel(reason: StringName = &"cancelled") -> void:
	if not _terminal and _context != null:
		_finish_failure(reason)


func _can_issue_next() -> bool:
	return _issued_count < _total_shots


func _launch_next() -> bool:
	var index := _issued_count
	var target: UnitBase = null if _ground_mode else _targets[floori(float(_issued_count) / float(_config.shot_count))]
	_issued_count += 1
	if not _ground_mode and (not is_instance_valid(target) or not target.is_inside_tree() or target.is_dead()):
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
	_projectile_indices[projectile.get_instance_id()] = index
	if projectile.has_method(&"set_execution_clock"):
		projectile.call(&"set_execution_clock", _context.execution_clock, _config.impact_radius_m if _ground_mode else 0.0)
	if projectile.has_signal(&"impact_presentation_prepared"):
		projectile.connect(&"impact_presentation_prepared", _on_impact_prepared)
	projectile.connect(&"projectile_hit", _on_projectile_hit.bind(projectile))
	projectile.tree_exiting.connect(_on_projectile_tree_exiting.bind(projectile))
	_launched_count += 1
	_launching = true
	var accepted: Variant = projectile.call(&"launch_point", _ground_points[index], _origin) if _ground_mode else projectile.call(&"launch", target, _origin)
	_launching = false
	if not (accepted is bool) or not bool(accepted):
		_disconnect_projectile(projectile)
		_projectiles.erase(projectile)
		_projectile_targets.erase(projectile.get_instance_id())
		_launched_count -= 1
		projectile.queue_free()
		return false
	projectile_launched.emit(_context, index, _ground_points[index] if _ground_mode else target.global_position)
	if _context == null or _terminal: return true
	if _issued_count >= _total_shots: _notify_emission_finished()
	if not _pending_hits.is_empty():
		if _ground_mode: set_physics_process(true)
		else: call_deferred(&"_finish_pending_hits")
	return true


func _on_projectile_hit(target: UnitBase, position: Vector3, direction: Vector3, projectile: Node3D) -> void:
	if _terminal or not _projectiles.has(projectile):
		return
	if _launching or (_ground_mode and not Engine.is_in_physics_frame()):
		_pending_hits.append([target, position, direction, projectile])
		if _ground_mode: set_physics_process(true)
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
	var index: int = _projectile_indices.get(projectile.get_instance_id(), -1)
	_projectile_indices.erase(projectile.get_instance_id())
	var expected_target := _projectile_targets.get(projectile.get_instance_id()) as UnitBase
	_projectile_targets.erase(projectile.get_instance_id())
	_settled_count += 1
	if _ground_mode:
		_finish_ground_hit(position, direction, index)
		return
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
	_notify_emission_finished()
	if _terminal or _context == null: return
	if _result.hit_outcomes.is_empty() and not _ground_mode:
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
	_projectile_indices.clear()
	_ground_points.clear()
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
	if _ground_mode:
		return projectile.has_signal(&"projectile_hit") and projectile.has_method(&"launch_point")
	if not projectile.has_signal(&"projectile_hit") or not projectile.has_method(&"launch"):
		return false
	for method: Dictionary in projectile.get_method_list():
		if StringName(method.get("name", &"")) != &"launch":
			continue
		var args: Array = method.get("args", []) as Array
		var return_info: Dictionary = method.get("return", {}) as Dictionary
		return args.size() == 2 and int(return_info.get("type", TYPE_NIL)) == TYPE_BOOL
	return false


## 返回本会话请求用于身份匹配；只读，不允许调用者更改运行中的目标或交付配置。
func get_delivery_context() -> SkillContext:
	return _context

## 只终止未发项目，已发投射物仍保留独立交付；供角色硬中断使用，不回滚已结算伤害。
func stop_pending_emission() -> void:
	if _terminal: return
	_total_shots = _issued_count
	set_physics_process(false)
	_notify_emission_finished()
	_check_finished()

func _notify_emission_finished() -> void:
	if _emission_notified or _context == null or _issued_count < _total_shots: return
	_emission_notified = true
	emission_finished.emit(_context)

func _on_impact_prepared(instance: Node3D) -> void:
	if _context != null and not _terminal:
		impact_presentation_prepared.emit(_context, instance)

func _sample_ground_points(config: ArcProjectileDeliveryConfig, context: SkillContext, center: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	var source := context.caster as Node3D
	if not is_instance_valid(source) or source.get_world_3d() == null: return points
	var random := RandomNumberGenerator.new()
	if context.scatter_seed == 0: random.randomize()
	else: random.seed = context.scatter_seed
	for shot: int in range(config.shot_count):
		var found := false
		for attempt: int in range(8):
			var angle := random.randf() * TAU
			var radius := config.scatter_radius_m * sqrt(random.randf())
			var point := center + Vector3(cos(angle), 0, sin(angle)) * radius
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 32, point + Vector3.DOWN * 64, 1)
			var ground := source.get_world_3d().direct_space_state.intersect_ray(ray)
			if not ground.is_empty():
				points.append(ground.position)
				found = true
				break
		if not found: return PackedVector3Array()
	return points

func _finish_ground_hit(position: Vector3, direction: Vector3, index: int) -> void:
	if _context == null or not is_instance_valid(_context.caster) or not _context.caster.is_inside_tree() or _context.caster.is_queued_for_deletion():
		_finish_failure(&"source_exited")
		return
	if not position.is_finite() or not direction.is_finite():
		_finish_failure(&"arc_hit_invalid")
		return
	var targets := NearbySkillTargetQuery.select_targets((_context.caster as Node3D).get_world_3d(), _context.caster, position, _config.impact_radius_m, 2147483647, TargetResolver.TargetRelationFlag.HOSTILE, null)
	for target: Node3D in targets:
		if _terminal or _context == null: return
		var hit := SkillHitOutcome.new()
		hit.target = target
		hit.impact_position = position
		var status := (target as UnitBase).get_status_effect_component()
		if is_instance_valid(status): hit.statuses_before_hit.assign(status.get_active_status_ids())
		_result.current_hit = hit
		_result.impact_position = position
		_result.impact_direction = direction
		for effect: SkillEffectBase in _effects:
			if not is_instance_valid(effect) or not effect.apply(_context, _result, target):
				_finish_failure(&"arc_effect_failed")
				return
		_result.affected_targets.append(target)
		_result.hit_outcomes.append(hit)
	projectile_landed.emit(_context, index, position)
	if not _terminal: _check_finished()

func _exit_tree() -> void:
	_cleanup_projectiles()
