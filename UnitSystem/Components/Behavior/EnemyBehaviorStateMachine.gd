class_name EnemyBehaviorStateMachine
extends Node

## 敌方单位的行为决策层：只读取唯一锁定目标，并提交移动或攻击请求。
## 不保存第二份目标，不处理导航、武器动画、命中、伤害或物理移动。

enum State { IDLE, CHASE, ATTACK, RETURN_HOME }
## 敌人在未发现目标时采用的守卫行为；只影响 IDLE 状态，不影响战斗距离内的战斗游荡。
enum IdleBehavior { STATIONARY, WANDER_AROUND_HOME }

signal state_changed(previous_state: State, current_state: State)

## 攻击游荡的内部计时区间下限，单位为秒。
const COMBAT_WANDER_INTERVAL_MIN: float = 1.5
## 攻击游荡的内部计时区间上限，单位为秒。
const COMBAT_WANDER_INTERVAL_MAX: float = 3.0
## 攻击游荡时相对 movement_speed 的速度倍率，用于压低绕行速度。
const COMBAT_WANDER_SPEED_MULTIPLIER: float = 0.45
## 单次游荡刷新最多生成的候选数量。
const MAXIMUM_CANDIDATE_ATTEMPTS: int = 8

@export_category("Leash")
## 敌人与出生点的水平距离超过该值时，立即取消战斗并返回出生点。
## 单位为米；默认 12m，适用于所有处于 CHASE 或 ATTACK 状态的敌人。
@export_range(0.5, 100.0, 0.1, "or_greater")
var leash_distance: float = 12.0
## 返回出生点到该距离内时，判定归位完成。
## 单位为米；默认 0.25m，归位后立即恢复正常索敌。
@export_range(0.05, 5.0, 0.05, "or_greater")
var home_arrival_distance: float = 0.25

@export_category("Attack Entry")
## 敌人每次从追击真实进入武器攻击范围时，写入现有公共冷却的随机延迟下限，单位为秒。
## 默认 0 秒；只错开进入攻击范围后的第一轮普攻，不改变后续公共冷却、技能、动画前摇或攻击频率。
@export_range(0.0, 5.0, 0.05)
var attack_entry_delay_min: float = 0.0
## 敌人每次从追击真实进入武器攻击范围时，写入现有公共冷却的随机延迟上限，单位为秒。
## 默认 0.5 秒；运行时自动确保不低于下限，并通过公共冷却既有的最大值规则避免与未结束冷却累加。
@export_range(0.0, 5.0, 0.05)
var attack_entry_delay_max: float = 0.5

@export_category("Idle Behavior")
## 未发现有效目标时的待机方式；默认在出生点附近游荡，静止模式会清除所有待机移动目标。
@export var idle_behavior: IdleBehavior = IdleBehavior.WANDER_AROUND_HOME
## 待机游荡点相对出生点的最大水平半径，单位为米；默认 0.8m，仅在游荡模式生效。
@export_range(0.0, 20.0, 0.05)
var idle_wander_radius: float = 0.8
## 抵达待机游荡点后，重新选择下一点前的最短等待时间，单位为秒；默认 1.5s。
@export_range(0.0, 20.0, 0.05)
var idle_wander_interval_min: float = 1.5
## 抵达待机游荡点后，重新选择下一点前的最长等待时间，单位为秒；默认 3.0s，运行时自动不小于最短值。
@export_range(0.0, 20.0, 0.05)
var idle_wander_interval_max: float = 3.0
## 待机游荡速度相对 AIUnitBase.movement_speed 的倍率；默认 0.35，仅在游荡模式生效。
@export_range(0.0, 1.0, 0.05)
var idle_wander_speed_multiplier: float = 0.35

@export_category("Combat Position")
## 攻击冷却期间单次游荡相对当前位置的最大步长，单位为米；0 表示不游荡。
@export_range(0.0, 5.0, 0.05)
var combat_wander_radius: float = 1.1
## 新游荡点与同队敌人当前/预定位置之间允许的最小水平间距，单位为米。
## 该值是设计师可调的参考值；实际候选评分只读取本参数，不内置固定数值。
@export_range(0.0, 5.0, 0.05)
var minimum_reserved_spacing: float = 0.45

var _owner_body: AIUnitBase
var _targeting: AITargetingComponent
var _combat: AICombatSystem
var _home_position := Vector3.ZERO
var _current_state: State = State.IDLE
var _configured := false
var _movement_target: Vector3 = Vector3.ZERO
var _combat_wander_target: Vector3 = Vector3.ZERO
var _combat_wander_target_valid: bool = false
var _wander_timer: float = 0.0
var _idle_wander_target: Vector3 = Vector3.ZERO
var _idle_wander_target_valid: bool = false
var _idle_wander_timer: float = 0.0
var _random_generator := RandomNumberGenerator.new()


## 注入敌人持有者、唯一的锁定目标组件与可选战斗组件。
## owner_body 决定出生点和移动执行；targeting_component 是唯一目标来源；
## combat_system 可为空以支持暂未装配武器的敌人。
func configure(owner_body: AIUnitBase, targeting_component: AITargetingComponent, combat_system: AICombatSystem) -> bool:
	if not is_instance_valid(owner_body) or not is_instance_valid(targeting_component):
		push_error("EnemyBehaviorStateMachine: owner and targeting are required.")
		return false
	_owner_body = owner_body
	_targeting = targeting_component
	_combat = combat_system
	_home_position = _owner_body.global_position
	_current_state = State.IDLE
	_owner_body.exit_combat()
	_configured = true
	_random_generator.randomize()
	_combat_wander_target_valid = false
	_wander_timer = 0.0
	if not _owner_body.died.is_connected(_on_owner_died):
		_owner_body.died.connect(_on_owner_died)
	if not _owner_body.revived.is_connected(_on_owner_revived):
		_owner_body.revived.connect(_on_owner_revived)
	return true


## 每个物理帧由 EnemyBase 调用一次；delta 当前不参与额外计时，保留该参数以统一 AI 行为组件的物理更新接口。
func physics_tick(delta: float) -> void:
	if not _configured or not is_instance_valid(_owner_body) or _owner_body.is_dead():
		return
	if _current_state == State.RETURN_HOME:
		_update_return_home()
		return
	if _is_outside_leash():
		_begin_return_home()
		return
	var target := _targeting.get_locked_target() if is_instance_valid(_targeting) else null
	if not is_instance_valid(target):
		if _current_state != State.IDLE:
			_begin_return_home()
		else:
			_update_idle_behavior(delta)
		return
	_clear_idle_wander()
	var attack_range := _get_attack_range()
	if attack_range <= 0.0:
		_owner_body.clear_movement_target()
		return
	var attack_tolerance := _get_attack_range_tolerance()
	if _horizontal_distance(_owner_body.global_position, target.global_position) > attack_range + attack_tolerance:
		_transition_to(State.CHASE)
		var direction := _direction_to_target(target)
		var ring_position := target.global_position - direction * attack_range
		ring_position.y = _owner_body.global_position.y
		_movement_target = ring_position
		_owner_body.set_movement_target(ring_position, -1.0, true)
		_owner_body.set_desired_facing(direction)
		return

	_transition_to(State.ATTACK)
	_owner_body.set_desired_facing(_direction_to_target(target))
	if is_instance_valid(_combat) and _combat.is_attacking():
		_clear_combat_wander()
		return
	if (
		is_instance_valid(_combat)
		and _combat.is_global_cooldown_ready()
		and not _combat.is_attacking()
	):
		if _combat.request_basic_attack(target) and _combat.is_attacking():
			_clear_combat_wander()
			return
	_submit_combat_wander_movement(target, delta)


## 返回当前行为状态，供调试界面与外部策略读取。
func get_current_state() -> State:
	return _current_state


## 返回运行时记录的出生点世界坐标。
func get_home_position() -> Vector3:
	return _home_position


func _begin_return_home() -> void:
	if is_instance_valid(_combat):
		_combat.cancel_current_action()
	if is_instance_valid(_targeting):
		_targeting.suspend_detection(999999.0, true)
	_clear_idle_wander()
	_clear_combat_wander()
	_owner_body.set_movement_target(_home_position)
	_transition_to(State.RETURN_HOME)


func _update_return_home() -> void:
	if _horizontal_distance(_owner_body.global_position, _home_position) > home_arrival_distance:
		_owner_body.set_movement_target(_home_position)
		return
	_owner_body.clear_movement_target()
	if is_instance_valid(_targeting):
		_targeting.resume_detection()
	_transition_to(State.IDLE)


## 根据当前待机枚举提交静止或出生点周围游荡；只在没有有效锁定目标的 IDLE 状态调用。
func _update_idle_behavior(delta: float) -> void:
	if idle_behavior == IdleBehavior.STATIONARY:
		_clear_idle_wander()
		return
	if not _idle_wander_target_valid:
		_select_new_idle_wander_target()
	_submit_idle_wander_movement(delta)


## 以出生点为中心生成候选点，并强制限制在配置半径内；便于测试子类提供确定性候选点。
func _select_new_idle_wander_target() -> void:
	var candidate := _generate_idle_wander_candidate()
	var offset := candidate - _home_position
	offset.y = 0.0
	var radius := maxf(idle_wander_radius, 0.0)
	if offset.length() > radius and offset.length_squared() > 0.0001:
		candidate = _home_position + offset.normalized() * radius
	candidate.y = _owner_body.global_position.y
	_idle_wander_target = candidate
	_idle_wander_target_valid = true
	_idle_wander_timer = _random_generator.randf_range(
		minf(idle_wander_interval_min, idle_wander_interval_max),
		maxf(idle_wander_interval_min, idle_wander_interval_max)
	)


## 提交待机移动；抵达后等待既定间隔才刷新目标点，避免持续快速抖动。
func _submit_idle_wander_movement(delta: float) -> void:
	if _horizontal_distance(_owner_body.global_position, _idle_wander_target) > _owner_body.arrival_distance:
		var speed := _owner_body.movement_speed * clampf(idle_wander_speed_multiplier, 0.0, 1.0)
		_owner_body.set_movement_target(_idle_wander_target, speed, true)
		return
	_idle_wander_timer = maxf(_idle_wander_timer - delta, 0.0)
	if _idle_wander_timer <= 0.0:
		_select_new_idle_wander_target()
	_owner_body.set_movement_target(
		_idle_wander_target,
		_owner_body.movement_speed * clampf(idle_wander_speed_multiplier, 0.0, 1.0),
		true
	)


## 生成出生点半径内的随机水平候选点；本方法可由测试子类覆写以固定随机结果。
func _generate_idle_wander_candidate() -> Vector3:
	var radius := _random_generator.randf_range(0.0, maxf(idle_wander_radius, 0.0))
	var angle := _random_generator.randf_range(0.0, TAU)
	return _home_position + Vector3(cos(angle), 0.0, sin(angle)) * radius


## 清理待机游荡的运行时目标与计时，并撤销其对 AIUnitBase 的移动请求。
func _clear_idle_wander() -> void:
	_idle_wander_target = Vector3.ZERO
	_idle_wander_target_valid = false
	_idle_wander_timer = 0.0
	if is_instance_valid(_owner_body):
		_owner_body.clear_movement_target()


## 攻击冷却期间提交低速游荡；候选点随机生成在目标附近，不受来向方向限制。
func _submit_combat_wander_movement(target: UnitBase, delta: float) -> void:
	if not is_instance_valid(target):
		return
	_wander_timer -= delta
	if (
		not _combat_wander_target_valid
		or (
			_wander_timer <= 0.0
			and _owner_body.global_position.distance_to(
				_combat_wander_target
			) <= _owner_body.slowing_distance
		)
	):
		_select_new_combat_wander_target(target)
	_movement_target = _combat_wander_target
	var orbit_speed: float = (
		_owner_body.movement_speed
		* clampf(COMBAT_WANDER_SPEED_MULTIPLIER, 0.0, 1.0)
	)
	_owner_body.set_movement_target(_movement_target, orbit_speed, false)
	_owner_body.set_desired_facing(_direction_to_target(target))


func _select_new_combat_wander_target(target: UnitBase) -> void:
	var occupied_positions: Array[Vector3] = (
		_collect_combat_occupied_positions()
	)
	var required_spacing: float = maxf(minimum_reserved_spacing, 0.0)
	var attempt_count: int = maxi(MAXIMUM_CANDIDATE_ATTEMPTS, 1)
	var selected_candidate: Vector3 = _combat_wander_target
	var best_candidate: Vector3 = selected_candidate
	var best_clearance: float = -1.0
	var has_best_candidate: bool = false

	for _attempt: int in range(attempt_count):
		var candidate: Vector3 = _generate_combat_wander_candidate(target)
		var clearance: float = _calculate_candidate_clearance(
			candidate,
			occupied_positions
		)
		if not has_best_candidate or clearance > best_clearance:
			best_candidate = candidate
			best_clearance = clearance
			has_best_candidate = true
		if clearance >= required_spacing:
			selected_candidate = candidate
			has_best_candidate = false
			break

	## 所有候选都偏挤时，不把单位强推出攻击范围；使用本轮最宽松候选。
	if has_best_candidate:
		selected_candidate = best_candidate

	_combat_wander_target = selected_candidate
	_combat_wander_target.y = _owner_body.global_position.y
	_combat_wander_target_valid = true
	_reset_wander_timer()


## 生成一个目标附近的随机游荡候选点；子类可在测试中替换随机来源。
func _generate_combat_wander_candidate(target: UnitBase) -> Vector3:
	var attack_range: float = maxf(_get_attack_range(), 0.1)
	var tolerance: float = maxf(_get_attack_range_tolerance(), 0.0)
	var minimum_radius: float = maxf(attack_range - tolerance, 0.1)
	var maximum_radius: float = maxf(attack_range + tolerance, minimum_radius)
	var wander_radius: float = maxf(combat_wander_radius, 0.0)
	var step_distance: float = 0.0
	if wander_radius > 0.0:
		var minimum_step: float = minf(
			wander_radius,
			maxf(
				wander_radius * 0.35,
				_owner_body.arrival_distance + 0.05
			)
		)
		step_distance = _random_generator.randf_range(
			minimum_step,
			wander_radius
		)
	var step_angle: float = _random_generator.randf_range(0.0, TAU)
	var offset := Vector3(
		cos(step_angle),
		0.0,
		sin(step_angle)
	) * step_distance
	var candidate := _owner_body.global_position + offset
	var to_target: Vector3 = candidate - target.global_position
	to_target.y = 0.0
	var target_distance: float = to_target.length()
	if target_distance > 0.0001:
		candidate = (
			target.global_position
			+ to_target.normalized()
			* clampf(target_distance, minimum_radius, maximum_radius)
		)
	else:
		candidate = target.global_position + Vector3.FORWARD * minimum_radius
	candidate.y = _owner_body.global_position.y
	return candidate


func _collect_combat_occupied_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if not is_instance_valid(_owner_body) or _owner_body.team_id == 0:
		return positions
	var tree := get_tree()
	var scene_root: Node = tree.current_scene if tree != null else null
	if not is_instance_valid(scene_root) and tree != null:
		scene_root = tree.root
	if is_instance_valid(scene_root):
		_append_same_team_enemy_occupancy(scene_root, positions)
	return positions


func _append_same_team_enemy_occupancy(
	node: Node,
	positions: Array[Vector3]
) -> void:
	var enemy_unit := node as EnemyBase
	if (
		enemy_unit != null
		and enemy_unit != _owner_body
		and enemy_unit.team_id != 0
		and enemy_unit.team_id == _owner_body.team_id
	):
		positions.append(enemy_unit.global_position)
		if enemy_unit.has_movement_target():
			positions.append(enemy_unit.get_current_movement_target())
	for child: Node in node.get_children():
		_append_same_team_enemy_occupancy(child, positions)


func _calculate_candidate_clearance(
	candidate_world: Vector3,
	occupied_positions: Array[Vector3]
) -> float:
	var clearance: float = INF
	for occupied_position: Vector3 in occupied_positions:
		clearance = minf(
			clearance,
			_horizontal_distance(candidate_world, occupied_position)
		)
	return clearance


func _clear_combat_wander() -> void:
	_combat_wander_target_valid = false
	_wander_timer = 0.0
	_movement_target = Vector3.ZERO
	_owner_body.clear_movement_target()


func _reset_wander_timer() -> void:
	_wander_timer = _random_generator.randf_range(
		COMBAT_WANDER_INTERVAL_MIN,
		COMBAT_WANDER_INTERVAL_MAX
	)


func _direction_to_target(target: UnitBase) -> Vector3:
	var direction: Vector3 = (
		target.global_position - _owner_body.global_position
	)
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return direction.normalized()


func _get_attack_range() -> float:
	return _combat.get_attack_range() if is_instance_valid(_combat) else 0.0


func _get_attack_range_tolerance() -> float:
	return (
		_combat.get_attack_range_tolerance()
		if is_instance_valid(_combat)
		else 0.0
	)


func _is_outside_leash() -> bool:
	return _horizontal_distance(_owner_body.global_position, _home_position) > leash_distance


func _transition_to(next_state: State) -> void:
	if _current_state == next_state:
		return
	var previous_state := _current_state
	_current_state = next_state
	if next_state != State.IDLE:
		_clear_idle_wander()
	if next_state == State.ATTACK:
		_combat_wander_target_valid = false
		_wander_timer = 0.0
		if previous_state == State.CHASE:
			_start_attack_entry_delay()
	if next_state == State.CHASE or next_state == State.ATTACK:
		_owner_body.enter_combat()
	else:
		_owner_body.exit_combat()
	state_changed.emit(previous_state, _current_state)


## 每次从 CHASE 真实进入 ATTACK 时生成一次随机延迟，并复用 AICombatSystem 的现有公共冷却。
## 重复停留在 ATTACK 不会再次进入本方法；直接从其他状态进入攻击也不增加等待。
func _start_attack_entry_delay() -> void:
	if not is_instance_valid(_combat):
		return
	var minimum_delay := maxf(attack_entry_delay_min, 0.0)
	var maximum_delay := maxf(attack_entry_delay_max, minimum_delay)
	var delay := _random_generator.randf_range(minimum_delay, maximum_delay)
	_combat.start_global_cooldown(delay)


func _on_owner_died(_source: Node) -> void:
	if is_instance_valid(_combat):
		_combat.cancel_current_action()
	if is_instance_valid(_targeting):
		_targeting.clear_locked_target()
	_owner_body.clear_movement_target()
	_clear_idle_wander()
	_clear_combat_wander()
	_transition_to(State.IDLE)


func _on_owner_revived(_health_value: float, _source: Node) -> void:
	_home_position = _owner_body.global_position
	if is_instance_valid(_targeting):
		_targeting.resume_detection()
	_clear_idle_wander()
	_clear_combat_wander()
	_transition_to(State.IDLE)


func _horizontal_distance(first_position: Vector3, second_position: Vector3) -> float:
	return Vector2(first_position.x - second_position.x, first_position.z - second_position.z).length()
