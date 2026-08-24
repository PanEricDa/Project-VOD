extends Node

## 将近战模块的 attack_hit 信号转换为局部卡刀与摄像机震动。
## 本节点不处理伤害，也不依赖 HeroController；删除本节点即可完整关闭命中反馈。

signal feedback_started(combo_index: int, intensity: float)
signal feedback_finished()

@export_category("Source")
## 相对于效果桥的攻击来源路径；目标必须提供 attack_hit 信号和 set_hit_stop_active 方法。
@export_node_path("Node") var attack_source_path: NodePath = ^"../Visual/AttackSpinPivot/MeleeAttackModule"

## 当前使用的外部反馈配置资源，可在 Inspector 中替换为其他武器或命中类型的 .tres。
@export var effect_profile: HitFeedbackProfile

var attack_source: Node
var active_camera: Camera3D
var random_generator: RandomNumberGenerator = RandomNumberGenerator.new()

var feedback_cooldown_remaining: float = 0.0
var hit_stop_remaining: float = 0.0
var hit_stop_is_active: bool = false

var shake_remaining: float = 0.0
var shake_total_duration: float = 0.0
var shake_amplitude: float = 0.0
var shake_sample_remaining: float = 0.0
var shake_target_offset: Vector3 = Vector3.ZERO
var shake_current_offset: Vector3 = Vector3.ZERO
var last_applied_camera_offset: Vector3 = Vector3.ZERO


## 解析攻击来源并监听统一命中信号。PROCESS_MODE_ALWAYS 保证局部卡刀不会停止效果计时。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	random_generator.randomize()
	attack_source = get_node_or_null(attack_source_path)
	if attack_source == null or not attack_source.has_signal("attack_hit"):
		push_error("HitFeedbackBridge: attack_source_path does not provide attack_hit: " + str(attack_source_path))
		set_process(false)
		return

	var hit_callable: Callable = Callable(self, "play_hit_feedback")
	if not attack_source.is_connected("attack_hit", hit_callable):
		attack_source.connect("attack_hit", hit_callable)

	if effect_profile == null:
		push_warning("HitFeedbackBridge: effect_profile is not configured; feedback is disabled.")


## 独立更新停顿计时和摄像机震动，不改变场景树或全局 time_scale。
func _process(delta: float) -> void:
	feedback_cooldown_remaining = max(feedback_cooldown_remaining - delta, 0.0)
	_update_hit_stop(delta)
	_update_camera_shake(delta)


## 公共反馈入口，签名与 MeleeAttackModule.attack_hit 完全一致。
## target、hit_position 和 hit_direction 当前保留给未来方向性震动、音效和粒子扩展。
func play_hit_feedback(
	target: CharacterBody3D,
	hit_position: Vector3,
	hit_direction: Vector3,
	combo_index: int = 1
) -> void:
	if effect_profile == null or not is_instance_valid(target):
		return
	# AI 攻击父模块可以通过统一开关禁用反馈；玩家模块没有该可选接口，因此保持原有行为。
	if (
		attack_source != null
		and attack_source.has_method("is_hit_feedback_enabled")
		and attack_source.call("is_hit_feedback_enabled") != true
	):
		return
	if feedback_cooldown_remaining > 0.0:
		return

	# 显式读取参数，确保接口已为未来方向性效果保留，同时避免临时阶段产生未使用参数警告。
	var _reserved_hit_position: Vector3 = hit_position
	var _reserved_hit_direction: Vector3 = hit_direction
	var intensity: float = effect_profile.get_combo_intensity(combo_index)
	feedback_cooldown_remaining = effect_profile.minimum_feedback_interval

	if effect_profile.hit_stop_enabled and effect_profile.hit_stop_duration > 0.0:
		_start_or_extend_hit_stop(effect_profile.hit_stop_duration * intensity)

	if effect_profile.camera_shake_enabled and effect_profile.shake_duration > 0.0:
		_start_or_refresh_camera_shake(intensity)

	feedback_started.emit(combo_index, intensity)


## 启动或延长局部卡刀；重复反馈只保留较大的剩余时间，不创建重叠计时任务。
func _start_or_extend_hit_stop(duration: float) -> void:
	hit_stop_remaining = max(hit_stop_remaining, max(duration, 0.0))
	if hit_stop_is_active or attack_source == null:
		return

	hit_stop_is_active = true
	if attack_source.has_method("set_hit_stop_active"):
		attack_source.call("set_hit_stop_active", true)


## 更新局部停顿，时间结束后恢复攻击模块原有播放进度。
func _update_hit_stop(delta: float) -> void:
	if not hit_stop_is_active:
		return

	hit_stop_remaining = max(hit_stop_remaining - delta, 0.0)
	if hit_stop_remaining > 0.0:
		return

	hit_stop_is_active = false
	if is_instance_valid(attack_source) and attack_source.has_method("set_hit_stop_active"):
		attack_source.call("set_hit_stop_active", false)
	_try_emit_feedback_finished()


## 刷新摄像机震动持续时间与本次强度，不累加多个独立震动协程。
func _start_or_refresh_camera_shake(intensity: float) -> void:
	shake_total_duration = max(effect_profile.shake_duration, 0.001)
	shake_remaining = shake_total_duration
	shake_amplitude = effect_profile.shake_amplitude * intensity
	shake_sample_remaining = 0.0
	shake_target_offset = Vector3.ZERO


## 对当前 Camera3D 添加局部 X/Y 随机偏移，并按指数曲线衰减。
## 每帧先移除旧偏移再添加新偏移，CameraRig 跟随和其他摄像机移动可以继续正常工作。
func _update_camera_shake(delta: float) -> void:
	var viewport_camera: Camera3D = get_viewport().get_camera_3d()
	if viewport_camera != active_camera:
		_remove_last_camera_offset()
		active_camera = viewport_camera

	if shake_remaining <= 0.0 or active_camera == null:
		_remove_last_camera_offset()
		return

	_remove_last_camera_offset()
	shake_remaining = max(shake_remaining - delta, 0.0)
	if shake_remaining <= 0.0:
		shake_current_offset = Vector3.ZERO
		shake_target_offset = Vector3.ZERO
		_try_emit_feedback_finished()
		return

	shake_sample_remaining -= delta
	if shake_sample_remaining <= 0.0:
		var sample_interval: float = 1.0 / max(effect_profile.shake_frequency, 1.0)
		shake_sample_remaining += sample_interval
		shake_target_offset = Vector3(
			random_generator.randf_range(-1.0, 1.0),
			random_generator.randf_range(-1.0, 1.0),
			0.0
		).normalized()

	var remaining_ratio: float = clamp(shake_remaining / shake_total_duration, 0.0, 1.0)
	var decay: float = pow(remaining_ratio, effect_profile.shake_decay_power)
	var desired_offset: Vector3 = shake_target_offset * shake_amplitude * decay
	var interpolation_weight: float = min(delta * effect_profile.shake_frequency * 4.0, 1.0)
	shake_current_offset = shake_current_offset.lerp(desired_offset, interpolation_weight)
	last_applied_camera_offset = shake_current_offset
	active_camera.position += last_applied_camera_offset


## 从摄像机局部位置中移除本效果上一帧施加的偏移，防止累计漂移。
func _remove_last_camera_offset() -> void:
	if is_instance_valid(active_camera) and last_applied_camera_offset != Vector3.ZERO:
		active_camera.position -= last_applied_camera_offset
	last_applied_camera_offset = Vector3.ZERO


## 停顿与震动都结束后发出一次反馈完成信号。
func _try_emit_feedback_finished() -> void:
	if not hit_stop_is_active and shake_remaining <= 0.0:
		feedback_finished.emit()


## 节点被移除或场景退出时恢复攻击模块和摄像机，保证效果桥可安全整体拆卸。
func _exit_tree() -> void:
	_remove_last_camera_offset()
	if hit_stop_is_active and is_instance_valid(attack_source) and attack_source.has_method("set_hit_stop_active"):
		attack_source.call("set_hit_stop_active", false)
	hit_stop_is_active = false
