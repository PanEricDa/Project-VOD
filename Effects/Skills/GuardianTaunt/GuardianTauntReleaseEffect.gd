class_name GuardianTauntReleaseEffect
extends Node3D

## Guardian 群体嘲讽的一次性释放视觉；只表达释放时机和范围，不处理仇恨结算。

## 特效开始播放时发送；不代表仇恨已经成功改变敌人的锁定目标。
signal effect_started()
## 时间轴自然结束时发送；主动 stop() 不发送该信号。
signal effect_finished()

const BASE_ANIMATION_DURATION: float = 0.5
const EFFECT_ANIMATION_NAME: StringName = &"taunt_release"

@export_category("Playback")
## 进入场景树后是否自动播放一次；正式技能生成的实例默认启用。
@export var autoplay: bool = true
## 自然播放结束后是否自动释放实例；关闭后可供预览或对象池重复播放。
@export var auto_free_on_finished: bool = true
## 整体播放时长，单位为秒；默认0.5秒，只影响视觉时间轴，不改变技能施法或冷却。
@export_range(0.1, 2.0, 0.05, "or_greater")
var effect_duration: float = 0.5

@export_category("Appearance")
## 范围环和爆发粒子的主色；默认橙红色，只影响本特效实例材质。
@export var threat_color: Color = Color("#ff642f")
## 中心闪光与局部灯光的高亮色；默认暖金色，只影响本特效实例。
@export var highlight_color: Color = Color("#ffd078")
## 冲击环完整展开后的外半径，单位为米；默认5米，对应当前嘲讽 Delivery 范围。
@export_range(0.1, 20.0, 0.1, "or_greater")
var effect_radius: float = 5.0
## 中心能量爆发的完整高度，单位为米；默认1.5米，仅影响可读性。
@export_range(0.1, 5.0, 0.1, "or_greater")
var core_height: float = 1.5
## 局部灯光的峰值能量；默认2.0，只影响短促释放闪光。
@export_range(0.0, 10.0, 0.1)
var flash_light_energy: float = 2.0

@export_category("Particles")
## 单次释放发射的爆发粒子数量；默认32，只影响表现密度和渲染开销。
@export_range(1, 128, 1)
var particle_amount: int = 32

@onready var threat_ring: MeshInstance3D = $ThreatRing
@onready var core_burst: MeshInstance3D = $CoreBurst
@onready var burst_particles: GPUParticles3D = $BurstParticles
@onready var burst_light: OmniLight3D = $BurstLight
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _playback_active: bool = false


## 初始化本实例的局部资源和播放状态，并按配置延迟自动播放。
func _ready() -> void:
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)
	_apply_parameters()
	reset_effect()
	if autoplay:
		call_deferred(&"play")


## 从头播放一次嘲讽释放视觉；重复调用会先复位，不叠加时间轴。
func play() -> void:
	animation_player.stop()
	reset_effect()
	animation_player.speed_scale = (
		BASE_ANIMATION_DURATION / maxf(effect_duration, 0.01)
	)
	_playback_active = true
	burst_particles.restart()
	burst_particles.emitting = true
	animation_player.play(EFFECT_ANIMATION_NAME)
	effect_started.emit()


## 立即停止视觉并恢复隐藏状态；不会影响已经完成的技能或仇恨结算。
func stop() -> void:
	_playback_active = false
	animation_player.stop()
	reset_effect()


## 返回本实例是否处于有效播放周期；只读，不代表技能运行状态。
func is_playing() -> bool:
	return _playback_active


## 将动态节点恢复到不可见起点，供停止、重播和对象池复用。
func reset_effect() -> void:
	threat_ring.scale = Vector3.ONE * 0.08
	threat_ring.transparency = 1.0
	core_burst.scale = Vector3(0.25, 0.05, 0.25)
	core_burst.transparency = 1.0
	burst_particles.emitting = false
	burst_light.light_energy = 0.0


## 把 Inspector 参数写入本实例独享的网格、材质、粒子和动画资源。
func _apply_parameters() -> void:
	var ring_mesh := threat_ring.mesh as TorusMesh
	if ring_mesh != null:
		ring_mesh.outer_radius = effect_radius
		ring_mesh.inner_radius = maxf(effect_radius - 0.12, 0.01)
	var core_mesh := core_burst.mesh as CylinderMesh
	if core_mesh != null:
		core_mesh.height = core_height
	core_burst.position.y = core_height * 0.5
	burst_particles.amount = maxi(particle_amount, 1)
	burst_light.light_color = highlight_color
	_apply_material(
		threat_ring.material_override as StandardMaterial3D,
		threat_color,
		0.86,
		3.0
	)
	_apply_material(
		core_burst.material_override as StandardMaterial3D,
		highlight_color,
		0.48,
		2.6
	)
	var particle_mesh := burst_particles.draw_pass_1 as QuadMesh
	if particle_mesh != null:
		_apply_material(
			particle_mesh.material as StandardMaterial3D,
			threat_color,
			0.9,
			3.2
		)
	_apply_light_peak()


## 将可配置灯光峰值写入实例独享动画，避免不同实例相互污染。
func _apply_light_peak() -> void:
	var animation := animation_player.get_animation(EFFECT_ANIMATION_NAME)
	if animation == null:
		return
	var track_index := animation.find_track(
		^"BurstLight:light_energy",
		Animation.TYPE_VALUE
	)
	if track_index < 0:
		return
	for key_index: int in animation.track_get_key_count(track_index):
		if is_equal_approx(
			animation.track_get_key_time(track_index, key_index),
			0.08
		):
			animation.track_set_key_value(
				track_index,
				key_index,
				flash_light_energy
			)


## 统一设置透明无光照材质，保证圆环、中心爆发和粒子色相一致。
func _apply_material(
	material: StandardMaterial3D,
	base_color: Color,
	alpha: float,
	emission_strength: float
) -> void:
	if material == null:
		return
	var color_with_alpha := base_color
	color_with_alpha.a = clampf(alpha, 0.0, 1.0)
	material.albedo_color = color_with_alpha
	material.emission_enabled = true
	material.emission = base_color
	material.emission_energy_multiplier = emission_strength


## 自然播放结束时关闭瞬时资源，并根据配置释放本实例。
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != EFFECT_ANIMATION_NAME or not _playback_active:
		return
	_playback_active = false
	burst_particles.emitting = false
	burst_light.light_energy = 0.0
	effect_finished.emit()
	if auto_free_on_finished:
		queue_free()


## 节点提前离树时关闭粒子和灯光，避免场景切换留下表现状态。
func _exit_tree() -> void:
	_playback_active = false
	if is_instance_valid(burst_particles):
		burst_particles.emitting = false
	if is_instance_valid(burst_light):
		burst_light.light_energy = 0.0
