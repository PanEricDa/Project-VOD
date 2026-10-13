class_name PyroblastCastChargeEffect
extends Node3D

## 脚底圆环火星上升后汇聚到发射点；纯视觉，不参与选目标、伤害或灼烧消耗。
## 每次开始播放时发送，不代表技能已释放。
signal effect_started()
## 仅自然播放完成时发送，打断 stop() 不发送。
signal effect_finished()

@export_category("Playback")
## 默认加入场景树后自动播放；Preview 可关闭后调用 play()，仅影响视觉启动。
@export var autoplay: bool = true
## 独立预览蓄力时长，单位秒，默认 1.2；正式技能通过 configure_cast 同步实际施法时长。
@export_range(0.1, 10.0, 0.05) var effect_duration: float = 1.2
@export_category("Shape")
## 脚底圆环半径，单位米，默认 0.55；仅是视觉尺寸，不表示攻击范围。
@export_range(0.1, 2.0, 0.01) var ring_radius: float = 0.55
## 主圆环径向宽度，单位米，默认 0.09；内扩散环使用其 70% 宽度，仅影响蓄力视觉。
@export_range(0.01, 0.3, 0.005) var ring_width: float = 0.09
## 火星数量，默认 40；共用一个 MultiMesh 绘制，影响蓄力密度。
@export_range(8, 128, 1) var spark_amount: int = 40
## 火星上升高度，单位米，默认 0.8；后半段从该高度向施法位置聚拢。
@export_range(0.1, 3.0, 0.05) var rise_height: float = 0.8
## 火星尺寸，单位米，默认 0.035；只影响粒子视觉。
@export_range(0.01, 0.12, 0.005) var spark_size: float = 0.035
## 预览施法点相对脚底的位置，单位米；正式技能传入实际发射点，覆盖此回退值。
@export var preview_cast_offset: Vector3 = Vector3(0.4, 0.8, -0.2)
@export_category("Colors")
## 圆环、火星和外壳的橙红色，默认火焰色，仅影响本蓄力实例。
@export var flame_color: Color = Color("#ff581b")
## 汇聚火核的金白色，默认暖白，仅影响本蓄力实例。
@export var core_color: Color = Color("#ffe6a0")

@onready var visual_root: Node3D = $VisualRoot
@onready var ring: MeshInstance3D = $VisualRoot/ChargeRing
@onready var expansion_ring: MeshInstance3D = $VisualRoot/ExpansionRing
@onready var sparks: MultiMeshInstance3D = $VisualRoot/RisingSparks
@onready var core: MeshInstance3D = $VisualRoot/ChargeCore
@onready var shell: MeshInstance3D = $VisualRoot/ChargeShell
@onready var light: OmniLight3D = $ChargeLight
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _active: bool = false
var _source: WeakRef
var _cast_anchor: WeakRef
var _local_cast_offset: Vector3
var _bound_to_cast: bool = false

func _ready() -> void:
	_local_cast_offset = preview_cast_offset
	var torus := ring.mesh as TorusMesh
	torus.inner_radius = maxf(ring_radius - ring_width, 0.01)
	torus.outer_radius = ring_radius
	var expansion_torus := expansion_ring.mesh as TorusMesh
	expansion_torus.inner_radius = maxf(ring_radius - ring_width * 0.7, 0.01)
	expansion_torus.outer_radius = ring_radius
	var multi := sparks.multimesh
	multi.instance_count = 0
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.instance_count = spark_amount
	_set_color(ring, flame_color)
	_set_color(expansion_ring, flame_color.lerp(core_color, 0.2))
	_set_color(shell, flame_color)
	_set_color(core, core_color)
	_set_color(sparks, flame_color.lerp(core_color, 0.45))
	light.light_color = flame_color
	animation_player.animation_finished.connect(_on_finished)
	reset_effect()
	if autoplay:
		call_deferred("play")

## source 是施法者，origin 是动作系统确认的世界发射变换，duration 是实际施法秒数。
## 绑定后圆环跟随 source 脚底；优先跟随角色既有 ProjectileOrigin，缺少时用初始局部偏移。
func configure_cast(source: Node3D, origin: Transform3D, duration: float) -> void:
	if not is_instance_valid(source) or not origin.is_finite():
		return
	_source = weakref(source)
	_bound_to_cast = true
	_local_cast_offset = source.to_local(origin.origin)
	var anchor := source.find_child("ProjectileOrigin", true, false) as Node3D
	if anchor != null:
		_cast_anchor = weakref(anchor)
	effect_duration = maxf(duration, 0.01)
	_update_anchors()

## 从头开始；可重复播放，不创建新的粒子节点或累积定时任务。
func play() -> void:
	if _bound_to_cast and (_source == null or not is_instance_valid(_source.get_ref())):
		stop()
		return
	reset_effect()
	_update_anchors()
	_active = true
	visual_root.visible = true
	animation_player.speed_scale = 1.2 / maxf(effect_duration, 0.01)
	animation_player.play(&"charge")
	animation_player.advance(0.0)
	set_process(true)
	effect_started.emit()

## 释放或打断立即关闭全部蓄力视觉；不伪造自然结束信号。
func stop() -> void:
	_active = false
	animation_player.stop()
	reset_effect()

## 清除本实例的可见火星、火核和局部灯光，不改变战斗数据。
func reset_effect() -> void:
	_active = false
	set_process(false)
	visual_root.visible = false
	core.scale = Vector3.ONE * 0.08
	shell.scale = Vector3.ONE * 0.08
	core.transparency = 1.0
	shell.transparency = 1.0
	ring.transparency = 1.0
	expansion_ring.transparency = 1.0
	expansion_ring.scale = Vector3.ONE * 0.55
	light.light_energy = 0.0
	sparks.multimesh.visible_instance_count = 0

## 返回视觉播放状态，不代表角色动作或技能合法性。
func is_playing() -> bool:
	return _active

func _process(_delta: float) -> void:
	if not _active:
		return
	if _bound_to_cast and (_source == null or not is_instance_valid(_source.get_ref())):
		stop()
		return
	_update_anchors()
	var progress := clampf(animation_player.current_animation_position / 1.2, 0.0, 1.0)
	var gather := smoothstep(0.5, 1.0, progress)
	ring.scale = Vector3.ONE * lerpf(0.85, 1.03, progress)
	ring.transparency = 1.0 - smoothstep(0.0, 0.12, progress) * (1.0 - gather) * 0.8
	# 内环在蓄力前半段由主环的 55% 半径扩散至 110%，并在后半段前消失。
	var spread := smoothstep(0.0, 0.55, progress)
	expansion_ring.scale = Vector3.ONE * lerpf(0.55, 1.1, spread)
	expansion_ring.transparency = 1.0 - smoothstep(0.0, 0.06, progress) * (1.0 - smoothstep(0.3, 0.55, progress)) * 0.9
	var cast_at := _get_cast_position()
	core.position = cast_at
	shell.position = cast_at
	core.scale = Vector3.ONE * lerpf(0.08, 1.0, gather)
	shell.scale = Vector3.ONE * lerpf(0.08, 1.0, gather)
	core.transparency = 1.0 - gather
	shell.transparency = 1.0 - gather * 0.5
	light.position = cast_at
	light.light_energy = gather * 1.8
	var multi := sparks.multimesh
	multi.visible_instance_count = spark_amount
	for index: int in range(spark_amount):
		var fraction := float(index) / float(spark_amount)
		var angle := fraction * TAU * 2.618
		var birth := fmod(fraction * 3.7, 1.0) * 0.24
		var ascent := clampf((progress - birth) / maxf(0.52 - birth, 0.01), 0.0, 1.0)
		var radius := ring_radius * (0.88 + 0.12 * sin(float(index)))
		var risen := Vector3(cos(angle + ascent * 0.18) * radius, 0.035 + rise_height * ascent, sin(angle + ascent * 0.18) * radius)
		var point := risen.lerp(cast_at, gather)
		point.y += sin(gather * PI) * 0.15
		var alpha := smoothstep(birth, birth + 0.06, progress) * (1.0 - smoothstep(0.93, 1.0, progress))
		var size := spark_size * (0.65 + 0.35 * sin(float(index) * 1.9))
		multi.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3(size, size * 2.5, size)), point))
		multi.set_instance_color(index, Color(1.0, 0.7 + fraction * 0.3, 0.5, alpha))

func _update_anchors() -> void:
	if _source != null and is_instance_valid(_source.get_ref()):
		var source := _source.get_ref() as Node3D
		global_transform = Transform3D(Basis.IDENTITY, source.global_position)

func _get_cast_position() -> Vector3:
	if _cast_anchor != null and is_instance_valid(_cast_anchor.get_ref()):
		return to_local((_cast_anchor.get_ref() as Node3D).global_position)
	if _source != null and is_instance_valid(_source.get_ref()):
		return to_local((_source.get_ref() as Node3D).to_global(_local_cast_offset))
	return preview_cast_offset

func _set_color(mesh: GeometryInstance3D, color: Color) -> void:
	var material := mesh.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(color, material.albedo_color.a)
		material.emission = color

func _on_finished(name: StringName) -> void:
	if name != &"charge" or not _active:
		return
	reset_effect()
	effect_finished.emit()
