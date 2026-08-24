class_name AIAttackModuleBase
extends Node3D

## AI 武器普通攻击组件的公共生命周期基类。
## 模块不读取 InputMap、不搜索目标，也不控制持有者的移动、朝向、重力或公共冷却。

signal attack_started(target: CharacterBody3D)
signal hit_window_opened(target: CharacterBody3D)
signal hit_window_closed(target: CharacterBody3D)
signal attack_finished(target: CharacterBody3D)
signal attack_cancelled(target: CharacterBody3D)
signal attack_hit(
	target: CharacterBody3D,
	hit_position: Vector3,
	hit_direction: Vector3
)

enum AttackState {
	IDLE,
	ATTACKING
}

@export_category("Attack Profile")
## 当前武器使用的静态攻击配置；每个继承模块应替换为自己的可复用 .tres。
@export var attack_profile: AIAttackProfile

@export_category("Animation")
## 模块内部 AnimationPlayer 的相对路径。
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = ^"AttackAnimationPlayer"

## 普通攻击动画名称；继承场景可以覆盖同名动画或改用其他名称。
@export var attack_animation_name: StringName = &"attack"

## 模块恢复静止姿态时使用的动画名称。
@export var reset_animation_name: StringName = &"RESET"

@export_category("Hitbox")
## 是否让动画命中窗口驱动父场景内置的通用体积检测；远程模块默认保持关闭。
@export var hitbox_enabled: bool = false

## 父场景内通用 Hitbox 检测组件的相对路径。
@export_node_path("Node3D") var hitbox_detector_path: NodePath = ^"DeliveryRoot/HitboxDetector"

@export_category("Hit Feedback")
## 是否允许继承自父场景的通用效果桥在命中时触发局部卡刀。
## 关闭后 attack_hit 信号仍会正常发送，伤害等未来监听者不会受到影响。
@export var hit_feedback_enabled: bool = true

@onready var attack_animation_player: AnimationPlayer = get_node_or_null(
	animation_player_path
) as AnimationPlayer

@onready var hitbox_detector: Node = get_node_or_null(
	hitbox_detector_path
)

## 当前模块生命周期状态。普通攻击公共冷却由 AllyBase 持有，不属于这里。
var attack_state: AttackState = AttackState.IDLE

## 当前攻击绑定的敌方目标；完成、取消或重置时清空。
var current_target: CharacterBody3D

## 当前动画方法轨道是否已经打开逻辑命中窗口。
var hit_window_is_open: bool = false

## 当前模块的物理持有者，由 AllyBase 装备接口注入，不依赖固定祖先节点路径。
var attack_owner: CharacterBody3D

## 当前攻击模块是否正被外部效果桥局部暂停。
var hit_stop_is_active: bool = false

## 进入停顿前动画是否确实在播放，用于解除停顿时精确恢复原进度。
var animation_was_playing_before_hit_stop: bool = false


## 初始化动画完成监听，并把模块恢复到 RESET 姿态。
func _ready() -> void:
	if attack_animation_player == null:
		push_error(
			"AIAttackModuleBase: animation_player_path is invalid: "
			+ str(animation_player_path)
		)
		return

	if not attack_animation_player.animation_finished.is_connected(_on_animation_finished):
		attack_animation_player.animation_finished.connect(_on_animation_finished)
	if hitbox_detector != null:
		if not hitbox_detector.hit_detected.is_connected(_on_hitbox_hit_detected):
			hitbox_detector.hit_detected.connect(_on_hitbox_hit_detected)
		hitbox_detector.configure(attack_owner)
	elif hitbox_enabled:
		push_warning(
			"AIAttackModuleBase: hitbox_enabled is true but hitbox_detector_path is invalid: "
			+ str(hitbox_detector_path)
		)
	reset_module()


## 请求模块对指定目标播放一次普通攻击。
## 返回 true 表示动画成功开始，调用者此时才应该启动普通攻击公共冷却。
func request_attack(target: CharacterBody3D) -> bool:
	if not can_attack():
		return false
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false

	current_target = target
	attack_state = AttackState.ATTACKING
	hit_window_is_open = false
	attack_animation_player.play(attack_animation_name)
	attack_started.emit(current_target)
	return true


## 取消正在执行的攻击并恢复默认姿态；不会修改持有者的公共冷却。
func cancel_attack() -> void:
	if attack_state != AttackState.ATTACKING:
		reset_module()
		return

	var cancelled_target: CharacterBody3D = current_target
	reset_module()
	attack_cancelled.emit(cancelled_target)


## 将模块恢复为可立即接收攻击请求的初始状态，供卸装、脱战或场景重置调用。
func reset_module() -> void:
	set_hit_stop_active(false)
	_close_hit_window()
	attack_state = AttackState.IDLE
	current_target = null
	if attack_animation_player == null:
		return
	attack_animation_player.stop()
	if attack_animation_player.has_animation(reset_animation_name):
		attack_animation_player.play(reset_animation_name)


## Profile、AnimationPlayer、动画和当前状态都有效时返回 true。
func can_attack() -> bool:
	return (
		attack_state == AttackState.IDLE
		and attack_profile != null
		and attack_animation_player != null
		and attack_animation_player.has_animation(attack_animation_name)
	)


## 当前正在播放实际攻击动画时返回 true。
func is_attacking() -> bool:
	return attack_state == AttackState.ATTACKING


## 外部 Effect 使用的统一局部卡刀接口。
## 只冻结当前攻击动画与 Hitbox 查询，不更改 AllyBase、公共冷却、重力或场景树处理状态。
func set_hit_stop_active(active: bool) -> void:
	if hit_stop_is_active == active:
		return

	hit_stop_is_active = active
	if hitbox_detector != null and hitbox_detector.has_method("set_detection_suspended"):
		hitbox_detector.call("set_detection_suspended", active)

	if not is_instance_valid(attack_animation_player):
		animation_was_playing_before_hit_stop = false
		return

	if active:
		animation_was_playing_before_hit_stop = attack_animation_player.is_playing()
		if animation_was_playing_before_hit_stop:
			attack_animation_player.pause()
		return

	if animation_was_playing_before_hit_stop and attack_state == AttackState.ATTACKING:
		attack_animation_player.play()
	animation_was_playing_before_hit_stop = false


## 返回当前攻击模块是否正处于外部效果触发的局部停顿。
func is_hit_stop_active() -> bool:
	return hit_stop_is_active


## 效果桥通过该开放接口读取模块级开关，避免把 AI 专用类型绑定进通用 Effect。
func is_hit_feedback_enabled() -> bool:
	return hit_feedback_enabled


## 返回武器允许发动攻击的水平中心距离，缺少 Profile 时返回 0。
func get_attack_range() -> float:
	if attack_profile == null:
		return 0.0
	return max(attack_profile.attack_range, 0.0)


## 返回攻击距离判定迟滞容差，缺少 Profile 时返回 0。
func get_attack_range_tolerance() -> float:
	if attack_profile == null:
		return 0.0
	return max(attack_profile.attack_range_tolerance, 0.0)


## 返回主人接近攻击范围时使用的移动速度倍率。
func get_approach_speed_multiplier() -> float:
	if attack_profile == null:
		return 1.0
	return max(attack_profile.approach_speed_multiplier, 0.0)


## 返回本武器攻击结束后是否要求主人回到职业警戒距离。
func should_return_to_guard_after_attack() -> bool:
	return attack_profile != null and attack_profile.return_to_guard_after_attack


## 注入或清除攻击模块的物理持有者，并转发给通用检测组件排除自身碰撞。
func configure_attack_owner(body: CharacterBody3D) -> void:
	attack_owner = body
	if hitbox_detector != null:
		hitbox_detector.configure(attack_owner)


## AnimationPlayer 方法轨道调用：打开未来检测器、投射物或技能 Delivery 的有效窗口。
func _open_hit_window() -> void:
	if attack_state != AttackState.ATTACKING or hit_window_is_open:
		return
	hit_window_is_open = true
	if hitbox_enabled and hitbox_detector != null:
		hitbox_detector.begin_detection()
	hit_window_opened.emit(current_target)


## AnimationPlayer 方法轨道调用：关闭当前有效窗口；重复调用不会重复发送信号。
func _close_hit_window() -> void:
	if hitbox_detector != null:
		hitbox_detector.end_detection()
	if not hit_window_is_open:
		return
	hit_window_is_open = false
	hit_window_closed.emit(current_target)


## 将独立检测组件的结果转发为攻击模块统一命中接口。
func _on_hitbox_hit_detected(
	target: CharacterBody3D,
	hit_position: Vector3,
	hit_direction: Vector3
) -> void:
	attack_hit.emit(target, hit_position, hit_direction)


## 动画结束后关闭窗口、清理目标并立即返回 IDLE。
## 是否允许再次攻击由持有者的公共冷却决定，模块自身不追加等待时间。
func _on_animation_finished(animation_name: StringName) -> void:
	if attack_state != AttackState.ATTACKING or animation_name != attack_animation_name:
		return

	var finished_target: CharacterBody3D = current_target
	set_hit_stop_active(false)
	_close_hit_window()
	current_target = null
	attack_state = AttackState.IDLE
	if attack_animation_player.has_animation(reset_animation_name):
		attack_animation_player.play(reset_animation_name)
	attack_finished.emit(finished_target)


## 节点被卸下时确保不会遗留暂停的 AnimationPlayer 或 ShapeCast 状态。
func _exit_tree() -> void:
	reset_module()
