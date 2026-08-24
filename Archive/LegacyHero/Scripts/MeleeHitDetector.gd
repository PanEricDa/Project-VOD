extends Node3D

## 与临时武器动画解耦的近战攻击体积检测器。
## 当前使用玩家稳定正前方的 BoxShape3D 查询；未来可以替换为剑刃 ShapeCast，而保持 attack_hit 接口不变。

signal attack_hit(
	target: CharacterBody3D,
	hit_position: Vector3,
	hit_direction: Vector3,
	combo_index: int
)

@export_category("Temporary Hit Volumes")
## 三段攻击的临时盒形区域尺寸，依次为宽度、高度和前后深度，单位为米。
@export var hitbox_sizes: Array[Vector3] = [
	Vector3(1.2, 0.8, 1.0),
	Vector3(1.3, 0.8, 1.1),
	Vector3(1.5, 0.9, 1.2)
]

## 三段攻击区域中心沿玩家正前方的偏移距离，单位为米。
@export var forward_offsets: Array[float] = [0.65, 0.7, 0.8]

## 攻击区域中心相对玩家底面原点的高度，单位为米。
@export_range(0.0, 3.0, 0.05) var hitbox_center_height: float = 0.4

## 参与攻击检测的物理层，默认只检测 Enemy（第 3 层，对应位掩码 4）。
@export_flags_3d_physics var enemy_collision_mask: int = 4

## 单次查询允许返回的最大候选数量。
@export_range(1, 128, 1, "or_greater") var maximum_results: int = 32

@export_category("Debug Visualization")
## 是否在攻击有效窗口内显示临时攻击区域。
@export var debug_hitbox_enabled: bool = true

## 攻击窗口开启但尚未命中时的黄色半透明颜色。
@export var debug_idle_color: Color = Color(1.0, 0.75, 0.08, 0.18)

## 当前攻击段已经命中至少一个目标后的红色半透明颜色。
@export var debug_hit_color: Color = Color(1.0, 0.08, 0.04, 0.35)

@onready var debug_hitbox: MeshInstance3D = $DebugHitbox

var character_body: CharacterBody3D
var facing_node: Node3D
var active_combo_index: int = 0
var detection_is_active: bool = false
var detection_is_suspended: bool = false
var hit_target_ids: Dictionary = {}
var query_shape: BoxShape3D = BoxShape3D.new()
var debug_material: StandardMaterial3D


## 建立调试材质。调试节点设为 top_level，避免继承第三击 AttackSpinPivot 的视觉旋转。
func _ready() -> void:
	debug_hitbox.top_level = true
	debug_hitbox.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	debug_hitbox.visible = false

	debug_material = StandardMaterial3D.new()
	debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	debug_material.albedo_color = debug_idle_color
	debug_hitbox.material_override = debug_material


## 由 MeleeAttackModule 注入玩家物理根节点和稳定朝向节点，避免检测器依赖固定场景层级。
func configure(body: CharacterBody3D, stable_facing_node: Node3D) -> void:
	character_body = body
	facing_node = stable_facing_node


## 开启指定攻击段的检测窗口，并清空本段已命中目标集合。
func begin_attack(combo_index: int) -> void:
	if not _has_profile(combo_index):
		end_attack()
		return

	active_combo_index = combo_index
	detection_is_active = true
	hit_target_ids.clear()
	_update_profile_shape()
	_set_debug_color(debug_idle_color)
	_update_debug_transform()
	debug_hitbox.visible = debug_hitbox_enabled


## 关闭攻击检测窗口并隐藏调试区域。
func end_attack() -> void:
	detection_is_active = false
	active_combo_index = 0
	hit_target_ids.clear()
	debug_hitbox.visible = false


## 局部卡刀期间暂停新的物理查询，但保留当前窗口和本段去重状态，恢复后继续原攻击段。
func set_detection_suspended(suspended: bool) -> void:
	detection_is_suspended = suspended


## 有效窗口内每个物理帧执行体积查询，以覆盖正在移动的敌方目标。
func _physics_process(_delta: float) -> void:
	if not detection_is_active or detection_is_suspended:
		return
	if not is_instance_valid(character_body) or not is_instance_valid(facing_node):
		end_attack()
		return

	var query_transform: Transform3D = _get_query_transform()
	_update_debug_transform(query_transform)

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = query_shape
	query.transform = query_transform
	query.collision_mask = enemy_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [character_body.get_rid()]

	var results: Array[Dictionary] = character_body.get_world_3d().direct_space_state.intersect_shape(
		query,
		maximum_results
	)
	for result: Dictionary in results:
		_process_result(result)


## 过滤敌方分组并保证同一攻击段对同一目标只发出一次命中信号。
func _process_result(result: Dictionary) -> void:
	var collider: Object = result.get("collider") as Object
	var enemy: CharacterBody3D = collider as CharacterBody3D
	if enemy == null or not enemy.is_in_group("enemy_targets"):
		return

	var target_id: int = enemy.get_instance_id()
	if hit_target_ids.has(target_id):
		return

	hit_target_ids[target_id] = true
	var hit_direction: Vector3 = _get_forward_direction()
	var hit_position: Vector3 = _estimate_hit_position(enemy, hit_direction)
	_set_debug_color(debug_hit_color)
	attack_hit.emit(enemy, hit_position, hit_direction, active_combo_index)


## 使用短射线估算敌人表面受击点；射线失败时回退到目标身体中心附近。
func _estimate_hit_position(enemy: CharacterBody3D, hit_direction: Vector3) -> Vector3:
	var ray_origin: Vector3 = character_body.global_position + Vector3.UP * hitbox_center_height
	var fallback_position: Vector3 = enemy.global_position + Vector3.UP * hitbox_center_height
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		fallback_position,
		enemy_collision_mask,
		[character_body.get_rid()]
	)
	var ray_result: Dictionary = character_body.get_world_3d().direct_space_state.intersect_ray(ray_query)
	if not ray_result.is_empty() and ray_result.get("collider") == enemy:
		return ray_result.get("position", fallback_position) as Vector3

	# 保留 hit_direction 参数以明确该回退点属于当前攻击方向，未来 ShapeCast 实现可直接替换本方法。
	if hit_direction.length_squared() <= 0.0001:
		return fallback_position
	return fallback_position


## 生成以玩家稳定正面为本地 -Z 的查询 Transform3D。
func _get_query_transform() -> Transform3D:
	var forward_direction: Vector3 = _get_forward_direction()
	var right_direction: Vector3 = forward_direction.cross(Vector3.UP).normalized()
	var query_basis: Basis = Basis(right_direction, Vector3.UP, -forward_direction)
	var profile_index: int = active_combo_index - 1
	var query_origin: Vector3 = (
		character_body.global_position
		+ forward_direction * forward_offsets[profile_index]
		+ Vector3.UP * hitbox_center_height
	)
	return Transform3D(query_basis, query_origin)


## 返回玩家 Visual 的水平正前方；异常情况下安全回退到 Godot 的默认前方 -Z。
func _get_forward_direction() -> Vector3:
	var forward_direction: Vector3 = -facing_node.global_basis.z
	forward_direction.y = 0.0
	if forward_direction.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return forward_direction.normalized()


## 根据当前攻击段更新查询形状和调试 BoxMesh 尺寸。
func _update_profile_shape() -> void:
	var profile_index: int = active_combo_index - 1
	var profile_size: Vector3 = hitbox_sizes[profile_index]
	query_shape.size = profile_size

	var debug_mesh: BoxMesh = debug_hitbox.mesh as BoxMesh
	if debug_mesh == null:
		debug_mesh = BoxMesh.new()
		debug_hitbox.mesh = debug_mesh
	debug_mesh.size = profile_size


## 将 top_level 调试盒放置到实际查询使用的世界 Transform3D。
func _update_debug_transform(query_transform: Transform3D = Transform3D.IDENTITY) -> void:
	if not debug_hitbox_enabled or character_body == null or facing_node == null:
		return
	if query_transform == Transform3D.IDENTITY:
		query_transform = _get_query_transform()
	debug_hitbox.global_transform = query_transform


## 更新调试盒材质颜色。
func _set_debug_color(color: Color) -> void:
	if debug_material != null:
		debug_material.albedo_color = color


## 检查当前段数是否同时存在尺寸和前向偏移配置。
func _has_profile(combo_index: int) -> bool:
	var profile_index: int = combo_index - 1
	return (
		profile_index >= 0
		and profile_index < hitbox_sizes.size()
		and profile_index < forward_offsets.size()
	)
