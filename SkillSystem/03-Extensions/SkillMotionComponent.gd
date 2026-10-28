@tool
class_name SkillMotionComponent
extends Node

## 动画游标定义进度；组件只生成水平位移意图，不执行物理或维护独立时钟。
enum Direction { FORWARD, BACKWARD, LEFT, RIGHT }
## 相对区间开始时稳定水平朝向的移动方向；默认后退，影响本技能动画位移。
@export var direction: Direction = Direction.BACKWARD
## 单个位移区间的总水平距离，单位米；默认0.8，必须有限且大于0，碰撞后不追补。
@export_range(0.01, 10.0, 0.01, "or_greater") var distance_m: float = 0.8

var _serial: int = -1
var _request_id: int = -1
var _progress: float = 0.0
var _locked_direction := Vector3.ZERO
var _finished: bool = false

## 返回供Inspector/技能验证使用的错误；不修改配置。
func validate_configuration() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(distance_m) or distance_m <= 0: errors.append("位移距离必须为有限正数（米）。")
	if direction < Direction.FORWARD or direction > Direction.RIGHT: errors.append("位移方向无效。")
	return errors

func _get_configuration_warnings() -> PackedStringArray:
	return validate_configuration()

## 消费控制器的实际动画秒数；request_id+action_serial标识动作，重复/旧样本不重复移动。
## sample包含interval、previous_position、position、forward和terminal，只读。
func sample_motion(request_id: int, action_serial: int, sample: Dictionary) -> Dictionary:
	var rejected := {"accepted": false, "displacement": Vector3.ZERO, "terminal": false}
	if not validate_configuration().is_empty() or request_id < 0 or action_serial < 1 or action_serial < _serial: return rejected
	var interval: Vector2 = sample.get("interval", Vector2.ZERO)
	var position: float = sample.get("position", NAN)
	var previous: float = sample.get("previous_position", NAN)
	var forward: Vector3 = sample.get("forward", Vector3.ZERO)
	forward.y = 0.0
	if not interval.is_finite() or interval.y <= interval.x or interval.x < 0 or not is_finite(position) or not is_finite(previous) or position < previous or not forward.is_finite() or forward.length_squared() < 0.0001: return rejected
	if action_serial == _serial and (_request_id != request_id or _finished): return rejected
	if action_serial > _serial:
		_serial = action_serial
		_request_id = request_id
		_progress = 0.0
		_finished = false
		forward = forward.normalized()
		match direction:
			Direction.FORWARD: _locked_direction = forward
			Direction.BACKWARD: _locked_direction = -forward
			Direction.LEFT: _locked_direction = Vector3.UP.cross(forward)
			Direction.RIGHT: _locked_direction = forward.cross(Vector3.UP)
	var progress := clampf((position - interval.x) / (interval.y - interval.x), 0.0, 1.0)
	# 保留真实游标，仅在浮点等价的结束边界收齐末段；不额外推进动画。
	if is_equal_approx(position, interval.y): progress = 1.0
	if progress <= _progress: return rejected
	var step := _locked_direction * distance_m * (progress - _progress)
	_progress = progress
	_finished = progress >= 1.0
	return {"accepted": true, "displacement": step, "terminal": _finished}

## 仅取消相同身份；保留序号墓碑，迟到样本不能复活已取消动作。
func cancel_motion(request_id: int, action_serial: int) -> void:
	if request_id == _request_id and action_serial == _serial: _finished = true
