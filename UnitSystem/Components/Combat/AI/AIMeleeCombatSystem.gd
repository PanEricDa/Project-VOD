class_name AIMeleeCombatSystem
extends AICombatSystem

## 近战战斗组件：只把通用攻击动画事件交付给盒形命中检测。

@export_category("Debug")
@export var debug_hitbox_enabled: bool = false:
	set(value):
		debug_hitbox_enabled = value
		if is_instance_valid(_melee_hitbox):
			_melee_hitbox.debug_hitbox_enabled = value

@onready var _melee_hitbox: MeleeHitboxComponent = $MeleeHitbox


func _configure_attack_delivery() -> bool:
	var controller := get_attack_controller()
	if not is_instance_valid(_melee_hitbox) or not is_instance_valid(controller):
		return false
	_melee_hitbox.debug_hitbox_enabled = debug_hitbox_enabled
	_melee_hitbox.configure_owner(_owner_body)
	_connect_once(controller.hit_window_opened, _on_hit_window_opened)
	_connect_once(controller.hit_window_closed, _on_hit_window_closed)
	_connect_once(controller.hit_stop_changed, _on_hit_stop_changed)
	_connect_once(_melee_hitbox.attack_hit, _on_melee_hit)
	return true


func cancel_current_action() -> void:
	if is_instance_valid(_melee_hitbox):
		_melee_hitbox.end_detection()
	super.cancel_current_action()


func _on_hit_window_opened(
	weapon_data: WeaponData,
	_target: UnitBase,
	attack_index: int,
	attack_direction: Vector3
) -> void:
	var melee_weapon := weapon_data as MeleeWeaponData
	if not is_instance_valid(_melee_hitbox):
		return
	var controller := get_attack_controller()
	var payload := controller.get_external_melee_payload() if is_instance_valid(controller) else {}
	if not payload.is_empty():
		_melee_hitbox.begin_custom_detection(payload.get("hitbox_size", Vector3.ZERO), payload.get("hitbox_center_offset", Vector3.ZERO), attack_index, attack_direction)
	elif melee_weapon != null:
		_melee_hitbox.begin_detection(melee_weapon, attack_index, attack_direction)


func _on_hit_window_closed() -> void:
	if is_instance_valid(_melee_hitbox):
		_melee_hitbox.end_detection()


func _on_hit_stop_changed(active: bool) -> void:
	if is_instance_valid(_melee_hitbox):
		_melee_hitbox.set_detection_suspended(active)


func _on_melee_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	attack_index: int
) -> void:
	var controller := get_attack_controller()
	if is_instance_valid(controller):
		controller.report_attack_hit(target, hit_position, hit_direction, attack_index)


func _connect_once(source_signal: Signal, callback: Callable) -> void:
	if not source_signal.is_connected(callback):
		source_signal.connect(callback)
