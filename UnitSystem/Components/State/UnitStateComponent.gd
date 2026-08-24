class_name UnitStateComponent
extends Node

## 单位状态与生命周期的统一入口。
## 当前只管理死亡、复活和死亡后的生命周期策略；生命值仍由 UnitBase 负责。

enum DeathMode {
	KEEP_FOR_REVIVE,
	REMOVE_AFTER_DELAY,
	REMOVE_IMMEDIATELY,
}

const VISUAL_SLOT_PATH: NodePath = ^"Visual"
const DEATH_ANIMATION_LIBRARY: StringName = &"unit"
const DEATH_ANIMATION_NAME: StringName = &"Die"
const UNIT_DISSOLVE_SHADER: Shader = preload("res://Effects/Death/UnitDissolve.gdshader")

@export_category("Death Response")
## 死亡后的单位处理方式：保留等待复活、延迟移除或立即移除。
@export var death_mode: DeathMode = DeathMode.KEEP_FOR_REVIVE
## 可选的额外死亡效果场景。效果由场景自身负责表现，不影响死亡动画判定。
@export var death_effect_scene: PackedScene
## 延迟移除模式下，从死亡开始计算的最短保留时间；动画未结束时会自动等待动画完成。
@export_range(0.0, 30.0, 0.05, "or_greater") var remove_after_seconds: float = 0.6

@export_category("Dissolve Appearance")
## 本体从死亡姿势消散至完全透明所需的时间。
@export_range(0.05, 10.0, 0.05, "or_greater") var dissolve_duration: float = 1.5
## 溶解边缘的高光颜色；默认采用金白色燃烧纸屑的观感。
@export var dissolve_edge_color: Color = Color(1.0, 0.76, 0.28, 1.0)
## 溶解边缘写入 HDR 发光通道的亮度；场景启用 Glow 后可看到更明显的光晕。
@export_range(0.0, 10.0, 0.1, "or_greater") var dissolve_edge_emission_energy: float = 50.0
## 高光边缘占噪声过渡带的宽度。
@export_range(0.01, 0.3, 0.01) var dissolve_edge_width: float = 0.06
## 溶解图案的细碎程度；数值越大，碎片越细密。
@export_range(0.1, 20.0, 0.1) var dissolve_noise_scale: float = 3.0

var _owner_unit: UnitBase
var _dead_state: bool = false
var _pending_destroy: bool = false
var _destroy_timer: SceneTreeTimer
var _spawned_effect: Node
var _animation_player: CharacterAnimationEventPlayer
var _death_animation_started: bool = false
var _dissolving: bool = false
var _dissolve_tween: Tween
var _dissolve_materials: Array[Dictionary] = []
var _dissolve_noise_offset: Vector3 = Vector3.ZERO
var _dissolve_randomizer := RandomNumberGenerator.new()
var _death_watchdog_timer: SceneTreeTimer
## 死亡动画回调未在此时限内到达时的保底时限，单位为秒。
## 默认 15.0 秒对任何正常死亡动画都足够长；只有信号丢失的异常情况才会触发。
const DEATH_WATCHDOG_SECONDS: float = 15.0


func _ready() -> void:
	# UnitBase 是默认父节点；在 ready 阶段立即连接，确保同一帧造成的伤害也能被状态组件接收。
	_dissolve_randomizer.randomize()
	_configure_from_parent()


func _exit_tree() -> void:
	_disconnect_owner()
	_destroy_timer = null
	_kill_dissolve_tween()
	_disconnect_animation_player()
	_cancel_death_watchdog()


func _configure_from_parent() -> void:
	if _owner_unit == null and get_parent() is UnitBase:
		configure_owner(get_parent() as UnitBase)


func configure_owner(owner_unit: UnitBase) -> void:
	if _owner_unit == owner_unit:
		return
	_disconnect_owner()
	_owner_unit = owner_unit
	if not is_instance_valid(_owner_unit):
		_owner_unit = null
		return
	_owner_unit.died.connect(_on_owner_died)
	_owner_unit.revived.connect(_on_owner_revived)


func _disconnect_owner() -> void:
	if not is_instance_valid(_owner_unit):
		_owner_unit = null
		return
	if _owner_unit.died.is_connected(_on_owner_died):
		_owner_unit.died.disconnect(_on_owner_died)
	if _owner_unit.revived.is_connected(_on_owner_revived):
		_owner_unit.revived.disconnect(_on_owner_revived)
	_owner_unit = null


func _on_owner_died(_source: Node) -> void:
	if _dead_state:
		return
	_dead_state = true
	# 延迟到本帧其他死亡监听器完成后再播放，避免 Player/AI 的动作清理覆盖死亡动画。
	call_deferred(&"_begin_death_presentation")


func _begin_death_presentation() -> void:
	if not _dead_state:
		return
	_death_animation_started = _play_death_animation()
	if death_mode == DeathMode.KEEP_FOR_REVIVE:
		return
	elif death_mode == DeathMode.REMOVE_IMMEDIATELY:
		_queue_owner_free()
	elif death_mode == DeathMode.REMOVE_AFTER_DELAY:
		if not _death_animation_started:
			_schedule_dissolve_start()
		else:
			_start_death_watchdog()

func _on_owner_revived(_current_health: float, _source: Node) -> void:
	_dead_state = false
	cancel_pending_destroy()
	_cancel_dissolve()
	_death_animation_started = false
	_cancel_death_watchdog()
	if is_instance_valid(_animation_player):
		_animation_player.reset_unit_animation()


func _resolve_animation_player() -> void:
	_disconnect_animation_player()
	if not is_instance_valid(_owner_unit):
		return
	var visual_root := _owner_unit.get_node_or_null(VISUAL_SLOT_PATH)
	if visual_root == null:
		return
	_animation_player = visual_root.find_child(
		&"CharacterAnimationPlayer",
		true,
		false
	) as CharacterAnimationEventPlayer
	if _animation_player == null:
		return
	_animation_player.death_animation_finished_requested.connect(_on_death_animation_finished)


func _disconnect_animation_player() -> void:
	if is_instance_valid(_animation_player):
		if _animation_player.death_animation_finished_requested.is_connected(_on_death_animation_finished):
			_animation_player.death_animation_finished_requested.disconnect(_on_death_animation_finished)
	_animation_player = null


func _play_death_animation() -> bool:
	_resolve_animation_player()
	if _animation_player == null:
		return false
	return _animation_player.play_named_animation(
		DEATH_ANIMATION_LIBRARY,
		DEATH_ANIMATION_NAME
	)


func _on_death_animation_finished() -> void:
	_cancel_death_watchdog()
	_death_animation_started = false
	if _dead_state and death_mode == DeathMode.REMOVE_AFTER_DELAY:
		_schedule_dissolve_start()


func _start_death_watchdog() -> void:
	if not is_instance_valid(_owner_unit) or not _owner_unit.is_inside_tree():
		return
	_cancel_death_watchdog()
	_death_watchdog_timer = get_tree().create_timer(DEATH_WATCHDOG_SECONDS)
	_death_watchdog_timer.timeout.connect(_on_death_watchdog_timeout)


func _on_death_watchdog_timeout() -> void:
	_death_watchdog_timer = null
	if _dead_state and not _dissolving:
		push_warning("UnitStateComponent: Death watchdog triggered for " + str(_owner_unit) + " - forcing dissolve pipeline.")
		if _death_animation_started:
			_death_animation_started = false
		_schedule_dissolve_start()


func _cancel_death_watchdog() -> void:
	_death_watchdog_timer = null


func _spawn_death_effect(_source: Node) -> void:
	if death_effect_scene == null or not is_instance_valid(_owner_unit):
		return
	if is_instance_valid(_spawned_effect):
		_spawned_effect.queue_free()
	_spawned_effect = death_effect_scene.instantiate()
	if _spawned_effect == null:
		return
	var effect_parent: Node = _owner_unit.get_parent()
	if effect_parent == null:
		return
	effect_parent.add_child(_spawned_effect)
	if _spawned_effect is Node3D:
		(_spawned_effect as Node3D).global_transform = _owner_unit.global_transform


func _schedule_dissolve_start() -> void:
	if _pending_destroy or not is_instance_valid(_owner_unit):
		return
	_pending_destroy = true
	var delay: float = maxf(remove_after_seconds, 0.0)
	if delay <= 0.0:
		_begin_dissolve_presentation()
		return
	_destroy_timer = get_tree().create_timer(delay)
	_destroy_timer.timeout.connect(_on_destroy_timer_timeout)


func _on_destroy_timer_timeout() -> void:
	_destroy_timer = null
	if _pending_destroy and _dead_state:
		_begin_dissolve_presentation()


func _begin_dissolve_presentation() -> void:
	if not _dead_state or _dissolving or not is_instance_valid(_owner_unit):
		return
	_pending_destroy = true
	_dissolving = true
	_dissolve_noise_offset = Vector3(
		_dissolve_randomizer.randf_range(-1000.0, 1000.0),
		_dissolve_randomizer.randf_range(-1000.0, 1000.0),
		_dissolve_randomizer.randf_range(-1000.0, 1000.0)
	)
	_spawn_death_effect(null)
	_apply_dissolve_materials()
	if dissolve_duration <= 0.0:
		_set_dissolve_progress(1.0)
		_queue_owner_free()
		return
	_dissolve_tween = create_tween()
	_dissolve_tween.tween_method(
		_set_dissolve_progress,
		0.0,
		1.0,
		dissolve_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_dissolve_tween.finished.connect(_on_dissolve_finished)


func _on_dissolve_finished() -> void:
	_dissolve_tween = null
	if _dead_state and _pending_destroy:
		_queue_owner_free()


func _apply_dissolve_materials() -> void:
	_restore_dissolve_materials()
	if not is_instance_valid(_owner_unit) or UNIT_DISSOLVE_SHADER == null:
		return
	var visual_root := _owner_unit.get_node_or_null(VISUAL_SLOT_PATH)
	if visual_root == null:
		return
	for candidate: Node in visual_root.find_children(
		"*",
		"GeometryInstance3D",
		true,
		false
	):
		var geometry := candidate as GeometryInstance3D
		if geometry == null:
			continue
		var original_material: Material = geometry.material_override
		var source_material: Material = original_material
		if source_material == null:
			if geometry is MeshInstance3D:
				source_material = (geometry as MeshInstance3D).get_active_material(0)
			elif geometry is CSGShape3D:
				source_material = (geometry as CSGShape3D).material
		var base_color := Color.WHITE
		var base_texture: Texture2D
		if source_material is BaseMaterial3D:
			var base_material := source_material as BaseMaterial3D
			base_color = base_material.albedo_color
			base_texture = base_material.albedo_texture
		var dissolve_material := ShaderMaterial.new()
		dissolve_material.shader = UNIT_DISSOLVE_SHADER
		dissolve_material.set_shader_parameter(&"base_color", base_color)
		dissolve_material.set_shader_parameter(
			&"edge_emission_energy",
			dissolve_edge_emission_energy
		)
		dissolve_material.set_shader_parameter(&"use_base_texture", base_texture != null)
		dissolve_material.set_shader_parameter(&"base_uv_scale", Vector3.ONE)
		dissolve_material.set_shader_parameter(&"base_uv_offset", Vector3.ZERO)
		dissolve_material.set_shader_parameter(&"use_triplanar", false)
		dissolve_material.set_shader_parameter(&"use_world_triplanar", false)
		if source_material is BaseMaterial3D:
			var mapping_material := source_material as BaseMaterial3D
			dissolve_material.set_shader_parameter(&"base_uv_scale", mapping_material.uv1_scale)
			dissolve_material.set_shader_parameter(&"base_uv_offset", mapping_material.uv1_offset)
			dissolve_material.set_shader_parameter(&"use_triplanar", mapping_material.uv1_triplanar)
			dissolve_material.set_shader_parameter(
				&"use_world_triplanar",
				mapping_material.uv1_triplanar and mapping_material.uv1_world_triplanar
			)
		if base_texture != null:
			dissolve_material.set_shader_parameter(&"base_texture", base_texture)
		dissolve_material.set_shader_parameter(&"edge_color", dissolve_edge_color)
		dissolve_material.set_shader_parameter(&"edge_width", dissolve_edge_width)
		dissolve_material.set_shader_parameter(&"noise_scale", dissolve_noise_scale)
		dissolve_material.set_shader_parameter(&"noise_offset", _dissolve_noise_offset)
		dissolve_material.set_shader_parameter(&"dissolve_progress", 0.0)
		_dissolve_materials.append({
			"geometry": geometry,
			"material": dissolve_material,
			"original_material": original_material,
		})
		geometry.material_override = dissolve_material


func _set_dissolve_progress(progress: float) -> void:
	for entry: Dictionary in _dissolve_materials:
		var material := entry.get("material") as ShaderMaterial
		if material != null:
			material.set_shader_parameter(&"dissolve_progress", progress)


func _restore_dissolve_materials() -> void:
	for entry: Dictionary in _dissolve_materials:
		var geometry := entry.get("geometry") as GeometryInstance3D
		if is_instance_valid(geometry):
			geometry.material_override = entry.get("original_material") as Material
	_dissolve_materials.clear()


func _kill_dissolve_tween() -> void:
	if _dissolve_tween != null and _dissolve_tween.is_valid():
		_dissolve_tween.kill()
	_dissolve_tween = null


func _cancel_dissolve() -> void:
	_kill_dissolve_tween()
	_dissolving = false
	_restore_dissolve_materials()


func _queue_owner_free() -> void:
	_pending_destroy = false
	_dissolving = false
	if is_instance_valid(_owner_unit):
		_owner_unit.queue_free()


func cancel_pending_destroy() -> void:
	# SceneTreeTimer 无法直接取消；通过状态闸门使已排队回调失效。
	_pending_destroy = false
	_destroy_timer = null


func restore_after_revive() -> void:
	_dead_state = false
	cancel_pending_destroy()
	_cancel_dissolve()


func is_pending_destroy() -> bool:
	return _pending_destroy


func is_dead_state() -> bool:
	return _dead_state


func is_dissolving() -> bool:
	return _dissolving


func has_dissolve_materials() -> bool:
	return not _dissolve_materials.is_empty()
