class_name FireballExplosionEffect
extends Node3D

## 爆炸视觉从隐藏状态开始播放时发送；不代表已经命中或造成伤害。
signal effect_started()
## 爆炸视觉自然播放完毕时发送；主动 stop() 不发送该信号。
signal effect_finished()

const BASE_ANIMATION_DURATION: float = 0.35
const EXPLOSION_ANIMATION_NAME: StringName = &"explode"

@export_category("Playback")
## 加入场景树后是否自动播放一次。
@export var autoplay: bool = true
## 自然播放完成后是否释放整个效果实例；Preview 会将其关闭以便循环复用。
@export var auto_free_on_finished: bool = true
## 爆炸视觉总时长，单位为秒；固定时间轴通过 speed_scale 等比缩放。
@export_range(0.1, 2.0, 0.01) var effect_duration: float = 0.35

@export_category("Colors")
## 爆炸中心瞬时闪光使用的暖白色。
@export var flash_color: Color = Color("#fff2b2")
## 扩张冲击球和主要爆发粒子使用的橙红色。
@export var explosion_color: Color = Color("#ff5a16")
## 较重、较暗的余烬粒子颜色。
@export var ember_color: Color = Color("#8f1d0c")

@export_category("Dimensions")
## 冲击球最终视觉半径，单位为米；只作为画面参考，不执行范围查询。
@export_range(0.1, 5.0, 0.05) var visual_radius: float = 1.2

@export_category("Particles")
## 主爆发粒子数量。
@export_range(1, 256, 1) var burst_amount: int = 34
## 暗红余烬数量。
@export_range(1, 128, 1) var ember_amount: int = 16

@export_category("Local Light")
## 爆炸初始闪光的峰值能量。
@export_range(0.0, 20.0, 0.1) var light_energy: float = 3.0
## 爆炸局部灯光影响范围，单位为米。
@export_range(0.1, 10.0, 0.1) var light_range: float = 2.2

@onready var visual_root: Node3D = $VisualRoot
@onready var flash_core: MeshInstance3D = $VisualRoot/FlashCore
@onready var explosion_sphere: MeshInstance3D = $VisualRoot/ExplosionSphere
@onready var burst_particles: GPUParticles3D = $BurstParticles
@onready var ember_burst: GPUParticles3D = $EmberBurst
@onready var explosion_light: OmniLight3D = $ExplosionLight
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## 当前是否处于一次有效的爆炸视觉播放周期中。
var playback_is_active: bool = false


## 初始化场景本地资源、动画监听和隐藏状态。
func _ready() -> void:
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)
	_apply_parameters()
	reset_effect()
	if autoplay:
		call_deferred("play")


## 从首帧播放一次爆炸；重复调用会先清理上一轮粒子与动画状态。
func play() -> void:
	animation_player.stop()
	reset_effect()
	animation_player.speed_scale = BASE_ANIMATION_DURATION / maxf(effect_duration, 0.01)
	playback_is_active = true
	visual_root.visible = true
	animation_player.play(EXPLOSION_ANIMATION_NAME)
	effect_started.emit()


## 主动中止爆炸并立即恢复隐藏状态，不发送自然完成信号。
func stop() -> void:
	playback_is_active = false
	animation_player.stop()
	reset_effect()


## 清理网格、粒子和灯光，使实例能够安全循环播放或进入对象池。
func reset_effect() -> void:
	visual_root.visible = false
	flash_core.scale = Vector3.ONE * 0.05
	flash_core.transparency = 1.0
	explosion_sphere.scale = Vector3.ONE * 0.05
	explosion_sphere.transparency = 1.0
	burst_particles.emitting = false
	ember_burst.emitting = false
	explosion_light.light_energy = 0.0


## 返回当前是否正在播放一次爆炸视觉。
func is_playing() -> bool:
	return playback_is_active


## 动画方法轨道调用：同时启动主爆发和暗红余烬的一次性发射。
func _burst_particles() -> void:
	burst_particles.restart()
	burst_particles.emitting = true
	ember_burst.restart()
	ember_burst.emitting = true


## 只处理 explode 动画的自然结束，先通知外部，再按配置决定是否释放实例。
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != EXPLOSION_ANIMATION_NAME or not playback_is_active:
		return
	playback_is_active = false
	reset_effect()
	effect_finished.emit()
	if auto_free_on_finished:
		queue_free()


## 把 Inspector 参数应用到当前实例独享的 Mesh、Material、粒子和灯光资源。
func _apply_parameters() -> void:
	var flash_mesh: SphereMesh = flash_core.mesh as SphereMesh
	if flash_mesh != null:
		flash_mesh.radius = visual_radius * 0.18
		flash_mesh.height = visual_radius * 0.36
	var explosion_mesh: SphereMesh = explosion_sphere.mesh as SphereMesh
	if explosion_mesh != null:
		explosion_mesh.radius = visual_radius
		explosion_mesh.height = visual_radius * 2.0

	burst_particles.amount = maxi(burst_amount, 1)
	ember_burst.amount = maxi(ember_amount, 1)
	explosion_light.light_color = explosion_color
	explosion_light.omni_range = light_range

	_apply_material_color(flash_core.material_override as StandardMaterial3D, flash_color, 0.98, 7.0)
	_apply_material_color(
		explosion_sphere.material_override as StandardMaterial3D,
		explosion_color,
		0.36,
		3.8
	)
	_apply_particle_color(burst_particles, explosion_color, 4.0)
	_apply_particle_color(ember_burst, ember_color, 2.6)
	_apply_light_animation_energy()


## 统一更新透明发光材质，并保留场景预设的混合与无阴影模式。
func _apply_material_color(
	material: StandardMaterial3D,
	color: Color,
	alpha: float,
	emission_multiplier: float
) -> void:
	if material == null:
		return
	var color_with_alpha: Color = color
	color_with_alpha.a = clampf(alpha, 0.0, 1.0)
	material.albedo_color = color_with_alpha
	material.emission = color
	material.emission_energy_multiplier = emission_multiplier


## 更新粒子 Quad 材质颜色，不改变径向运动和生命周期参数。
func _apply_particle_color(
	particles: GPUParticles3D,
	color: Color,
	emission_multiplier: float
) -> void:
	var particle_mesh: QuadMesh = particles.draw_pass_1 as QuadMesh
	if particle_mesh == null:
		return
	_apply_material_color(
		particle_mesh.material as StandardMaterial3D,
		color,
		0.92,
		emission_multiplier
	)


## 将可调灯光峰值写入本实例动画，确保 Inspector 参数控制实际闪光强度。
func _apply_light_animation_energy() -> void:
	var animation: Animation = animation_player.get_animation(EXPLOSION_ANIMATION_NAME)
	if animation == null:
		return
	var track_index: int = animation.find_track(^"ExplosionLight:light_energy", Animation.TYPE_VALUE)
	if track_index < 0:
		return
	for key_index: int in animation.track_get_key_count(track_index):
		var key_time: float = animation.track_get_key_time(track_index, key_index)
		if is_equal_approx(key_time, 0.04):
			animation.track_set_key_value(track_index, key_index, light_energy)
		elif is_equal_approx(key_time, 0.14):
			animation.track_set_key_value(track_index, key_index, light_energy * 0.36)


## 节点退出时关闭粒子和灯光，避免编辑器预览留下动态渲染状态。
func _exit_tree() -> void:
	playback_is_active = false
	if is_instance_valid(burst_particles):
		burst_particles.emitting = false
	if is_instance_valid(ember_burst):
		ember_burst.emitting = false
	if is_instance_valid(explosion_light):
		explosion_light.light_energy = 0.0
