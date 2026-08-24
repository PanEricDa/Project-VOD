class_name AITrackingArcProjectile
extends Node3D

## 目标抵达型追踪抛物线投射物。
## 弹道与命中规则都由本场景维护；武器仅负责在动画事件发生时创建本节点。

signal projectile_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3
)

enum HitRule {
	## 终点持续跟随有效目标，到达后直接确认命中。
	TARGET_ARRIVAL,
}

@export_category("Hit Rule")
## 当前第一版只实现目标抵达命中；后续物理碰撞与范围落点会扩展为新的枚举值。
@export var hit_rule: HitRule = HitRule.TARGET_ARRIVAL

@export_category("Tracking Arc")
## 从发射点抵达目标的预期时长，单位为秒。
@export_range(0.01, 5.0, 0.01)
var flight_duration: float = 0.30

## 抛物线中点相对直线路径额外抬升的高度，单位为米。
@export_range(0.0, 10.0, 0.05)
var arc_height: float = 0.80

## 最终命中点相对于目标根节点向上的偏移，单位为米。
@export_range(-5.0, 5.0, 0.05)
var target_height_offset: float = 0.25

@export_category("Lifetime")
## 投射物异常未抵达时的最长存活时间，单位为秒。
@export_range(0.01, 30.0, 0.05)
var maximum_lifetime: float = 2.0

var tracked_target: UnitBase
var launch_position: Vector3 = Vector3.ZERO
var elapsed_time: float = 0.0
var flight_is_active: bool = false
var hit_was_emitted: bool = false


func _ready() -> void:
	set_physics_process(false)


## 从指定世界坐标开始向目标飞行。投射物自身的 Inspector 参数决定全部弹道行为。
func launch(target: UnitBase, start_position: Vector3) -> bool:
	if hit_rule != HitRule.TARGET_ARRIVAL:
		return false
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if flight_duration <= 0.0 or maximum_lifetime <= 0.0:
		return false
	tracked_target = target
	launch_position = start_position
	elapsed_time = 0.0
	hit_was_emitted = false
	flight_is_active = true
	global_position = launch_position
	set_physics_process(true)
	return true


func _physics_process(delta: float) -> void:
	if not flight_is_active:
		return
	if not is_instance_valid(tracked_target) or not tracked_target.is_inside_tree():
		_finish_without_hit()
		return
	elapsed_time += maxf(delta, 0.0)
	if elapsed_time >= maximum_lifetime:
		_finish_without_hit()
		return
	var has_arrived: bool = elapsed_time + 0.000001 >= flight_duration
	var progress: float = 1.0 if has_arrived else clampf(elapsed_time / flight_duration, 0.0, 1.0)
	var tracked_end: Vector3 = tracked_target.global_position + Vector3.UP * target_height_offset
	var base_position: Vector3 = launch_position.lerp(tracked_end, progress)
	var next_position: Vector3 = base_position + Vector3.UP * sin(progress * PI) * arc_height
	var flight_direction: Vector3 = next_position - global_position
	global_position = next_position
	_update_visual_facing(flight_direction)
	if has_arrived:
		_finish_with_hit(tracked_end, flight_direction)


func _update_visual_facing(flight_direction: Vector3) -> void:
	if flight_direction.length_squared() <= 0.000001:
		return
	var normalized_direction := flight_direction.normalized()
	if absf(normalized_direction.dot(Vector3.UP)) >= 0.999:
		return
	look_at(global_position + normalized_direction, Vector3.UP)


func _finish_with_hit(hit_position: Vector3, flight_direction: Vector3) -> void:
	if hit_was_emitted:
		return
	hit_was_emitted = true
	flight_is_active = false
	set_physics_process(false)
	var safe_direction := flight_direction.normalized()
	if safe_direction.length_squared() <= 0.000001:
		safe_direction = Vector3.FORWARD
	projectile_hit.emit(tracked_target, hit_position, safe_direction)
	queue_free()


func _finish_without_hit() -> void:
	flight_is_active = false
	set_physics_process(false)
	queue_free()
