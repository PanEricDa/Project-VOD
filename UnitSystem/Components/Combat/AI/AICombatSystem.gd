class_name AICombatSystem
extends Node3D

## 所有自动控制单位共用的轻量战斗协调器。
##
## 本组件只管理武器装配、普通攻击提交与公共冷却。它不搜索目标、不决定导航，也不
## 直接播放动画；这些职责分别属于行为状态机与 AIAttackController。
signal weapon_equipped(weapon_data: WeaponData)
signal weapon_unequipped()
signal attack_started(target: UnitBase, attack_index: int)
signal attack_finished(target: UnitBase, attack_index: int)
signal attack_cancelled(target: UnitBase, attack_index: int)
signal attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	attack_index: int
)
signal global_cooldown_started(duration: float)
signal global_cooldown_finished()
signal external_action_released()
signal external_action_finished()
signal external_action_cancelled()

@export_category("Weapon")
## 由 AIUnitBase 根节点转交的共享武器数据；不作为子节点 Inspector 配置项。
var starting_weapon: WeaponData

@export_category("Global Cooldown")
## 普通攻击或未来技能成功提交后使用的基础公共冷却，单位为秒。
@export_range(0.0, 10.0, 0.05)
var base_global_cooldown_duration: float = 1.0

@onready var _attack_controller: AIAttackController = $AttackController

var _owner_body: AIUnitBase
var _global_cooldown_remaining: float = 0.0
var _configured: bool = false
var _use_external_global_cooldown: bool = false


## 由持有单位根节点注入初始武器，保留为运行时接口而非重复 Inspector 字段。
func set_starting_weapon(weapon_data: WeaponData) -> void:
	starting_weapon = weapon_data


## 动态只读 Inspector 信息只观察真实运行状态，不产生第二份配置或存档数据。
func _get_property_list() -> Array[Dictionary]:
	return [
		{
			"name": "Runtime Debug",
			"type": TYPE_NIL,
			"hint_string": "debug_",
			"usage": PROPERTY_USAGE_GROUP,
		},
		{
			"name": "debug_equipped_weapon",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "WeaponData",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "debug_current_attack_target",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_NODE_TYPE,
			"hint_string": "UnitBase",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "debug_current_attack_animation",
			"type": TYPE_STRING_NAME,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "debug_global_cooldown_remaining",
			"type": TYPE_FLOAT,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		},
	]


func _get(property: StringName) -> Variant:
	match property:
		&"debug_equipped_weapon":
			return get_equipped_weapon()
		&"debug_current_attack_target":
			return (
				_attack_controller.get_current_target()
				if is_instance_valid(_attack_controller)
				else null
			)
		&"debug_current_attack_animation":
			return (
				_attack_controller.get_current_attack_animation()
				if is_instance_valid(_attack_controller)
				else &""
			)
		&"debug_global_cooldown_remaining":
			return _global_cooldown_remaining
	return null


## 注入通用 AI 物理宿主。无视觉且未装备武器的纯 AIUnitBase 仍可安全配置。
func configure(owner_body: AIUnitBase) -> bool:
	cancel_current_action()
	_owner_body = owner_body
	_configured = (
		is_instance_valid(_owner_body)
		and is_instance_valid(_attack_controller)
	)
	if not _configured:
		return false

	if not _attack_controller.configure(_owner_body):
		_configured = false
		return false
	_connect_controller_signals()
	if not _configure_attack_delivery():
		_configured = false
		return false
	if starting_weapon != null and not equip_weapon(starting_weapon):
		_configured = false
		return false
	notify_property_list_changed()
	return true


func _process(delta: float) -> void:
	if _global_cooldown_remaining <= 0.0:
		return
	var previous_remaining: float = _global_cooldown_remaining
	_global_cooldown_remaining = maxf(
		_global_cooldown_remaining - delta,
		0.0
	)
	if previous_remaining > 0.0 and _global_cooldown_remaining <= 0.0:
		notify_property_list_changed()
		global_cooldown_finished.emit()


func equip_weapon(weapon_data: WeaponData) -> bool:
	if not _configured or not is_instance_valid(_attack_controller):
		return false
	return _attack_controller.equip_weapon(weapon_data)


func unequip_weapon() -> void:
	if is_instance_valid(_attack_controller):
		_attack_controller.unequip_weapon()


## 由 AI 决策层提交一次普通攻击。只有真实开始动画后才启动公共冷却。
func request_basic_attack(target: UnitBase) -> bool:
	if not can_request_basic_attack(target):
		return false
	if not _attack_controller.request_attack(target):
		return false
	if not _use_external_global_cooldown:
		start_global_cooldown()
	return true


func cancel_current_action() -> void:
	if is_instance_valid(_attack_controller):
		_attack_controller.cancel_attack()


## 将外部动作请求转交给角色动画控制器；本层不认识具体技能类型。
func request_external_action(effective_cast_time: float, target: UnitBase = null, action_payload: Dictionary = {}) -> bool:
	if (
		not is_instance_valid(_owner_body)
		or not _owner_body.is_inside_tree()
		or _owner_body.is_dead()
	):
		# 死亡与离树只影响本次动作资格，不改写技能或自动施法配置。
		return false
	return (
		_configured
		and is_instance_valid(_attack_controller)
		and _attack_controller.request_external_action(effective_cast_time, target, action_payload)
	)


func cancel_external_action() -> void:
	if is_instance_valid(_attack_controller):
		_attack_controller.cancel_external_action()


func get_action_launch_transform() -> Transform3D:
	return (
		_attack_controller.get_action_launch_transform()
		if is_instance_valid(_attack_controller)
		else Transform3D.IDENTITY
	)


func can_request_basic_attack(target: UnitBase) -> bool:
	if (
		not is_instance_valid(_owner_body)
		or _owner_body.is_dead()
		or not _configured
		or (not _use_external_global_cooldown and not is_global_cooldown_ready())
		or not is_instance_valid(_attack_controller)
		or not _attack_controller.can_attack()
		or not _is_valid_target(target)
	):
		return false
	var offset: Vector3 = target.global_position - _owner_body.global_position
	offset.y = 0.0
	return offset.length() <= (
		get_attack_range() + get_attack_range_tolerance()
	)


func is_attacking() -> bool:
	return (
		is_instance_valid(_attack_controller)
		and _attack_controller.is_attacking()
	)


func get_equipped_weapon() -> WeaponData:
	return (
		_attack_controller.get_equipped_weapon()
		if is_instance_valid(_attack_controller)
		else null
	)


func get_attack_range() -> float:
	var weapon_data: WeaponData = get_equipped_weapon()
	return maxf(weapon_data.attack_range, 0.0) if weapon_data != null else 0.0


func get_attack_range_tolerance() -> float:
	var weapon_data: WeaponData = get_equipped_weapon()
	return (
		maxf(weapon_data.attack_range_tolerance, 0.0)
		if weapon_data != null
		else 0.0
	)


## 返回已装备武器在普攻动作期间允许保留的水平移动速度比例；未装备武器时安全返回 1，不额外限制既有移动逻辑。
func get_attack_movement_speed_multiplier() -> float:
	var weapon_data: WeaponData = get_equipped_weapon()
	return (
		clampf(weapon_data.attack_movement_speed_multiplier, 0.0, 1.0)
		if weapon_data != null
		else 1.0
	)


func is_global_cooldown_ready() -> bool:
	return _global_cooldown_remaining <= 0.0


func get_global_cooldown_remaining() -> float:
	return _global_cooldown_remaining


## 由 AI 行为状态机统一管理技能与普攻共用行动 GCD 时启用。
func set_use_external_global_cooldown(active: bool) -> void:
	_use_external_global_cooldown = active
	if active:
		_global_cooldown_remaining = 0.0


## 启动或延长公共冷却。负数参数表示使用本组件的基础配置。
func start_global_cooldown(base_duration: float = -1.0) -> void:
	var requested_duration: float = (
		base_global_cooldown_duration
		if base_duration < 0.0
		else base_duration
	)
	var effective_duration: float = calculate_global_cooldown_duration(
		requested_duration
	)
	if effective_duration <= 0.0:
		return
	_global_cooldown_remaining = maxf(
		_global_cooldown_remaining,
		effective_duration
	)
	notify_property_list_changed()
	global_cooldown_started.emit(effective_duration)


## 未来全局规则、单位属性及状态修正只需在该唯一入口组合。
##
## 第一阶段不依赖任何属性或全局单例，只返回经过安全夹取的基础值。
func calculate_global_cooldown_duration(base_duration: float) -> float:
	return maxf(base_duration, 0.0)


func _is_valid_target(target: UnitBase) -> bool:
	return (
		is_instance_valid(target)
		and target.is_inside_tree()
		and target.is_targetable()
		and not target.is_dead()
		and is_instance_valid(_owner_body)
		and _owner_body.is_hostile_to(target)
	)


func _connect_controller_signals() -> void:
	var connections: Array[Array] = [
		[_attack_controller.weapon_equipped, _on_weapon_equipped],
		[_attack_controller.weapon_unequipped, _on_weapon_unequipped],
		[_attack_controller.attack_started, _on_attack_started],
		[_attack_controller.attack_finished, _on_attack_finished],
		[_attack_controller.attack_cancelled, _on_attack_cancelled],
		[_attack_controller.attack_hit, _on_controller_attack_hit],
		[
			_attack_controller.external_action_released,
			_on_external_action_released,
		],
		[
			_attack_controller.external_action_finished,
			_on_external_action_finished,
		],
		[
			_attack_controller.external_action_cancelled,
			_on_external_action_cancelled,
		],
	]
	for connection_data: Array in connections:
		var source_signal: Signal = connection_data[0] as Signal
		var callback: Callable = connection_data[1] as Callable
		if not source_signal.is_connected(callback):
			source_signal.connect(callback)


func _on_weapon_equipped(weapon_data: WeaponData) -> void:
	notify_property_list_changed()
	weapon_equipped.emit(weapon_data)


func _on_weapon_unequipped() -> void:
	notify_property_list_changed()
	weapon_unequipped.emit()


func _on_attack_started(target: UnitBase, attack_index: int) -> void:
	notify_property_list_changed()
	attack_started.emit(target, attack_index)


func _on_attack_finished(target: UnitBase, attack_index: int) -> void:
	notify_property_list_changed()
	attack_finished.emit(target, attack_index)


func _on_attack_cancelled(target: UnitBase, attack_index: int) -> void:
	notify_property_list_changed()
	attack_cancelled.emit(target, attack_index)

## 供不同交付子类将已确认的命中统一回传至战斗核心。
func report_attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	attack_index: int
) -> void:
	_apply_basic_attack_damage(target, attack_index)
	attack_hit.emit(
		target,
		hit_position,
		hit_direction,
		attack_index
	)


## 近战与远程 AI 共用确认命中出口结算普攻，未装备武器时仍向外发送命中事件。
func _apply_basic_attack_damage(
	target: UnitBase,
	attack_index: int
) -> float:
	var weapon_data: WeaponData = get_equipped_weapon()
	if _owner_body == null or weapon_data == null:
		return 0.0
	return CombatValueResolver.apply_damage(
		_owner_body,
		target,
		weapon_data.basic_attack_base_damage,
		weapon_data.basic_attack_power_ratio,
		weapon_data.get_combo_damage_multiplier(attack_index),
		weapon_data.basic_attack_threat_multiplier,
		weapon_data.basic_attack_damage_variance
	)


## 统一处理普通攻击或近战技能的命中；两者最终均提交给 CombatValueResolver。
func _apply_resolved_hit_damage(target: UnitBase, attack_index: int) -> float:
	var payload := _attack_controller.get_external_melee_payload() if is_instance_valid(_attack_controller) else {}
	if not payload.is_empty() and _owner_body != null:
		return CombatValueResolver.apply_damage(_owner_body, target, float(payload.get("base_damage", 0.0)), float(payload.get("power_ratio", 0.0)), float(payload.get("damage_multiplier", 1.0)), float(payload.get("threat_multiplier", 1.0)))
	return _apply_basic_attack_damage(target, attack_index)


func _on_controller_attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	attack_index: int
) -> void:
	_apply_resolved_hit_damage(target, attack_index)
	attack_hit.emit(target, hit_position, hit_direction, attack_index)


func _on_external_action_released() -> void:
	external_action_released.emit()


func _on_external_action_finished() -> void:
	external_action_finished.emit()


func _on_external_action_cancelled() -> void:
	external_action_cancelled.emit()


## 近战、远程等子类在这里连接动画事件与自己的交付组件。
func _configure_attack_delivery() -> bool:
	return true


func get_attack_controller() -> AIAttackController:
	return _attack_controller if is_instance_valid(_attack_controller) else null
