class_name AIUnitBase
extends UnitBase

## 所有自动移动单位共享的中间父类。
##
## 本类直接拥有导航、移动、冲刺、重力和视觉转向的执行逻辑。
## Ally 与 Enemy 子类只需要覆盖 `_update_ai_movement()` 提交本帧意图，
## 不应自行调用 move_and_slide() 或直接实现另一套重力和速度写入流程。

@export_category("Equipment")
## 该 AI 单位进入运行树后自动交给 CombatSystem 装配的武器数据。
## 设计师只需要在单位根节点配置一次，不再进入 CombatSystem 子节点重复设置。
@export var starting_weapon: WeaponData
enum MotionState {
	IDLE,
	MOVING,
	ATTACK_MOVING,
	DASHING,
	RECOVERING,
}

@export_category("Movement")
## 普通移动时允许达到的最大水平速度，单位为米/秒。
@export_range(0.1, 20.0, 0.1, "or_greater")
var movement_speed: float = 4.2
## 水平速度接近目标速度时使用的加速度和减速度。
@export_range(0.1, 100.0, 0.1, "or_greater")
var movement_acceleration: float = 20.0
## 距离移动目标小于该值后按比例减速，避免到达时突然停止。
@export_range(0.01, 5.0, 0.01, "or_greater")
var slowing_distance: float = 0.2
## 距离移动目标小于该值时视为到达。
@export_range(0.01, 2.0, 0.01, "or_greater")
var arrival_distance: float = 0.15

@export_category("Dash")
## 冲刺阶段允许达到的最大水平速度。
@export_range(0.1, 40.0, 0.1, "or_greater")
var dash_speed: float = 9.0
## 单次冲刺允许移动的最大距离。
@export_range(0.1, 20.0, 0.1, "or_greater")
var dash_max_distance: float = 3.0
## 冲刺距离目标小于该值时结束。
@export_range(0.01, 2.0, 0.01, "or_greater")
var dash_arrival_distance: float = 0.35
## 冲刺结束后再次允许冲刺前需要等待的时间。
@export_range(0.0, 10.0, 0.1)
var dash_cooldown: float = 1.5
## 冲刺结束后的平滑减速时间。
@export_range(0.0, 2.0, 0.05)
var dash_recovery_duration: float = 0.2
## 冲刺速度接近目标速度时使用的加速度。
@export_range(0.1, 200.0, 0.5, "or_greater")
var dash_acceleration: float = 40.0

@export_category("Facing")
## Visual 节点绕 Y 轴朝向期望方向时的插值速度。
@export_range(0.1, 30.0, 0.1, "or_greater")
var rotation_speed: float = 7.0

@export_category("Physics")
## 项目默认三维重力的倍率。
@export_range(0.0, 10.0, 0.1, "or_greater")
var gravity_multiplier: float = 1.0

@export_category("Targeting")
## 首次发现敌对单位的水平半径，单位为米。锁定保持半径由 AITargetingComponent 自动增加一米。
@export_range(0.1, 100.0, 0.1, "or_greater")
var targeting_radius: float = 6.0
## 进入战斗状态后切换使用的索敌半径，单位为米。0 表示战斗状态沿用 targeting_radius。
@export_range(0.0, 100.0, 0.5, "or_greater")
var combat_targeting_radius: float = 0.0

@onready var _movement_system: Node3D = $MovementSystem
@onready var _navigation_agent: NavigationAgent3D = \
	$MovementSystem/NavigationAgent3D
@onready var _visual_root: Node3D = $Visual
## CombatSystem 是可选的同级组件：具体单位场景自行挂载近战、远程或未来的其他战斗实现。
## 统一节点名保持为 CombatSystem，便于父类以相同接口获取，不让 AIUnitBase 绑定任一攻击类型。
@onready var _combat_system: AICombatSystem = get_node_or_null(^"CombatSystem") as AICombatSystem
@onready var _targeting_component: AITargetingComponent = \
	get_node_or_null(^"AITargetingComponent") as AITargetingComponent

var _gravity_force: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)
var _motion_state: MotionState = MotionState.IDLE
var _movement_target: Vector3 = Vector3.ZERO
var _movement_target_is_valid: bool = false
var _requested_maximum_speed: float = -1.0
var _face_movement_direction: bool = true
var _desired_facing_direction: Vector3 = Vector3.FORWARD

var _dash_target: Vector3 = Vector3.ZERO
var _dash_direction: Vector3 = Vector3.ZERO
var _dash_remaining_distance: float = 0.0
var _dash_cooldown_remaining: float = 0.0
var _recovery_remaining: float = 0.0
## 当前攻击动画请求的锁定水平位移方向。
var _attack_motion_direction: Vector3 = Vector3.ZERO
## 当前攻击位移的速度，单位为米/秒。
var _attack_motion_speed: float = 0.0
## 当前攻击位移尚未完成的真实水平距离。
var _attack_motion_remaining_distance: float = 0.0
## 命中卡刀期间仅暂停攻击位移，不暂停重力、GCD 或其他单位。
var _attack_motion_suspended: bool = false
var _ai_movement_ready: bool = false


func _ready() -> void:
	super._ready()
	_connect_death_lifecycle()
	_connect_combat_lifecycle()
	_ai_movement_ready = _validate_movement_nodes()
	if not _ai_movement_ready:
		push_error(
			"AIUnitBase: MovementSystem configuration is incomplete. Node="
			+ str(get_path())
		)
		set_physics_process(false)
		return
	_reset_motion_runtime_state()
	if is_instance_valid(_combat_system) and starting_weapon != null:
		_combat_system.set_starting_weapon(starting_weapon)
	if is_instance_valid(_combat_system) and not _combat_system.configure(self):
		push_error(
			"AIUnitBase: CombatSystem configuration failed. Node="
			+ str(get_path())
		)
	if is_instance_valid(_targeting_component):
		_targeting_component.configure(self, targeting_radius)


## 固定 AI 物理顺序：子类先提交意图，本类随后唯一地执行速度、重力、转向和碰撞移动。
func _physics_process(delta: float) -> void:
	if not _ai_movement_ready:
		return
	if is_dead():
		# 死亡期间不再运行子类 AI，只保留水平停止、重力和碰撞。
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return
	advance_hit_movement_lock(delta)
	if is_hit_movement_locked():
		## 受击停顿只冻结本帧水平移动，不清除状态机已提交的目标、冲刺或攻击请求。
		## 倒计时结束后 AI 会继续复用原有意图，重力与 CharacterBody3D 碰撞始终保持更新。
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return

	_update_ai_movement(delta)
	_update_dash_cooldown(delta)
	match _motion_state:
		MotionState.ATTACK_MOVING:
			_process_attack_motion(delta)
		MotionState.DASHING:
			_process_dash(delta)
		MotionState.RECOVERING:
			_process_recovery(delta)
		_:
			_process_regular_motion(delta)

	_apply_gravity(delta)
	_update_visual_facing(delta)
	var previous_position: Vector3 = global_position
	move_and_slide()
	match _motion_state:
		MotionState.ATTACK_MOVING:
			_update_attack_motion_after_slide(previous_position)
		MotionState.DASHING:
			_update_dash_after_slide(previous_position)


## 子类行为入口。默认 AI 没有主动行为，因此持续清空移动目标并平滑减速。
func _update_ai_movement(_delta: float) -> void:
	clear_movement_target()


## 提交持续移动目标。maximum_speed 为负数时使用根节点 Inspector 的 movement_speed。
func set_movement_target(
	target_position: Vector3,
	maximum_speed: float = -1.0,
	face_movement_direction: bool = true
) -> void:
	if is_dead():
		return
	_movement_target = target_position
	_movement_target_is_valid = true
	_requested_maximum_speed = maximum_speed
	_face_movement_direction = face_movement_direction
	if is_instance_valid(_navigation_agent):
		_navigation_agent.target_position = target_position


## 清除主动移动目标，但仍保留平滑减速、重力和视觉朝向执行。
func clear_movement_target() -> void:
	_movement_target_is_valid = false
	_requested_maximum_speed = -1.0
	_face_movement_direction = true
	if _motion_state == MotionState.MOVING:
		_motion_state = MotionState.IDLE


func has_movement_target() -> bool:
	return _movement_target_is_valid


## 返回当前提交给运动层的导航目标；没有有效目标时安全返回 Vector3.ZERO。
## 该接口只用于同队 AI 的占位扫描等只读场景，不提供改写入口。
func get_current_movement_target() -> Vector3:
	return _movement_target


## 返回当前移动请求是否允许运动层自动把视觉朝向改为移动方向。
func should_face_movement_direction() -> bool:
	return _face_movement_direction


## 设置世界空间期望朝向；垂直分量会被忽略。
func set_desired_facing(direction: Vector3) -> void:
	var horizontal_direction := Vector3(direction.x, 0.0, direction.z)
	if horizontal_direction.length_squared() > 0.0001:
		_desired_facing_direction = horizontal_direction.normalized()


## 立即将 Visual 的世界朝向对齐到指定水平方向；仅用于技能、攻击等必须从第一帧精确朝向目标的动作启动点。
## 参数 direction 为世界空间方向，Y 分量会被忽略；普通移动仍应使用 set_desired_facing() 保持平滑转向。
func snap_visual_facing(direction: Vector3) -> void:
	set_desired_facing(direction)
	if not is_instance_valid(_visual_root):
		return
	var horizontal_direction := Vector3(direction.x, 0.0, direction.z)
	if horizontal_direction.length_squared() <= 0.0001:
		return
	var normalized_direction := horizontal_direction.normalized()
	_visual_root.rotation.y = atan2(
		-normalized_direction.x,
		-normalized_direction.z
	)


## 请求一次由 AIUnitBase 唯一物理移动流程执行的攻击位移。
##
## 方向在请求时水平化并锁定；距离和速度分别使用米与米/秒。冲刺和冲刺恢复拥有
## 更高优先级，因此这两个阶段拒绝新的攻击位移。
func request_attack_motion(
	direction: Vector3,
	distance: float,
	speed: float
) -> bool:
	if (
		is_dead()
		or _motion_state == MotionState.DASHING
		or _motion_state == MotionState.RECOVERING
		or distance <= 0.0
		or speed <= 0.0
	):
		return false
	var horizontal_direction := Vector3(direction.x, 0.0, direction.z)
	if horizontal_direction.length_squared() <= 0.0001:
		return false

	clear_movement_target()
	_attack_motion_direction = horizontal_direction.normalized()
	_attack_motion_speed = speed
	_attack_motion_remaining_distance = distance
	_attack_motion_suspended = false
	_desired_facing_direction = _attack_motion_direction
	_motion_state = MotionState.ATTACK_MOVING
	return true


## 清除尚未完成的攻击推进，不影响重力、公共冷却或攻击动画本身。
func cancel_attack_motion() -> void:
	_attack_motion_direction = Vector3.ZERO
	_attack_motion_speed = 0.0
	_attack_motion_remaining_distance = 0.0
	_attack_motion_suspended = false
	if _motion_state == MotionState.ATTACK_MOVING:
		_motion_state = MotionState.IDLE
		velocity.x = 0.0
		velocity.z = 0.0


func is_attack_motion_active() -> bool:
	return (
		_motion_state == MotionState.ATTACK_MOVING
		and _attack_motion_remaining_distance > 0.0001
		and _attack_motion_speed > 0.0
		and _attack_motion_direction.length_squared() > 0.0001
	)


## 暂停或恢复当前攻击推进；方向、速度和剩余距离保持不变。
func set_attack_motion_suspended(active: bool) -> void:
	_attack_motion_suspended = active and is_attack_motion_active()


func is_attack_motion_suspended() -> bool:
	return _attack_motion_suspended


## 请求朝目标执行一次冲刺；冷却、恢复中或目标过近时返回 false。
func request_dash(target_position: Vector3) -> bool:
	if is_dead():
		return false
	if _motion_state == MotionState.ATTACK_MOVING:
		cancel_attack_motion()
	if not can_dash():
		return false
	var offset: Vector3 = target_position - global_position
	offset.y = 0.0
	if offset.length_squared() <= 0.01:
		return false

	_dash_target = target_position
	_dash_direction = offset.normalized()
	_dash_remaining_distance = minf(dash_max_distance, offset.length())
	_desired_facing_direction = _dash_direction
	_motion_state = MotionState.DASHING
	return true


func can_dash() -> bool:
	return (
		not is_dead()
		and _motion_state != MotionState.DASHING
		and _motion_state != MotionState.RECOVERING
		and _dash_cooldown_remaining <= 0.0
	)


func is_dashing() -> bool:
	return _motion_state == MotionState.DASHING


func is_recovering() -> bool:
	return _motion_state == MotionState.RECOVERING


func get_dash_cooldown_remaining() -> float:
	return _dash_cooldown_remaining


func is_ai_movement_ready() -> bool:
	return _ai_movement_ready


## 返回所有自动控制单位共用的战斗协调组件。
func get_combat_system() -> AICombatSystem:
	return _combat_system if is_instance_valid(_combat_system) else null


func _connect_death_lifecycle() -> void:
	if not died.is_connected(_on_ai_died):
		died.connect(_on_ai_died)
	if not revived.is_connected(_on_ai_revived):
		revived.connect(_on_ai_revived)


## 连接 UnitBase 的战斗状态信号，进出战斗时切换索敌半径。
func _connect_combat_lifecycle() -> void:
	if not combat_state_changed.is_connected(_on_combat_state_changed):
		combat_state_changed.connect(_on_combat_state_changed)


func _on_combat_state_changed(
	_previous_state: CombatState,
	current_state: CombatState
) -> void:
	if not is_instance_valid(_targeting_component):
		return
	if current_state == CombatState.IN_COMBAT:
		if combat_targeting_radius > 0.0:
			_targeting_component.set_targeting_radius(combat_targeting_radius)
	else:
		_targeting_component.set_targeting_radius(targeting_radius)


func _on_ai_died(_source: Node) -> void:
	# 只清理通用固定子节点，不依赖 AllyBase 或 EnemyBase 的具体实现。
	clear_movement_target()
	cancel_attack_motion()
	_reset_motion_runtime_state()
	velocity.x = 0.0
	velocity.z = 0.0

	var combat_system := get_node_or_null(^"CombatSystem")
	if combat_system != null and combat_system.has_method(&"cancel_current_action"):
		combat_system.call(&"cancel_current_action")
	var skill_host := get_node_or_null(^"SkillHost")
	if skill_host != null and skill_host.has_method(&"cancel_active_skill"):
		skill_host.call(&"cancel_active_skill", &"owner_died")
	var targeting_component := get_node_or_null(^"AITargetingComponent")
	if (
		targeting_component != null
		and targeting_component.has_method(&"clear_locked_target")
	):
		targeting_component.call(&"clear_locked_target")


func _on_ai_revived(
	_revived_health_value: float,
	_source: Node
) -> void:
	# 复活不恢复死亡前的导航、冲刺或攻击推进，只清理残余水平状态。
	_reset_motion_runtime_state()
	velocity.x = 0.0
	velocity.z = 0.0


func _process_regular_motion(delta: float) -> void:
	var desired_velocity := Vector3.ZERO
	if _movement_target_is_valid:
		var next_position: Vector3 = _get_next_navigation_position()
		var offset: Vector3 = next_position - global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > arrival_distance:
			var maximum_speed: float = (
				_requested_maximum_speed
				if _requested_maximum_speed >= 0.0
				else movement_speed
			)
			var speed_factor: float = clampf(
				distance / maxf(slowing_distance, 0.0001),
				0.0,
				1.0
			)
			desired_velocity = offset.normalized() * maximum_speed * speed_factor
			if _face_movement_direction:
				_desired_facing_direction = offset.normalized()
			_motion_state = MotionState.MOVING
		else:
			_motion_state = MotionState.IDLE
	else:
		_motion_state = MotionState.IDLE

	velocity.x = move_toward(
		velocity.x,
		desired_velocity.x,
		movement_acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		desired_velocity.z,
		movement_acceleration * delta
	)


## 使用锁定方向提交本帧攻击速度；真实位移在 move_and_slide() 后结算。
func _process_attack_motion(delta: float) -> void:
	if not is_attack_motion_active():
		cancel_attack_motion()
		return
	if _attack_motion_suspended:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var frame_speed: float = minf(
		_attack_motion_speed,
		_attack_motion_remaining_distance / maxf(delta, 0.000001)
	)
	velocity.x = _attack_motion_direction.x * frame_speed
	velocity.z = _attack_motion_direction.z * frame_speed


## 按实际碰撞后位移扣减剩余距离；撞墙时立即结束，避免持续向墙体无限推挤。
func _update_attack_motion_after_slide(previous_position: Vector3) -> void:
	if _attack_motion_suspended:
		return
	var displacement: Vector3 = global_position - previous_position
	var horizontal_distance := Vector2(displacement.x, displacement.z).length()
	_attack_motion_remaining_distance = maxf(
		_attack_motion_remaining_distance - horizontal_distance,
		0.0
	)
	if is_on_wall() or _attack_motion_remaining_distance <= 0.0001:
		cancel_attack_motion()


func _get_next_navigation_position() -> Vector3:
	_navigation_agent.target_position = _movement_target
	var next_position: Vector3 = _movement_target
	if not _navigation_agent.is_navigation_finished():
		var navigation_position: Vector3 = (
			_navigation_agent.get_next_path_position()
		)
		if navigation_position.distance_to(global_position) > arrival_distance:
			next_position = navigation_position
	return next_position


func _process_dash(delta: float) -> void:
	var target_offset: Vector3 = _dash_target - global_position
	target_offset.y = 0.0
	if (
		target_offset.length() <= dash_arrival_distance
		or _dash_remaining_distance <= 0.001
	):
		_finish_dash()
		return

	var speed_for_frame: float = minf(
		dash_speed,
		_dash_remaining_distance / maxf(delta, 0.000001)
	)
	velocity.x = move_toward(
		velocity.x,
		_dash_direction.x * speed_for_frame,
		dash_acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		_dash_direction.z * speed_for_frame,
		dash_acceleration * delta
	)


func _update_dash_after_slide(previous_position: Vector3) -> void:
	var displacement: Vector3 = global_position - previous_position
	var horizontal_distance := Vector2(displacement.x, displacement.z).length()
	_dash_remaining_distance = maxf(
		_dash_remaining_distance - horizontal_distance,
		0.0
	)
	if is_on_wall() or _dash_remaining_distance <= 0.001:
		_finish_dash()


func _finish_dash() -> void:
	_dash_remaining_distance = 0.0
	_dash_direction = Vector3.ZERO
	_recovery_remaining = dash_recovery_duration
	_dash_cooldown_remaining = dash_cooldown
	_motion_state = (
		MotionState.RECOVERING
		if _recovery_remaining > 0.0
		else MotionState.IDLE
	)


func _process_recovery(delta: float) -> void:
	_recovery_remaining = maxf(_recovery_remaining - delta, 0.0)
	velocity.x = move_toward(
		velocity.x,
		0.0,
		movement_acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		0.0,
		movement_acceleration * delta
	)
	if _recovery_remaining <= 0.0:
		_motion_state = MotionState.IDLE


func _update_dash_cooldown(delta: float) -> void:
	_dash_cooldown_remaining = maxf(
		_dash_cooldown_remaining - delta,
		0.0
	)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity_force * gravity_multiplier * delta
	else:
		velocity.y = -0.1


func _update_visual_facing(delta: float) -> void:
	if _desired_facing_direction.length_squared() <= 0.0001:
		return
	var target_yaw: float = atan2(
		-_desired_facing_direction.x,
		-_desired_facing_direction.z
	)
	_visual_root.rotation.y = lerp_angle(
		_visual_root.rotation.y,
		target_yaw,
		minf(rotation_speed * delta, 1.0)
	)


func _reset_motion_runtime_state() -> void:
	_motion_state = MotionState.IDLE
	_movement_target_is_valid = false
	_requested_maximum_speed = -1.0
	_face_movement_direction = true
	_dash_target = Vector3.ZERO
	_dash_direction = Vector3.ZERO
	_dash_remaining_distance = 0.0
	_dash_cooldown_remaining = 0.0
	_recovery_remaining = 0.0
	_attack_motion_direction = Vector3.ZERO
	_attack_motion_speed = 0.0
	_attack_motion_remaining_distance = 0.0
	_attack_motion_suspended = false


func _validate_movement_nodes() -> bool:
	if (
		not is_instance_valid(_movement_system)
		or not is_instance_valid(_navigation_agent)
		or not is_instance_valid(_visual_root)
	):
		return false
	if not _movement_system.transform.is_equal_approx(Transform3D.IDENTITY):
		push_warning(
			"AIUnitBase: MovementSystem should keep an identity transform. Node="
			+ str(get_path())
		)
	return true
