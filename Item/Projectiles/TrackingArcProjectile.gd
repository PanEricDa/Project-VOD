class_name AITrackingArcProjectile
extends Node3D

## 目标抵达型追踪抛物线投射物。
## 弹道与命中规则都由本场景维护；武器仅负责在动画事件发生时创建本节点。

signal projectile_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3
)

## 命中主视觉尚未进树时通知；消费者可登记请求时钟和完成监听，不能在此执行伤害。
signal impact_presentation_prepared(instance: Node3D)
var _execution_clock: SkillExecutionClock
var _fixed_destination: Vector3 = Vector3.INF
var _born_physics_frame: int = -1
var _impact_radius: float = 0.0

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

@export_category("Presentation")
## 可选独立命中特效场景；默认空无特效，有效抵达目标时在世界命中位置生成。
## 特效须自行播放和销毁，仅影响视觉，不改变本投射物的命中、伤害或范围规则。
@export var impact_effect_scene: PackedScene

var tracked_target: UnitBase
var launch_position: Vector3 = Vector3.ZERO
var elapsed_time: float = 0.0
var flight_is_active: bool = false
var hit_was_emitted: bool = false


func _ready() -> void:
	set_physics_process(false)


## 从指定世界坐标开始向目标飞行。投射物自身的 Inspector 参数决定全部弹道行为。
func launch(target: UnitBase, start_position: Vector3) -> bool:
	_fixed_destination = Vector3.INF
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
	if _fixed_destination.is_finite() and Engine.get_physics_frames() <= _born_physics_frame: return
	if _execution_clock != null:
		delta = _execution_clock.get_delta(delta)
	if not flight_is_active or delta <= 0:
		return
	if not _fixed_destination.is_finite() and (not is_instance_valid(tracked_target) or not tracked_target.is_inside_tree()):
		_finish_without_hit()
		return
	elapsed_time += maxf(delta, 0.0)
	if elapsed_time >= maximum_lifetime:
		_finish_without_hit()
		return
	var has_arrived: bool = elapsed_time + 0.000001 >= flight_duration
	var progress: float = 1.0 if has_arrived else clampf(elapsed_time / flight_duration, 0.0, 1.0)
	var tracked_end: Vector3 = _fixed_destination if _fixed_destination.is_finite() else tracked_target.global_position + Vector3.UP * target_height_offset
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
	_spawn_impact_presentation(hit_position, safe_direction)
	projectile_hit.emit(tracked_target, hit_position, safe_direction)
	queue_free()


## hit_direction为世界入射方向；只传给支持定向的视觉，不改变命中或伤害。
func _spawn_impact_presentation(hit_position: Vector3, hit_direction: Vector3) -> void:
	if impact_effect_scene == null or (not _fixed_destination.is_finite() and (not is_instance_valid(tracked_target) or tracked_target.is_dead())):
		return
	var instance: Node = impact_effect_scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return
	var effect := instance as Node3D
	effect.transform = Transform3D(Basis.IDENTITY, hit_position)
	if get_parent() is Node3D:
		effect.transform = (get_parent() as Node3D).global_transform.affine_inverse() * effect.transform
	if effect.has_method(&"configure_impact_direction"):
		effect.call(&"configure_impact_direction", hit_direction)
	if effect.has_method(&"set_execution_clock"):
		effect.call(&"set_execution_clock", _execution_clock)
	if _impact_radius > 0 and effect.has_method(&"configure_impact_radius"):
		effect.call(&"configure_impact_radius", _impact_radius)
	impact_presentation_prepared.emit(effect)
	if is_instance_valid(effect) and is_inside_tree():
		get_parent().add_child(effect)


## 注入可选请求时钟及本次视觉半径；null保持原世界时间，半径0保持资产原尺寸。
func set_execution_clock(clock: SkillExecutionClock, impact_radius_m: float = 0.0) -> void:
	_execution_clock = clock
	_impact_radius = impact_radius_m
	for child: Node in get_children():
		if child.has_method(&"set_execution_clock"):
			child.call(&"set_execution_clock", clock)

## 向固定世界落点发射，不追踪单位；落地信号target为空，交付按自身范围规则处理。
func launch_point(destination: Vector3, start_position: Vector3) -> bool:
	if not destination.is_finite() or not start_position.is_finite() or flight_duration <= 0 or maximum_lifetime <= 0:
		return false
	tracked_target = null
	_fixed_destination = destination
	launch_position = start_position
	elapsed_time = 0.0
	hit_was_emitted = false
	flight_is_active = true
	global_position = start_position
	_born_physics_frame = Engine.get_physics_frames()
	set_physics_process(true)
	return true

func _finish_without_hit() -> void:
	flight_is_active = false
	set_physics_process(false)
	queue_free()
