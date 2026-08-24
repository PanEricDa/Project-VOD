extends Node3D

enum PreviewPhase {
	CHARGE,
	FLIGHT,
	EXPLOSION,
	PAUSE,
}

@export_category("Sequence Timing")
## 固定路径飞行速度，使用未来火球投射物计划默认值 9m/s。
@export_range(0.5, 30.0, 0.5) var preview_speed: float = 9.0
## 完整爆炸结束后等待多久重新开始下一轮，单位为秒。
@export_range(0.1, 3.0, 0.05) var replay_delay: float = 0.9

@onready var charge_effect: Node3D = $PreviewCaster/CastAnchor/FireballCastChargeEffect
@onready var flight_effect: Node3D = $FlightCarrier/FireballFlightEffect
@onready var explosion_effect: Node3D = $ImpactPoint/FireballExplosionEffect
@onready var start_marker: Marker3D = $FlightPath/StartMarker
@onready var end_marker: Marker3D = $FlightPath/EndMarker
@onready var flight_carrier: Node3D = $FlightCarrier
@onready var preview_camera: Camera3D = $Camera3D

var current_phase: PreviewPhase = PreviewPhase.PAUSE
var phase_time: float = 0.0
var start_position: Vector3 = Vector3.ZERO
var end_position: Vector3 = Vector3.ZERO
var travel_duration: float = 0.0


## 初始化固定构图、路径和三个公开信号；本脚本只服务视觉串联预览。
func _ready() -> void:
	preview_camera.look_at_from_position(
		Vector3(0.0, 1.8, 4.8),
		Vector3(0.0, 0.48, 0.0),
		Vector3.UP
	)
	start_position = start_marker.global_position
	end_position = end_marker.global_position
	travel_duration = start_position.distance_to(end_position) / maxf(preview_speed, 0.01)
	if not charge_effect.is_connected(&"effect_finished", _on_charge_finished):
		charge_effect.connect(&"effect_finished", _on_charge_finished)
	if not explosion_effect.is_connected(&"effect_finished", _on_explosion_finished):
		explosion_effect.connect(&"effect_finished", _on_explosion_finished)
	charge_effect.call("stop")
	flight_effect.call("stop")
	explosion_effect.call("stop")
	flight_carrier.global_position = start_position
	call_deferred("_begin_charge")


## 仅在飞行和循环间隔阶段更新；蓄力与爆炸时长由各自已批准的组件控制。
func _process(delta: float) -> void:
	if current_phase == PreviewPhase.FLIGHT:
		phase_time += delta
		var progress: float = clampf(
			phase_time / maxf(travel_duration, 0.001),
			0.0,
			1.0
		)
		flight_carrier.global_position = start_position.lerp(end_position, progress)
		if progress >= 1.0:
			_begin_explosion()
		return
	if current_phase == PreviewPhase.PAUSE:
		phase_time += delta
		if phase_time >= replay_delay:
			_begin_charge()


## 开始蓄力阶段并把飞行载体复位到施法点。
func _begin_charge() -> void:
	current_phase = PreviewPhase.CHARGE
	phase_time = 0.0
	flight_carrier.global_position = start_position
	flight_effect.call("stop")
	explosion_effect.call("stop")
	charge_effect.call("play")


## 蓄力自然完成后立刻切换到飞行效果，并让预览载体沿固定路径移动。
func _on_charge_finished() -> void:
	if current_phase != PreviewPhase.CHARGE:
		return
	current_phase = PreviewPhase.FLIGHT
	phase_time = 0.0
	flight_carrier.global_position = start_position
	flight_effect.call("start")


## 抵达终点后停止持续尾迹并在目标处播放一次独立爆炸视觉。
func _begin_explosion() -> void:
	if current_phase != PreviewPhase.FLIGHT:
		return
	current_phase = PreviewPhase.EXPLOSION
	phase_time = 0.0
	flight_carrier.global_position = end_position
	flight_effect.call("stop")
	explosion_effect.call("play")


## 爆炸自然结束后进入空白间隔，避免下一轮蓄力紧贴上一轮残影。
func _on_explosion_finished() -> void:
	if current_phase != PreviewPhase.EXPLOSION:
		return
	current_phase = PreviewPhase.PAUSE
	phase_time = 0.0


## Preview 被关闭时主动停止三个效果，避免编辑器保留粒子与灯光状态。
func _exit_tree() -> void:
	if is_instance_valid(charge_effect):
		charge_effect.call("stop")
	if is_instance_valid(flight_effect):
		flight_effect.call("stop")
	if is_instance_valid(explosion_effect):
		explosion_effect.call("stop")
