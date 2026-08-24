class_name GuardianShieldSkillEffect
extends Node3D

## Guardian 的一次性盾击技能表现。
## 场景局部 -Z 视为角色正前方；本脚本不处理命中、伤害、仇恨或防御 Buff。

## 特效开始播放时发送；仅用于未来音效、对象池或表现编排。
signal effect_started()
## 单次视觉自然结束时发送；主动 stop() 不会发送该信号。
signal effect_finished()

const BASE_ANIMATION_DURATION: float = 0.5
const EFFECT_ANIMATION_NAME: StringName = &"shield_bash"

@export_category("Playback")
## 是否在进入场景树后自动播放一次；正式 SkillBase 实例化时默认启用，Preview 也依赖此项循环观察。
@export var autoplay: bool = true
## 自然播放结束后是否自动释放本特效实例；正式技能表现默认启用，Preview 会关闭以便循环重播。
@export var auto_free_on_finished: bool = true
## 整体播放时长，单位为秒；通过缩放固定 0.5 秒动画时间轴实现，不影响技能命中或 Buff 持续时间。
@export_range(0.1, 3.0, 0.05, "or_greater") var effect_duration: float = 0.5

@export_category("Appearance")
## 盾击冲击弧与地面防御环使用的冷蓝色；只影响本特效实例的局部材质。
@export var gold_color: Color = Color("#4fb8ff")
## 冲击弧中央闪光与局部灯光使用的浅蓝白色；只影响本特效实例的局部材质。
@export var highlight_color: Color = Color("#d9f3ff")
## 前方冲击弧最终抵达的局部 Z 坐标，单位为米；负值表示角色正前方，不影响真实 Hitbox 距离。
@export_range(-5.0, -0.05, 0.05) var arc_end_forward_offset: float = -1.1
## 地面防御环的外半径，单位为米；仅提供技能已激活的视觉提示。
@export_range(0.1, 5.0, 0.05) var defense_ring_radius: float = 0.72
## 局部灯光的最高能量；只改善近距离视觉，不改变世界环境光或任何游戏数值。
@export_range(0.0, 10.0, 0.1) var flash_light_energy: float = 1.4

@onready var shield_arc: MeshInstance3D = $ShieldArc
@onready var defense_ring: MeshInstance3D = $DefenseRing
@onready var impact_light: OmniLight3D = $ImpactLight
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _playback_active: bool = false


## 初始化局部材质、尺寸和动画事件；延迟自动播放确保调用者可在 add_child 后先设置位置。
func _ready() -> void:
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)
	_apply_parameters()
	reset_effect()
	if autoplay:
		call_deferred("play")


## 从头播放一次盾击表现；重复调用会精确复位，而不会叠加多个动画或灯光状态。
func play() -> void:
	animation_player.stop()
	reset_effect()
	animation_player.speed_scale = BASE_ANIMATION_DURATION / maxf(effect_duration, 0.01)
	_playback_active = true
	animation_player.play(EFFECT_ANIMATION_NAME)
	effect_started.emit()


## 立即停止并隐藏所有动态视觉；适用于取消表现或对象池回收。
func stop() -> void:
	_playback_active = false
	animation_player.stop()
	reset_effect()


## 返回本实例是否正处于有效播放周期，供 Preview 或未来对象池查询。
func is_playing() -> bool:
	return _playback_active


## 复位到不可见的起始状态，确保下一次播放不会遗留上一轮的位置、透明度或灯光。
func reset_effect() -> void:
	shield_arc.position = Vector3(0.0, 0.33, -0.28)
	shield_arc.scale = Vector3.ONE * 0.2
	shield_arc.transparency = 1.0
	defense_ring.scale = Vector3.ONE * 0.22
	defense_ring.transparency = 1.0
	impact_light.light_energy = 0.0


## 动画自然完成后关闭瞬时灯光并按配置发送完成信号、释放实例。
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != EFFECT_ANIMATION_NAME or not _playback_active:
		return
	_playback_active = false
	impact_light.light_energy = 0.0
	effect_finished.emit()
	if auto_free_on_finished:
		queue_free()


## 将 Inspector 参数写入场景独享 Mesh、Material 和 Animation 资源，避免污染其他特效实例。
func _apply_parameters() -> void:
	var ring_mesh := defense_ring.mesh as TorusMesh
	if ring_mesh != null:
		ring_mesh.outer_radius = defense_ring_radius
		ring_mesh.inner_radius = maxf(defense_ring_radius - 0.055, 0.01)
	_apply_material(shield_arc.material_override as StandardMaterial3D, gold_color, 0.78, 2.8)
	_apply_material(defense_ring.material_override as StandardMaterial3D, gold_color, 0.55, 1.8)
	impact_light.light_color = highlight_color
	_apply_arc_forward_offset()
	_apply_light_peak()


## 将 Inspector 的冲击弧终点写入局部动画关键帧，保证配置值与实际播放轨迹一致。
func _apply_arc_forward_offset() -> void:
	var animation := animation_player.get_animation(EFFECT_ANIMATION_NAME)
	if animation == null:
		return
	var track_index := animation.find_track(^"ShieldArc:position", Animation.TYPE_VALUE)
	if track_index < 0:
		return
	for key_index in animation.track_get_key_count(track_index):
		var key_time := animation.track_get_key_time(track_index, key_index)
		if is_equal_approx(key_time, 0.12) or is_equal_approx(key_time, 0.5):
			animation.track_set_key_value(
				track_index,
				key_index,
				Vector3(0.0, 0.33, arc_end_forward_offset)
			)


## 把可配置的灯光峰值写入局部动画关键帧，保留 AnimationPlayer 中可视化的时间设计。
func _apply_light_peak() -> void:
	var animation := animation_player.get_animation(EFFECT_ANIMATION_NAME)
	if animation == null:
		return
	var track_index := animation.find_track(^"ImpactLight:light_energy", Animation.TYPE_VALUE)
	if track_index < 0:
		return
	for key_index in animation.track_get_key_count(track_index):
		if is_equal_approx(animation.track_get_key_time(track_index, key_index), 0.12):
			animation.track_set_key_value(track_index, key_index, flash_light_energy)


## 统一更新无光照发光材质的色相、透明度和亮度。
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
	material.emission = base_color
	material.emission_energy_multiplier = emission_strength


## 节点退出场景树时保证不留下局部灯光，适配提前销毁与场景切换。
func _exit_tree() -> void:
	_playback_active = false
	if is_instance_valid(impact_light):
		impact_light.light_energy = 0.0
