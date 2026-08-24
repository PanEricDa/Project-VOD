class_name IndependentTrackingProjectileDeliveryAgent
extends "res://SkillSystem/07-Delivery/00-Agents/SkillDeliveryAgentBase.gd"

signal projectile_launched(projectile: Node3D)
signal projectile_impacted(position: Vector3)

const DIRECTION_EPSILON_SQUARED: float = 0.000001
const REQUIRED_LAUNCH_ARGUMENT_COUNT: int = 8

@export_category("Projectile")
## 要生成的投射物场景。该场景必须提供本脚本约定的八参数 launch() 方法。
@export var projectile_scene: PackedScene
## 投射物每秒移动的世界距离，由本组件原样传递给投射物。
@export_range(0.1, 100.0, 0.1, "or_greater") var projectile_speed: float = 12.0
## 追踪方向每秒允许旋转的最大角度；真正的转向运算由投射物负责。
@export_range(0.0, 2160.0, 1.0, "or_greater") var turn_speed_degrees: float = 540.0
## 投射物允许存活的最长时间，超时后的销毁或结算由投射物负责。
@export_range(0.1, 60.0, 0.1, "or_greater") var maximum_lifetime: float = 5.0
## 传递给投射物的命中扩散半径。零值表示由投射物执行单点或自身默认处理。
@export_range(0.0, 30.0, 0.05, "or_greater") var impact_radius: float = 0.0

@export_category("Aiming")
## 在目标根节点高度上附加的瞄准高度，避免投射物默认射向角色脚底。
@export_range(-10.0, 10.0, 0.05) var aim_height: float = 0.25

var _active_projectile: Node3D
var _launch_origin: Vector3 = Vector3.ZERO
var _intended_position: Vector3 = Vector3.ZERO


## 创建投射物并把通用发射参数交给投射物自身。
## 本方法只管理“生成与交接”，不判断伤害、范围目标或最终命中对象。
func launch(context: SkillContextType, launch_transform: Transform3D) -> bool:
	if delivery_state != DeliveryState.IDLE:
		return false
	if not _is_context_valid(context) or not _is_configuration_valid():
		return false
	if not launch_transform.is_finite():
		return false

	var caster := context.caster as Node3D
	var target := context.resolved_target as CharacterBody3D
	_launch_origin = launch_transform.origin
	_intended_position = target.global_position + Vector3.UP * aim_height
	var initial_direction: Vector3 = _intended_position - _launch_origin
	if not initial_direction.is_finite():
		return false
	if initial_direction.length_squared() <= DIRECTION_EPSILON_SQUARED:
		return false
	initial_direction = initial_direction.normalized()

	var instance: Node = projectile_scene.instantiate()
	if not instance is Node3D:
		if is_instance_valid(instance):
			instance.free()
		return false
	var projectile := instance as Node3D
	if not _has_compatible_projectile_contract(projectile):
		projectile.free()
		return false

	# 投射物与交付代理同属 delivery_parent，代理结束后不会提前删除仍在播放爆炸表现的投射物。
	context.delivery_parent.add_child(projectile)
	_connect_projectile(projectile)
	var launch_result: Variant = projectile.callv(&"launch", [
		caster,
		target,
		_launch_origin,
		initial_direction,
		projectile_speed,
		turn_speed_degrees,
		maximum_lifetime,
		impact_radius,
	])
	if not (launch_result is bool) or not bool(launch_result):
		_disconnect_projectile(projectile)
		projectile.queue_free()
		return false

	delivery_context = context
	context.cast_origin = _launch_origin
	delivery_state = DeliveryState.TRAVELLING
	_active_projectile = projectile
	delivery_started.emit(context)
	projectile_launched.emit(projectile)
	return true


## 取消交付时同时清理仍在飞行的投射物，防止取消后的残留投射物继续命中。
func cancel_delivery(reason: StringName = &"cancelled") -> void:
	if delivery_state in [DeliveryState.IMPACTED, DeliveryState.CANCELLED]:
		return
	if is_instance_valid(_active_projectile):
		_disconnect_projectile(_active_projectile)
		_active_projectile.queue_free()
	_active_projectile = null
	super.cancel_delivery(reason)


func get_active_projectile() -> Node3D:
	return _active_projectile if is_instance_valid(_active_projectile) else null


## 投射物只需报告撞击位置；具体伤害与受影响目标仍由投射物自己的实现决定。
func _on_projectile_impacted(impact_position: Vector3) -> void:
	if delivery_state != DeliveryState.TRAVELLING or finish_emitted:
		return
	delivery_state = DeliveryState.IMPACTED
	var result: SkillDeliveryResultType = SkillDeliveryResultType.new()
	result.succeeded = true
	result.original_target = (
		delivery_context.resolved_target
		if delivery_context != null and is_instance_valid(delivery_context.resolved_target)
		else null
	)
	result.origin_position = _launch_origin
	result.intended_position = _intended_position
	result.impact_position = impact_position
	var impact_direction: Vector3 = impact_position - _launch_origin
	if impact_direction.length_squared() > DIRECTION_EPSILON_SQUARED:
		result.impact_direction = impact_direction.normalized()
	projectile_impacted.emit(impact_position)
	delivery_impacted.emit(delivery_context, result)
	_emit_finished_once(result)
	_active_projectile = null
	queue_free()


## 若投射物没有先报告撞击就自行退出，交付以明确失败结束，避免调用方永久等待。
func _on_projectile_tree_exiting() -> void:
	if delivery_state != DeliveryState.TRAVELLING or finish_emitted:
		return
	delivery_state = DeliveryState.CANCELLED
	var result: SkillDeliveryResultType = SkillDeliveryResultType.new()
	result.succeeded = false
	result.failure_reason = &"projectile_ended_without_impact"
	result.origin_position = _launch_origin
	result.intended_position = _intended_position
	delivery_failed.emit(delivery_context, result.failure_reason)
	_emit_finished_once(result)
	_active_projectile = null
	queue_free()


func _is_context_valid(context: SkillContextType) -> bool:
	if context == null:
		return false
	if not is_instance_valid(context.caster) or not context.caster.is_inside_tree():
		return false
	if not context.resolved_target is CharacterBody3D:
		return false
	if not is_instance_valid(context.resolved_target) or not context.resolved_target.is_inside_tree():
		return false
	if not is_instance_valid(context.delivery_parent) or not context.delivery_parent.is_inside_tree():
		return false
	return true


func _is_configuration_valid() -> bool:
	if projectile_scene == null:
		return false
	if not (
		is_finite(projectile_speed)
		and is_finite(turn_speed_degrees)
		and is_finite(maximum_lifetime)
		and is_finite(impact_radius)
		and is_finite(aim_height)
	):
		return false
	return (
		projectile_speed > 0.0
		and turn_speed_degrees >= 0.0
		and maximum_lifetime > 0.0
		and impact_radius >= 0.0
	)


## 在调用动态投射物接口前检查最小契约，避免错误场景产生参数数量或返回类型错误。
func _has_compatible_projectile_contract(projectile: Node3D) -> bool:
	if not projectile.has_signal(&"projectile_impacted"):
		return false
	var impact_signal: Dictionary = _find_named_entry(
		projectile.get_signal_list(),
		&"projectile_impacted"
	)
	var impact_arguments: Array = impact_signal.get("args", []) as Array
	if impact_arguments.size() != 1 or int((impact_arguments[0] as Dictionary).get("type", TYPE_NIL)) != TYPE_VECTOR3:
		return false

	var launch_method: Dictionary = _find_named_entry(projectile.get_method_list(), &"launch")
	if launch_method.is_empty():
		return false
	var arguments: Array = launch_method.get("args", []) as Array
	if arguments.size() != REQUIRED_LAUNCH_ARGUMENT_COUNT:
		return false
	var return_info: Dictionary = launch_method.get("return", {}) as Dictionary
	return int(return_info.get("type", TYPE_NIL)) == TYPE_BOOL


func _connect_projectile(projectile: Node3D) -> void:
	projectile.projectile_impacted.connect(_on_projectile_impacted)
	projectile.tree_exiting.connect(_on_projectile_tree_exiting)


func _disconnect_projectile(projectile: Node3D) -> void:
	var impact_callback := Callable(self, &"_on_projectile_impacted")
	if projectile.is_connected(&"projectile_impacted", impact_callback):
		projectile.disconnect(&"projectile_impacted", impact_callback)
	var exit_callback := Callable(self, &"_on_projectile_tree_exiting")
	if projectile.is_connected(&"tree_exiting", exit_callback):
		projectile.disconnect(&"tree_exiting", exit_callback)


func _find_named_entry(entries: Array[Dictionary], entry_name: StringName) -> Dictionary:
	for entry: Dictionary in entries:
		if StringName(entry.get("name", &"")) == entry_name:
			return entry
	return {}


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if projectile_scene == null:
		warnings.append("TrackingProjectileDeliveryAgent requires a projectile_scene.")
	if projectile_speed <= 0.0:
		warnings.append("projectile_speed must be greater than zero.")
	if maximum_lifetime <= 0.0:
		warnings.append("maximum_lifetime must be greater than zero.")
	if turn_speed_degrees < 0.0:
		warnings.append("turn_speed_degrees cannot be negative.")
	if impact_radius < 0.0:
		warnings.append("impact_radius cannot be negative.")
	return warnings


func _exit_tree() -> void:
	if is_instance_valid(_active_projectile):
		_disconnect_projectile(_active_projectile)
	_active_projectile = null
