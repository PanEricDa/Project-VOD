extends Node3D

signal projectile_impacted(position: Vector3)
signal projectile_targets_resolved(targets: Array[CharacterBody3D])
signal fireball_hit(target: CharacterBody3D, hit_position: Vector3, hit_direction: Vector3)
signal fireball_exploded(position: Vector3, targets: Array[CharacterBody3D])

const ENEMY_COLLISION_MASK: int = 4
const AIM_HEIGHT: float = 0.25
const DIRECTION_EPSILON_SQUARED: float = 0.000001

var _caster_ref: WeakRef
var _target_ref: WeakRef
var _current_direction: Vector3 = Vector3.FORWARD
var _speed: float = 0.0
var _turn_speed_radians: float = 0.0
var _lifetime: float = 0.0
var _explosion_radius: float = 0.0
var _elapsed: float = 0.0
var _impact_handled: bool = false
var _processing_impact: bool = false
var _active: bool = false
var _caster_rid: RID


func _ready() -> void:
	# 场景实例默认保持静止，只有成功发射后才参与物理更新。
	set_physics_process(false)
	var sweep := _get_collision_sweep()
	if sweep != null:
		sweep.enabled = false
	var flight := _get_flight_effect()
	if flight != null and flight.has_method(&"stop"):
		flight.call(&"stop")
	var explosion := _get_explosion_effect()
	if explosion != null:
		if explosion.has_method(&"stop"):
			explosion.call(&"stop")
		_connect_explosion_finished(explosion)


func launch(
	caster: Node3D,
	target: CharacterBody3D,
	start_position: Vector3,
	initial_direction: Vector3,
	speed: float,
	turn_speed_degrees: float,
	lifetime: float,
	explosion_radius: float
) -> bool:
	# 所有参数先完整校验；失败时不改变当前视觉或物理生命周期。
	# 此 guard 独立于可重置的发射状态，信号同步回调期间绝不允许重启同一实例。
	if _processing_impact:
		return false
	if not is_instance_valid(caster) or not caster.is_inside_tree():
		return false
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if not start_position.is_finite() or not initial_direction.is_finite():
		return false
	if not (
		is_finite(speed)
		and is_finite(turn_speed_degrees)
		and is_finite(lifetime)
		and is_finite(explosion_radius)
	):
		return false
	if initial_direction.length_squared() <= DIRECTION_EPSILON_SQUARED:
		return false
	if speed <= 0.0 or turn_speed_degrees < 0.0 or lifetime <= 0.0 or explosion_radius < 0.0:
		return false

	_caster_ref = weakref(caster)
	_target_ref = weakref(target)
	_current_direction = initial_direction.normalized()
	_speed = speed
	_turn_speed_radians = deg_to_rad(turn_speed_degrees)
	_lifetime = lifetime
	_explosion_radius = explosion_radius
	_elapsed = 0.0
	_impact_handled = false
	_active = true
	global_position = start_position
	_update_visual_facing(_current_direction)

	# 使用 RID 显式排除施法者，避免其碰撞层配置异常时误伤自身。
	_caster_rid = RID()
	if caster is CollisionObject3D:
		_caster_rid = (caster as CollisionObject3D).get_rid()
	var sweep := _get_collision_sweep()
	if sweep != null:
		sweep.clear_exceptions()
		if _caster_rid.is_valid():
			sweep.add_exception_rid(_caster_rid)
		sweep.target_position = Vector3.ZERO
		sweep.enabled = true

	var explosion := _get_explosion_effect()
	if explosion != null:
		_connect_explosion_finished(explosion)
		if explosion.has_method(&"stop"):
			explosion.call(&"stop")
		if explosion.has_method(&"reset_effect"):
			explosion.call(&"reset_effect")
	var flight := _get_flight_effect()
	if flight != null and flight.has_method(&"start"):
		flight.call(&"start")
	set_physics_process(true)
	return true


func _physics_process(delta: float) -> void:
	if not _active or _impact_handled:
		return
	var remaining_lifetime: float = _lifetime - _elapsed
	if remaining_lifetime <= 0.0:
		_expire()
		return
	var step_delta: float = min(delta, remaining_lifetime)
	if step_delta <= 0.0:
		return
	_elapsed = min(_elapsed + step_delta, _lifetime)

	_update_homing(step_delta)
	var displacement: Vector3 = _current_direction * _speed * step_delta
	var sweep := _get_collision_sweep()
	if sweep != null and sweep.enabled:
		# ShapeCast 的目标位于本地空间，必须逆变换世界位移以抵消朝向旋转。
		sweep.target_position = global_transform.basis.inverse() * displacement
		sweep.force_shapecast_update()
		var nearest := _nearest_collision(sweep, displacement.normalized())
		if not nearest.is_empty():
			_handle_impact(nearest["position"], nearest["collider"])
			return

	global_position += displacement
	_update_visual_facing(_current_direction)
	if _elapsed >= _lifetime:
		_expire()


func _update_homing(delta: float) -> void:
	var target := _get_valid_target()
	if target == null:
		return
	var desired_offset: Vector3 = target.global_position + Vector3.UP * AIM_HEIGHT - global_position
	if desired_offset.length_squared() <= DIRECTION_EPSILON_SQUARED:
		return
	var desired := desired_offset.normalized()
	var maximum_turn := _turn_speed_radians * delta
	_current_direction = _rotate_direction_limited(_current_direction, desired, maximum_turn)


func _rotate_direction_limited(current: Vector3, desired: Vector3, maximum_turn: float) -> Vector3:
	# 接近反向时叉积趋近零；选择稳定的正交轴，避免 slerp 产生零向量或 NaN。
	var angle := current.angle_to(desired)
	if angle <= maximum_turn:
		return desired
	if maximum_turn <= 0.0:
		return current
	var axis := current.cross(desired)
	if axis.length_squared() <= DIRECTION_EPSILON_SQUARED:
		axis = current.cross(Vector3.UP)
		if axis.length_squared() <= DIRECTION_EPSILON_SQUARED:
			axis = current.cross(Vector3.RIGHT)
	var rotated := current.rotated(axis.normalized(), maximum_turn).normalized()
	if not rotated.is_finite() or rotated.length_squared() <= DIRECTION_EPSILON_SQUARED:
		return current
	return rotated


func _nearest_collision(sweep: ShapeCast3D, world_direction: Vector3) -> Dictionary:
	var nearest_progress := INF
	var nearest_instance_id: int = 9223372036854775807
	var nearest_index: int = 2147483647
	var nearest: Dictionary = {}
	for index: int in sweep.get_collision_count():
		var collision_position := sweep.get_collision_point(index)
		# 接触点到起点的径向距离不代表沿扫掠路径的先后；使用世界位移方向上的投影进度。
		var progress := (collision_position - global_position).dot(world_direction)
		var collider: Object = sweep.get_collider(index)
		var instance_id := collider.get_instance_id() if is_instance_valid(collider) else 9223372036854775807
		var earlier := progress < nearest_progress - 0.000001
		var tied_progress := is_equal_approx(progress, nearest_progress)
		var stable_tie := tied_progress and (
			instance_id < nearest_instance_id
			or (instance_id == nearest_instance_id and index < nearest_index)
		)
		if earlier or stable_tie:
			nearest_progress = progress
			nearest_instance_id = instance_id
			nearest_index = index
			nearest = {
				"position": collision_position,
				"collider": collider,
			}
	return nearest


func _handle_impact(impact_position: Vector3, collider: Object) -> void:
	if _processing_impact or _impact_handled:
		return
	_processing_impact = true
	_impact_handled = true
	_active = false
	set_physics_process(false)
	var sweep := _get_collision_sweep()
	if sweep != null:
		sweep.enabled = false
	var flight := _get_flight_effect()
	if flight != null and flight.has_method(&"stop"):
		flight.call(&"stop")
	global_position = impact_position

	# 直接命中的敌人与范围查询共用同一去重表，保证每个实例只发出一次命中。
	var accepted_by_id: Dictionary = {}
	var targets: Array[CharacterBody3D] = []
	var direct_enemy := _as_valid_enemy(collider)
	if direct_enemy != null:
		_add_unique_target(direct_enemy, accepted_by_id, targets)
		_query_explosion_targets(impact_position, accepted_by_id, targets)
	# 先解析单体和范围目标，再通知通用交付层结算效果。
	projectile_targets_resolved.emit(targets)
	projectile_impacted.emit(impact_position)
	for enemy: CharacterBody3D in targets:
		fireball_hit.emit(
			enemy,
			impact_position,
			_hit_direction(impact_position, enemy.global_position)
		)
	fireball_exploded.emit(impact_position, targets)

	# 游戏信号先完成，再播放纯视觉爆炸；没有合法视觉时立即释放。
	var explosion := _get_explosion_effect()
	if explosion != null and explosion.has_method(&"play") and explosion.has_signal(&"effect_finished"):
		_connect_explosion_finished(explosion)
		explosion.call(&"play")
	else:
		queue_free()
	_processing_impact = false


func _query_explosion_targets(
	explosion_position: Vector3,
	accepted_by_id: Dictionary,
	targets: Array[CharacterBody3D]
) -> void:
	var results: Array[Dictionary] = []
	if is_zero_approx(_explosion_radius):
		# Jolt 无法构建零半径球；点查询精确表达半径为零，且仍只执行一次物理查询。
		var point_parameters := PhysicsPointQueryParameters3D.new()
		point_parameters.position = explosion_position
		point_parameters.collision_mask = ENEMY_COLLISION_MASK
		point_parameters.collide_with_bodies = true
		point_parameters.collide_with_areas = false
		if _caster_rid.is_valid():
			point_parameters.exclude = [_caster_rid]
		results = get_world_3d().direct_space_state.intersect_point(point_parameters, 32)
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = _explosion_radius
		var shape_parameters := PhysicsShapeQueryParameters3D.new()
		shape_parameters.shape = sphere
		shape_parameters.transform = Transform3D(Basis.IDENTITY, explosion_position)
		shape_parameters.collision_mask = ENEMY_COLLISION_MASK
		shape_parameters.collide_with_bodies = true
		shape_parameters.collide_with_areas = false
		if _caster_rid.is_valid():
			shape_parameters.exclude = [_caster_rid]
		results = get_world_3d().direct_space_state.intersect_shape(shape_parameters, 32)
	for result: Dictionary in results:
		var enemy := _as_valid_enemy(result.get("collider"))
		if enemy != null:
			_add_unique_target(enemy, accepted_by_id, targets)


func _as_valid_enemy(candidate: Variant) -> CharacterBody3D:
	if not (candidate is CharacterBody3D):
		return null
	var body := candidate as CharacterBody3D
	if not is_instance_valid(body) or not body.is_inside_tree():
		return null
	if (body.collision_layer & ENEMY_COLLISION_MASK) == 0:
		return null
	if not body.is_in_group(&"enemy_targets"):
		return null
	return body


func _add_unique_target(
	target: CharacterBody3D,
	accepted_by_id: Dictionary,
	targets: Array[CharacterBody3D]
) -> void:
	var instance_id := target.get_instance_id()
	if accepted_by_id.has(instance_id):
		return
	accepted_by_id[instance_id] = true
	targets.append(target)


func _hit_direction(impact_position: Vector3, target_position: Vector3) -> Vector3:
	var outward := target_position - impact_position
	outward.y = 0.0
	if outward.length_squared() > DIRECTION_EPSILON_SQUARED:
		return outward.normalized()
	var fallback := _current_direction
	fallback.y = 0.0
	if fallback.length_squared() > DIRECTION_EPSILON_SQUARED:
		return fallback.normalized()
	return Vector3.FORWARD


func _update_visual_facing(direction: Vector3) -> void:
	if direction.length_squared() <= DIRECTION_EPSILON_SQUARED:
		return
	var up := Vector3.UP
	if absf(direction.normalized().dot(up)) > 0.999:
		return
	global_basis = Basis.looking_at(direction.normalized(), up)


func _expire() -> void:
	_active = false
	set_physics_process(false)
	var sweep := _get_collision_sweep()
	if sweep != null:
		sweep.enabled = false
	var flight := _get_flight_effect()
	if flight != null and flight.has_method(&"stop"):
		flight.call(&"stop")
	var explosion := _get_explosion_effect()
	if explosion != null and explosion.has_method(&"stop"):
		explosion.call(&"stop")
	queue_free()


func _on_explosion_effect_finished() -> void:
	if _impact_handled and not is_queued_for_deletion():
		queue_free()


func _connect_explosion_finished(explosion: Node) -> void:
	if not explosion.has_signal(&"effect_finished"):
		return
	var callback := Callable(self, &"_on_explosion_effect_finished")
	if not explosion.is_connected(&"effect_finished", callback):
		explosion.connect(&"effect_finished", callback)


func _get_valid_target() -> CharacterBody3D:
	if _target_ref == null:
		return null
	var candidate: Variant = _target_ref.get_ref()
	if candidate is CharacterBody3D and is_instance_valid(candidate) and candidate.is_inside_tree():
		return candidate as CharacterBody3D
	return null


func _get_collision_sweep() -> ShapeCast3D:
	return get_node_or_null(^"CollisionSweep") as ShapeCast3D


func _get_flight_effect() -> Node:
	return get_node_or_null(^"FireballFlightEffect")


func _get_explosion_effect() -> Node:
	return get_node_or_null(^"FireballExplosionEffect")


func _exit_tree() -> void:
	_active = false
	set_physics_process(false)
	var sweep := _get_collision_sweep()
	if sweep != null:
		sweep.enabled = false
	var flight := _get_flight_effect()
	if flight != null and flight.has_method(&"stop"):
		flight.call(&"stop")
	var explosion := _get_explosion_effect()
	if explosion != null and explosion.has_method(&"stop"):
		explosion.call(&"stop")
