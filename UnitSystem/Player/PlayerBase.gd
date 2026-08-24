class_name PlayerBase
extends UnitBase

## 玩家控制单位的基础实现。
##
## 本脚本只读取移动 InputMap 并处理移动、冲刺、重力和最终视觉朝向。目标锁定由
## 可选的 PlayerTargetingComponent 提供；攻击、摄像机与视觉特效仍由其他组件承担，
## 避免再次形成综合控制器。

@export_category("Equipment")
## Hero 或其他玩家单位进入运行树后自动装配的武器数据。
## 设计师只需要在玩家单位根节点配置一次。
@export var starting_weapon: WeaponData

## PlayerBase 当前锁定的敌方目标发生变化时转发。
##
## 该信号是面向 UI、技能和伙伴管控系统的稳定入口，使外部系统无需依赖索敌组件
## 在场景树中的具体路径。target 为 null 表示锁定已经解除。
signal locked_target_changed(target: UnitBase)

const MOVE_LEFT_ACTION: StringName = &"player_move_left"
const MOVE_RIGHT_ACTION: StringName = &"player_move_right"
const MOVE_FORWARD_ACTION: StringName = &"player_move_forward"
const MOVE_BACKWARD_ACTION: StringName = &"player_move_backward"
const DASH_ACTION: StringName = &"player_dash"
## PlayerBase 使用固定、稳定的索敌组件装配路径，不向 Inspector 暴露重复配置。
## 节点被删除时仍通过 get_node_or_null() 安全降级，玩家移动和冲刺不受影响。
const TARGETING_SYSTEM_PATH: NodePath = ^"TargetingSystem"

@export_category("Movement")
@export_range(0.1, 20.0, 0.1, "or_greater")
var movement_speed: float = 4.0
@export_range(0.1, 100.0, 0.1, "or_greater")
var movement_acceleration: float = 24.0
@export_range(0.1, 30.0, 0.1, "or_greater")
var visual_rotation_speed: float = 12.0

@export_category("Dash")
@export_range(0.1, 20.0, 0.1, "or_greater")
var dash_distance: float = 2.5
@export_range(0.1, 50.0, 0.1, "or_greater")
var dash_speed: float = 10.0
@export_range(1, 10, 1, "or_greater")
var maximum_consecutive_dashes: int = 2
@export_range(0.0, 30.0, 0.1, "or_greater")
var dash_cooldown_duration: float = 2.0
## 冲刺开始阶段免疫常规伤害所占的比例，取值为 0.0 至 1.0。
## 默认 0.5 表示冲刺前半段无敌；设为 0 会关闭无敌，设为 1 则整个冲刺免伤。
## 该参数仅影响 PlayerBase 对 apply_damage() 的处理，不改变碰撞、位移、攻击取消或冲刺冷却。
@export_range(0.0, 1.0, 0.01)
var dash_invulnerability_ratio: float = 0.5

@export_category("Physics")
@export_range(0.0, 10.0, 0.1, "or_greater")
var gravity_multiplier: float = 1.0

@onready var _visual_root: Node3D = $Visual
@onready var _targeting_component: Node = get_node_or_null(
	TARGETING_SYSTEM_PATH
)

## 最后一次有效玩家输入方向保持公开，供友方编队在视觉节点不可用时读取。
var last_movement_direction: Vector3 = Vector3.FORWARD

var _gravity_force: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)
var _dash_direction: Vector3 = Vector3.ZERO
var _dash_remaining_distance: float = 0.0
## 当前冲刺剩余距离大于此阈值时处于无敌阶段。
## 阈值在冲刺启动时按当次实际 dash_distance 锁定，避免运行中调整 Inspector 数值影响已开始的冲刺。
var _dash_invulnerability_end_distance: float = 0.0
var _available_dash_count: int = 0
var _dash_cooldown_remaining: float = 0.0
## 与攻击位移分开维护的常规水平速度，避免每帧把攻击速度重复累加到 velocity。
var _regular_horizontal_velocity: Vector2 = Vector2.ZERO
var _attack_motion_direction: Vector3 = Vector3.ZERO
var _attack_motion_speed: float = 0.0
var _attack_motion_remaining_distance: float = 0.0
var _attack_motion_suspended: bool = false
## 由 GameRunController 在房间结算时维护的运行时输入许可。
## false 时仅屏蔽新的移动和冲刺输入；重力、碰撞、相机跟随与已开始的动作仍按原流程更新。
var _player_input_enabled: bool = true


func _ready() -> void:
	super._ready()
	_available_dash_count = maxi(maximum_consecutive_dashes, 1)
	if not is_instance_valid(_visual_root):
		push_error("PlayerBase: Visual node is missing. Node=" + str(get_path()))
		set_physics_process(false)
	var attack_controller := get_node_or_null(^"AttackController")
	if attack_controller != null and attack_controller.has_method(&"set_starting_weapon"):
		attack_controller.call("set_starting_weapon", starting_weapon)
	_configure_targeting_component()
	_connect_death_lifecycle()


func _physics_process(delta: float) -> void:
	if is_dead():
		# 死亡单位仍保留 CharacterBody3D 的重力和碰撞，只停止水平行动。
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return

	_update_dash_cooldown(delta)
	advance_hit_movement_lock(delta)
	if is_hit_movement_locked():
		## 受击只暂停水平行动；Dash 的剩余距离会因未产生实际位移而保留，
		## 停顿结束后可继续原冲刺，重力与碰撞则始终按正常物理流程运行。
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return
	var input_vector := Vector2.ZERO
	if _player_input_enabled:
		input_vector = Input.get_vector(
			MOVE_LEFT_ACTION,
			MOVE_RIGHT_ACTION,
			MOVE_FORWARD_ACTION,
			MOVE_BACKWARD_ACTION
		)
	var movement_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	if movement_direction.length_squared() > 0.0001:
		last_movement_direction = movement_direction.normalized()

	if (
		_player_input_enabled
		and Input.is_action_just_pressed(DASH_ACTION)
		and _can_start_dash()
	):
		_start_dash(movement_direction)

	if is_player_dashing():
		_process_dash(delta)
	else:
		_process_regular_movement(delta, movement_direction)
		_apply_attack_motion_velocity(delta)
	_apply_gravity(delta)

	# 锁定目标只覆盖视觉朝向，不修改本帧移动速度或冲刺方向。组件缺失或没有有效
	# 目标时，自动回退到原有的冲刺/移动朝向。
	var facing_direction := Vector3.ZERO
	if is_instance_valid(_targeting_component):
		var target_direction: Variant = _targeting_component.call(
			"get_locked_target_direction"
		)
		if target_direction is Vector3:
			facing_direction = target_direction
	if facing_direction.length_squared() <= 0.0001:
		facing_direction = (
			_dash_direction if is_player_dashing() else movement_direction
		)
	if facing_direction.length_squared() > 0.0001:
		_rotate_visual_toward(facing_direction, delta)

	var previous_position: Vector3 = global_position
	move_and_slide()
	if is_player_dashing():
		_update_dash_distance(previous_position, movement_direction)


func is_player_dashing() -> bool:
	return _dash_remaining_distance > 0.001


## 返回玩家当前是否正处于冲刺前段的常规伤害免疫期。
## 无敌仅在冲刺仍有效且剩余距离尚未越过启动时锁定的阈值时成立；
## 冲刺撞墙、完成、死亡或复活均会清除冲刺，因此会立即返回 false。
func is_dash_invulnerable() -> bool:
	return (
		is_player_dashing()
		and _dash_remaining_distance > _dash_invulnerability_end_distance
	)


## 覆盖 UnitBase 的常规受伤入口，以实现玩家冲刺无敌。
## amount 为请求伤害值，source 为可选伤害来源；无敌期间返回 0 且不发送受伤、血条或死亡信号。
## 非无敌阶段完全复用 UnitBase 的伤害结算，确保防御、死亡和其他系统保持同一条逻辑链路。
## 参数 threat_multiplier 只负责在玩家作为敌方伤害接收者时继续透传统一仇恨语义；它不影响玩家的无敌判定或实际受伤量。
func apply_damage(
	amount: float,
	source: Node = null,
	threat_multiplier: float = 1.0
) -> float:
	if is_dash_invulnerable():
		return 0.0
	return super.apply_damage(amount, source, threat_multiplier)


## 允许或禁止玩家发起新的本地输入请求。
## enabled 为 false 时，移动、冲刺、攻击和锁定输入均不会再触发；不会暂停世界，也不会取消已开始的攻击或冲刺。
## 此接口由上层游戏流程调用，不作为 Inspector 参数暴露，避免运行时结算状态被手动覆盖。
func set_player_input_enabled(enabled: bool) -> void:
	_player_input_enabled = enabled
	var attack_controller := get_node_or_null(^"AttackController")
	if attack_controller != null and attack_controller.has_method(&"set_input_enabled"):
		attack_controller.call("set_input_enabled", enabled)
	if _targeting_component != null and _targeting_component.has_method(&"set_input_enabled"):
		_targeting_component.call("set_input_enabled", enabled)


## 返回当前是否允许玩家发起新的移动、攻击、冲刺和锁定输入。
## 仅用于 GameRunController 与 Inspector 外的调试查询；返回 false 不代表单位死亡或世界暂停。
func is_player_input_enabled() -> bool:
	return _player_input_enabled


func get_available_dash_count() -> int:
	return _available_dash_count


func get_dash_cooldown_remaining() -> float:
	return _dash_cooldown_remaining


## 请求一次受 CharacterBody3D 碰撞约束的攻击前进位移。
##
## direction 会在请求时水平化并锁定；后续角色转向不会让同一段攻击轨迹弯曲。
## distance 和 speed 分别使用米与米/秒。冲刺拥有更高优先级，因此冲刺期间拒绝请求。
func request_attack_motion(
	direction: Vector3,
	distance: float,
	speed: float
) -> bool:
	if is_dead() or is_player_dashing() or distance <= 0.0 or speed <= 0.0:
		return false
	var horizontal_direction := Vector3(direction.x, 0.0, direction.z)
	if horizontal_direction.length_squared() <= 0.0001:
		return false
	_attack_motion_direction = horizontal_direction.normalized()
	_attack_motion_remaining_distance = distance
	_attack_motion_speed = speed
	_attack_motion_suspended = false
	return true


## 立即清除尚未完成的攻击位移，不影响当前攻击动画或常规移动。
func cancel_attack_motion() -> void:
	_attack_motion_direction = Vector3.ZERO
	_attack_motion_speed = 0.0
	_attack_motion_remaining_distance = 0.0
	_attack_motion_suspended = false


func is_attack_motion_active() -> bool:
	return (
		_attack_motion_remaining_distance > 0.0001
		and _attack_motion_speed > 0.0
		and _attack_motion_direction.length_squared() > 0.0001
	)


func get_attack_motion_remaining_distance() -> float:
	return _attack_motion_remaining_distance


## 暂停或恢复当前攻击推进，不清除方向、速度或剩余距离。
##
## 该接口只控制攻击附加位移；玩家常规移动、重力与冲刺仍由原流程处理。
func set_attack_motion_suspended(active: bool) -> void:
	_attack_motion_suspended = active and is_attack_motion_active()


## 返回当前攻击推进是否被外部反馈系统局部暂停。
func is_attack_motion_suspended() -> bool:
	return _attack_motion_suspended


## 返回 marker 触发瞬间角色视觉所面对的水平世界方向。
##
## 锁定目标与普通移动都已经通过 PlayerBase 的现有逻辑更新 Visual 朝向，因此攻击
## 控制器不需要重复判断目标或输入方向。
func get_attack_forward_direction() -> Vector3:
	if is_instance_valid(_visual_root):
		var visual_forward: Vector3 = -_visual_root.global_transform.basis.z
		visual_forward.y = 0.0
		if visual_forward.length_squared() > 0.0001:
			return visual_forward.normalized()
	var fallback := Vector3(
		last_movement_direction.x,
		0.0,
		last_movement_direction.z
	)
	return fallback.normalized() if fallback.length_squared() > 0.0001 else Vector3.FORWARD


## 返回索敌组件当前维护的锁定目标。
##
## 组件未装配或已经被卸载时安全返回 null，调用者不需要自行检查节点路径。
func get_locked_target() -> UnitBase:
	if not is_instance_valid(_targeting_component):
		return null
	return _targeting_component.call("get_locked_target") as UnitBase


## 通过 PlayerBase 稳定接口解除当前锁定。
##
## 组件未装配时该方法为空操作，确保外部 UI 或技能清理流程可以始终安全调用。
func clear_locked_target() -> void:
	if is_instance_valid(_targeting_component):
		_targeting_component.call("clear_locked_target")


func _configure_targeting_component() -> void:
	if not is_instance_valid(_targeting_component):
		return
	if (
		_targeting_component.has_signal(&"locked_target_changed")
		and not _targeting_component.is_connected(
			&"locked_target_changed",
			_on_targeting_locked_target_changed
		)
	):
		_targeting_component.connect(
			&"locked_target_changed",
			_on_targeting_locked_target_changed
		)
	if _targeting_component.has_method(&"configure"):
		_targeting_component.call("configure", self)


func _connect_death_lifecycle() -> void:
	if not died.is_connected(_on_player_died):
		died.connect(_on_player_died)
	if not revived.is_connected(_on_player_revived):
		revived.connect(_on_player_revived)


func _on_player_died(_source: Node) -> void:
	# 死亡只收束运行时动作，不改写 Inspector 中的行动资格开关。
	cancel_attack_motion()
	_dash_remaining_distance = 0.0
	_dash_invulnerability_end_distance = 0.0
	_dash_direction = Vector3.ZERO
	_regular_horizontal_velocity = Vector2.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	clear_locked_target()

	var attack_controller := get_node_or_null(^"AttackController")
	if attack_controller != null and attack_controller.has_method(&"cancel_combo"):
		attack_controller.call(&"cancel_combo")
	var skill_host := get_node_or_null(^"SkillHost")
	if skill_host != null and skill_host.has_method(&"cancel_active_skill"):
		skill_host.call(&"cancel_active_skill", &"owner_died")


func _on_player_revived(
	_revived_health_value: float,
	_source: Node
) -> void:
	# 复活只恢复接受新请求的资格，旧冲刺、攻击位移和水平速度不会恢复。
	cancel_attack_motion()
	_dash_remaining_distance = 0.0
	_dash_invulnerability_end_distance = 0.0
	_dash_direction = Vector3.ZERO
	_regular_horizontal_velocity = Vector2.ZERO
	velocity.x = 0.0
	velocity.z = 0.0


func _on_targeting_locked_target_changed(target: UnitBase) -> void:
	locked_target_changed.emit(target)


func _process_regular_movement(delta: float, direction: Vector3) -> void:
	_regular_horizontal_velocity.x = move_toward(
		_regular_horizontal_velocity.x,
		direction.x * movement_speed,
		movement_acceleration * delta
	)
	_regular_horizontal_velocity.y = move_toward(
		_regular_horizontal_velocity.y,
		direction.z * movement_speed,
		movement_acceleration * delta
	)
	velocity.x = _regular_horizontal_velocity.x
	velocity.z = _regular_horizontal_velocity.y


func _start_dash(input_direction: Vector3) -> void:
	var attack_controller := get_node_or_null(^"AttackController")
	if (
		attack_controller != null
		and attack_controller.has_method(&"interrupt_attack_for_dash")
	):
		attack_controller.call(
			"interrupt_attack_for_dash",
			dash_distance / maxf(dash_speed, 0.000001)
		)
	# 冲刺优先级高于攻击位移，开始冲刺时立即清除剩余攻击推进。
	cancel_attack_motion()
	_dash_direction = (
		input_direction.normalized()
		if input_direction.length_squared() > 0.0001
		else last_movement_direction.normalized()
	)
	_dash_remaining_distance = dash_distance
	_dash_invulnerability_end_distance = dash_distance * (
		1.0 - clampf(dash_invulnerability_ratio, 0.0, 1.0)
	)
	_available_dash_count = maxi(_available_dash_count - 1, 0)


func _process_dash(delta: float) -> void:
	var frame_speed: float = minf(
		dash_speed,
		_dash_remaining_distance / maxf(delta, 0.000001)
	)
	velocity.x = _dash_direction.x * frame_speed
	velocity.z = _dash_direction.z * frame_speed


func _update_dash_distance(
	previous_position: Vector3,
	input_direction: Vector3
) -> void:
	var frame_displacement: Vector3 = global_position - previous_position
	var horizontal_distance := Vector2(
		frame_displacement.x,
		frame_displacement.z
	).length()
	_dash_remaining_distance = maxf(
		_dash_remaining_distance - horizontal_distance,
		0.0
	)
	if is_on_wall() or _dash_remaining_distance <= 0.001:
		_finish_dash(input_direction)


func _finish_dash(input_direction: Vector3) -> void:
	_dash_remaining_distance = 0.0
	_dash_invulnerability_end_distance = 0.0
	_dash_direction = Vector3.ZERO
	_regular_horizontal_velocity = Vector2(
		input_direction.x * movement_speed,
		input_direction.z * movement_speed
	)
	velocity.x = _regular_horizontal_velocity.x
	velocity.z = _regular_horizontal_velocity.y
	if _available_dash_count <= 0:
		_dash_cooldown_remaining = dash_cooldown_duration


func _can_start_dash() -> bool:
	return (
		not is_dead()
		and not is_player_dashing()
		and _available_dash_count > 0
	)


func _update_dash_cooldown(delta: float) -> void:
	if _dash_cooldown_remaining <= 0.0:
		return
	_dash_cooldown_remaining = maxf(_dash_cooldown_remaining - delta, 0.0)
	if _dash_cooldown_remaining <= 0.0:
		_available_dash_count = maxi(maximum_consecutive_dashes, 1)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity_force * gravity_multiplier * delta
	else:
		velocity.y = -0.1


func _apply_attack_motion_velocity(delta: float) -> void:
	if not is_attack_motion_active() or _attack_motion_suspended:
		return
	var safe_delta: float = maxf(delta, 0.000001)
	var frame_speed: float = minf(
		_attack_motion_speed,
		_attack_motion_remaining_distance / safe_delta
	)
	velocity.x += _attack_motion_direction.x * frame_speed
	velocity.z += _attack_motion_direction.z * frame_speed
	# 消耗名义位移而不是强制修改 global_position。发生墙壁碰撞时 move_and_slide()
	# 会阻挡实际移动，但本次推进仍按正常时长结束，不会持续卡在墙上无限推挤。
	_attack_motion_remaining_distance = maxf(
		_attack_motion_remaining_distance - frame_speed * delta,
		0.0
	)
	if _attack_motion_remaining_distance <= 0.0001:
		_attack_motion_direction = Vector3.ZERO
		_attack_motion_speed = 0.0


func _rotate_visual_toward(direction: Vector3, delta: float) -> void:
	var target_yaw: float = atan2(-direction.x, -direction.z)
	_visual_root.rotation.y = lerp_angle(
		_visual_root.rotation.y,
		target_yaw,
		minf(visual_rotation_speed * delta, 1.0)
	)
