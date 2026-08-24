class_name IndependentSkillDeliveryAgentBase
extends Node3D

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")
const SkillDeliveryResultType = preload("res://SkillSystem/01-Core/SkillDeliveryResult.gd")

signal delivery_started(context: RefCounted)
signal delivery_impacted(context: RefCounted, result: RefCounted)
signal payload_applied(context: RefCounted, result: RefCounted, target: Node3D, payload: Resource)
signal payload_failed(context: RefCounted, result: RefCounted, target: Node3D, payload: Resource)
signal delivery_failed(context: RefCounted, reason: StringName)
signal delivery_finished(context: RefCounted, result: RefCounted)

enum DeliveryState {
	IDLE,
	TRAVELLING,
	IMPACTED,
	CANCELLED,
}

var delivery_state: DeliveryState = DeliveryState.IDLE
var delivery_context: SkillContextType
var finish_emitted: bool = false


## 抽象 Agent 不包含运行策略，因此明确拒绝启动。
func launch(context: SkillContextType, _origin_transform: Transform3D) -> bool:
	delivery_context = context
	delivery_failed.emit(context, &"delivery_agent_not_implemented")
	return false


## 取消仍在运行的交付实例，并保证完成信号只发送一次。
func cancel_delivery(reason: StringName = &"cancelled") -> void:
	if delivery_state in [DeliveryState.IMPACTED, DeliveryState.CANCELLED]:
		return
	delivery_state = DeliveryState.CANCELLED
	var result: SkillDeliveryResultType = SkillDeliveryResultType.new()
	result.succeeded = false
	result.failure_reason = reason
	delivery_failed.emit(delivery_context, reason)
	_emit_finished_once(result)
	queue_free()


func get_delivery_state() -> DeliveryState:
	return delivery_state


func get_context() -> SkillContextType:
	return delivery_context


func _emit_finished_once(result: SkillDeliveryResultType) -> void:
	if finish_emitted:
		return
	finish_emitted = true
	delivery_finished.emit(delivery_context, result)
