extends CharacterBody3D

## 玩家锁定的敌方目标发生变化时发出。参数为 null 表示取消锁定。
signal locked_target_changed(target: CharacterBody3D)

## 玩家在水平地面上的最大常规移动速度，单位为米/秒。
## 该参数暴露在 Inspector 中，便于直接调整基础移动手感。
@export_range(0.1, 20.0, 0.1, "or_greater") var movement_speed: float = 4.0

## 玩家常规移动加速和减速的变化率，单位为米/秒²。
## 渐进加速可以避免输入开始或结束时速度瞬间跳变。
@export_range(0.1, 100.0, 0.1, "or_greater") var movement_acceleration: float = 24.0

## 玩家视觉模型转向目标方向时的角速度，单位为弧度/秒。
## 只旋转 Visual，不旋转 CharacterBody3D 根节点，因此不会影响固定摄像机方向。
@export_range(0.1, 30.0, 0.1, "or_greater") var visual_rotation_speed: float = 12.0

@export_category("Target Lock")
## 玩家与锁定目标之间允许保持的最大距离，超过该距离会自动取消锁定。
@export_range(0.5, 50.0, 0.1, "or_greater") var target_lock_maximum_distance: float = 5.0

## 鼠标射线参与检测的物理层。默认同时检测 World（第 1 层）和 Enemy（第 3 层）。
@export_flags_3d_physics var target_selection_collision_mask: int = 5

## 鼠标选择射线的最大长度，只负责获取点击位置，不改变锁定允许距离。
@export_range(10.0, 2000.0, 1.0, "or_greater") var target_selection_ray_length: float = 1000.0

@export_category("Target Lock Range Indicator")
## 是否持续显示玩家脚下的锁定距离圆环。
@export var target_lock_indicator_enabled: bool = true

## 锁定范围圆环的径向厚度，单位为米。
@export_range(0.005, 0.25, 0.005, "or_greater") var target_lock_indicator_thickness: float = 0.03

## 圆环相对玩家根节点的高度偏移，略高于地面以减少深度闪烁。
@export_range(0.0, 1.0, 0.005) var target_lock_indicator_height: float = 0.03

## 玩家未锁定目标时使用的绿色半透明颜色。
@export var target_lock_indicator_color: Color = Color(0.18, 0.9, 0.32, 0.32)

## 玩家成功锁定敌方目标时使用的红色半透明颜色。
@export var target_lock_indicator_locked_color: Color = Color(1.0, 0.12, 0.08, 0.58)

## 每次冲刺希望移动的最大水平距离，单位为米。
## 实际距离会受到墙体等碰撞阻挡；脚本不会为了达到该距离而穿过障碍物。
@export_range(0.1, 20.0, 0.1, "or_greater") var dash_distance: float = 2.5

## 冲刺期间的水平移动速度，单位为米/秒。
## 冲刺持续时间由 dash_distance / dash_speed 自动得出，无需额外配置持续时间。
@export_range(0.1, 50.0, 0.1, "or_greater") var dash_speed: float = 10.0

## 冷却前允许连续使用的最大冲刺次数。
## 默认值为 2，表示玩家可以连续冲刺两次；次数耗尽后必须等待完整冷却。
@export_range(1, 10, 1, "or_greater") var maximum_consecutive_dashes: int = 2

## 全部冲刺次数耗尽后的冷却时间，单位为秒。
## 冷却从最后一次冲刺结束时开始，完成后会一次性恢复全部冲刺次数。
@export_range(0.0, 30.0, 0.1, "or_greater") var dash_cooldown_duration: float = 2.0

## 指向玩家视觉模型容器的节点引用。
## 所有朝向旋转都施加到此节点，以保持碰撞体和摄像机控制相互独立。
@onready var visual: Node3D = $Visual
@onready var target_lock_range_indicator: MeshInstance3D = $TargetLockRangeIndicator

## 从 Godot 项目物理设置读取的默认重力加速度。
## 使用项目设置而不是硬编码数值，确保遵循 Godot 4.7 的全局物理配置。
@export_category("Physics")
## 玩家受到的重力倍率。1.0 使用项目默认重力，0.0 可关闭重力，更高数值会加快下落。
@export_range(0.0, 10.0, 0.1, "or_greater") var gravity_multiplier: float = 1.0

## 从 Godot 项目物理设置读取默认重力加速度，确保遵循 Godot 4.7 的全局配置。
var gravity_force: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

## 玩家最后一次有效移动的世界方向。
## 没有按住移动键时按下冲刺，会沿该方向冲刺；初始方向为场景正前方 -Z。
var last_movement_direction: Vector3 = Vector3.FORWARD

## 当前由玩家左键选中的敌方 CharacterBody3D；null 表示没有锁定目标。
var locked_target: CharacterBody3D

## 当前冲刺使用的固定世界方向。
## 冲刺开始后锁定该方向，避免冲刺途中改变按键造成瞬间转弯。
var dash_direction: Vector3 = Vector3.ZERO

## 当前冲刺尚未完成的水平距离，单位为米。
## 大于零表示正在冲刺，归零后恢复常规移动。
var dash_remaining_distance: float = 0.0

## 当前仍可使用的冲刺次数。
## 该运行时状态在场景初始化和冷却完成时恢复为 maximum_consecutive_dashes。
var available_dash_count: int = 0

## 当前冷却剩余时间，单位为秒。
## 大于零表示冲刺次数正在恢复；归零时会重新补满全部冲刺次数。
var dash_cooldown_remaining: float = 0.0


## Godot 节点初始化回调，负责根据 Inspector 参数初始化冲刺次数。
func _ready() -> void:
	available_dash_count = maximum_consecutive_dashes
	_configure_target_lock_range_indicator()


## 创建玩家锁定距离的水平 TorusMesh 圆环。
## 圆环半径直接读取 target_lock_maximum_distance，因此显示范围与自动解除锁定的判定距离一致。
func _configure_target_lock_range_indicator() -> void:
	target_lock_range_indicator.visible = target_lock_indicator_enabled
	target_lock_range_indicator.position.y = target_lock_indicator_height
	target_lock_range_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not target_lock_indicator_enabled:
		return

	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = max(
		target_lock_maximum_distance - target_lock_indicator_thickness,
		0.001
	)
	ring_mesh.outer_radius = target_lock_maximum_distance
	ring_mesh.rings = 96
	ring_mesh.ring_segments = 6
	target_lock_range_indicator.mesh = ring_mesh

	var ring_material: StandardMaterial3D = StandardMaterial3D.new()
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	target_lock_range_indicator.material_override = ring_material
	_update_target_lock_indicator_color()


## 根据当前锁定状态更新圆环颜色；只改变材质显示，不影响锁定范围和射线检测。
func _update_target_lock_indicator_color() -> void:
	if not target_lock_indicator_enabled:
		return

	var ring_material: StandardMaterial3D = (
		target_lock_range_indicator.material_override as StandardMaterial3D
	)
	if ring_material == null:
		return

	ring_material.albedo_color = (
		target_lock_indicator_locked_color
		if is_instance_valid(locked_target)
		else target_lock_indicator_color
	)


## Godot 固定物理帧回调，负责读取 InputMap、处理冲刺、应用重力并移动角色。
## 参数 delta 表示当前物理帧经过的秒数，确保速度和距离计算不依赖帧率。
## 通过 InputMap 处理鼠标左键目标选择。
## 点击敌方 CharacterBody3D 会尝试锁定；点击地面、其他物体或空白位置都会取消当前锁定。
func _unhandled_input(event: InputEvent) -> void:
	# F 键通过独立 InputMap 动作自动选择锁定范围内距离玩家最近的敌方单位。
	# 自动选择与鼠标中键共用 _set_locked_target，因此颜色、朝向、信号和超距解除规则保持一致。
	if event.is_action_pressed("player_target_nearest"):
		_lock_nearest_target()
		get_viewport().set_input_as_handled()
		return

	if not event.is_action_pressed("player_target_select"):
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null:
		return

	_select_target_at_screen_position(mouse_event.position)
	get_viewport().set_input_as_handled()


## 从当前摄像机穿过鼠标位置发射三维射线，并根据首次命中的碰撞体决定锁定结果。
## 射线只检测 target_selection_collision_mask 指定的层，玩家自身通过 RID 排除。
func _select_target_at_screen_position(screen_position: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		_clear_locked_target()
		return

	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var ray_end: Vector3 = ray_origin + ray_direction * target_selection_ray_length
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		target_selection_collision_mask,
		[get_rid()]
	)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_clear_locked_target()
		return

	var collider: Node = hit.get("collider") as Node
	var enemy: CharacterBody3D = collider as CharacterBody3D
	if enemy == null or not enemy.is_in_group("enemy_targets"):
		_clear_locked_target()
		return

	if global_position.distance_to(enemy.global_position) > target_lock_maximum_distance:
		_clear_locked_target()
		return

	_set_locked_target(enemy)


## 在 enemy_targets 分组中查找锁定距离内与玩家最近的 CharacterBody3D。
## 当前阶段只按空间距离选择，不要求目标位于屏幕内，也不执行墙体视线遮挡检测。
## 范围内没有有效敌人时会调用统一取消方法，行为与鼠标点击地面一致。
func _lock_nearest_target() -> void:
	var nearest_enemy: CharacterBody3D
	var nearest_distance_squared: float = INF
	var maximum_distance_squared: float = target_lock_maximum_distance * target_lock_maximum_distance

	for candidate: Node in get_tree().get_nodes_in_group("enemy_targets"):
		var enemy: CharacterBody3D = candidate as CharacterBody3D
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue

		var distance_squared: float = global_position.distance_squared_to(enemy.global_position)
		if distance_squared > maximum_distance_squared:
			continue
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_enemy = enemy

	if nearest_enemy == null:
		_clear_locked_target()
		return

	_set_locked_target(nearest_enemy)


## 在物理帧开始时检查目标是否仍然有效且处于允许距离内。
## 目标被删除、离开场景树或超过最大距离时都会自动解除锁定。
func _validate_locked_target() -> void:
	if locked_target == null:
		return

	if not is_instance_valid(locked_target) or not locked_target.is_inside_tree():
		_clear_locked_target()
		return

	if global_position.distance_to(locked_target.global_position) > target_lock_maximum_distance:
		_clear_locked_target()


## 返回玩家指向锁定目标的水平单位方向，用于覆盖移动和冲刺产生的视觉朝向。
func _get_locked_target_direction() -> Vector3:
	if not is_instance_valid(locked_target):
		return Vector3.ZERO

	var target_direction: Vector3 = locked_target.global_position - global_position
	target_direction.y = 0.0
	if target_direction.length_squared() <= 0.0001:
		return Vector3.ZERO

	return target_direction.normalized()


## 统一设置锁定目标，避免重复选择同一个目标时重复发送信号。
func _set_locked_target(target: CharacterBody3D) -> void:
	if locked_target == target:
		return

	locked_target = target
	_update_target_lock_indicator_color()
	locked_target_changed.emit(locked_target)


## 统一取消目标锁定，并通知以后接入的 UI、攻击或技能系统。
func _clear_locked_target() -> void:
	if locked_target == null:
		return

	locked_target = null
	_update_target_lock_indicator_color()
	locked_target_changed.emit(null)


func _physics_process(delta: float) -> void:
	_validate_locked_target()
	# 冷却计时使用固定物理帧更新，确保计时行为稳定且不受渲染帧率影响。
	_update_dash_cooldown(delta)

	# 通过 InputMap 读取四个移动动作并生成长度不超过 1 的二维输入向量。
	# 这可以保证斜向移动不会比直线移动更快。
	var input_vector: Vector2 = Input.get_vector(
		"player_move_left",
		"player_move_right",
		"player_move_forward",
		"player_move_backward"
	)

	# 将二维输入映射到 Godot 3D 世界的 XZ 水平平面。
	# X 轴负责左右移动，负 Z 轴代表场景正前方。
	var movement_direction: Vector3 = Vector3(input_vector.x, 0.0, input_vector.y)

	# 记录最后一次有效输入方向，供静止状态下的冲刺使用。
	if movement_direction.length_squared() > 0.0001:
		last_movement_direction = movement_direction.normalized()

	# 所有冲刺触发都通过 InputMap 的 player_dash 动作处理。
	# 只有当前未在冲刺时才接受新的触发，避免一次冲刺被重复重置。
	if Input.is_action_just_pressed("player_dash") and _can_start_dash():
		_start_dash(movement_direction)

	# 冲刺与常规移动采用互斥逻辑。
	# 冲刺期间锁定高速度和方向；冲刺结束后恢复平滑常规移动。
	if _is_dashing():
		_process_dash(delta)
	else:
		_process_regular_movement(delta, movement_direction)

	# 无论是否冲刺都应用相同的重力和贴地逻辑。
	_apply_gravity(delta)

	# 仅在存在有效方向时调整视觉模型朝向。
	var facing_direction: Vector3 = _get_locked_target_direction()
	if facing_direction.length_squared() <= 0.0001:
		facing_direction = dash_direction if _is_dashing() else movement_direction
	if facing_direction.length_squared() > 0.0001:
		_rotate_visual_toward(facing_direction, delta)

	# 保存移动前的位置，用于计算本物理帧实际完成的冲刺距离。
	var previous_position: Vector3 = global_position

	# 使用 Godot 4.7 CharacterBody3D 标准方法处理位移、地面和墙体碰撞。
	move_and_slide()

	# 冲刺距离以碰撞处理后的真实水平位移扣除，因此撞墙不会被计算为已移动距离。
	if _is_dashing():
		_update_dash_distance(previous_position, movement_direction)


## 处理非冲刺状态下的常规平滑移动。
## 参数 delta 是物理帧时长，参数 direction 是当前 InputMap 生成的水平移动方向。
func _process_regular_movement(delta: float, direction: Vector3) -> void:
	var target_velocity_x: float = direction.x * movement_speed
	var target_velocity_z: float = direction.z * movement_speed

	# 逐步接近期望速度，实现平滑且与物理帧率无关的加速和减速。
	velocity.x = move_toward(velocity.x, target_velocity_x, movement_acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity_z, movement_acceleration * delta)


## 开始一次新的冲刺。
## 如果当前存在移动输入，使用输入方向；否则沿角色最后一次有效移动方向冲刺。
func _start_dash(input_direction: Vector3) -> void:
	if input_direction.length_squared() > 0.0001:
		dash_direction = input_direction.normalized()
	else:
		dash_direction = last_movement_direction.normalized()

	dash_remaining_distance = dash_distance

	# 每次成功开始冲刺时消耗一次储备次数。
	# 次数耗尽后必须等待本次冲刺结束并完成冷却，才能再次冲刺。
	available_dash_count = max(available_dash_count - 1, 0)


## 为当前冲刺帧设置水平速度。
## 最后一帧会自动降低速度，避免单个物理帧越过配置的 dash_distance。
func _process_dash(delta: float) -> void:
	# 根据剩余距离限制本帧速度，使理论位移不会超过尚未完成的冲刺距离。
	var frame_dash_speed: float = min(dash_speed, dash_remaining_distance / max(delta, 0.000001))
	velocity.x = dash_direction.x * frame_dash_speed
	velocity.z = dash_direction.z * frame_dash_speed



## 根据 move_and_slide 后的真实位移更新剩余冲刺距离。
## 如果碰到墙体或距离完成，则结束冲刺并恢复常规水平速度。
func _update_dash_distance(previous_position: Vector3, input_direction: Vector3) -> void:
	var frame_displacement: Vector3 = global_position - previous_position
	var horizontal_distance: float = Vector2(frame_displacement.x, frame_displacement.z).length()
	dash_remaining_distance = max(dash_remaining_distance - horizontal_distance, 0.0)

	# 撞墙时立即结束冲刺，防止角色持续顶住墙体等待剩余距离耗尽。
	if is_on_wall() or dash_remaining_distance <= 0.001:
		_finish_dash(input_direction)


## 结束当前冲刺，并依据当前移动输入恢复普通水平速度。
## 没有输入时会立即停止冲刺水平速度，避免冲刺结束后继续高速滑行。
func _finish_dash(input_direction: Vector3) -> void:
	dash_remaining_distance = 0.0
	dash_direction = Vector3.ZERO
	velocity.x = input_direction.x * movement_speed
	velocity.z = input_direction.z * movement_speed

	# 最后一次可用冲刺结束后才开始冷却，确保完整冲刺过程不占用冷却时间。
	if available_dash_count <= 0:
		dash_cooldown_remaining = dash_cooldown_duration


## 返回当前是否允许开始一次新冲刺。
## 必须同时满足“不在冲刺中”和“仍有可用次数”两个条件。
func _can_start_dash() -> bool:
	return not _is_dashing() and available_dash_count > 0


## 按固定物理帧更新冲刺冷却，并在冷却结束时恢复全部次数。
## 参数 delta 是当前物理帧经过的秒数。
func _update_dash_cooldown(delta: float) -> void:
	if dash_cooldown_remaining <= 0.0:
		return

	dash_cooldown_remaining = max(dash_cooldown_remaining - delta, 0.0)

	# 冷却归零后一次性补满次数，使最大连续次数始终由 Inspector 参数控制。
	if dash_cooldown_remaining <= 0.0:
		available_dash_count = maximum_consecutive_dashes


## 返回玩家当前是否处于冲刺状态。
## 将状态判断集中在一个方法中，可以避免多个逻辑位置使用不一致的阈值。
func _is_dashing() -> bool:
	return dash_remaining_distance > 0.001


## 应用项目默认重力和稳定贴地速度。
## 参数 delta 是当前物理帧经过的秒数。
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity_force * gravity_multiplier * delta
	else:
		# 很小的向下速度可以帮助 CharacterBody3D 在地面接触时保持稳定。
		velocity.y = -0.1


## 平滑旋转视觉模型，使模型的本地前方（-Z）朝向当前移动或冲刺方向。
## 参数 direction 是世界空间的水平朝向，参数 delta 用于保证转向速度不依赖帧率。
func _rotate_visual_toward(direction: Vector3, delta: float) -> void:
	var target_yaw: float = atan2(-direction.x, -direction.z)

	# lerp_angle 会在跨越 -PI 与 PI 时自动选择最短旋转路径。
	visual.rotation.y = lerp_angle(
		visual.rotation.y,
		target_yaw,
		min(visual_rotation_speed * delta, 1.0)
	)
