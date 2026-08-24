class_name PlayerTargetingComponent
extends Node3D

## 玩家主动索敌与锁敌的可拆装组件。
##
## 组件只负责读取锁定 InputMap、维护锁定目标、执行目标合法性检查并输出水平朝向。
## 它不会直接修改持有者的速度、旋转、冲刺、摄像机或技能状态，因而可以从 PlayerBase
## 中安全卸下，不影响玩家的基础移动逻辑。

signal locked_target_changed(target: UnitBase)

@export_category("Input")
## 鼠标按屏幕位置选择目标所使用的 InputMap 动作。
@export var target_select_action: StringName = &"player_target_select"
## 自动选择锁定范围内最近敌人所使用的 InputMap 动作。
@export var target_nearest_action: StringName = &"player_target_nearest"

@export_category("Target Lock")
## 锁定可以维持的最大三维世界距离；目标超出该距离后会自动解除。
@export_range(0.5, 50.0, 0.1, "or_greater")
var maximum_lock_distance: float = 5.0
## 鼠标摄像机射线参与检测的物理层。默认同时包含地面层和敌人层。
@export_flags_3d_physics var selection_collision_mask: int = 5
## 鼠标摄像机射线的最大长度；该值不改变实际允许锁定的距离。
@export_range(10.0, 2000.0, 1.0, "or_greater")
var selection_ray_length: float = 1000.0
## 自动选择和合法性检查读取的候选分组。
@export var candidate_group: StringName = &"enemy_targets"

@export_category("Range Indicator")
## 是否显示脚下的锁定范围圆环；关闭显示不会关闭锁定功能。
@export var indicator_enabled: bool = true
## 圆环径向厚度，单位为米。
@export_range(0.005, 0.25, 0.005, "or_greater")
var indicator_thickness: float = 0.03
## 圆环相对玩家根节点的高度，轻微抬高可减少与地面重叠闪烁。
@export_range(0.0, 1.0, 0.005)
var indicator_height: float = 0.03
## 尚未锁定目标时使用的绿色半透明颜色。
@export var indicator_idle_color: Color = Color(0.18, 0.9, 0.32, 0.32)
## 已锁定有效目标时使用的红色半透明颜色。
@export var indicator_locked_color: Color = Color(1.0, 0.12, 0.08, 0.58)

@onready var _range_indicator: MeshInstance3D = (
	get_node_or_null(^"TargetLockRangeIndicator") as MeshInstance3D
)

var _owner_unit: UnitBase
var _locked_target: UnitBase
## 由 PlayerBase 统一维护的输入许可。
## false 时保留现有锁定与合法性检查，但不再响应鼠标选择或最近目标快捷键。
var _input_enabled: bool = true


func _ready() -> void:
	_configure_indicator()
	_validate_input_actions()
	# 子场景会先于 PlayerBase 根节点执行 _ready()，因此必须等待持有者显式注入后
	# 才接收玩家输入，避免尚未配置完成时错误处理锁定请求。
	set_process_unhandled_input(false)


func _exit_tree() -> void:
	# 离开场景树时不再广播状态变化；这里只释放运行时引用，避免接收者正在销毁时
	# 收到无意义的回调。
	_locked_target = null
	_owner_unit = null


## 注入负责使用本组件的玩家单位。
##
## 返回 false 表示传入对象为空、已失效或不是场景树中的 UnitBase。配置失败会清理
## 现有锁定并停止输入处理，但不会阻断持有者自身的物理处理。
func configure(owner_unit: UnitBase) -> bool:
	if (
		not is_instance_valid(owner_unit)
		or not owner_unit.is_inside_tree()
	):
		clear_locked_target()
		_owner_unit = null
		set_process_unhandled_input(false)
		return false

	if _owner_unit != owner_unit:
		clear_locked_target()
	_owner_unit = owner_unit
	set_process_unhandled_input(_input_enabled)
	return true


## 允许或禁止组件读取新的锁定 InputMap 请求。
## enabled 为 false 时不清除既有目标，保证结算界面出现后角色朝向与其他只读系统不会产生额外状态跳变。
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	set_process_unhandled_input(_input_enabled and is_instance_valid(_owner_unit))


## 返回当前有效锁定目标；没有锁定时返回 null。
func get_locked_target() -> UnitBase:
	return _locked_target


## 尝试锁定指定单位。
##
## 成功返回 true。显式请求了非法目标时会统一解除旧锁定，使鼠标点击地面、友军或
## 范围外目标与旧 Hero 的交互规则保持一致。
func request_lock(target: UnitBase) -> bool:
	if not is_valid_lock_target(target):
		clear_locked_target()
		return false
	if _locked_target == target:
		return true

	_locked_target = target
	_update_indicator_color()
	locked_target_changed.emit(_locked_target)
	return true


## 解除当前目标。
##
## 只有状态实际从“有目标”变为“无目标”时才发送一次信号，避免消费者收到重复事件。
func clear_locked_target() -> void:
	if _locked_target == null:
		_update_indicator_color()
		return

	_locked_target = null
	_update_indicator_color()
	locked_target_changed.emit(null)


## 在候选分组中选择距离持有者最近的合法目标。
##
## 本阶段使用三维世界距离，不要求目标出现在屏幕内，也不执行墙体视线检测。
func lock_nearest_target() -> bool:
	if not _has_valid_owner():
		clear_locked_target()
		return false

	var nearest_target: UnitBase
	var nearest_distance_squared: float = INF
	for candidate_node: Node in get_tree().get_nodes_in_group(candidate_group):
		var candidate := candidate_node as UnitBase
		if not is_valid_lock_target(candidate):
			continue
		var distance_squared: float = (
			_owner_unit.global_position.distance_squared_to(
				candidate.global_position
			)
		)
		if distance_squared >= nearest_distance_squared:
			continue
		nearest_distance_squared = distance_squared
		nearest_target = candidate

	if nearest_target == null:
		clear_locked_target()
		return false
	return request_lock(nearest_target)


## 从活动 Camera3D 穿过屏幕坐标发射射线并尝试锁定命中的 UnitBase。
##
## 无摄像机、空命中、地面命中或非法单位命中都返回 false 并解除旧锁定。
func select_target_at_screen_position(screen_position: Vector2) -> bool:
	if not _has_valid_owner():
		clear_locked_target()
		return false

	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		clear_locked_target()
		return false

	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var ray_end: Vector3 = ray_origin + ray_direction * selection_ray_length
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		selection_collision_mask,
		[_owner_unit.get_rid()]
	)
	var hit: Dictionary = (
		_owner_unit.get_world_3d().direct_space_state.intersect_ray(query)
	)
	if hit.is_empty():
		clear_locked_target()
		return false

	var hit_node: Node = hit.get("collider") as Node
	return request_lock(_find_unit_from_node(hit_node))


## 返回玩家指向当前锁定目标的水平单位向量。
##
## 组件只输出方向，由 PlayerBase 决定旋转哪个视觉节点。目标无效或几乎与玩家重合时
## 返回 Vector3.ZERO，使 PlayerBase 可以回退到冲刺或移动朝向。
func get_locked_target_direction() -> Vector3:
	if not is_valid_lock_target(_locked_target):
		return Vector3.ZERO

	var direction: Vector3 = (
		_locked_target.global_position - _owner_unit.global_position
	)
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return Vector3.ZERO
	return direction.normalized()


## 统一判断某个单位能否成为当前玩家的锁定目标。
func is_valid_lock_target(target: UnitBase) -> bool:
	if not _has_valid_owner():
		return false
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if not target.is_in_group(candidate_group):
		return false
	if not target.is_targetable() or target.is_dead():
		return false
	if not _owner_unit.is_hostile_to(target):
		return false
	var maximum_distance_squared: float = (
		maximum_lock_distance * maximum_lock_distance
	)
	return (
		_owner_unit.global_position.distance_squared_to(
			target.global_position
		)
		<= maximum_distance_squared
	)


func _physics_process(_delta: float) -> void:
	if _locked_target != null and not is_valid_lock_target(_locked_target):
		clear_locked_target()


func _unhandled_input(event: InputEvent) -> void:
	if not _input_enabled:
		return
	if (
		InputMap.has_action(target_nearest_action)
		and event.is_action_pressed(target_nearest_action)
	):
		lock_nearest_target()
		get_viewport().set_input_as_handled()
		return

	if (
		not InputMap.has_action(target_select_action)
		or not event.is_action_pressed(target_select_action)
	):
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event == null:
		return
	select_target_at_screen_position(mouse_event.position)
	get_viewport().set_input_as_handled()


func _has_valid_owner() -> bool:
	return (
		is_instance_valid(_owner_unit)
		and _owner_unit.is_inside_tree()
		and not _owner_unit.is_dead()
	)


func _find_unit_from_node(node: Node) -> UnitBase:
	var current: Node = node
	while current != null:
		var unit := current as UnitBase
		if unit != null:
			return unit
		current = current.get_parent()
	return null


func _configure_indicator() -> void:
	if _range_indicator == null:
		push_warning(
			"PlayerTargetingComponent: TargetLockRangeIndicator is missing. "
			+ "Target locking remains available."
		)
		return

	_range_indicator.visible = indicator_enabled
	_range_indicator.position.y = indicator_height
	_range_indicator.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	if not indicator_enabled:
		return

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = maxf(
		maximum_lock_distance - indicator_thickness,
		0.001
	)
	ring_mesh.outer_radius = maximum_lock_distance
	ring_mesh.rings = 96
	ring_mesh.ring_segments = 6
	_range_indicator.mesh = ring_mesh

	var ring_material := StandardMaterial3D.new()
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_range_indicator.material_override = ring_material
	_update_indicator_color()


func _update_indicator_color() -> void:
	if _range_indicator == null or not indicator_enabled:
		return
	var ring_material := (
		_range_indicator.material_override as StandardMaterial3D
	)
	if ring_material == null:
		return
	ring_material.albedo_color = (
		indicator_locked_color
		if is_instance_valid(_locked_target)
		else indicator_idle_color
	)


func _validate_input_actions() -> void:
	if not InputMap.has_action(target_select_action):
		push_warning(
			"PlayerTargetingComponent: missing InputMap action "
			+ str(target_select_action)
		)
	if not InputMap.has_action(target_nearest_action):
		push_warning(
			"PlayerTargetingComponent: missing InputMap action "
			+ str(target_nearest_action)
		)
