class_name PlayerAttackController
extends Node

## 玩家武器攻击的轻量控制器。
##
## 本节点只负责装备武器、读取攻击 InputMap、维护连击状态和驱动角色视觉中的
## CharacterAnimationPlayer。它不会修改 PlayerBase 的移动、速度、碰撞或朝向。

signal weapon_equipped(weapon_data: WeaponData)
signal weapon_unequipped()
signal attack_started(combo_index: int)
signal attack_finished(combo_index: int)
signal combo_finished()
signal attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	combo_index: int
)

enum AttackState {
	IDLE,
	ATTACKING,
	CHAIN_WAIT,
	ROUND_WAIT,
}

const VISUAL_SLOT_PATH: NodePath = ^"Visual"
const MELEE_HITBOX_PATH: NodePath = ^"MeleeHitbox"
const WEAPON_SOCKET_PATH: NodePath = ^"CharacterRoot/WeaponSocket"
const ANIMATION_PLAYER_NAME: StringName = &"CharacterAnimationPlayer"
const WEAPON_LIBRARY_NAME: StringName = &"weapon"
const RESET_ANIMATION_NAME: StringName = &"RESET"
const BASIC_ATTACK_PREFIX := "basic_attack_"
const DASH_CANCEL_WINDOW_SCALE: float = 0.5

@export_category("Weapon")
## 由 PlayerBase 根节点转交的武器；不作为子节点 Inspector 配置项。
var starting_weapon: WeaponData

@export_category("Input")
## 正规 InputMap 攻击动作，默认对应鼠标左键。
@export var attack_action: StringName = &"player_attack"
## 当前攻击结束前允许缓存下一次输入的时间。
@export_range(0.0, 1.0, 0.01, "or_greater")
var input_buffer_duration: float = 0.15
## 一段攻击结束后，玩家仍可继续本轮连击的最长等待时间。
@export_range(0.0, 3.0, 0.05, "or_greater")
var combo_reset_duration: float = 0.7
## 开启后，持续按住攻击键会自动衔接剩余连段。
@export var hold_to_auto_chain: bool = true
## 完成最后一段后，持续按键自动开始下一轮前的停顿时间。
@export_range(0.0, 3.0, 0.05, "or_greater")
var hold_combo_restart_delay: float = 0.3

var _state: AttackState = AttackState.IDLE
var _combo_index: int = 0
var _attack_animation_count: int = 0
var _input_buffer_remaining: float = 0.0
var _combo_reset_remaining: float = 0.0
var _round_restart_remaining: float = 0.0
var _current_attack_animation: StringName = &""
var _equipped_weapon: WeaponData
var _weapon_visual: Node3D
var _weapon_socket: Node3D
var _animation_player: AnimationPlayer
var _melee_hitbox: Node
## 当前是否处于局部命中停顿。该状态只冻结攻击相关流程，不影响角色常规移动、
## 重力、场景树或摄像机自身的震动更新。
var _hit_stop_active: bool = false
## 记录进入停顿前攻击动画是否确实正在播放，避免恢复时误启动 RESET 或空闲动画。
var _animation_was_playing_before_hit_stop: bool = false
## 由 PlayerBase 统一维护的输入许可。
## false 时不会读取新的攻击按键，也不会因持续按住而开启后续连击；当前已播放的攻击动画仍自然完成。
var _input_enabled: bool = true


## 由 PlayerBase 根节点注入初始武器；使用延迟装备确保视觉端点已经就绪。
func set_starting_weapon(weapon_data: WeaponData) -> void:
	starting_weapon = weapon_data
	if is_inside_tree() and starting_weapon != null:
		call_deferred("_equip_starting_weapon")


func _ready() -> void:
	_resolve_visual_endpoints()
	_resolve_melee_hitbox()
	if starting_weapon != null:
		# 继承场景中的视觉实例会与本节点在同一轮进入树。延迟一次装备可确保所有
		# 子节点的 _ready() 已完成，同时不会让 PlayerBase 依赖具体视觉类型。
		call_deferred("_equip_starting_weapon")


func _process(delta: float) -> void:
	# 冲刺优先级高于普通攻击。PlayerBase 不需要反向依赖控制器；控制器通过
	# 可选公开接口观察冲刺状态，并统一清理动画、位移和 Hitbox 窗口。
	if _input_enabled and InputMap.has_action(attack_action) and Input.is_action_just_pressed(
		attack_action
	):
		request_attack()

	# 停顿期间仍先读取攻击输入，使玩家能够缓存下一段连击；随后冻结所有攻击状态
	# 计时器，保证输入缓存、连击窗口与轮次等待不会在卡刀期间被消耗。
	if _hit_stop_active:
		return

	match _state:
		AttackState.ATTACKING:
			_input_buffer_remaining = maxf(
				_input_buffer_remaining - delta,
				0.0
			)
		AttackState.CHAIN_WAIT:
			_combo_reset_remaining = maxf(
				_combo_reset_remaining - delta,
				0.0
			)
			if _combo_reset_remaining <= 0.0:
				_finish_combo(false)
		AttackState.ROUND_WAIT:
			if not _is_attack_action_pressed():
				_state = AttackState.IDLE
				return
			_round_restart_remaining = maxf(
				_round_restart_remaining - delta,
				0.0
			)
			if _round_restart_remaining <= 0.0:
				_start_attack(1)


## 原子装备一件武器。
##
## 新资源会在移除旧装备之前完整验证。返回 false 表示配置无效，此时当前武器、
## 模型和动画库均保持原样。
func equip_weapon(weapon_data: WeaponData) -> bool:
	if not _resolve_visual_endpoints():
		_report_configuration_error("HeroVisual endpoints are unavailable")
		return false
	var validation := _validate_weapon_data(weapon_data)
	if not bool(validation.get("valid", false)):
		_report_configuration_error(str(validation.get("reason", "invalid weapon")))
		return false

	var new_visual: Node3D = validation.get("visual") as Node3D
	var attack_count: int = int(validation.get("attack_count", 0))
	cancel_combo()
	_remove_equipped_assets(false)

	_weapon_socket.add_child(new_visual)
	_weapon_visual = new_visual
	_animation_player.add_animation_library(
		WEAPON_LIBRARY_NAME,
		weapon_data.animation_library
	)
	_equipped_weapon = weapon_data
	_attack_animation_count = attack_count
	_play_reset_animation()
	weapon_equipped.emit(weapon_data)
	return true


## 卸下当前武器，并清理视觉、动画库和连击状态。
func unequip_weapon() -> void:
	var had_weapon: bool = _equipped_weapon != null
	cancel_combo()
	_remove_equipped_assets(true)
	if had_weapon:
		weapon_unequipped.emit()


## 请求发动或续接一次攻击。
##
## 攻击中调用只刷新短暂输入缓存；连击等待期调用会直接播放下一段。
func request_attack() -> void:
	var owner_unit := get_parent() as UnitBase
	if owner_unit != null and owner_unit.is_dead():
		return
	if _attack_animation_count <= 0 or not is_instance_valid(_animation_player):
		return
	match _state:
		AttackState.IDLE:
			_start_attack(1)
		AttackState.ATTACKING:
			_input_buffer_remaining = input_buffer_duration
		AttackState.CHAIN_WAIT:
			var next_index: int = _combo_index + 1
			if next_index <= _attack_animation_count:
				_start_attack(next_index)
		AttackState.ROUND_WAIT:
			_start_attack(1)


## 立即中断当前攻击并恢复武器 RESET 姿势。
func cancel_combo() -> void:
	var had_active_combo: bool = (
		_state != AttackState.IDLE or _combo_index > 0
	)
	# 必须先解除局部停顿，再重置状态。这样 AnimationPlayer、攻击位移和 Hitbox
	# 都能回到一致的可用状态，冲刺或卸装武器时不会遗留冻结标记。
	set_hit_stop_active(false)
	_state = AttackState.IDLE
	_combo_index = 0
	_input_buffer_remaining = 0.0
	_combo_reset_remaining = 0.0
	_round_restart_remaining = 0.0
	_current_attack_animation = &""
	_close_attack_hit_window()
	_cancel_owner_attack_motion()
	_play_reset_animation()
	if had_active_combo:
		combo_finished.emit()


## 仅在某段攻击动画实际播放期间返回 true。
## Dash 取消当前攻击动作，但保留当前连击序号，令下一次攻击可接续至下一段。
## 续接窗口只补回 Dash 时长的一半；因为原窗口仍在 Dash 期间自然倒计时，
## 所以连续 Dash 无法无限延长连击窗口。
func interrupt_attack_for_dash(expected_dash_duration: float) -> bool:
	if _state != AttackState.ATTACKING:
		return false
	set_hit_stop_active(false)
	_close_attack_hit_window()
	_cancel_owner_attack_motion()
	_input_buffer_remaining = 0.0
	_round_restart_remaining = 0.0
	_current_attack_animation = &""
	_state = AttackState.CHAIN_WAIT
	_combo_reset_remaining = combo_reset_duration + (
		maxf(expected_dash_duration, 0.0) * DASH_CANCEL_WINDOW_SCALE
	)
	_play_reset_animation()
	return true


func is_attacking() -> bool:
	return _state == AttackState.ATTACKING


## 允许或禁止控制器读取新的攻击 InputMap 请求。
## enabled 为 false 时不会取消当前动画、命中窗口或已缓存的攻击流程，只阻止结算界面期间新增的玩家攻击输入。
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


## 返回当前连段序号；空闲或轮次间隔期间为 0。
func get_combo_index() -> int:
	return _combo_index


## 开启或解除本地攻击停顿。
##
## 开启后仅暂停当前攻击动画、攻击前移和新的 Hitbox 查询；PlayerBase 的普通
## WASD、重力、冲刺之外的世界逻辑以及摄像机震动仍由各自节点正常更新。
func set_hit_stop_active(active: bool) -> void:
	if _hit_stop_active == active:
		return
	_resolve_visual_endpoints()
	_resolve_melee_hitbox()
	_hit_stop_active = active

	var actor: Node = get_parent()
	if actor != null and actor.has_method(&"set_attack_motion_suspended"):
		actor.call("set_attack_motion_suspended", active)
	if (
		is_instance_valid(_melee_hitbox)
		and _melee_hitbox.has_method(&"set_detection_suspended")
	):
		_melee_hitbox.call("set_detection_suspended", active)

	if active:
		_animation_was_playing_before_hit_stop = (
			is_instance_valid(_animation_player)
			and _animation_player.is_playing()
		)
		if _animation_was_playing_before_hit_stop:
			_animation_player.pause()
		return

	if (
		_animation_was_playing_before_hit_stop
		and _state == AttackState.ATTACKING
		and is_instance_valid(_animation_player)
	):
		# 不传动画名会从 pause() 保存的当前位置继续播放，而不是从头重播。
		_animation_player.play()
	_animation_was_playing_before_hit_stop = false


## 返回当前是否正在执行局部攻击停顿，供独立反馈桥和测试安全查询。
func is_hit_stop_active() -> bool:
	return _hit_stop_active


func _equip_starting_weapon() -> void:
	if starting_weapon != null:
		equip_weapon(starting_weapon)


func _start_attack(combo_index: int) -> void:
	if combo_index < 1 or combo_index > _attack_animation_count:
		return
	var animation_name := StringName(
		"%s/%s%d" % [
			WEAPON_LIBRARY_NAME,
			BASIC_ATTACK_PREFIX,
			combo_index,
		]
	)
	if not _animation_player.has_animation(animation_name):
		_report_configuration_error(
			"resolved attack animation is missing: " + str(animation_name)
		)
		_finish_combo(false)
		return
	_state = AttackState.ATTACKING
	_combo_index = combo_index
	_input_buffer_remaining = 0.0
	_combo_reset_remaining = 0.0
	_round_restart_remaining = 0.0
	_current_attack_animation = animation_name
	_animation_player.play(animation_name)
	attack_started.emit(combo_index)


func _on_animation_finished(animation_name: StringName) -> void:
	if (
		_state != AttackState.ATTACKING
		or animation_name != _current_attack_animation
	):
		return
	_close_attack_hit_window()
	var finished_index: int = _combo_index
	attack_finished.emit(finished_index)
	_current_attack_animation = &""

	if finished_index >= _attack_animation_count:
		_finish_combo(true)
		return

	var should_chain: bool = (
		_input_buffer_remaining > 0.0
		or (hold_to_auto_chain and _is_attack_action_pressed())
	)
	_input_buffer_remaining = 0.0
	if should_chain:
		_start_attack(finished_index + 1)
		return

	_state = AttackState.CHAIN_WAIT
	_combo_reset_remaining = combo_reset_duration
	_play_reset_animation()


func _finish_combo(completed_full_round: bool) -> void:
	_close_attack_hit_window()
	_state = AttackState.IDLE
	_combo_index = 0
	_input_buffer_remaining = 0.0
	_combo_reset_remaining = 0.0
	_current_attack_animation = &""
	_play_reset_animation()
	combo_finished.emit()
	if (
		completed_full_round
		and hold_to_auto_chain
		and _is_attack_action_pressed()
	):
		_state = AttackState.ROUND_WAIT
		_round_restart_remaining = hold_combo_restart_delay


func _play_reset_animation() -> void:
	if not is_instance_valid(_animation_player):
		return
	var reset_name := StringName(
		str(WEAPON_LIBRARY_NAME) + "/" + str(RESET_ANIMATION_NAME)
	)
	if _animation_player.has_animation(reset_name):
		_animation_player.play(reset_name)
	else:
		_animation_player.stop()


func _is_attack_action_pressed() -> bool:
	return (
		_input_enabled
		and
		InputMap.has_action(attack_action)
		and Input.is_action_pressed(attack_action)
	)


func _resolve_visual_endpoints() -> bool:
	if is_instance_valid(_weapon_socket) and is_instance_valid(_animation_player):
		return true
	var actor: Node = get_parent()
	if actor == null:
		return false
	var visual_slot := actor.get_node_or_null(VISUAL_SLOT_PATH) as Node3D
	if visual_slot == null or visual_slot.get_child_count() != 1:
		return false
	var visual_root := visual_slot.get_child(0) as Node3D
	if visual_root == null:
		return false
	_weapon_socket = visual_root.get_node_or_null(WEAPON_SOCKET_PATH) as Node3D
	_animation_player = visual_root.get_node_or_null(
		NodePath(str(ANIMATION_PLAYER_NAME))
	) as AnimationPlayer
	if not is_instance_valid(_animation_player):
		return false
	if not _animation_player.animation_finished.is_connected(
		_on_animation_finished
	):
		_animation_player.animation_finished.connect(_on_animation_finished)
	if (
		_animation_player.has_signal(&"attack_motion_requested")
		and not _animation_player.is_connected(
			&"attack_motion_requested",
			_on_attack_motion_requested
		)
	):
		_animation_player.connect(
			&"attack_motion_requested",
			_on_attack_motion_requested
		)
	if (
		_animation_player.has_signal(&"hit_window_open_requested")
		and not _animation_player.is_connected(
			&"hit_window_open_requested",
			_on_hit_window_open_requested
		)
	):
		_animation_player.connect(
			&"hit_window_open_requested",
			_on_hit_window_open_requested
		)
	if (
		_animation_player.has_signal(&"hit_window_close_requested")
		and not _animation_player.is_connected(
			&"hit_window_close_requested",
			_on_hit_window_close_requested
		)
	):
		_animation_player.connect(
			&"hit_window_close_requested",
			_on_hit_window_close_requested
		)
	return is_instance_valid(_weapon_socket)


func _resolve_melee_hitbox() -> bool:
	if is_instance_valid(_melee_hitbox):
		return true
	var actor := get_parent() as UnitBase
	if actor == null:
		return false
	_melee_hitbox = actor.get_node_or_null(MELEE_HITBOX_PATH)
	if not is_instance_valid(_melee_hitbox):
		return false
	if (
		not _melee_hitbox.has_method(&"configure_owner")
		or not _melee_hitbox.has_method(&"begin_detection")
		or not _melee_hitbox.has_method(&"end_detection")
		or not _melee_hitbox.has_signal(&"attack_hit")
	):
		_melee_hitbox = null
		return false
	_melee_hitbox.call("configure_owner", actor)
	if not _melee_hitbox.is_connected(&"attack_hit", _on_melee_hitbox_attack_hit):
		_melee_hitbox.connect(&"attack_hit", _on_melee_hitbox_attack_hit)
	return true


func _on_hit_window_open_requested() -> void:
	# Workbench、RESET 和空闲动画中的方法键不会启动实际查询。
	if _state != AttackState.ATTACKING or _equipped_weapon == null:
		return
	var melee_weapon := _equipped_weapon as MeleeWeaponData
	if melee_weapon == null or not _resolve_melee_hitbox():
		return
	var actor: Node = get_parent()
	if actor == null or not actor.has_method(&"get_attack_forward_direction"):
		return
	var direction: Variant = actor.call("get_attack_forward_direction")
	if direction is Vector3:
		var typed_direction: Vector3 = direction
		_melee_hitbox.call(
			"begin_detection",
			melee_weapon,
			_combo_index,
			typed_direction
		)


func _on_hit_window_close_requested() -> void:
	_close_attack_hit_window()


func _close_attack_hit_window() -> void:
	if is_instance_valid(_melee_hitbox):
		_melee_hitbox.call("end_detection")


func _on_melee_hitbox_attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	combo_index: int
) -> void:
	_apply_basic_attack_damage(target, combo_index)
	attack_hit.emit(target, hit_position, hit_direction, combo_index)


## 在既有命中出口统一结算玩家普攻，未装备武器时保留命中事件而不改变目标生命。
func _apply_basic_attack_damage(
	target: UnitBase,
	attack_index: int
) -> float:
	var source := get_parent() as UnitBase
	if source == null or _equipped_weapon == null:
		return 0.0
	return CombatValueResolver.apply_damage(
		source,
		target,
		_equipped_weapon.basic_attack_base_damage,
		_equipped_weapon.basic_attack_power_ratio,
		_equipped_weapon.get_combo_damage_multiplier(attack_index),
		_equipped_weapon.basic_attack_threat_multiplier,
		_equipped_weapon.basic_attack_damage_variance
	)


func _on_attack_motion_requested() -> void:
	# Workbench 预览、RESET 或空闲动画也可能触发方法调用；只有一段玩家攻击实际处于
	# ATTACKING 状态时才允许把 marker 转交给物理层。
	if _state != AttackState.ATTACKING or _equipped_weapon == null:
		return
	var melee_weapon := _equipped_weapon as MeleeWeaponData
	if melee_weapon == null:
		return
	var distance_index: int = _combo_index - 1
	if (
		distance_index < 0
		or distance_index >= melee_weapon.attack_forward_distances.size()
	):
		return
	var distance: float = melee_weapon.attack_forward_distances[
		distance_index
	]
	var speed: float = melee_weapon.attack_motion_speed
	if distance <= 0.0 or speed <= 0.0:
		return
	var actor: Node = get_parent()
	if (
		actor == null
		or not actor.has_method(&"get_attack_forward_direction")
		or not actor.has_method(&"request_attack_motion")
	):
		return
	var direction: Variant = actor.call("get_attack_forward_direction")
	if not direction is Vector3:
		return
	actor.call("request_attack_motion", direction, distance, speed)


func _cancel_owner_attack_motion() -> void:
	var actor: Node = get_parent()
	if actor != null and actor.has_method(&"cancel_attack_motion"):
		actor.call("cancel_attack_motion")


func _exit_tree() -> void:
	set_hit_stop_active(false)
	_close_attack_hit_window()


func _validate_weapon_data(weapon_data: WeaponData) -> Dictionary:
	if weapon_data == null:
		return {"valid": false, "reason": "WeaponData is null"}
	if weapon_data.visual_scene == null:
		return {"valid": false, "reason": "visual_scene is missing"}
	if weapon_data.animation_library == null:
		return {"valid": false, "reason": "animation_library is missing"}
	if not weapon_data.animation_library.has_animation(RESET_ANIMATION_NAME):
		return {"valid": false, "reason": "RESET animation is missing"}

	var attack_indices: Array[int] = []
	for animation_name: StringName in weapon_data.animation_library.get_animation_list():
		var name_text := str(animation_name)
		if not name_text.begins_with(BASIC_ATTACK_PREFIX):
			continue
		var suffix := name_text.trim_prefix(BASIC_ATTACK_PREFIX)
		if not suffix.is_valid_int() or int(suffix) < 1:
			return {
				"valid": false,
				"reason": "invalid basic attack name: " + name_text,
			}
		attack_indices.append(int(suffix))
	if attack_indices.is_empty():
		return {"valid": false, "reason": "basic_attack_1 is missing"}
	attack_indices.sort()
	for expected_index: int in range(1, attack_indices.back() + 1):
		if not attack_indices.has(expected_index):
			return {
				"valid": false,
				"reason": "basic attack sequence has a gap at %d" % expected_index,
			}

	var visual_instance: Node = weapon_data.visual_scene.instantiate()
	if not visual_instance is Node3D:
		if visual_instance != null:
			visual_instance.free()
		return {"valid": false, "reason": "visual_scene root must be Node3D"}
	return {
		"valid": true,
		"visual": visual_instance as Node3D,
		"attack_count": attack_indices.back(),
	}


func _remove_equipped_assets(clear_weapon_data: bool) -> void:
	if is_instance_valid(_weapon_visual):
		var visual_parent: Node = _weapon_visual.get_parent()
		if visual_parent != null:
			visual_parent.remove_child(_weapon_visual)
		_weapon_visual.queue_free()
	_weapon_visual = null
	if (
		is_instance_valid(_animation_player)
		and _animation_player.has_animation_library(WEAPON_LIBRARY_NAME)
	):
		# AnimationPlayer 在移除当前正在引用的 Library 后仍会保留动画名称。
		# Godot 4.7 随后释放节点时可能访问已经不存在的动画，因此必须先停止并清空
		# current_animation，再移除 Library。
		_animation_player.stop()
		_animation_player.current_animation = &""
		_animation_player.remove_animation_library(WEAPON_LIBRARY_NAME)
	_attack_animation_count = 0
	if clear_weapon_data:
		_equipped_weapon = null


func _report_configuration_error(message: String) -> void:
	# 使用普通诊断输出而非 push_error/push_warning，避免一次可恢复的装备失败污染
	# Godot Debugger；equip_weapon() 的 bool 返回值仍允许调用方明确处理失败。
	print("PlayerAttackController: " + message)
