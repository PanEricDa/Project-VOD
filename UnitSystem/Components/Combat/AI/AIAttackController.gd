class_name AIAttackController
extends Node

## AI 武器普通攻击的执行器。
##
## 本组件不读取 InputMap、不搜索目标、不导航，也不维护公共冷却。它只接收一个已经
## 决定好的敌对目标，从 WeaponData 注入视觉与动画库，并随机播放一段 basic_attack_n。
signal weapon_equipped(weapon_data: WeaponData)
signal weapon_unequipped()
signal attack_started(target: UnitBase, attack_index: int)
signal attack_finished(target: UnitBase, attack_index: int)
signal attack_cancelled(target: UnitBase, attack_index: int)
## 各类攻击交付组件统一通过此事件回传命中，供反馈桥与战斗核心订阅。
signal attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	attack_index: int
)
## 由近战或远程 Combat 子类消费；控制器不再直接依赖某一种交付方式。
signal hit_window_opened(
	weapon_data: WeaponData,
	target: UnitBase,
	attack_index: int,
	attack_direction: Vector3
)
signal hit_window_closed()
signal hit_stop_changed(active: bool)
## 由远程武器动画事件触发；远程 CombatSystem 消费后创建对应投射物。
signal projectile_release_requested(
	weapon_data: WeaponData,
	target: UnitBase,
	attack_index: int,
	attack_direction: Vector3
)
## 外部动作到达动画方法轨道中的 release_action 标记。
signal external_action_released()
## 外部动作到达 finish_action 标记并释放控制器占用。
signal external_action_finished()
## 外部动作被显式取消。
signal external_action_cancelled()

enum AttackState {
	IDLE,
	ATTACKING,
	EXTERNAL_ACTION,
}

const VISUAL_SLOT_PATH: NodePath = ^"Visual"
const WEAPON_SOCKET_PATH: NodePath = ^"CharacterRoot/WeaponSocket"
const ANIMATION_PLAYER_NAME: StringName = &"CharacterAnimationPlayer"
const WEAPON_LIBRARY_NAME: StringName = &"weapon"
const RESET_ANIMATION_NAME: StringName = &"RESET"
const BASIC_ATTACK_PREFIX: String = "basic_attack_"
const BASIC_CAST_ANIMATION_NAME: StringName = &"basic_cast_1"

@export_category("Hit Feedback")
## 关闭后命中信号仍会发送，只是不允许通用反馈桥触发局部卡刀。
@export var hit_feedback_enabled: bool = true

var _owner_body: AIUnitBase
var _weapon_socket: Node3D
var _animation_player: CharacterAnimationEventPlayer
var _weapon_visual: Node3D
var _equipped_weapon: WeaponData

var _state: AttackState = AttackState.IDLE
var _attack_animation_count: int = 0
var _attack_index_bag: Array[int] = []
var _last_selected_attack_index: int = 0
var _current_attack_index: int = 0
var _current_attack_animation: StringName = &""
var _current_target: UnitBase
var _locked_attack_direction: Vector3 = Vector3.FORWARD
var _current_external_action_animation: StringName = &""
var _external_melee_payload: Dictionary = {}

var _hit_stop_active: bool = false
var _animation_was_playing_before_hit_stop: bool = false


## 注入通用 AI 物理宿主与近战判定组件，并解析当前具体角色 Visual 的固定端点。
func configure(owner_body: AIUnitBase) -> bool:
	cancel_attack()
	_owner_body = owner_body
	if not is_instance_valid(_owner_body):
		return false
	return true


## 原子装备一份共享 WeaponData。验证失败时保留当前武器和动画库。
func equip_weapon(weapon_data: WeaponData) -> bool:
	if not _resolve_visual_endpoints():
		return false
	var validation: Dictionary = _validate_weapon_data(weapon_data)
	if not bool(validation.get("valid", false)):
		print(
			"AIAttackController: "
			+ str(validation.get("reason", "invalid weapon"))
		)
		return false

	var new_visual := validation.get("visual") as Node3D
	var attack_count: int = int(validation.get("attack_count", 0))
	cancel_attack()
	_remove_equipped_assets(false)

	_weapon_socket.add_child(new_visual)
	_weapon_visual = new_visual
	_animation_player.add_animation_library(
		WEAPON_LIBRARY_NAME,
		weapon_data.animation_library
	)
	_equipped_weapon = weapon_data
	_attack_animation_count = attack_count
	_attack_index_bag.clear()
	_last_selected_attack_index = 0
	_play_reset_animation()
	weapon_equipped.emit(weapon_data)
	return true


## 卸载武器视觉、动画库和运行时随机袋。
func unequip_weapon() -> void:
	var had_weapon: bool = _equipped_weapon != null
	cancel_attack()
	_remove_equipped_assets(true)
	if had_weapon:
		weapon_unequipped.emit()


## 请求对指定敌对目标播放一段随机普通攻击。
func request_attack(target: UnitBase) -> bool:
	if not can_attack() or not _is_valid_target(target):
		return false
	var attack_direction: Vector3 = target.global_position - _owner_body.global_position
	attack_direction.y = 0.0
	if attack_direction.length_squared() <= 0.0001:
		attack_direction = _read_visual_forward()
	if attack_direction.length_squared() <= 0.0001:
		return false

	var selected_index: int = _take_next_attack_index()
	if selected_index <= 0:
		return false
	var animation_name := StringName(
		"%s/%s%d" % [
			WEAPON_LIBRARY_NAME,
			BASIC_ATTACK_PREFIX,
			selected_index,
		]
	)
	if not _animation_player.has_animation(animation_name):
		return false

	_current_target = target
	_current_attack_index = selected_index
	_current_attack_animation = animation_name
	_locked_attack_direction = attack_direction.normalized()
	_state = AttackState.ATTACKING
	_animation_player.play(animation_name)
	attack_started.emit(_current_target, _current_attack_index)
	return true


## 播放当前角色已经装配的通用施法动作。
##
## 调用者只传入已经计算完成的有效施法时间；本控制器不得反向访问 Skill、
## SkillHost 或 Unit 字段重新读取该数据。动画优先取当前武器的 basic_cast_1，
## 没有时再取角色的 basic_cast_1，并要求恰好一个 release_action 方法标记。
func request_external_action(effective_cast_time: float, target: UnitBase = null, action_payload: Dictionary = {}) -> bool:
	if (
		_state != AttackState.IDLE
		or not _resolve_visual_endpoints()
	):
		return false
	if is_instance_valid(_owner_body) and _owner_body.is_dead():
		return false
	if not is_finite(effective_cast_time) or effective_cast_time < 0.0:
		return _reject_external_action(
			"effective_cast_time must be finite and non-negative"
		)
	var requested_animation: StringName = action_payload.get("animation_name", &"")
	var resolved_action: Dictionary = _resolve_cast_animation(effective_cast_time, requested_animation)
	if resolved_action.is_empty():
		return _reject_external_action(
			(
				"no compatible generic cast animation; expected "
				+ "weapon/basic_cast_1 "
				+ "with exactly one valid release_action marker"
			)
		)
	var animation_name: StringName = resolved_action.get(
		"animation_name",
		&""
	)
	var playback_speed: float = resolved_action.get(
		"playback_speed",
		0.0
	)

	_current_external_action_animation = animation_name
	_external_melee_payload = action_payload.duplicate()
	_current_target = target
	_current_attack_index = 1
	if is_instance_valid(target):
		var direction := target.global_position - _owner_body.global_position
		direction.y = 0.0
		_locked_attack_direction = direction.normalized() if direction.length_squared() > 0.0001 else _read_visual_forward()
	_state = AttackState.EXTERNAL_ACTION
	_animation_player.play(
		animation_name,
		-1.0,
		playback_speed
	)
	return true


## 按稳定命名契约解析首个“存在且事件轨道有效”的当前动作。
##
## 武器可以提供职业化动作，但无效的旧武器动画不能遮蔽角色自身的有效回退动作。
## 返回值同时携带根据请求数据算出的播放速度，避免后续阶段再次回访任何技能字段。
func _resolve_cast_animation(effective_cast_time: float, requested_animation: StringName = &"") -> Dictionary:
	if not is_instance_valid(_animation_player):
		return {}
	var local_animation := requested_animation if not requested_animation.is_empty() else BASIC_CAST_ANIMATION_NAME
	var weapon_animation := StringName(str(WEAPON_LIBRARY_NAME) + "/" + str(local_animation))
	for animation_name: StringName in [weapon_animation]:
		if not _animation_player.has_animation(animation_name):
			continue
		var animation := _animation_player.get_animation(animation_name)
		var release_times := _find_method_marker_times(
			animation,
			&"release_action"
		)
		if release_times.size() != 1:
			continue
		var release_time: float = release_times[0]
		var playback_speed: float = 1.0
		if effective_cast_time <= 0.0:
			if not is_zero_approx(release_time):
				continue
		else:
			playback_speed = release_time / effective_cast_time
		if not is_finite(playback_speed) or playback_speed <= 0.0:
			continue
		return {
			"animation_name": animation_name,
			"playback_speed": playback_speed,
		}
	return {}


## 配置或传入数据错误必须留下可检索的明确原因，同时保持失败返回值供上层取消动作。
func _reject_external_action(reason: String) -> bool:
	push_error("AIAttackController: external action rejected: " + reason)
	return false


## 仅取消外部动作；普通攻击仍由 cancel_attack() 维护其既有信号语义。
func cancel_external_action() -> void:
	if _state != AttackState.EXTERNAL_ACTION:
		return
	set_hit_stop_active(false)
	_current_external_action_animation = &""
	_external_melee_payload.clear()
	_state = AttackState.IDLE
	_play_reset_animation()
	external_action_cancelled.emit()


## 返回当前具体角色 Visual 中 ProjectileOrigin 的世界变换。
##
## 找不到专用发射点时退回 WeaponSocket，使外部技能仍有稳定且不依赖世界原点的出口。
func get_action_launch_transform() -> Transform3D:
	if not _resolve_visual_endpoints():
		return Transform3D.IDENTITY
	var projectile_origin := _weapon_socket.get_node_or_null(
		^"ProjectileOrigin"
	) as Node3D
	if projectile_origin != null:
		return projectile_origin.global_transform
	return _weapon_socket.global_transform


## 取消当前攻击并完整关闭动画事件产生的位移和判定窗口。
func cancel_attack() -> void:
	if _state == AttackState.EXTERNAL_ACTION:
		cancel_external_action()
		return
	var was_attacking: bool = _state == AttackState.ATTACKING
	var cancelled_target: UnitBase = _current_target
	var cancelled_index: int = _current_attack_index
	set_hit_stop_active(false)
	_close_attack_hit_window()
	if is_instance_valid(_owner_body):
		_owner_body.cancel_attack_motion()
	_state = AttackState.IDLE
	_current_target = null
	_current_attack_index = 0
	_current_attack_animation = &""
	_current_external_action_animation = &""
	_locked_attack_direction = Vector3.FORWARD
	_play_reset_animation()
	if was_attacking:
		attack_cancelled.emit(cancelled_target, cancelled_index)


func can_attack() -> bool:
	return (
		_state == AttackState.IDLE
		and _equipped_weapon != null
		and _attack_animation_count > 0
		and is_instance_valid(_owner_body)
		and not _owner_body.is_dead()
		and is_instance_valid(_animation_player)
	)


func is_attacking() -> bool:
	return _state == AttackState.ATTACKING


func get_current_attack_index() -> int:
	return _current_attack_index


func get_current_target() -> UnitBase:
	return _current_target if is_instance_valid(_current_target) else null


func get_current_attack_animation() -> StringName:
	return _current_attack_animation


func get_equipped_weapon() -> WeaponData:
	return _equipped_weapon


func report_attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	attack_index: int
) -> void:
	if is_instance_valid(_owner_body) and _owner_body.is_dead():
		return
	attack_hit.emit(target, hit_position, hit_direction, attack_index)


func is_hit_feedback_enabled() -> bool:
	return hit_feedback_enabled


## 通用反馈桥使用的局部卡刀接口。
##
## 只暂停当前攻击动画和新的 Hitbox 查询；AI 当前不会消费动画位移 marker。
## AICombatSystem 的公共冷却由独立节点计时，因此不会被该状态暂停。
func set_hit_stop_active(active: bool) -> void:
	if _hit_stop_active == active:
		return
	if is_instance_valid(_owner_body) and _owner_body.is_dead():
		return
	_hit_stop_active = active
	hit_stop_changed.emit(active)
	if is_instance_valid(_owner_body):
		_owner_body.set_attack_motion_suspended(active)
	if not is_instance_valid(_animation_player):
		_animation_was_playing_before_hit_stop = false
		return
	if active:
		_animation_was_playing_before_hit_stop = (
			_animation_player.is_playing()
		)
		if _animation_was_playing_before_hit_stop:
			_animation_player.pause()
		return
	if (
		_animation_was_playing_before_hit_stop
		and _state != AttackState.IDLE
	):
		_animation_player.play()
	_animation_was_playing_before_hit_stop = false


func is_hit_stop_active() -> bool:
	return _hit_stop_active


func _resolve_visual_endpoints() -> bool:
	if (
		is_instance_valid(_weapon_socket)
		and is_instance_valid(_animation_player)
	):
		return true
	if not is_instance_valid(_owner_body):
		return false
	var visual_slot := _owner_body.get_node_or_null(
		VISUAL_SLOT_PATH
	) as Node3D
	if visual_slot == null:
		return false
	# Visual 插槽允许存在其他辅助/装饰子节点；只接受同时提供武器插槽
	# 与角色动画播放器的具体视觉场景，避免依赖固定子节点数量。
	_weapon_socket = null
	_animation_player = null
	var valid_visual_count: int = 0
	for child: Node in visual_slot.get_children():
		var candidate_visual := child as Node3D
		if candidate_visual == null:
			continue
		var candidate_socket := candidate_visual.get_node_or_null(
			WEAPON_SOCKET_PATH
		) as Node3D
		var candidate_animation := candidate_visual.get_node_or_null(
			NodePath(str(ANIMATION_PLAYER_NAME))
		) as CharacterAnimationEventPlayer
		if candidate_socket != null and candidate_animation != null:
			valid_visual_count += 1
			_weapon_socket = candidate_socket
			_animation_player = candidate_animation
	if (
		valid_visual_count != 1
		or _weapon_socket == null
		or _animation_player == null
	):
		_weapon_socket = null
		_animation_player = null
		return false

	var animation_callback := Callable(self, "_on_animation_finished")
	if not _animation_player.animation_finished.is_connected(
		animation_callback
	):
		_animation_player.animation_finished.connect(animation_callback)
	## AI 普通攻击只播放武器动画，不消费 attack_motion_requested。
	##
	## AnimationLibrary 仍会在原时间点正常发出该信号，玩家控制器也可以继续使用同一
	## 动画事件；这里只是不把它转换为 AIUnitBase 的 CharacterBody3D 真实位移。
	var open_callback := Callable(self, "_on_hit_window_open_requested")
	if not _animation_player.hit_window_open_requested.is_connected(
		open_callback
	):
		_animation_player.hit_window_open_requested.connect(open_callback)
	var close_callback := Callable(self, "_on_hit_window_close_requested")
	if not _animation_player.hit_window_close_requested.is_connected(
		close_callback
	):
		_animation_player.hit_window_close_requested.connect(close_callback)
	var projectile_callback := Callable(self, "_on_projectile_release_requested")
	if not _animation_player.projectile_release_requested.is_connected(
		projectile_callback
	):
		_animation_player.projectile_release_requested.connect(projectile_callback)
	var action_release_callback := Callable(
		self,
		"_on_external_action_release_requested"
	)
	if not _animation_player.action_release_requested.is_connected(
		action_release_callback
	):
		_animation_player.action_release_requested.connect(
			action_release_callback
		)
	var action_finish_callback := Callable(
		self,
		"_on_external_action_finish_requested"
	)
	if not _animation_player.action_finish_requested.is_connected(
		action_finish_callback
	):
		_animation_player.action_finish_requested.connect(
			action_finish_callback
		)
	return true


## 从动画的方法轨道中提取指定无参数方法的全部时间点。
##
## 第一版要求 release_action 唯一，避免一次动作意外重复交付技能。
func _find_method_marker_times(
	animation: Animation,
	method_name: StringName
) -> Array[float]:
	var result: Array[float] = []
	if animation == null:
		return result
	for track_index: int in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_METHOD:
			continue
		for key_index: int in range(
			animation.track_get_key_count(track_index)
		):
			var key_value: Variant = animation.track_get_key_value(
				track_index,
				key_index
			)
			if (
				key_value is Dictionary
				and StringName(
					(key_value as Dictionary).get("method", &"")
				) == method_name
			):
				result.append(
					animation.track_get_key_time(
						track_index,
						key_index
					)
				)
	return result


func _validate_weapon_data(weapon_data: WeaponData) -> Dictionary:
	if weapon_data == null:
		return {"valid": false, "reason": "WeaponData is null"}
	if weapon_data.visual_scene == null:
		return {"valid": false, "reason": "visual_scene is missing"}
	if weapon_data.animation_library == null:
		return {"valid": false, "reason": "animation_library is missing"}
	if not weapon_data.animation_library.has_animation(
		RESET_ANIMATION_NAME
	):
		return {"valid": false, "reason": "RESET animation is missing"}

	var attack_indices: Array[int] = []
	for animation_name: StringName in (
		weapon_data.animation_library.get_animation_list()
	):
		var name_text: String = str(animation_name)
		if not name_text.begins_with(BASIC_ATTACK_PREFIX):
			continue
		var suffix: String = name_text.trim_prefix(BASIC_ATTACK_PREFIX)
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
				"reason": "basic attack sequence has a gap at %d"
					% expected_index,
			}

	var visual_instance: Node = weapon_data.visual_scene.instantiate()
	if not visual_instance is Node3D:
		if visual_instance != null:
			visual_instance.free()
		return {
			"valid": false,
			"reason": "visual_scene root must be Node3D",
		}
	return {
		"valid": true,
		"visual": visual_instance as Node3D,
		"attack_count": attack_indices.back(),
	}


func _take_next_attack_index() -> int:
	if _attack_index_bag.is_empty():
		_refill_attack_index_bag()
	if _attack_index_bag.is_empty():
		return 0
	var selected_index: int = _attack_index_bag.pop_back()
	_last_selected_attack_index = selected_index
	return selected_index


func _refill_attack_index_bag() -> void:
	_attack_index_bag.clear()
	for attack_index: int in range(1, _attack_animation_count + 1):
		_attack_index_bag.append(attack_index)
	_attack_index_bag.shuffle()
	if (
		_attack_index_bag.size() > 1
		and _attack_index_bag.back() == _last_selected_attack_index
	):
		var last_index: int = _attack_index_bag.size() - 1
		var replacement_index: int = randi_range(0, last_index - 1)
		var replacement_value: int = _attack_index_bag[replacement_index]
		_attack_index_bag[replacement_index] = _attack_index_bag[last_index]
		_attack_index_bag[last_index] = replacement_value


func _is_valid_target(target: UnitBase) -> bool:
	return (
		is_instance_valid(target)
		and target.is_inside_tree()
		and target.is_targetable()
		and not target.is_dead()
		and is_instance_valid(_owner_body)
		and _owner_body.is_hostile_to(target)
	)


func _read_visual_forward() -> Vector3:
	if not is_instance_valid(_owner_body):
		return Vector3.ZERO
	var visual_slot := _owner_body.get_node_or_null(
		VISUAL_SLOT_PATH
	) as Node3D
	if visual_slot == null:
		return Vector3.ZERO
	var direction: Vector3 = -visual_slot.global_basis.z
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO


func _on_animation_finished(animation_name: StringName) -> void:
	if (
		_state == AttackState.EXTERNAL_ACTION
		and animation_name == _current_external_action_animation
	):
		_finish_external_action()
		return
	if (
		_state != AttackState.ATTACKING
		or animation_name != _current_attack_animation
	):
		return
	var finished_target: UnitBase = _current_target
	var finished_index: int = _current_attack_index
	set_hit_stop_active(false)
	_close_attack_hit_window()
	if is_instance_valid(_owner_body):
		_owner_body.cancel_attack_motion()
	_state = AttackState.IDLE
	_current_target = null
	_current_attack_index = 0
	_current_attack_animation = &""
	_locked_attack_direction = Vector3.FORWARD
	_play_reset_animation()
	attack_finished.emit(finished_target, finished_index)


func _on_external_action_release_requested() -> void:
	if _state == AttackState.EXTERNAL_ACTION:
		external_action_released.emit()


func _on_external_action_finish_requested() -> void:
	if _state == AttackState.EXTERNAL_ACTION:
		_finish_external_action()


func _finish_external_action() -> void:
	set_hit_stop_active(false)
	_current_external_action_animation = &""
	_external_melee_payload.clear()
	_state = AttackState.IDLE
	_play_reset_animation()
	external_action_finished.emit()


func _on_hit_window_open_requested() -> void:
	if _equipped_weapon == null:
		return
	if _state == AttackState.EXTERNAL_ACTION and not _external_melee_payload.is_empty():
		hit_window_opened.emit(_equipped_weapon, _current_target, 1, _locked_attack_direction)
		return
	if _state != AttackState.ATTACKING:
		return
	hit_window_opened.emit(
		_equipped_weapon,
		_current_target,
		_current_attack_index,
		_locked_attack_direction
	)


func _on_hit_window_close_requested() -> void:
	hit_window_closed.emit()


func _on_projectile_release_requested() -> void:
	if (
		_state != AttackState.ATTACKING
		or _equipped_weapon == null
		or not is_instance_valid(_current_target)
	):
		return
	projectile_release_requested.emit(
		_equipped_weapon,
		_current_target,
		_current_attack_index,
		_locked_attack_direction
	)


## 为独立交付组件提供已解析的武器插槽，避免重复搜索角色 Visual 层级。
func get_weapon_socket() -> Node3D:
	return _weapon_socket if is_instance_valid(_weapon_socket) else null


## 返回当前外部近战技能的只读命中载荷；空字典代表普通攻击或远程施法动作。
func get_external_melee_payload() -> Dictionary:
	return _external_melee_payload.duplicate()


func _close_attack_hit_window() -> void:
	hit_window_closed.emit()


func _play_reset_animation() -> void:
	if not is_instance_valid(_animation_player):
		return
	if is_instance_valid(_owner_body) and _owner_body.is_dead():
		return
	var reset_name := StringName(
		str(WEAPON_LIBRARY_NAME) + "/" + str(RESET_ANIMATION_NAME)
	)
	if _animation_player.has_animation(reset_name):
		_animation_player.play(reset_name)
	else:
		_animation_player.stop()


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
		_animation_player.stop()
		_animation_player.current_animation = &""
		_animation_player.remove_animation_library(WEAPON_LIBRARY_NAME)
	_attack_animation_count = 0
	_attack_index_bag.clear()
	_last_selected_attack_index = 0
	if clear_weapon_data:
		_equipped_weapon = null


func _exit_tree() -> void:
	set_hit_stop_active(false)
	_close_attack_hit_window()
	if is_instance_valid(_owner_body):
		_owner_body.cancel_attack_motion()
