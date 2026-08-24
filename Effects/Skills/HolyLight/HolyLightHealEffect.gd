class_name HolyLightHealEffect
extends Node3D

## 单体圣光治疗视觉开始播放时发送；不代表生命值已经恢复。
signal effect_started()

## 单次视觉时间轴自然播放结束时发送；stop() 不会发送该信号。
signal effect_finished()

const BASE_ANIMATION_DURATION: float = 0.5
const HEAL_ANIMATION_NAME: StringName = &"heal"

@export_category("Playback")
## 进入场景树后是否自动播放一次效果。
@export var autoplay: bool = true
## 自然播放结束后是否自动释放当前效果实例。
@export var auto_free_on_finished: bool = true
## 整体播放时长；通过 AnimationPlayer.speed_scale 缩放固定 0.5 秒时间轴。
@export_range(0.1, 2.0, 0.05) var effect_duration: float = 0.5

@export_category("Colors")
## 地面光环和主要粒子使用的暖金色。
@export var primary_gold_color: Color = Color("#ffd36a")
## 光柱和局部灯光使用的象牙白。
@export var ivory_light_color: Color = Color("#fff4d6")
## 四芒星中心使用的高亮纯白。
@export var highlight_color: Color = Color.WHITE

@export_category("Dimensions")
## 地面光环的外半径，单位为米。
@export_range(0.1, 5.0, 0.05) var ring_radius: float = 0.65
## 圣光柱的完整高度，单位为米。
@export_range(0.1, 5.0, 0.05) var column_height: float = 1.2
## 圣光柱底部半径，单位为米。
@export_range(0.05, 2.0, 0.05) var column_radius: float = 0.32

@export_category("Particles")
## 单次治疗发射的上升光点数量。
@export_range(1, 128, 1) var particle_amount: int = 18

@export_category("Local Light")
## 灯光脉冲峰值能量，动画中的 1.2 会按该值同比缩放。
@export_range(0.0, 10.0, 0.1) var light_energy: float = 1.2
## 局部灯光作用范围，单位为米。
@export_range(0.1, 10.0, 0.1) var light_range: float = 1.5

@onready var ground_ring: MeshInstance3D = $GroundRing
@onready var light_column: MeshInstance3D = $LightColumn
@onready var rising_particles: GPUParticles3D = $RisingParticles
@onready var heal_flash: Node3D = $HealFlash
@onready var vertical_ray: MeshInstance3D = $HealFlash/VerticalRay
@onready var horizontal_ray: MeshInstance3D = $HealFlash/HorizontalRay
@onready var healing_light: OmniLight3D = $HealingLight
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## 当前是否处于一次有效播放周期中。
var playback_is_active: bool = false


## 初始化本实例资源参数、动画监听和隐藏状态，并按配置延迟自动播放。
func _ready() -> void:
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)
	_apply_parameters()
	reset_effect()
	if autoplay:
		call_deferred("play")


## 从头播放一次治疗视觉；重复调用会先精确复位再重新开始，不叠加计时任务。
func play() -> void:
	animation_player.stop()
	reset_effect()
	animation_player.speed_scale = BASE_ANIMATION_DURATION / max(effect_duration, 0.01)
	playback_is_active = true
	animation_player.play(HEAL_ANIMATION_NAME)
	effect_started.emit()


## 立即停止当前视觉并恢复完全隐藏状态；主动停止不发送完成信号。
func stop() -> void:
	playback_is_active = false
	animation_player.stop()
	reset_effect()


## 将所有动态节点恢复到动画起始状态，供停止、重播和对象池复用。
func reset_effect() -> void:
	rising_particles.emitting = false
	ground_ring.scale = Vector3.ONE * 0.2
	ground_ring.transparency = 1.0
	light_column.scale = Vector3(0.55, 0.05, 0.55)
	light_column.transparency = 1.0
	heal_flash.scale = Vector3.ONE * 0.2
	vertical_ray.transparency = 1.0
	horizontal_ray.transparency = 1.0
	healing_light.light_energy = 0.0


## 返回当前实例是否正在执行一次有效治疗视觉时间轴。
func is_playing() -> bool:
	return playback_is_active


## 动画方法轨道调用：重新启动一次性粒子发射，确保重复播放仍从首帧开始。
func _start_particles() -> void:
	rising_particles.restart()
	rising_particles.emitting = true


## 动画方法轨道调用：停止继续发射；已产生粒子按自身寿命自然消散。
func _stop_particles() -> void:
	rising_particles.emitting = false


## 自然播放结束时只完成当前有效周期，并按配置选择保留或释放实例。
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != HEAL_ANIMATION_NAME or not playback_is_active:
		return
	playback_is_active = false
	rising_particles.emitting = false
	healing_light.light_energy = 0.0
	effect_finished.emit()
	if auto_free_on_finished:
		queue_free()


## 把 Inspector 参数写入本实例的 scene-local Mesh、Material、粒子和灯光资源。
func _apply_parameters() -> void:
	var ring_mesh: TorusMesh = ground_ring.mesh as TorusMesh
	if ring_mesh != null:
		ring_mesh.outer_radius = ring_radius
		ring_mesh.inner_radius = max(ring_radius - 0.07, 0.01)
	var column_mesh: CylinderMesh = light_column.mesh as CylinderMesh
	if column_mesh != null:
		column_mesh.height = column_height
		column_mesh.bottom_radius = column_radius
		column_mesh.top_radius = column_radius * 0.75
	light_column.position.y = column_height * 0.5

	rising_particles.amount = maxi(particle_amount, 1)
	healing_light.light_color = ivory_light_color
	healing_light.omni_range = light_range
	_apply_light_animation_energy()

	_apply_material_color(
		ground_ring.material_override as StandardMaterial3D,
		primary_gold_color,
		0.82,
		2.2
	)
	_apply_material_color(
		light_column.material_override as StandardMaterial3D,
		ivory_light_color,
		0.32,
		1.8
	)
	_apply_material_color(
		vertical_ray.material_override as StandardMaterial3D,
		highlight_color,
		0.95,
		2.8
	)
	_apply_material_color(
		horizontal_ray.material_override as StandardMaterial3D,
		highlight_color,
		0.95,
		2.8
	)
	var particle_mesh: QuadMesh = rising_particles.draw_pass_1 as QuadMesh
	if particle_mesh != null:
		_apply_material_color(
			particle_mesh.material as StandardMaterial3D,
			primary_gold_color,
			0.9,
			2.5
		)


## 将 Inspector 中的灯光峰值写入当前实例独享的动画资源。
## 这样既保留可视化动画轨道，也避免一个特效实例的参数污染其他实例。
func _apply_light_animation_energy() -> void:
	var animation: Animation = animation_player.get_animation(HEAL_ANIMATION_NAME)
	if animation == null:
		return
	var track_index: int = animation.find_track(
		^"HealingLight:light_energy",
		Animation.TYPE_VALUE
	)
	if track_index < 0:
		return
	for key_index: int in animation.track_get_key_count(track_index):
		var key_time: float = animation.track_get_key_time(track_index, key_index)
		if is_equal_approx(key_time, 0.15):
			animation.track_set_key_value(track_index, key_index, light_energy)
		elif is_equal_approx(key_time, 0.26):
			animation.track_set_key_value(track_index, key_index, light_energy / 3.0)


## 统一更新透明发光材质，避免各视觉节点出现不一致的色相或亮度。
func _apply_material_color(
	material: StandardMaterial3D,
	base_color: Color,
	alpha: float,
	emission_multiplier: float
) -> void:
	if material == null:
		return
	var color_with_alpha: Color = base_color
	color_with_alpha.a = clamp(alpha, 0.0, 1.0)
	material.albedo_color = color_with_alpha
	material.emission = base_color
	material.emission_energy_multiplier = emission_multiplier


## 节点离开场景树时关闭粒子和灯光，避免对象池或父节点删除留下残余状态。
func _exit_tree() -> void:
	playback_is_active = false
	if is_instance_valid(rising_particles):
		rising_particles.emitting = false
	if is_instance_valid(healing_light):
		healing_light.light_energy = 0.0
