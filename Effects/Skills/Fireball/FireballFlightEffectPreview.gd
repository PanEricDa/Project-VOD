extends Node3D

@export_category("Preview Motion")
## 预览载体沿固定路径移动的速度，使用未来投射物计划默认值 9m/s。
@export_range(0.5, 30.0, 0.5) var preview_speed: float = 9.0
## 每次抵达终点后保留的观察间隔，单位为秒。
@export_range(0.1, 3.0, 0.05) var replay_delay: float = 0.5

@onready var start_marker: Marker3D = $FlightPath/StartMarker
@onready var end_marker: Marker3D = $FlightPath/EndMarker
@onready var flight_carrier: Node3D = $FlightCarrier
@onready var effect: Node3D = $FlightCarrier/FireballFlightEffect
@onready var preview_camera: Camera3D = $Camera3D

var start_position: Vector3 = Vector3.ZERO
var end_position: Vector3 = Vector3.ZERO
var path_length: float = 0.0
var travel_time: float = 0.0
var phase_time: float = 0.0
var is_traveling: bool = true


## 初始化固定构图和飞行路径；Preview 自身负责移动，正式效果保持纯视觉组件。
func _ready() -> void:
	preview_camera.look_at_from_position(
		Vector3(0.0, 1.65, 4.2),
		Vector3(0.0, 0.62, 0.0),
		Vector3.UP
	)
	start_position = start_marker.global_position
	end_position = end_marker.global_position
	path_length = start_position.distance_to(end_position)
	travel_time = path_length / maxf(preview_speed, 0.01)
	_restart_flight()


## 沿固定直线路径推动预览载体；此方法不属于正式投射物运动实现。
func _process(delta: float) -> void:
	phase_time += delta
	if is_traveling:
		var progress: float = clampf(phase_time / maxf(travel_time, 0.001), 0.0, 1.0)
		flight_carrier.global_position = start_position.lerp(end_position, progress)
		if progress >= 1.0:
			is_traveling = false
			phase_time = 0.0
			effect.call("stop")
		return
	if phase_time >= replay_delay:
		_restart_flight()


## 将载体复位到起点并重新启动持续尾迹，形成便于反复观察的循环。
func _restart_flight() -> void:
	phase_time = 0.0
	is_traveling = true
	flight_carrier.global_position = start_position
	effect.call("start")
