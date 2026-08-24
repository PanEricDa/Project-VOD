class_name AIAttackHitbox
extends Node3D

## AI 攻击模块共用的体积命中检测组件。
## 组件只在父攻击模块打开命中窗口时工作，不处理伤害、击退、受击反馈或目标状态。

signal hit_detected(
	target: CharacterBody3D,
	hit_position: Vector3,
	hit_direction: Vector3
)

@export_category("Target Filter")
## 参与检测的物理层，默认只查询项目 Enemy 第 3 层，对应位掩码 4。
@export_flags_3d_physics var target_collision_mask: int = 4

## 目标除物理层匹配外还必须属于该分组，避免其他 Enemy 层物体被误认作战斗单位。
@export var target_group: StringName = &"enemy_targets"

## 单个物理帧允许 ShapeCast 返回的最大候选数量。
@export_range(1, 128, 1, "or_greater") var maximum_results: int = 32

@export_category("Debug Visualization")
## 是否在检测窗口内显示与 BoxShape3D 等大的半透明调试盒。
@export var debug_hitbox_enabled: bool = false

## 窗口开启但尚未命中目标时使用的黄色半透明颜色。
@export var debug_idle_color: Color = Color(1.0, 0.75, 0.08, 0.18)

## 当前窗口至少命中一个目标后使用的红色半透明颜色。
@export var debug_hit_color: Color = Color(1.0, 0.08, 0.04, 0.35)

@onready var hitbox_shape_cast: ShapeCast3D = $HitboxShapeCast
@onready var debug_hitbox: MeshInstance3D = $DebugHitbox

## 持有当前攻击模块的物理角色，用于从 ShapeCast 查询中排除自身。
var owner_body: CharacterBody3D

## 当前是否处于动画定义的有效命中窗口。
var detection_is_active: bool = false

## 局部卡刀期间只暂停新的 ShapeCast 查询；有效窗口和单轮去重集合都会完整保留。
var detection_is_suspended: bool = false

## 当前窗口已经命中过的目标实例 ID；窗口重新开始时清空。
var hit_target_ids: Dictionary = {}

## 每个检测实例独立持有的调试材质，避免多个单位互相修改颜色。
var debug_material: StandardMaterial3D


## 初始化 ShapeCast 参数、调试材质和默认关闭状态。
func _ready() -> void:
	hitbox_shape_cast.enabled = false
	hitbox_shape_cast.target_position = Vector3.ZERO
	hitbox_shape_cast.collision_mask = target_collision_mask
	hitbox_shape_cast.collide_with_bodies = true
	hitbox_shape_cast.collide_with_areas = false
	hitbox_shape_cast.max_results = maximum_results

	debug_hitbox.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	debug_material = StandardMaterial3D.new()
	debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	debug_hitbox.material_override = debug_material
	# 父场景的 Mesh SubResource 会被所有继承场景共享；同步尺寸前复制，避免实例间互相改写。
	if debug_hitbox.mesh != null:
		debug_hitbox.mesh = debug_hitbox.mesh.duplicate() as Mesh
	else:
		debug_hitbox.mesh = BoxMesh.new()
	_sync_debug_mesh_size()
	end_detection()


## 注入或清除攻击持有者，并同步 ShapeCast 的碰撞例外。
## 模块可独立测试，因此 body 为 null 时仍允许检测，只是不排除持有者。
func configure(body: CharacterBody3D) -> void:
	owner_body = body
	if not is_instance_valid(hitbox_shape_cast):
		return
	hitbox_shape_cast.clear_exceptions()
	if is_instance_valid(owner_body):
		hitbox_shape_cast.add_exception(owner_body)


## 开启新一轮检测，清空单轮去重集合并立即同步形状和调试显示。
func begin_detection() -> void:
	if not _has_valid_shape():
		end_detection()
		push_warning("AIAttackHitbox: HitboxShapeCast requires a valid Shape3D.")
		return

	hit_target_ids.clear()
	detection_is_active = true
	detection_is_suspended = false
	hitbox_shape_cast.collision_mask = target_collision_mask
	hitbox_shape_cast.max_results = maximum_results
	hitbox_shape_cast.enabled = true
	_sync_debug_mesh_size()
	_set_debug_color(debug_idle_color)
	debug_hitbox.visible = debug_hitbox_enabled


## 关闭检测并恢复完全静止状态；取消、复位、脱战和卸装都会经过该入口。
func end_detection() -> void:
	detection_is_active = false
	detection_is_suspended = false
	hit_target_ids.clear()
	if is_instance_valid(hitbox_shape_cast):
		hitbox_shape_cast.enabled = false
	if is_instance_valid(debug_hitbox):
		debug_hitbox.visible = false


## 返回当前是否正在执行有效体积查询。
func is_detecting() -> bool:
	return detection_is_active


## 暂停或恢复当前有效窗口的物理查询，不清空已经命中的目标 ID。
## 恢复时只有仍处于有效窗口且形状有效，才会重新启用 ShapeCast。
func set_detection_suspended(suspended: bool) -> void:
	detection_is_suspended = suspended
	if not is_instance_valid(hitbox_shape_cast):
		return
	hitbox_shape_cast.enabled = (
		detection_is_active
		and not detection_is_suspended
		and _has_valid_shape()
	)


## 供攻击模块、效果桥测试和未来调试工具读取当前查询暂停状态。
func is_detection_suspended() -> bool:
	return detection_is_suspended


## 有效窗口内每个物理帧强制刷新 ShapeCast，使窗口开启前已在区域内的目标也能被检测。
func _physics_process(_delta: float) -> void:
	if not detection_is_active or detection_is_suspended or not _has_valid_shape():
		return

	hitbox_shape_cast.force_shapecast_update()
	var collision_count: int = min(
		hitbox_shape_cast.get_collision_count(),
		maximum_results
	)
	for collision_index: int in range(collision_count):
		_process_collision(collision_index)


## 过滤碰撞对象，并保证同一窗口内每个目标只发送一次命中事件。
func _process_collision(collision_index: int) -> void:
	var target: CharacterBody3D = hitbox_shape_cast.get_collider(
		collision_index
	) as CharacterBody3D
	if target == null or target == owner_body:
		return
	if not target.is_in_group(target_group):
		return

	var target_id: int = target.get_instance_id()
	if hit_target_ids.has(target_id):
		return

	hit_target_ids[target_id] = true
	_set_debug_color(debug_hit_color)
	hit_detected.emit(
		target,
		hitbox_shape_cast.get_collision_point(collision_index),
		_get_hit_direction()
	)


## 返回检测组件世界朝向的水平 -Z，异常情况下回退为 Godot 默认前方。
func _get_hit_direction() -> Vector3:
	var hit_direction: Vector3 = -global_basis.z
	hit_direction.y = 0.0
	if hit_direction.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return hit_direction.normalized()


## BoxShape3D 用于当前近战原型时，让调试 BoxMesh 自动采用相同尺寸。
func _sync_debug_mesh_size() -> void:
	if not is_instance_valid(hitbox_shape_cast) or not is_instance_valid(debug_hitbox):
		return
	var box_shape: BoxShape3D = hitbox_shape_cast.shape as BoxShape3D
	if box_shape == null:
		return
	var box_mesh: BoxMesh = debug_hitbox.mesh as BoxMesh
	if box_mesh == null:
		box_mesh = BoxMesh.new()
		debug_hitbox.mesh = box_mesh
	box_mesh.size = box_shape.size


func _set_debug_color(color: Color) -> void:
	if debug_material != null:
		debug_material.albedo_color = color


func _has_valid_shape() -> bool:
	return is_instance_valid(hitbox_shape_cast) and hitbox_shape_cast.shape != null
