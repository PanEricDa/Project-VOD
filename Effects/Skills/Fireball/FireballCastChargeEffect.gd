class_name FireballCastChargeEffect
extends Node3D

## 每次蓄力视觉从隐藏状态开始播放时发送；不代表技能已经成功施放。
signal effect_started()
## 蓄力视觉自然播放至时间轴末尾时发送；主动调用 stop() 不发送该信号。
signal effect_finished()

const BASE_ANIMATION_DURATION: float = 0.75
const CHARGE_ANIMATION_NAME: StringName = &"charge"

@export_category("Playback")
## 加入场景树后是否自动播放一次，正式技能模块可关闭并通过 play() 精确控制。
@export var autoplay: bool = true
## 整段蓄力视觉的实际时长；内部固定动画会通过 speed_scale 等比缩放。
@export_range(0.1, 3.0, 0.05) var effect_duration: float = 0.75

@export_category("Colors")
## 火球最内层高亮核心的暖白颜色。
@export var core_color: Color = Color("#fff2b2")
## 火球外层半透明火焰壳的橙色。
@export var shell_color: Color = Color("#ff7a1a")
## 向核心聚拢的小型火星使用的金橙色。
@export var spark_color: Color = Color("#ffb347")

@export_category("Dimensions")
## 核心球的半径，单位为米；保持较小以免遮挡角色手部。
@export_range(0.02, 0.5, 0.01) var core_radius: float = 0.09
## 外层火焰壳半径，单位为米；应始终略大于核心半径。
@export_range(0.03, 0.8, 0.01) var shell_radius: float = 0.15

@export_category("Particles")
## 聚拢粒子数量；OrbitSparks 会自动使用该值的大约一半。
@export_range(1, 128, 1) var particle_amount: int = 22
## 聚拢粒子的球形出生半径，单位为米；较小范围让火星保持贴近施法核心。
@export_range(0.05, 1.5, 0.01) var gather_spawn_radius: float = 0.60
## 聚拢粒子的初始向心速度，单位为米每秒；保持较低以表现缓慢启动。
@export_range(0.0, 5.0, 0.05) var gather_speed: float = 0.10
## 聚拢粒子的持续向心加速度，单位为米每平方秒；数值越高，后段汇聚越迅速。
@export_range(0.0, 20.0, 0.1) var gather_acceleration: float = 4.2
## 核心附近装饰火星的球形出生半径，单位为米；不得扩散到角色身体之外。
@export_range(0.03, 0.5, 0.01) var orbit_spawn_radius: float = 0.14

@export_category("Local Light")
## 蓄力达到峰值时的局部灯光能量。
@export_range(0.0, 10.0, 0.1) var light_energy: float = 1.8
## 局部灯光作用范围，单位为米；默认只照亮施法者附近。
@export_range(0.1, 10.0, 0.1) var light_range: float = 1.4

@onready var visual_root: Node3D = $VisualRoot
@onready var charge_core: MeshInstance3D = $VisualRoot/ChargeCore
@onready var charge_shell: MeshInstance3D = $VisualRoot/ChargeShell
@onready var gathering_particles: GPUParticles3D = $VisualRoot/GatheringParticles
@onready var orbit_sparks: GPUParticles3D = $VisualRoot/OrbitSparks
@onready var charge_light: OmniLight3D = $ChargeLight
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## 当前是否处于一次有效的蓄力视觉播放周期中。
var playback_is_active: bool = false


## 初始化场景本地资源、动画监听和确定性隐藏状态。
func _ready() -> void:
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)
	_apply_parameters()
	reset_effect()
	if autoplay:
		call_deferred("play")


## 从头播放一次蓄力；重复调用会先复位，不会叠加粒子或计时任务。
func play() -> void:
	animation_player.stop()
	reset_effect()
	animation_player.speed_scale = BASE_ANIMATION_DURATION / maxf(effect_duration, 0.01)
	playback_is_active = true
	animation_player.play(CHARGE_ANIMATION_NAME)
	effect_started.emit()


## 立即停止当前播放并恢复隐藏状态；主动停止不会伪造自然完成事件。
func stop() -> void:
	playback_is_active = false
	animation_player.stop()
	reset_effect()


## 清除动画、灯光和粒子残留，使组件可以安全重复使用或对象池复用。
func reset_effect() -> void:
	gathering_particles.emitting = false
	orbit_sparks.emitting = false
	visual_root.scale = Vector3.ONE * 0.08
	charge_core.transparency = 1.0
	charge_shell.transparency = 1.0
	charge_light.light_energy = 0.0


## 返回当前是否正在播放蓄力视觉，不表示 SkillModuleBase 的施法状态。
func is_playing() -> bool:
	return playback_is_active


## 动画方法轨道调用：重新启动两组粒子，确保每轮都从首帧开始。
func _start_particles() -> void:
	gathering_particles.restart()
	gathering_particles.emitting = true
	orbit_sparks.restart()
	orbit_sparks.emitting = true


## 动画方法轨道调用：停止继续生成，新产生的粒子按自身寿命自然消散。
func _stop_particles() -> void:
	gathering_particles.emitting = false
	orbit_sparks.emitting = false


## 只响应 charge 动画的自然结束，精确复位后再通知外部重播或交付逻辑。
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != CHARGE_ANIMATION_NAME or not playback_is_active:
		return
	playback_is_active = false
	reset_effect()
	effect_finished.emit()


## 将 Inspector 参数写入当前实例独享的 Mesh、Material、粒子和灯光资源。
func _apply_parameters() -> void:
	var core_mesh: SphereMesh = charge_core.mesh as SphereMesh
	if core_mesh != null:
		core_mesh.radius = core_radius
		core_mesh.height = core_radius * 2.0
	var shell_mesh: SphereMesh = charge_shell.mesh as SphereMesh
	if shell_mesh != null:
		shell_mesh.radius = maxf(shell_radius, core_radius + 0.01)
		shell_mesh.height = maxf(shell_radius, core_radius + 0.01) * 2.0

	gathering_particles.amount = maxi(particle_amount, 1)
	orbit_sparks.amount = maxi(roundi(float(particle_amount) * 0.5), 1)
	var gathering_material: ParticleProcessMaterial = (
		gathering_particles.process_material as ParticleProcessMaterial
	)
	if gathering_material != null:
		gathering_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
		gathering_material.emission_sphere_radius = gather_spawn_radius
		gathering_material.initial_velocity_min = 0.0
		gathering_material.initial_velocity_max = 0.0
		gathering_material.radial_velocity_min = -gather_speed * 1.1
		gathering_material.radial_velocity_max = -gather_speed * 0.9
		gathering_material.radial_accel_min = -gather_acceleration * 1.1
		gathering_material.radial_accel_max = -gather_acceleration * 0.9
	var orbit_material: ParticleProcessMaterial = orbit_sparks.process_material as ParticleProcessMaterial
	if orbit_material != null:
		orbit_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		orbit_material.emission_sphere_radius = orbit_spawn_radius
	charge_light.light_color = shell_color
	charge_light.omni_range = light_range

	_apply_material_color(charge_core.material_override as StandardMaterial3D, core_color, 0.98, 5.5)
	_apply_material_color(charge_shell.material_override as StandardMaterial3D, shell_color, 0.42, 3.2)
	_apply_particle_color(gathering_particles, spark_color, 3.5)
	_apply_particle_color(orbit_sparks, core_color, 4.5)
	_apply_light_animation_energy()


## 更新透明发光材质，同时保留场景中已经配置的透明与无阴影渲染模式。
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


## 更新粒子绘制 Quad 的材质颜色，不改变粒子运动参数和生命周期。
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


## 把可调灯光峰值写入当前实例的动画资源，避免硬编码覆盖 Inspector 参数。
func _apply_light_animation_energy() -> void:
	var animation: Animation = animation_player.get_animation(CHARGE_ANIMATION_NAME)
	if animation == null:
		return
	var track_index: int = animation.find_track(^"ChargeLight:light_energy", Animation.TYPE_VALUE)
	if track_index < 0:
		return
	for key_index: int in animation.track_get_key_count(track_index):
		var key_time: float = animation.track_get_key_time(track_index, key_index)
		if is_equal_approx(key_time, 0.5):
			animation.track_set_key_value(track_index, key_index, light_energy)
		elif is_equal_approx(key_time, 0.64):
			animation.track_set_key_value(track_index, key_index, light_energy * 0.72)
		elif is_equal_approx(key_time, 0.75):
			animation.track_set_key_value(track_index, key_index, light_energy * 0.9)


## 节点离开场景树时关闭所有动态渲染状态，避免编辑器预览遗留粒子或灯光。
func _exit_tree() -> void:
	playback_is_active = false
	if is_instance_valid(gathering_particles):
		gathering_particles.emitting = false
	if is_instance_valid(orbit_sparks):
		orbit_sparks.emitting = false
	if is_instance_valid(charge_light):
		charge_light.light_energy = 0.0
