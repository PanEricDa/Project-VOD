extends Node3D

## 可整体拆装的三连击近战模块。
## 本脚本只管理输入、连击状态与动画事件，不读取或修改玩家移动、冲刺、重力和锁定逻辑。

signal combo_started()
signal attack_started(combo_index: int)
signal combo_window_opened(combo_index: int)
signal hit_window_opened(combo_index: int)
signal hit_window_closed(combo_index: int)
signal attack_finished(combo_index: int)
signal combo_finished()
signal lunge_started(combo_index: int, distance: float)
signal lunge_finished(combo_index: int)
signal spin_started(combo_index: int, revolutions: float)
signal spin_finished(combo_index: int)
signal attack_hit(
	target: CharacterBody3D,
	hit_position: Vector3,
	hit_direction: Vector3,
	combo_index: int
)

enum AttackState {
	IDLE,
	ATTACKING,
	CHAIN_WAIT
}

@export_category("Input")
## 触发近战攻击的 InputMap 动作名称，默认绑定鼠标右键。
@export var attack_action: StringName = &"player_attack"

@export_category("Animation")
## 动画播放器路径。未来替换正式动画资产时可指向新的 AnimationPlayer。
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = ^"AttackAnimationPlayer"

## 三段攻击动画名称，数组顺序就是连击顺序。
@export var attack_animation_names: Array[StringName] = [
	&"attack_1",
	&"attack_2",
	&"attack_3"
]

## 非攻击状态下用于恢复武器默认姿态的动画名称。
@export var reset_animation_name: StringName = &"RESET"

@export_category("Combo")
## 攻击输入可被暂存的时间。连击窗口开启时，尚未过期的输入会排队到下一段。
@export_range(0.0, 1.0, 0.01) var input_buffer_duration: float = 0.15

## 当前攻击结束但没有排队输入时，仍允许续接下一段的等待时间。
@export_range(0.0, 2.0, 0.05) var combo_reset_duration: float = 0.7

@export_category("Attack Lunge")
## 是否启用每段近战攻击的轻微物理前移；关闭后只播放武器动画。
@export var lunge_enabled: bool = true

## 三段攻击各自希望前移的总距离，单位为米；数组顺序与 attack_animation_names 一致。
@export var lunge_distances: Array[float] = [0.2, 0.25, 0.35]

## 三段攻击各自完成前移所需的时间，单位为秒。
@export var lunge_durations: Array[float] = [0.10, 0.12, 0.16]

## 相对于模块根节点的玩家 CharacterBody3D 路径。
## 默认模块位于 Hero/Visual/AttackSpinPivot 下，因此 ../../.. 指向 Hero。
@export_node_path("CharacterBody3D") var character_body_path: NodePath = ^"../../.."

## 相对于模块根节点的玩家稳定正面节点路径，默认 ../.. 指向 Hero/Visual。
@export_node_path("Node3D") var facing_node_path: NodePath = ^"../.."

@export_category("Third Attack Spin")
## 是否启用第三段攻击的视觉顺时针旋转。
@export var third_attack_spin_enabled: bool = true

## 第三段攻击旋转的圈数，默认完整旋转一圈。
@export_range(0.0, 3.0, 0.05, "or_greater") var third_attack_spin_revolutions: float = 1.0

## 完成第三段旋转所需时间，单位为秒。
@export_range(0.05, 1.0, 0.01, "or_greater") var third_attack_spin_duration: float = 0.32

## 正式顺时针旋转前，角色先逆时针转动的蓄力角度。
@export_range(0.0, 180.0, 1.0) var third_attack_spin_windup_degrees: float = 90.0

## 整个旋转时间中分配给逆时针蓄力阶段的比例。
@export_range(0.05, 0.5, 0.01) var third_attack_spin_windup_ratio: float = 0.22

## 逆时针蓄力结束后的短暂停顿时间；暂停期间第三击尚未进入攻击判定阶段。
@export_range(0.0, 0.3, 0.005, "or_greater") var third_attack_spin_windup_pause: float = 0.2

## 只承载攻击视觉旋转的枢轴路径，默认父节点 AttackSpinPivot。
@export_node_path("Node3D") var spin_pivot_path: NodePath = ^".."

@onready var attack_animation_player: AnimationPlayer = get_node(animation_player_path) as AnimationPlayer
@onready var melee_hit_detector: Node = $MeleeHitDetector

var character_body: CharacterBody3D
var facing_node: Node3D
var spin_pivot: Node3D

var attack_state: AttackState = AttackState.IDLE
var current_combo_index: int = -1
var queued_next_attack: bool = false
var combo_window_is_open: bool = false
var hit_window_is_open: bool = false
var input_buffer_remaining: float = 0.0
var combo_wait_remaining: float = 0.0
var lunge_initial_distance: float = 0.0
var lunge_duration: float = 0.0
var lunge_elapsed: float = 0.0
var lunge_combo_index: int = 0
var lunge_is_active: bool = false
var spin_initial_yaw: float = 0.0
var spin_duration: float = 0.0
var spin_elapsed: float = 0.0
var spin_combo_index: int = 0
var spin_is_active: bool = false
var spin_windup_pause_remaining: float = 0.0
var spin_windup_pause_is_active: bool = false
var spin_attack_phase_started: bool = false
var hit_stop_is_active: bool = false
var animation_was_playing_before_hit_stop: bool = false


## 初始化动画结束监听，并确保武器从 RESET 姿态开始。
func _ready() -> void:
	character_body = get_node_or_null(character_body_path) as CharacterBody3D
	facing_node = get_node_or_null(facing_node_path) as Node3D
	spin_pivot = get_node_or_null(spin_pivot_path) as Node3D
	melee_hit_detector.configure(character_body, facing_node)
	if not melee_hit_detector.attack_hit.is_connected(_on_melee_hit_detector_attack_hit):
		melee_hit_detector.attack_hit.connect(_on_melee_hit_detector_attack_hit)
	if character_body == null or facing_node == null:
		push_warning(
			"MeleeAttackModule: lunge node paths are invalid; attack animations remain available. "
			+ "Body=" + str(character_body_path)
			+ ", Facing=" + str(facing_node_path)
		)

	if attack_animation_player == null:
		push_error("MeleeAttackModule: animation_player_path is invalid: " + str(animation_player_path))
		set_process(false)
		set_process_unhandled_input(false)
		return

	if not attack_animation_player.animation_finished.is_connected(_on_animation_finished):
		attack_animation_player.animation_finished.connect(_on_animation_finished)

	_play_reset_animation()


## 在玩家自身的 move_and_slide 完成后追加本帧攻击前移，不读取或覆盖玩家 velocity。
func _physics_process(delta: float) -> void:
	if hit_stop_is_active:
		return
	_process_spin(delta)
	# 第三击蓄力后的短暂停顿只冻结本模块的攻击位移，不影响 HeroController 的正常移动。
	if spin_windup_pause_is_active:
		return
	_process_lunge(delta)


## 模块自行读取 InputMap，不要求 HeroController 转发输入。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(attack_action):
		request_attack()
		get_viewport().set_input_as_handled()


## 更新输入缓存和连击续接等待时间，不参与任何角色物理移动。
func _process(delta: float) -> void:
	if hit_stop_is_active:
		return
	input_buffer_remaining = max(input_buffer_remaining - delta, 0.0)

	if attack_state != AttackState.CHAIN_WAIT:
		return

	combo_wait_remaining = max(combo_wait_remaining - delta, 0.0)
	if combo_wait_remaining <= 0.0:
		_finish_combo()


## 请求一次攻击。可由 InputMap、AI、技能系统或测试代码共同调用。
func request_attack() -> void:
	if attack_animation_names.is_empty():
		return

	match attack_state:
		AttackState.IDLE:
			combo_started.emit()
			_start_attack(0)
		AttackState.ATTACKING:
			input_buffer_remaining = input_buffer_duration
			# 当前段播放期间的输入直接作为下一段缓存；连击窗口仍负责向外部系统报告正式续接时机。
			# 这样可以容忍极短动画和低帧率，不要求玩家精确命中某一个方法轨道帧。
			if current_combo_index < attack_animation_names.size() - 1:
				queued_next_attack = true
		AttackState.CHAIN_WAIT:
			if current_combo_index < attack_animation_names.size() - 1:
				_start_attack(current_combo_index + 1)
			else:
				_finish_combo()


## 立即取消当前攻击并恢复默认姿态，同时发送 combo_finished 信号。
func cancel_combo() -> void:
	if attack_state == AttackState.IDLE:
		reset_module()
		return

	_finish_combo()


## 将模块恢复到初始状态。该接口便于场景切换、禁用战斗或替换动画资产时调用。
func reset_module() -> void:
	set_hit_stop_active(false)
	_cancel_lunge()
	_cancel_spin()
	melee_hit_detector.end_attack()
	attack_state = AttackState.IDLE
	current_combo_index = -1
	queued_next_attack = false
	combo_window_is_open = false
	hit_window_is_open = false
	input_buffer_remaining = 0.0
	combo_wait_remaining = 0.0
	_play_reset_animation()


## 返回当前是否正在实际播放攻击动画；连击等待阶段返回 false。
func is_attacking() -> bool:
	return attack_state == AttackState.ATTACKING


## 返回当前连击段数，使用 1、2、3 表示；未进入连击时返回 0。
func get_combo_index() -> int:
	return current_combo_index + 1


## 外部效果系统使用的局部卡刀接口。
## 暂停时冻结攻击动画、前移、第三击旋转和新的命中查询，但不影响 HeroController 或场景树。
func set_hit_stop_active(active: bool) -> void:
	if hit_stop_is_active == active:
		return

	hit_stop_is_active = active
	if melee_hit_detector.has_method("set_detection_suspended"):
		melee_hit_detector.call("set_detection_suspended", active)

	if active:
		animation_was_playing_before_hit_stop = attack_animation_player.is_playing()
		if animation_was_playing_before_hit_stop:
			attack_animation_player.pause()
		return

	if animation_was_playing_before_hit_stop and attack_state == AttackState.ATTACKING:
		attack_animation_player.play()
	animation_was_playing_before_hit_stop = false


## 返回当前攻击模块是否正被外部效果桥局部暂停。
func is_hit_stop_active() -> bool:
	return hit_stop_is_active


## 播放指定数组索引对应的攻击动画，并重置该段的窗口状态。
func _start_attack(animation_index: int) -> void:
	if animation_index < 0 or animation_index >= attack_animation_names.size():
		_finish_combo()
		return

	var animation_name: StringName = attack_animation_names[animation_index]
	if not attack_animation_player.has_animation(animation_name):
		push_error("MeleeAttackModule: missing attack animation: " + str(animation_name))
		_finish_combo()
		return

	attack_state = AttackState.ATTACKING
	current_combo_index = animation_index
	queued_next_attack = false
	combo_window_is_open = false
	hit_window_is_open = false
	input_buffer_remaining = 0.0
	combo_wait_remaining = 0.0
	attack_animation_player.play(animation_name)
	attack_started.emit(get_combo_index())


## AnimationPlayer 方法轨道调用：开启可接受下一段输入的连击窗口。
func _open_combo_window() -> void:
	if attack_state != AttackState.ATTACKING:
		return

	combo_window_is_open = true
	combo_window_opened.emit(get_combo_index())
	if input_buffer_remaining > 0.0 and current_combo_index < attack_animation_names.size() - 1:
		queued_next_attack = true


## AnimationPlayer 方法轨道调用：关闭当前攻击的连击输入窗口。
func _close_combo_window() -> void:
	combo_window_is_open = false


## AnimationPlayer 方法轨道调用：开放未来伤害组件使用的有效攻击窗口。
func _open_hit_window() -> void:
	if attack_state != AttackState.ATTACKING or hit_window_is_open:
		return

	hit_window_is_open = true
	melee_hit_detector.begin_attack(get_combo_index())
	hit_window_opened.emit(get_combo_index())


## AnimationPlayer 方法轨道调用：关闭未来伤害组件使用的有效攻击窗口。
func _close_hit_window() -> void:
	if not hit_window_is_open:
		return

	hit_window_is_open = false
	melee_hit_detector.end_attack()
	hit_window_closed.emit(get_combo_index())


## 转发检测器的统一命中结果，使外部伤害系统只需要连接 MeleeAttackModule。
func _on_melee_hit_detector_attack_hit(
	target: CharacterBody3D,
	hit_position: Vector3,
	hit_direction: Vector3,
	combo_index: int
) -> void:
	attack_hit.emit(target, hit_position, hit_direction, combo_index)


## AnimationPlayer 方法轨道调用：根据当前连击段数启动对应的轻微前移。
func _request_lunge_for_current_attack() -> void:
	if not lunge_enabled or attack_state != AttackState.ATTACKING:
		return
	if character_body == null or facing_node == null:
		return

	var array_index: int = current_combo_index
	if array_index < 0 or array_index >= lunge_distances.size() or array_index >= lunge_durations.size():
		return

	var requested_distance: float = max(lunge_distances[array_index], 0.0)
	var requested_duration: float = max(lunge_durations[array_index], 0.001)
	if requested_distance <= 0.0:
		return

	lunge_initial_distance = requested_distance
	lunge_duration = requested_duration
	lunge_elapsed = 0.0
	lunge_combo_index = get_combo_index()
	lunge_is_active = true
	lunge_started.emit(lunge_combo_index, lunge_initial_distance)


## 使用二次缓出曲线分配每帧位移，并通过 move_and_collide 保证墙体能够阻挡前移。
## 位移方向每帧读取玩家视觉正前方，因此锁定目标转向时会自然沿目标方向推进。
func _process_lunge(delta: float) -> void:
	if not lunge_is_active:
		return
	if not is_instance_valid(character_body) or not is_instance_valid(facing_node):
		_cancel_lunge()
		return

	var previous_progress: float = clamp(lunge_elapsed / lunge_duration, 0.0, 1.0)
	lunge_elapsed = min(lunge_elapsed + delta, lunge_duration)
	var current_progress: float = clamp(lunge_elapsed / lunge_duration, 0.0, 1.0)
	var previous_eased: float = 1.0 - pow(1.0 - previous_progress, 2.0)
	var current_eased: float = 1.0 - pow(1.0 - current_progress, 2.0)
	var frame_distance: float = lunge_initial_distance * (current_eased - previous_eased)

	var forward_direction: Vector3 = -facing_node.global_basis.z
	forward_direction.y = 0.0
	if forward_direction.length_squared() <= 0.0001:
		_cancel_lunge()
		return

	var collision: KinematicCollision3D = character_body.move_and_collide(
		forward_direction.normalized() * frame_distance
	)
	if collision != null:
		_finish_lunge()
		return

	if lunge_elapsed >= lunge_duration:
		_finish_lunge()


## 取消尚未完成的前移，不发送完成信号；用于取消连击或重置模块。
func _cancel_lunge() -> void:
	lunge_is_active = false
	lunge_initial_distance = 0.0
	lunge_duration = 0.0
	lunge_elapsed = 0.0
	lunge_combo_index = 0


## 正常完成或被墙体阻挡时结束本段前移，并发送对应段数的完成信号。
func _finish_lunge() -> void:
	if not lunge_is_active:
		return

	var finished_combo_index: int = lunge_combo_index
	_cancel_lunge()
	lunge_finished.emit(finished_combo_index)


## AnimationPlayer 方法轨道调用：第三击开始时启动视觉枢轴的顺时针整圈旋转。
func _request_third_attack_spin() -> void:
	if not third_attack_spin_enabled or current_combo_index != 2:
		return
	if spin_pivot == null or third_attack_spin_revolutions <= 0.0:
		return
	# 动画方法轨道或外部测试重复发出请求时，保留当前旋转进度，避免中途重新记录角度并导致朝向漂移。
	if spin_is_active:
		return

	spin_initial_yaw = spin_pivot.rotation.y
	spin_duration = max(third_attack_spin_duration, 0.001)
	spin_elapsed = 0.0
	spin_combo_index = get_combo_index()
	spin_is_active = true
	spin_windup_pause_remaining = 0.0
	spin_windup_pause_is_active = false
	spin_attack_phase_started = false
	spin_started.emit(spin_combo_index, third_attack_spin_revolutions)


## 先逆时针转到配置的蓄力角度，再顺时针越过一整圈并回到初始正向。
## 旋转只作用于 AttackSpinPivot，不会改变 Hero/Visual 的游戏朝向或伙伴编队参照。
func _process_spin(delta: float) -> void:
	if not spin_is_active:
		return
	if not is_instance_valid(spin_pivot):
		_cancel_spin()
		return

	# 蓄力到达 90° 后保持姿态短暂停顿；结束时才开启第三击检测并恢复动画。
	if spin_windup_pause_is_active:
		spin_windup_pause_remaining = max(spin_windup_pause_remaining - delta, 0.0)
		if spin_windup_pause_remaining <= 0.0:
			spin_windup_pause_is_active = false
			spin_attack_phase_started = true
			_open_hit_window()
			if attack_state == AttackState.ATTACKING and not hit_stop_is_active:
				attack_animation_player.play()
		return

	spin_elapsed = min(spin_elapsed + delta, spin_duration)
	var progress: float = clamp(spin_elapsed / spin_duration, 0.0, 1.0)
	var windup_ratio: float = clamp(third_attack_spin_windup_ratio, 0.01, 0.99)
	var windup_angle: float = deg_to_rad(third_attack_spin_windup_degrees)
	# 即使某一物理帧跨过阶段分界，也先钳制到准确的蓄力终点，保证短暂停顿不会被跳过。
	if (
		not spin_attack_phase_started
		and progress >= windup_ratio
		and third_attack_spin_windup_pause > 0.0
	):
		spin_elapsed = spin_duration * windup_ratio
		spin_pivot.rotation.y = spin_initial_yaw + windup_angle
		spin_windup_pause_remaining = third_attack_spin_windup_pause
		spin_windup_pause_is_active = true
		attack_animation_player.pause()
		return

	if progress <= windup_ratio:
		var windup_progress: float = clamp(progress / windup_ratio, 0.0, 1.0)
		var windup_smooth: float = windup_progress * windup_progress * (3.0 - 2.0 * windup_progress)
		spin_pivot.rotation.y = spin_initial_yaw + windup_angle * windup_smooth
		if progress >= windup_ratio:
			spin_attack_phase_started = true
			_open_hit_window()
	else:
		# 没有配置暂停或低帧率直接跨过分界点时，仍确保判定只从正式旋转阶段开始。
		if not spin_attack_phase_started:
			spin_attack_phase_started = true
			_open_hit_window()
		var clockwise_progress: float = clamp(
			(progress - windup_ratio) / (1.0 - windup_ratio),
			0.0,
			1.0
		)
		var clockwise_smooth: float = (
			clockwise_progress
			* clockwise_progress
			* (3.0 - 2.0 * clockwise_progress)
		)
		# 从 +90° 蓄力位置顺时针移动到 -360°，总顺时针行程为 450°，终点等价于初始正向。
		var final_clockwise_angle: float = -TAU * third_attack_spin_revolutions
		var current_relative_angle: float = lerp(
			windup_angle,
			final_clockwise_angle,
			clockwise_smooth
		)
		spin_pivot.rotation.y = spin_initial_yaw + current_relative_angle

	if spin_elapsed >= spin_duration:
		_finish_spin()


## 取消未完成旋转并恢复触发前姿态，保证 cancel_combo 和模块重置不会留下视觉偏转。
func _cancel_spin() -> void:
	if spin_is_active and is_instance_valid(spin_pivot):
		spin_pivot.rotation.y = spin_initial_yaw

	spin_is_active = false
	spin_initial_yaw = 0.0
	spin_duration = 0.0
	spin_elapsed = 0.0
	spin_combo_index = 0
	spin_windup_pause_remaining = 0.0
	spin_windup_pause_is_active = false
	spin_attack_phase_started = false


## 完成整圈后恢复等价的初始角度数值，并发送第三击旋转完成信号。
func _finish_spin() -> void:
	if not spin_is_active:
		return

	var finished_combo_index: int = spin_combo_index
	if is_instance_valid(spin_pivot):
		spin_pivot.rotation.y = spin_initial_yaw
	spin_is_active = false
	spin_initial_yaw = 0.0
	spin_duration = 0.0
	spin_elapsed = 0.0
	spin_combo_index = 0
	spin_windup_pause_remaining = 0.0
	spin_windup_pause_is_active = false
	spin_attack_phase_started = false
	spin_finished.emit(finished_combo_index)


## 当前攻击动画结束后，优先执行已排队的下一段；否则进入可续接等待阶段。
func _on_animation_finished(animation_name: StringName) -> void:
	if attack_state != AttackState.ATTACKING:
		return
	if attack_animation_names[current_combo_index] != animation_name:
		return

	_close_hit_window()
	_close_combo_window()
	attack_finished.emit(get_combo_index())

	if queued_next_attack and current_combo_index < attack_animation_names.size() - 1:
		_start_attack(current_combo_index + 1)
		return

	if current_combo_index >= attack_animation_names.size() - 1:
		_finish_combo()
		return

	attack_state = AttackState.CHAIN_WAIT
	combo_wait_remaining = combo_reset_duration
	_play_reset_animation()


## 完整结束当前连击，恢复 RESET，并向外部系统报告连击结束。
func _finish_combo() -> void:
	var combo_was_active: bool = attack_state != AttackState.IDLE
	reset_module()
	if combo_was_active:
		combo_finished.emit()


## 安全播放 RESET；正式资产只需提供同名动画或修改导出字段。
func _play_reset_animation() -> void:
	if attack_animation_player != null and attack_animation_player.has_animation(reset_animation_name):
		attack_animation_player.play(reset_animation_name)
