class_name FireballFlightEffect
extends Node3D

const FLIGHT_PULSE_ANIMATION: StringName = &"flight_pulse"

@export_category("Playback")
## 加入场景树后是否立即启动持续飞行视觉；正式投射物也可关闭后手动调用 start()。
@export var autoplay: bool = true

@export_category("Colors")
## 火球内部高亮核心的暖白颜色。
@export var core_color: Color = Color("#fff2b2")
## 半透明外层火焰壳与主要尾迹使用的橙红色。
@export var shell_color: Color = Color("#ff641a")
## 稀疏余烬使用的暗红色，用于从主尾焰中提供层次差异。
@export var spark_color: Color = Color("#8f1d0c")

@export_category("Dimensions")
## 暖白核心半径，单位为米。
@export_range(0.02, 0.5, 0.01) var core_radius: float = 0.09
## 橙红外焰半径，单位为米；应略大于核心。
@export_range(0.03, 0.8, 0.01) var shell_radius: float = 0.15

@export_category("Trail")
## 连续尾焰粒子数量；粒子使用世界坐标，发射器移动后会留在原位衰减。
@export_range(1, 256, 1) var trail_amount: int = 28
## 单个尾焰粒子存活时间，单位为秒；较短数值保持尾迹紧凑。
@export_range(0.05, 2.0, 0.01) var trail_lifetime: float = 0.28
## 暗红余烬数量；低数量避免快速飞行时形成杂乱长线。
@export_range(1, 128, 1) var spark_amount: int = 8

@export_category("Local Light")
## 飞行脉冲峰值灯光能量。
@export_range(0.0, 10.0, 0.1) var light_energy: float = 1.4
## 局部灯光作用范围，单位为米。
@export_range(0.1, 10.0, 0.1) var light_range: float = 1.6

@onready var visual_root: Node3D = $VisualRoot
@onready var core_visual: MeshInstance3D = $VisualRoot/CoreVisual
@onready var flame_shell: MeshInstance3D = $VisualRoot/FlameShell
@onready var trail_particles: GPUParticles3D = $TrailParticles
@onready var ember_sparks: GPUParticles3D = $EmberSparks
@onready var local_light: OmniLight3D = $LocalLight
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## 当前是否正在输出持续飞行视觉；不表示投射物仍然具有碰撞或目标。
var effect_is_active: bool = false


## 初始化当前实例独享的视觉资源，并按配置选择是否自动启动。
func _ready() -> void:
	_apply_parameters()
	reset_effect()
	if autoplay:
		call_deferred("start")


## 从确定性初始状态启动火球核心、循环脉冲和两组连续尾迹。
func start() -> void:
	animation_player.stop()
	reset_effect()
	effect_is_active = true
	visual_root.visible = true
	local_light.light_energy = light_energy
	trail_particles.restart()
	trail_particles.emitting = true
	ember_sparks.restart()
	ember_sparks.emitting = true
	animation_player.play(FLIGHT_PULSE_ANIMATION)


## 停止持续视觉并清理灯光与发射状态；已经产生的世界粒子按寿命自然消失。
func stop() -> void:
	effect_is_active = false
	animation_player.stop()
	reset_effect()


## 恢复可重复使用的隐藏状态，不移动当前节点，也不处理任何投射物逻辑。
func reset_effect() -> void:
	visual_root.visible = false
	flame_shell.scale = Vector3.ONE
	flame_shell.transparency = 0.12
	trail_particles.emitting = false
	ember_sparks.emitting = false
	local_light.light_energy = 0.0


## 返回持续飞行视觉是否处于启用状态。
func is_active() -> bool:
	return effect_is_active


## 把 Inspector 参数写入场景本地 Mesh、Material、粒子和灯光资源。
func _apply_parameters() -> void:
	var core_mesh: SphereMesh = core_visual.mesh as SphereMesh
	if core_mesh != null:
		core_mesh.radius = core_radius
		core_mesh.height = core_radius * 2.0
	var shell_mesh: SphereMesh = flame_shell.mesh as SphereMesh
	if shell_mesh != null:
		var safe_shell_radius: float = maxf(shell_radius, core_radius + 0.01)
		shell_mesh.radius = safe_shell_radius
		shell_mesh.height = safe_shell_radius * 2.0

	trail_particles.amount = maxi(trail_amount, 1)
	trail_particles.lifetime = maxf(trail_lifetime, 0.01)
	ember_sparks.amount = maxi(spark_amount, 1)
	local_light.light_color = shell_color
	local_light.omni_range = light_range

	_apply_material_color(core_visual.material_override as StandardMaterial3D, core_color, 0.98, 5.8)
	_apply_material_color(flame_shell.material_override as StandardMaterial3D, shell_color, 0.48, 3.6)
	_apply_particle_color(trail_particles, shell_color, 3.2)
	_apply_particle_color(ember_sparks, spark_color, 2.8)
	_apply_light_animation_energy()


## 统一更新透明发光材质，保留场景预先配置的无阴影和混合模式。
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


## 更新粒子 Quad 的颜色，不让正式投射物关心粒子材质内部结构。
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
		0.9,
		emission_multiplier
	)


## 将可调峰值写入本实例的循环动画，使 Inspector 灯光参数保持权威。
func _apply_light_animation_energy() -> void:
	var animation: Animation = animation_player.get_animation(FLIGHT_PULSE_ANIMATION)
	if animation == null:
		return
	var track_index: int = animation.find_track(^"LocalLight:light_energy", Animation.TYPE_VALUE)
	if track_index < 0:
		return
	for key_index: int in animation.track_get_key_count(track_index):
		var key_time: float = animation.track_get_key_time(track_index, key_index)
		if is_equal_approx(key_time, 0.0) or is_equal_approx(key_time, 0.32):
			animation.track_set_key_value(track_index, key_index, light_energy)
		elif is_equal_approx(key_time, 0.16):
			animation.track_set_key_value(track_index, key_index, light_energy * 0.72)


## 离开场景树时停止粒子与灯光，避免编辑器预览或对象池留下渲染残留。
func _exit_tree() -> void:
	effect_is_active = false
	if is_instance_valid(trail_particles):
		trail_particles.emitting = false
	if is_instance_valid(ember_sparks):
		ember_sparks.emitting = false
	if is_instance_valid(local_light):
		local_light.light_energy = 0.0
