class_name IndependentBasicDeliveryAgent
extends "res://SkillSystem/07-Delivery/00-Agents/SkillDeliveryAgentBase.gd"

@export_category("Delivery Strategies")
@export var trajectory: Resource
@export var collision_policy: Resource
@export var impact_selector: Resource
@export var payloads: Array[Resource] = []

@export_category("Presentation")
@export var launch_presentation: Resource
@export var travel_presentation: Resource
@export var impact_presentation: Resource

var origin_transform: Transform3D = Transform3D.IDENTITY
var previous_transform: Transform3D = Transform3D.IDENTITY
var destination: Vector3 = Vector3.ZERO
var elapsed_time: float = 0.0
var travel_duration: float = 0.0


## 验证策略并启动独立的交付实例。零时长交付会在本次调用内完成 Impact。
func launch(context: SkillContextType, launch_transform: Transform3D) -> bool:
	if delivery_state != DeliveryState.IDLE or not is_instance_valid(context):
		return false
	if trajectory == null or collision_policy == null or impact_selector == null:
		return false
	delivery_context = context
	origin_transform = launch_transform
	previous_transform = launch_transform
	global_transform = launch_transform
	context.cast_origin = launch_transform.origin
	destination = context.target_position
	if destination == Vector3.INF and is_instance_valid(context.resolved_target):
		destination = context.resolved_target.global_position
		context.target_position = destination
	if destination == Vector3.INF:
		return false
	travel_duration = maxf(
		float(trajectory.call("get_travel_duration", context, launch_transform.origin, destination)),
		0.0
	)
	delivery_state = DeliveryState.TRAVELLING
	delivery_started.emit(context)
	_play_presentation(launch_presentation, get_parent(), launch_transform, null)
	_play_presentation(travel_presentation, self, launch_transform, null)
	if travel_duration <= 0.0:
		global_transform = trajectory.call(
			"sample_transform", context, origin_transform, destination, 1.0
		) as Transform3D
		_evaluate_collision(1.0)
	return true


func _physics_process(delta: float) -> void:
	if delivery_state != DeliveryState.TRAVELLING or travel_duration <= 0.0:
		return
	elapsed_time = minf(elapsed_time + delta, travel_duration)
	var progress: float = clampf(elapsed_time / travel_duration, 0.0, 1.0)
	previous_transform = global_transform
	global_transform = trajectory.call(
		"sample_transform", delivery_context, origin_transform, destination, progress
	) as Transform3D
	_evaluate_collision(progress)


func _evaluate_collision(progress: float) -> void:
	var result: SkillDeliveryResultType = collision_policy.call(
		"evaluate", delivery_context, previous_transform, global_transform, progress
	) as SkillDeliveryResultType
	if result == null:
		if progress >= 1.0:
			_fail_and_finish(&"collision_no_result")
		return
	if not result.succeeded:
		_fail_and_finish(result.failure_reason, result)
		return
	_resolve_impact(result)


func _resolve_impact(result: SkillDeliveryResultType) -> void:
	var targets: Array[Node3D] = impact_selector.call(
		"select_targets", delivery_context, result
	) as Array[Node3D]
	result.affected_targets = targets
	if targets.is_empty():
		_fail_and_finish(&"no_valid_impact_target", result)
		return
	for target: Node3D in targets:
		for payload: Resource in payloads:
			if payload != null and bool(payload.call("apply", delivery_context, result, target)):
				payload_applied.emit(delivery_context, result, target, payload)
			else:
				payload_failed.emit(delivery_context, result, target, payload)
	delivery_state = DeliveryState.IMPACTED
	_play_presentation(impact_presentation, get_parent(), global_transform, result)
	delivery_impacted.emit(delivery_context, result)
	_emit_finished_once(result)
	queue_free()


func _fail_and_finish(reason: StringName, result: SkillDeliveryResultType = null) -> void:
	if result == null:
		result = SkillDeliveryResultType.new()
	result.succeeded = false
	result.failure_reason = reason
	delivery_state = DeliveryState.CANCELLED
	delivery_failed.emit(delivery_context, reason)
	_emit_finished_once(result)
	queue_free()


func _play_presentation(
	presentation: Resource,
	parent: Node,
	world_transform: Transform3D,
	result: SkillDeliveryResultType
) -> void:
	if presentation != null and presentation.has_method(&"play"):
		presentation.call("play", parent, world_transform, delivery_context, result)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if trajectory == null:
		warnings.append("BasicDeliveryAgent requires a trajectory Resource.")
	if collision_policy == null:
		warnings.append("BasicDeliveryAgent requires a collision_policy Resource.")
	if impact_selector == null:
		warnings.append("BasicDeliveryAgent requires an impact_selector Resource.")
	return warnings
