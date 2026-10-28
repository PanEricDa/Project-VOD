class_name CombatRunTimer
extends CanvasLayer

## 可独立装配的房间计时显示。只跟踪玩家起步和本轮用时；
## 胜负由 GameRunController 调用 stop()，最佳纪录不由本组件保存。
@export_category("Assembly")
## 本轮玩家单位；默认空，未配置时保持零且不自动查找。只观察主动移动，不修改玩家行为。
@export var player: PlayerBase

var _elapsed_seconds: float = 0.0
var _started: bool = false
var _stopped: bool = false

@onready var _time_label: Label = $Panel/Time

func _ready() -> void:
	if is_instance_valid(player):
		# 在玩家本帧移动前捕获意图，避免冲刺/外力在帧末结束后丢失来源。
		process_physics_priority = player.process_physics_priority - 1
	_refresh_display()

func _physics_process(_delta: float) -> void:
	if _started or _stopped or not is_instance_valid(player):
		return
	if player.is_dead() or not player.is_player_input_enabled():
		return
	if player.get_forced_movement_token() > 0:
		return
	var direction := Input.get_vector(
		PlayerBase.MOVE_LEFT_ACTION, PlayerBase.MOVE_RIGHT_ACTION,
		PlayerBase.MOVE_FORWARD_ACTION, PlayerBase.MOVE_BACKWARD_ACTION
	)
	if not direction.is_zero_approx() or player.is_player_dashing() or Input.is_action_just_pressed(PlayerBase.DASH_ACTION):
		_check_start_after_movement.call_deferred(player.global_position)

## previous_position为玩家本物理帧执行前的位置；只验证该次主动输入是否真正产生水平位移。
func _check_start_after_movement(previous_position: Vector3) -> void:
	if _started or _stopped or not is_instance_valid(player):
		return
	var difference: Vector3 = player.global_position - previous_position
	if Vector2(difference.x, difference.z).length_squared() > 0.00000001:
		_started = true

func _process(delta: float) -> void:
	if _started and not _stopped:
		_elapsed_seconds += maxf(delta, 0.0)
		_refresh_display()

## 停止本轮计时并返回累计游戏秒；幂等。未起步时为0，不表示一次有效通关纪录。
func stop() -> float:
	_stopped = true
	return _elapsed_seconds

## 返回本轮累计游戏秒，不四舍五入；供胜负结算只读使用。
func get_elapsed_seconds() -> float:
	return _elapsed_seconds

## 是否已由玩家实际主动移动触发本轮；停止后保留，用于排除未开跑的最佳纪录。
func has_started() -> bool:
	return _started

## seconds为有限非负游戏秒；显示为分钟:秒:百分秒，向下截断。
## 为保持六位，显示上限99:59:99；实际累计值不截断，最佳纪录仍比较原始时间。
static func format_time(seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0.0:
		return "--:--:--"
	var centiseconds: int = mini(int(floor(seconds * 100.0)), 599999)
	@warning_ignore("integer_division")
	var minutes: int = centiseconds / 6000
	@warning_ignore("integer_division")
	var whole_seconds: int = (centiseconds / 100) % 60
	return "%02d:%02d:%02d" % [minutes, whole_seconds, centiseconds % 100]

func _refresh_display() -> void:
	if is_instance_valid(_time_label):
		_time_label.text = format_time(_elapsed_seconds)
