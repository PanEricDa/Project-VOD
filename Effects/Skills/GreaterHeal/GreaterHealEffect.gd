class_name GreaterHealEffect
extends Node3D

## 圣印降临视觉开始播放时发送；不代表生命值已经恢复。
signal effect_started()

## 单次视觉时间轴自然播放结束时发送；stop() 不会发送该信号。
signal effect_finished()

const BASE_ANIMATION_DURATION: float = 0.8
const EFFECT_ANIMATION_NAME: StringName = &"greater_heal"

@export_category("Playback")
## 进入场景树后是否自动播放一次效果；只影响本特效实例。
@export var autoplay: bool = true
## 自然播放结束后是否自动释放当前效果实例；关闭后可用于预览或对象池重播。
@export var auto_free_on_finished: bool = true
## 整体播放时长，单位为秒；按比例缩放固定0.8秒的圣印时间轴。
@export_range(0.2, 3.0, 0.05) var effect_duration: float = 0.8

@export_category("Colors")
## 下降圣印与祝福微粒使用的暖金色；只影响本特效实例。
@export var seal_gold_color: Color = Color("#ffd875")
## 球形恢复脉冲与局部灯光使用的象牙白；只影响本特效实例。
@export var pulse_light_color: Color = Color("#fff7dc")

@export_category("Dimensions")
## 圣印圆环外半径，单位为米；决定头顶圣印的视觉尺寸。
@export_range(0.1, 2.0, 0.05) var seal_radius: float = 0.55
## 圣印初始高度，单位为米；相对技能目标原点向上偏移。
@export_range(0.2, 4.0, 0.05) var seal_start_height: float = 1.7
## 恢复脉冲完整半径，单位为米；只表达单体治疗反馈，不代表作用范围。
@export_range(0.1, 3.0, 0.05) var pulse_radius: float = 0.85

@export_category("Particles")
## 圣印融入目标时释放的祝福微粒数量；只影响视觉密度。
@export_range(1, 128, 1) var particle_amount: int = 16

@export_category("Local Light")
## 恢复脉冲峰值灯光能量；0表示关闭局部灯光。
@export_range(0.0, 10.0, 0.1) var light_energy: float = 1.8
## 局部灯光作用范围，单位为米；只影响本次视觉照明。
@export_range(0.1, 10.0, 0.1) var light_range: float = 1.8

@onready var descending_seal: Node3D = $DescendingSeal
@onready var seal_ring: MeshInstance3D = $DescendingSeal/SealRing
@onready var seal_vertical: MeshInstance3D = $DescendingSeal/SealVertical
@onready var seal_horizontal: MeshInstance3D = $DescendingSeal/SealHorizontal
@onready var recovery_pulse: MeshInstance3D = $RecoveryPulse
@onready var blessing_motes: GPUParticles3D = $BlessingMotes
@onready var healing_light: OmniLight3D = $HealingLight
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## 当前实例是否处于一次有效的圣印播放周期。
var playback_is_active: bool = false


## 初始化场景内独享资源、动画监听与隐藏状态，并按配置延迟自动播放。
func _ready() -> void:
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)
	_apply_parameters()
	reset_effect()
	if autoplay:
		call_deferred(&"play")


## 从头播放一次圣印降临；重复调用会先复位，不叠加计时或粒子发射。
func play() -> void:
	animation_player.stop()
	reset_effect()
	animation_player.speed_scale = BASE_ANIMATION_DURATION / maxf(effect_duration, 0.01)
	playback_is_active = true
	animation_player.play(EFFECT_ANIMATION_NAME)
	effect_started.emit()


## 立即停止当前视觉并恢复隐藏状态；主动停止不发送完成信号。
func stop() -> void:
	playback_is_active = false
	animation_player.stop()
	reset_effect()


## 将圣印、脉冲、微粒和灯光恢复到动画起始状态，供重播与对象池使用。
func reset_effect() -> void:
	descending_seal.position.y = seal_start_height
	descending_seal.scale = Vector3.ONE * 0.6
	descending_seal.rotation = Vector3.ZERO
	seal_ring.transparency = 1.0
	seal_vertical.transparency = 1.0
	seal_horizontal.transparency = 1.0
	recovery_pulse.visible = false
	recovery_pulse.scale = Vector3.ONE * 0.15
	recovery_pulse.transparency = 1.0
	blessing_motes.emitting = false
	healing_light.light_energy = 0.0


## 返回当前实例是否正在执行一次有效的圣印降临时间轴。
func is_playing() -> bool:
	return playback_is_active


## 动画方法轨道调用：只在圣印融入目标后才让恢复球进入渲染，避免透明球产生脚部暗影。
func _show_recovery_pulse() -> void:
	recovery_pulse.visible = true


## 动画方法轨道调用：从融入时刻重新发射一次祝福微粒。
func _start_particles() -> void:
	blessing_motes.restart()
	blessing_motes.emitting = true


## 动画方法轨道调用：停止继续发射，已产生微粒按生命周期自然消散。
func _stop_particles() -> void:
	blessing_motes.emitting = false


## 只处理本特效的自然结束事件，并根据配置保留或释放实例。
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != EFFECT_ANIMATION_NAME or not playback_is_active:
		return
	playback_is_active = false
	recovery_pulse.visible = false
	blessing_motes.emitting = false
	healing_light.light_energy = 0.0
	effect_finished.emit()
	if auto_free_on_finished:
		queue_free()


## 把Inspector参数写入本实例独享的几何体、材质、粒子、灯光与动画资源。
func _apply_parameters() -> void:
	var ring_mesh := seal_ring.mesh as TorusMesh
	if ring_mesh != null:
		ring_mesh.outer_radius = seal_radius
		ring_mesh.inner_radius = maxf(seal_radius - 0.07, 0.01)
	var pulse_mesh := recovery_pulse.mesh as SphereMesh
	if pulse_mesh != null:
		pulse_mesh.radius = pulse_radius
		pulse_mesh.height = pulse_radius * 2.0
	blessing_motes.amount = maxi(particle_amount, 1)
	healing_light.light_color = pulse_light_color
	healing_light.omni_range = light_range
	_apply_material_color(seal_ring.material_override as StandardMaterial3D, seal_gold_color, 0.9, 2.8)
	_apply_material_color(seal_vertical.material_override as StandardMaterial3D, seal_gold_color, 0.9, 2.8)
	_apply_material_color(seal_horizontal.material_override as StandardMaterial3D, seal_gold_color, 0.9, 2.8)
	_apply_material_color(recovery_pulse.material_override as StandardMaterial3D, pulse_light_color, 0.22, 2.2)
	var particle_mesh := blessing_motes.draw_pass_1 as QuadMesh
	if particle_mesh != null:
		_apply_material_color(particle_mesh.material as StandardMaterial3D, seal_gold_color, 0.85, 2.4)
	_apply_light_animation_energy()


## 将配置的峰值灯光能量写入当前实例独享的动画轨道。
func _apply_light_animation_energy() -> void:
	var animation := animation_player.get_animation(EFFECT_ANIMATION_NAME)
	if animation == null:
		return
	var track_index := animation.find_track(^"HealingLight:light_energy", Animation.TYPE_VALUE)
	if track_index < 0:
		return
	for key_index: int in animation.track_get_key_count(track_index):
		var key_time := animation.track_get_key_time(track_index, key_index)
		if is_equal_approx(key_time, 0.5):
			animation.track_set_key_value(track_index, key_index, light_energy)
		elif is_equal_approx(key_time, 0.65):
			animation.track_set_key_value(track_index, key_index, light_energy * 0.28)


## 统一更新透明发光材质，保证圣印和脉冲保持同一牧师色系。
func _apply_material_color(
	material: StandardMaterial3D,
	base_color: Color,
	alpha: float,
	emission_multiplier: float
) -> void:
	if material == null:
		return
	var color_with_alpha := base_color
	color_with_alpha.a = clampf(alpha, 0.0, 1.0)
	material.albedo_color = color_with_alpha
	material.emission = base_color
	material.emission_energy_multiplier = emission_multiplier


## 节点离树时关闭粒子和灯光，避免场景切换留下残余表现。
func _exit_tree() -> void:
	playback_is_active = false
	if is_instance_valid(blessing_motes):
		blessing_motes.emitting = false
	if is_instance_valid(healing_light):
		healing_light.light_energy = 0.0
