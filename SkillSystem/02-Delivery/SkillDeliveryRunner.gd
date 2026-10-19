class_name SkillDeliveryRunner
extends Node
## 通用交付执行器：追踪与弧线各请求独立会话，固定Runner/Effects保持原技能装配。
## 接受通知先于交付效果；true不保证命中/效果最终成功，最终结果由完成/失败信号报告。
signal delivery_started(context: SkillContext)
signal delivery_finished(context: SkillContext, result: SkillDeliveryResult)
signal delivery_failed(context: SkillContext, reason: StringName)
## 本次所有待发项目终结，和交付/主视觉完成分开。
signal emission_finished(context: SkillContext)
## 命中表现尚未进树，订阅者登记完成与时钟，不参与伤害。
signal impact_presentation_prepared(context: SkillContext, instance: Node3D)
## 第index颗成功发出，point为冻结世界落点/目标点。
signal projectile_launched(context: SkillContext, index: int, point: Vector3)
## 第index颗已经落地并完成本颗数值，主视觉可能仍播放。
signal projectile_landed(context: SkillContext, index: int, point: Vector3)
const DIRECTION_EPSILON_SQUARED: float = 0.000001
var _busy: bool = false
var _current_context: SkillContext
var _origin_position: Vector3 = Vector3.ZERO
var _intended_position: Vector3 = Vector3.ZERO
var _arc_sessions: Array[ArcProjectileDeliverySession] = []
var _tracking_sessions: Array[TrackingProjectileDeliverySession] = []

## config/context/launch_transform/effects为本次交付输入；false仅表示未接受，不允许接受后效果失败退回false。
func execute(
	config: SkillDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool:
	if config == null or context == null:
		return false
	if not launch_transform.is_finite():
		return false
	if not config.validate_configuration().is_empty():
		return false
	if not _is_context_base_valid(context):
		return false
	if config is ArcProjectileDeliveryConfig:
		return _execute_arc_projectile(config as ArcProjectileDeliveryConfig, context, launch_transform, effects)
	if config is TrackingProjectileDeliveryConfig:
		return _execute_tracking_projectile(
			config as TrackingProjectileDeliveryConfig,
			context,
			launch_transform,
			effects
		)
	if _busy:
		return false
	if config is InstantTargetDeliveryConfig:
		return _execute_instant_target(
			config as InstantTargetDeliveryConfig,
			context,
			launch_transform,
			effects
		)
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

## 取消本Runner所有在途会话；单个请求动作取消不得调用此入口误杀其他已释放交付。
func cancel(reason: StringName = &"cancelled") -> void:
	for session: Node in _arc_sessions.duplicate() + _tracking_sessions.duplicate():
		if is_instance_valid(session): session.cancel(reason)

## 是否仍有在途会话或同步交付；不是下一次角色施放资格。
func is_busy() -> bool:
	return _busy or not _arc_sessions.is_empty() or not _tracking_sessions.is_empty()

func _execute_arc_projectile(
	config: ArcProjectileDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool:
	var session := ArcProjectileDeliverySession.new()
	add_child(session)
	session.delivery_finished.connect(_on_arc_finished.bind(session))
	session.delivery_failed.connect(_on_arc_failed.bind(session))
	session.emission_finished.connect(func(ctx: SkillContext) -> void: emission_finished.emit(ctx))
	session.impact_presentation_prepared.connect(func(ctx: SkillContext, instance: Node3D) -> void: impact_presentation_prepared.emit(ctx, instance))
	session.projectile_launched.connect(func(ctx: SkillContext, index: int, point: Vector3) -> void: projectile_launched.emit(ctx, index, point))
	session.projectile_landed.connect(func(ctx: SkillContext, index: int, point: Vector3) -> void: projectile_landed.emit(ctx, index, point))
	# start内部首发即可触发同步中断，先登记，失败再回滚，不能让停止接口漏掉启动中的会话。
	_arc_sessions.append(session)
	if not session.start(config, context, launch_transform, effects):
		_arc_sessions.erase(session)
		session.queue_free()
		return false
	delivery_started.emit(context)
	return true

## 按根执行正身份只停止后续发射；已发在途保留，不可用于取消其他技能会话。
func stop_pending_emission(request_id: int) -> void:
	if request_id <= 0: return
	for session: ArcProjectileDeliverySession in _arc_sessions.duplicate():
		if is_instance_valid(session):
			var context: SkillContext = session.get_delivery_context()
			if context != null and (context.execution_id == request_id or (context.damage_context != null and context.damage_context.request_id == request_id)):
				session.stop_pending_emission()

func _on_arc_finished(context: SkillContext, result: SkillDeliveryResult, session: ArcProjectileDeliverySession) -> void:
	_arc_sessions.erase(session)
	delivery_finished.emit(context, result)

func _on_arc_failed(context: SkillContext, reason: StringName, session: ArcProjectileDeliverySession) -> void:
	_arc_sessions.erase(session)
	delivery_failed.emit(context, reason)


## 按配置的目标收集模式执行瞬发交付：逐目标、逐 Effect 应用，任一 Effect 失败即
## 沿用既有 fail-fast 契约终止；每个目标的全部 Effect 成功后才计入 affected_targets 一次。


func _execute_tracking_projectile(config: TrackingProjectileDeliveryConfig, context: SkillContext, launch_transform: Transform3D, effects: Array[SkillEffectBase]) -> bool:
	var session := TrackingProjectileDeliverySession.new()
	add_child(session)
	session.delivery_finished.connect(_on_tracking_finished.bind(session))
	session.delivery_failed.connect(_on_tracking_failed.bind(session))
	if not session.start(config, context, launch_transform, effects):
		session.queue_free()
		return false
	_tracking_sessions.append(session)
	delivery_started.emit(context)
	return true

func _on_tracking_finished(context: SkillContext, result: SkillDeliveryResult, session: TrackingProjectileDeliverySession) -> void:
	_tracking_sessions.erase(session)
	delivery_finished.emit(context, result)

func _on_tracking_failed(context: SkillContext, reason: StringName, session: TrackingProjectileDeliverySession) -> void:
	_tracking_sessions.erase(session)
	delivery_failed.emit(context, reason)

func _execute_instant_target(
	config: InstantTargetDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool:
	var effect_targets := _collect_instant_effect_targets(config, context)
	if effect_targets.is_empty() or effects.is_empty() or effects.any(func(effect): return not is_instance_valid(effect)):
		return false
	var reference_target: Node3D = effect_targets[0]
	_begin_delivery(
		context,
		launch_transform.origin,
		reference_target.global_position
	)
	var result := _make_success_result(reference_target.global_position)
	for target: Node3D in effect_targets:
		result.current_hit = _make_hit_outcome(target, target.global_position)
		for effect: SkillEffectBase in effects:
			if not is_instance_valid(effect) or not effect.apply(
				context,
				result,
				target
			):
				_finish_failure(&"instant_effect_failed")
				return true
		result.affected_targets.append(target)
	var finished_context: SkillContext = _current_context
	_clear_runtime_state()
	delivery_finished.emit(finished_context, result)
	return true


## 收集一次瞬发交付的效果目标集合。
## SINGLE 只返回有效已解析目标；CASTER_RADIUS 以施法者为圆心，从 context.candidate_targets
## 的请求快照（并在触发目标被意外遗漏时合并它）筛选关系、存活、可选取与水平半径内的单位，
## 按实例 ID 去重；不修改 context.candidate_targets 原数组。

func _collect_instant_effect_targets(
	config: InstantTargetDeliveryConfig,
	context: SkillContext
) -> Array[Node3D]:
	var collected: Array[Node3D] = []
	if (
		config.target_collection_mode
		== InstantTargetDeliveryConfig.TargetCollectionMode.SINGLE
	):
		if is_instance_valid(context.resolved_target):
			collected.append(context.resolved_target)
		return collected

	var caster := context.caster
	var candidates: Array[Node3D] = []
	candidates.append_array(context.candidate_targets)
	if (
		is_instance_valid(context.resolved_target)
		and not candidates.has(context.resolved_target)
	):
		candidates.append(context.resolved_target)
	var seen_ids: Dictionary = {}
	for candidate: Node3D in candidates:
		if not is_instance_valid(candidate) or not candidate.is_inside_tree():
			continue
		if not TargetResolver.is_candidate_valid(
			caster,
			candidate,
			config.affected_relations,
			true,
			true
		):
			continue
		var horizontal_offset: Vector3 = (
			candidate.global_position - caster.global_position
		)
		horizontal_offset.y = 0.0
		if horizontal_offset.length() > config.effect_radius + 0.05:
			continue
		var instance_id := candidate.get_instance_id()
		if seen_ids.has(instance_id):
			continue
		seen_ids[instance_id] = true
		collected.append(candidate)
	return collected

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
	_begin_delivery(context, launch_transform.origin, destination)
	var launch_result: Variant = area.call(&"launch", context)
	if not (launch_result is bool) or not bool(launch_result):
		area.queue_free()
		_finish_failure(&"ground_area_effect_failed")
		return true
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

func _is_context_base_valid(context: SkillContext) -> bool:
	return (
		is_instance_valid(context.caster)
		and context.caster.is_inside_tree()
		and is_instance_valid(context.delivery_parent)
		and context.delivery_parent.is_inside_tree()
	)


func _clear_runtime_state() -> void:
	_busy = false
	_current_context = null
	_origin_position = Vector3.ZERO
	_intended_position = Vector3.ZERO

func _exit_tree() -> void:
	cancel(&"runner_exiting")
	_arc_sessions.clear()
	_tracking_sessions.clear()
	_clear_runtime_state()
