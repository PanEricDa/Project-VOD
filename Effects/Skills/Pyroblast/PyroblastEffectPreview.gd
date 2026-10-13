extends Node3D

## 仅服务视觉预览，复用正式特效；不引用角色 AI，不进行战斗结算。
enum PreviewMode { CHARGE, FLIGHT, IMPACT, SEQUENCE }
@export_category("Preview")
## 预览阶段；默认 SEQUENCE 串联全部，其他模式分别单独观察蓄力、飞行或命中。
@export var preview_mode: PreviewMode = PreviewMode.SEQUENCE
## 每轮结束后的观察间隔，单位秒，默认 0.8，仅影响预览。
@export_range(0.1, 3.0, 0.05) var replay_delay: float = 0.8
## 预览飞行时长，单位秒，默认 0.48，与炎爆投射物初始值一致。
@export_range(0.1, 3.0, 0.01) var flight_duration: float = 0.48
## 预览弹道抬升高度，单位米，默认 0.55，与炎爆投射物初始值一致。
@export_range(0.0, 3.0, 0.05) var arc_height: float = 0.55

@onready var charge: Node3D = $PreviewCaster/PyroblastCastChargeEffect
@onready var origin: Marker3D = $PreviewCaster/ProjectileOrigin
@onready var caster: Node3D = $PreviewCaster
@onready var carriers: Node3D = $FlightCarriers
@onready var targets: Node3D = $TargetPoints
@onready var caption: Label = $CanvasLayer/Caption

var _phase: StringName = &"pause"
var _time: float = 0.0
var _volley_count: int = 1
var _cycle: int = 0

func _ready() -> void:
	$Camera3D.look_at(Vector3(0.0, 0.55, 0.0))
	charge.connect(&"effect_finished", _on_charge_finished)
	charge.call(&"configure_cast", caster, origin.global_transform, 1.2)
	charge.call(&"stop")
	for carrier: Node in carriers.get_children():
		carrier.get_child(0).call(&"stop")
	for target: Node in targets.get_children():
		target.get_node("PyroblastImpactEffect").call(&"stop")
	call_deferred(&"_begin_cycle")

func _process(delta: float) -> void:
	_time += maxf(delta, 0.0)
	if _phase == &"flight":
		var progress := clampf(_time / flight_duration, 0.0, 1.0)
		for index: int in range(_volley_count):
			var carrier := carriers.get_child(index) as Node3D
			var target := targets.get_child(index) as Node3D
			var previous := carrier.global_position
			carrier.global_position = origin.global_position.lerp(target.global_position, progress) + Vector3.UP * sin(progress * PI) * arc_height
			var direction := carrier.global_position - previous
			if direction.length_squared() > 0.000001 and absf(direction.normalized().dot(Vector3.UP)) < 0.999:
				carrier.look_at(carrier.global_position + direction)
		if progress >= 1.0:
			_finish_flight()
	elif _phase == &"impact" and _time >= 0.55:
		_pause()
	elif _phase == &"pause" and _time >= replay_delay:
		_begin_cycle()

func _begin_cycle() -> void:
	_cycle += 1
	_volley_count = 1 if _cycle % 2 == 1 else 3
	if preview_mode == PreviewMode.CHARGE:
		_phase = &"charge"
		_time = 0.0
		caption.text = "炎爆术 · 脚下火星升起 → 汇聚施法点"
		charge.call(&"play")
	elif preview_mode == PreviewMode.FLIGHT:
		_begin_flight()
	elif preview_mode == PreviewMode.IMPACT:
		_begin_impact()
	else:
		_phase = &"charge"
		_time = 0.0
		caption.text = "炎爆术 · 蓄力 · 本轮 %d 枚火球" % _volley_count
		charge.call(&"play")

func _on_charge_finished() -> void:
	if _phase != &"charge":
		return
	if preview_mode == PreviewMode.SEQUENCE:
		_begin_flight()
	else:
		_pause()

func _begin_flight() -> void:
	_phase = &"flight"
	_time = 0.0
	caption.text = "炎爆术 · %d 枚火球同帧齐射 · 短粗拖尾" % _volley_count
	for index: int in range(carriers.get_child_count()):
		var carrier := carriers.get_child(index) as Node3D
		carrier.global_position = origin.global_position
		if index < _volley_count:
			carrier.get_child(0).call(&"start")
		else:
			carrier.get_child(0).call(&"stop")

func _finish_flight() -> void:
	for carrier: Node in carriers.get_children():
		carrier.get_child(0).call(&"stop")
	if preview_mode == PreviewMode.SEQUENCE:
		_begin_impact()
	else:
		_pause()

func _begin_impact() -> void:
	_phase = &"impact"
	_time = 0.0
	caption.text = "炎爆术 · 单体集中爆燃"
	for index: int in range(_volley_count):
		targets.get_child(index).get_node("PyroblastImpactEffect").call(&"play")

func _pause() -> void:
	_phase = &"pause"
	_time = 0.0
	caption.text = "炎爆术 · 重播间隔（交替展示单发 / 三目标齐射）"
