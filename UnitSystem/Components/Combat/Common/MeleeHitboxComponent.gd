class_name MeleeHitboxComponent
extends Node3D

## 玩家与 AI 近战攻击共用的盒形命中检测组件。
##
## 组件只在动画打开判定窗口后查询物理世界，并只发送命中信息。武器决定每段
## Hitbox 的尺寸与偏移，控制器决定何时开关窗口；本组件不处理伤害或攻击状态机。

signal attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	attack_index: int
)

@export_category("Detection")
## 参与近战查询的物理层。默认值 6 同时包含玩家/伙伴所在的第 2 层（位掩码 2）
## 与敌方所在的第 3 层（位掩码 4）；是否实际命中仍由 is_hostile_to() 阵营判断决定，
## 因此该宽松候选范围不会造成同阵营误伤，适用于玩家、伙伴和敌方共用的近战组件。
@export_flags_3d_physics var target_collision_mask: int = 6
## 单个物理帧最多读取的重叠结果数量。
@export_range(1, 128, 1, "or_greater") var maximum_results: int = 32

@export_category("Debug Visualization")
## 开启后仅在有效攻击窗口内显示与真实查询一致的半透明盒体。
@export var debug_hitbox_enabled: bool = true
## 判定窗口尚未命中任何敌人时的颜色。
@export var debug_idle_color: Color = Color(1.0, 0.75, 0.08, 0.18)
## 当前窗口命中过至少一个敌人后的颜色。
@export var debug_hit_color: Color = Color(1.0, 0.08, 0.04, 0.35)

@onready var debug_hitbox: MeshInstance3D = $DebugHitbox

var _owner_unit: UnitBase
var _active_attack_index: int = 0
var _active_size: Vector3 = Vector3.ZERO
var _active_offset: Vector3 = Vector3.ZERO
var _locked_direction: Vector3 = Vector3.ZERO
var _detection_active: bool = false
var _detection_suspended: bool = false
var _hit_target_ids: Dictionary = {}
var _query_shape: BoxShape3D = BoxShape3D.new()
var _debug_material: StandardMaterial3D


func _ready() -> void:
	# 调试盒沿用普通子节点 Transform，不使用 top_level 世界节点。每个物理帧会把
	# 世界查询 Transform 转换为相对于本组件父节点的局部 Transform，避免 top_level
	# 节点初始化时先落到世界原点，再在首帧跳到 AI 位置。
	debug_hitbox.top_level = false
	debug_hitbox.visible = false
	debug_hitbox.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var source_mesh := debug_hitbox.mesh as BoxMesh
	debug_hitbox.mesh = source_mesh.duplicate() if source_mesh != null else BoxMesh.new()

	_debug_material = StandardMaterial3D.new()
	_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_debug_material.albedo_color = debug_idle_color
	debug_hitbox.material_override = _debug_material


func _exit_tree() -> void:
	end_detection()


## 注入拥有本组件的任意 UnitBase。传入 null 会立即关闭当前检测窗口。
func configure_owner(owner_unit: UnitBase) -> void:
	end_detection()
	_owner_unit = owner_unit
	if is_instance_valid(_owner_unit):
		# 先初始化到持有者当前世界位置。AICombatSystem 的 Hitbox 位于一个
		# 非 Node3D 的中间节点下，若不在这里建立初始 Transform，第一次攻击
		# 窗口打开前调试盒会保留默认原点；后续攻击则会因为复用上一轮位置而看似正常。
		_write_debug_transform(_owner_unit.global_transform)
		if is_instance_valid(debug_hitbox):
			debug_hitbox.visible = false


## 使用当前武器指定连击段的数据打开一个全新的检测窗口。
##
## 返回 false 表示持有者、数组索引、尺寸或方向无效；攻击动画仍可继续播放。
func begin_detection(
	weapon_data: MeleeWeaponData,
	attack_index: int,
	locked_direction: Vector3
) -> bool:
	end_detection()
	if not is_instance_valid(_owner_unit) or weapon_data == null:
		return false
	var profile_index: int = attack_index - 1
	if (
		profile_index < 0
		or profile_index >= weapon_data.hitbox_sizes.size()
		or profile_index >= weapon_data.hitbox_center_offsets.size()
	):
		return false

	var profile_size: Vector3 = weapon_data.hitbox_sizes[profile_index]
	if profile_size.x <= 0.0 or profile_size.y <= 0.0 or profile_size.z <= 0.0:
		return false
	var horizontal_direction := Vector3(
		locked_direction.x,
		0.0,
		locked_direction.z
	)
	if horizontal_direction.length_squared() <= 0.0001:
		return false

	_active_attack_index = attack_index
	_active_size = profile_size
	_active_offset = weapon_data.hitbox_center_offsets[profile_index]
	_locked_direction = horizontal_direction.normalized()
	_query_shape.size = _active_size
	_hit_target_ids.clear()
	_detection_active = true
	_update_debug_visual()
	return true


## 使用技能自身的尺寸与偏移打开检测窗口；attack_index 仅作为命中事件标识，不读取武器普攻数组。
func begin_custom_detection(hitbox_size: Vector3, hitbox_center_offset: Vector3, attack_index: int, locked_direction: Vector3) -> bool:
	end_detection()
	if not is_instance_valid(_owner_unit) or hitbox_size.x <= 0.0 or hitbox_size.y <= 0.0 or hitbox_size.z <= 0.0:
		return false
	var horizontal_direction := Vector3(locked_direction.x, 0.0, locked_direction.z)
	if horizontal_direction.length_squared() <= 0.0001:
		return false
	_active_attack_index = maxi(attack_index, 1)
	_active_size = hitbox_size
	_active_offset = hitbox_center_offset
	_locked_direction = horizontal_direction.normalized()
	_query_shape.size = _active_size
	_hit_target_ids.clear()
	_detection_active = true
	_update_debug_visual()
	return true


## 关闭检测、清空本窗口去重记录，并隐藏调试盒。
func end_detection() -> void:
	_detection_active = false
	_detection_suspended = false
	_active_attack_index = 0
	_active_size = Vector3.ZERO
	_active_offset = Vector3.ZERO
	_locked_direction = Vector3.ZERO
	_hit_target_ids.clear()
	if is_instance_valid(debug_hitbox):
		debug_hitbox.visible = false
		# 保留最后一次有效的世界 Transform，只隐藏节点。不要重置为
		# Transform3D.IDENTITY，否则 top_level 调试盒会短暂出现在世界原点，
		# 下一次攻击窗口可能在首个物理帧前闪现错误位置。


## 返回当前是否存在有效攻击判定窗口。
func is_detecting() -> bool:
	return _detection_active


## 暂停或恢复当前窗口的新物理查询，同时保留窗口、方向与已命中目标集合。
func set_detection_suspended(active: bool) -> void:
	_detection_suspended = active and _detection_active


## 返回当前有效窗口是否被外部卡刀反馈暂停。
func is_detection_suspended() -> bool:
	return _detection_suspended


func _physics_process(_delta: float) -> void:
	if not _detection_active:
		return
	if not is_instance_valid(_owner_unit) or not _owner_unit.is_inside_tree():
		end_detection()
		return

	# 实际查询和调试显示共用同一份世界 Transform，避免两者在攻击位移期间产生
	# 位置差异。调试盒直到首个真实查询帧完成坐标同步后才会显示。
	var query_transform: Transform3D = _build_query_transform()
	_update_debug_transform(query_transform)
	if _detection_suspended:
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _query_shape
	query.transform = query_transform
	query.collision_mask = target_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [_owner_unit.get_rid()]
	var results: Array[Dictionary] = (
		_owner_unit.get_world_3d().direct_space_state.intersect_shape(
			query,
			maximum_results
		)
	)
	for result: Dictionary in results:
		_process_result(result)


func _process_result(result: Dictionary) -> void:
	var target := result.get("collider") as UnitBase
	if target == null or target == _owner_unit:
		return
	if not target.is_targetable() or target.is_dead():
		return
	if not _owner_unit.is_hostile_to(target):
		return
	var target_id: int = target.get_instance_id()
	if _hit_target_ids.has(target_id):
		return

	_hit_target_ids[target_id] = true
	_set_debug_color(debug_hit_color)
	var hit_position: Vector3 = target.global_position + Vector3.UP * 0.4
	attack_hit.emit(
		target,
		hit_position,
		_locked_direction,
		_active_attack_index
	)


## 根据角色底面原点、锁定朝向和设计师偏移生成实际查询变换。
func _build_query_transform() -> Transform3D:
	var right_direction: Vector3 = _locked_direction.cross(Vector3.UP).normalized()
	var query_basis := Basis(right_direction, Vector3.UP, -_locked_direction)
	var query_origin := (
		_owner_unit.global_position
		+ right_direction * _active_offset.x
		+ Vector3.UP * _active_offset.y
		+ _locked_direction * _active_offset.z
	)
	return Transform3D(query_basis, query_origin)


func _update_debug_visual() -> void:
	if not is_instance_valid(debug_hitbox):
		return
	# 开窗时先保持隐藏，等首个物理查询帧写入新 Transform 后再显示。
	debug_hitbox.visible = false
	var debug_mesh := debug_hitbox.mesh as BoxMesh
	if debug_mesh == null:
		debug_mesh = BoxMesh.new()
		debug_hitbox.mesh = debug_mesh
	debug_mesh.size = _active_size
	_set_debug_color(debug_idle_color)


func _update_debug_transform(query_transform: Transform3D) -> void:
	if not is_instance_valid(debug_hitbox):
		return
	_write_debug_transform(query_transform)
	debug_hitbox.visible = debug_hitbox_enabled


func _write_debug_transform(world_transform: Transform3D) -> void:
	if not is_instance_valid(debug_hitbox):
		return
	var parent_node := debug_hitbox.get_parent() as Node3D
	if parent_node == null:
		return
	# 实际查询仍使用 query_transform 世界坐标；这里只是将同一结果转换为
	# 调试盒父节点的局部坐标，保证显示和查询完全重合且不依赖玩家节点。
	debug_hitbox.transform = (
		parent_node.global_transform.affine_inverse() * world_transform
	)
	debug_hitbox.force_update_transform()


func _set_debug_color(color: Color) -> void:
	if _debug_material != null:
		_debug_material.albedo_color = color
