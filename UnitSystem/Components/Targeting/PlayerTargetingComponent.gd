class_name PlayerTargetingComponent
extends Node3D

## 玩家主动索敌与锁敌的可拆装组件。
##
## 组件只负责读取锁定 InputMap、维护锁定目标、执行目标合法性检查并输出水平朝向。
## 它同时驱动两个互相独立的显示层：玩家脚下的 Debug 范围圆环（开发工具，正式配置默认
## 关闭，仅可视化最大锁定距离）与目标脚下的正式锁定特效 TargetLockIndicator（单实例
## 三状态表现，只呈现锁定结果，不参与任何锁定判定）。
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

@export_category("Debug Range Indicator")
## 是否显示玩家脚下的锁定范围 Debug 圆环；仅用于开发时观察最大锁定距离，
## 正式游戏默认关闭。关闭显示不会关闭锁定功能，也不影响正式锁定特效。
@export var indicator_enabled: bool = false
## Debug 圆环径向厚度，单位为米；只影响开发可视化，不参与锁定判定。
@export_range(0.005, 0.25, 0.005, "or_greater")
var indicator_thickness: float = 0.03
## Debug 圆环相对玩家根节点的高度，单位为米；轻微抬高可减少与地面重叠闪烁。
@export_range(0.0, 1.0, 0.005)
var indicator_height: float = 0.03
## Debug 圆环尚未锁定目标时使用的绿色半透明颜色；与正式特效无任何资源共享。
@export var indicator_idle_color: Color = Color(0.18, 0.9, 0.32, 0.32)
## Debug 圆环已锁定有效目标时使用的红色半透明颜色；与正式特效无任何资源共享。
@export var indicator_locked_color: Color = Color(1.0, 0.12, 0.08, 0.58)

@export_category("Formal Lock Indicator")
## 正式锁定特效总开关；关闭只隐藏目标脚下的圆环表现，
## 不影响锁定能力、合法性判断和信号语义。
@export var formal_indicator_enabled: bool = true
## 正式锁定特效的默认场景资源；由组件场景指定为 TargetLockIndicator.tscn，
## 允许以后整体替换美术表现而不修改锁定算法。留空或实例化失败时安全降级为无显示。
@export var formal_indicator_scene: PackedScene
## 正式特效相对目标根节点世界位置的统一抬高，单位为米；默认 0.03 以减少地面重叠闪烁。
@export_range(0.0, 0.5, 0.005)
var formal_indicator_height: float = 0.03

@onready var _range_indicator: MeshInstance3D = (
	get_node_or_null(^"TargetLockRangeIndicator") as MeshInstance3D
)

var _owner_unit: UnitBase
var _locked_target: UnitBase
## 是否持有需要管理的锁定引用。目标被直接释放后其引用与 null 比较结果相同，
## 无法单凭 _locked_target 区分“从未锁定”与“引用失效”，因此用该标记兜底，
## 保证统一清空路径（广播 null 并让正式特效退出）在目标被释放时仍然执行。
var _lock_held: bool = false
## 由 PlayerBase 统一维护的输入许可。
## false 时保留现有锁定与合法性检查，但不再响应鼠标选择或最近目标快捷键。
var _input_enabled: bool = true
## 当前唯一的正式锁定特效实例；未配置、被禁用或创建失败时为 null。
var _formal_indicator: TargetLockIndicator
## 正式特效初始化诊断是否已输出过，避免重复刷屏。
var _formal_indicator_issue_reported: bool = false


func _ready() -> void:
	_configure_indicator()
	_create_formal_indicator()
	_validate_input_actions()
	# 子场景会先于 PlayerBase 根节点执行 _ready()，因此必须等待持有者显式注入后
	# 才接收玩家输入，避免尚未配置完成时错误处理锁定请求。
	set_process_unhandled_input(false)


func _exit_tree() -> void:
	# 离开场景树时不再广播状态变化；这里只释放运行时引用，避免接收者正在销毁时
	# 收到无意义的回调。
	_dispose_formal_indicator()
	_locked_target = null
	_lock_held = false
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
	_lock_held = true
	_update_indicator_color()
	locked_target_changed.emit(_locked_target)
	_enter_formal_indicator(_locked_target)
	return true


## 解除当前目标。
##
## 只有状态实际从“有目标”变为“无目标”时才发送一次信号，避免消费者收到重复事件。
## 目标已被直接释放时 _locked_target 与 null 不可区分，由 _lock_held 保证
## 仍然完整执行一次广播与正式特效退出。
func clear_locked_target() -> void:
	if _locked_target == null and not _lock_held:
		_update_indicator_color()
		return

	_locked_target = null
	_lock_held = false
	_update_indicator_color()
	locked_target_changed.emit(null)
	_exit_formal_indicator()


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
	if (
		not is_instance_valid(_locked_target)
		or not is_valid_lock_target(_locked_target)
	):
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
	if _locked_target == null and not _lock_held:
		return
	# 目标已被直接释放时引用与 null 不可区分，且带类型参数的合法性函数会在
	# 调用点拒绝已释放对象，因此先用 is_instance_valid 短路再进入统一清空路径。
	if (
		not is_instance_valid(_locked_target)
		or not is_valid_lock_target(_locked_target)
	):
		clear_locked_target()
		return
	_update_formal_indicator_position()


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


## 初始化期间至多创建一个正式特效实例。
## 与 _configure_indicator() 完全独立：特效被禁用、场景未配置、实例类型错误或缺少
## 必要表现接口时只输出一次诊断并安全降级，不阻断输入验证和锁定初始化。
func _create_formal_indicator() -> void:
	if not formal_indicator_enabled:
		return
	if formal_indicator_scene == null:
		_report_formal_indicator_issue(
			"PlayerTargetingComponent: formal indicator scene is not configured. "
			+ "Target locking remains available."
		)
		return
	var instantiated_root := formal_indicator_scene.instantiate()
	var indicator := instantiated_root as TargetLockIndicator
	if indicator == null:
		# 类型不符的替换场景已经实例化但不会入树；立即释放避免孤儿节点泄漏。
		instantiated_root.queue_free()
		_report_formal_indicator_issue(
			"PlayerTargetingComponent: formal indicator scene root is not a TargetLockIndicator."
		)
		return
	if not (
		indicator.has_method(&"play_enter")
		and indicator.has_method(&"update_world_position")
		and indicator.has_method(&"play_exit")
		and indicator.has_method(&"hide_immediately")
	):
		indicator.queue_free()
		_report_formal_indicator_issue(
			"PlayerTargetingComponent: formal indicator is missing its presentation interface."
		)
		return
	add_child(indicator)
	_formal_indicator = indicator


## 计算目标脚下（含统一高度偏移）的世界位置并触发进入表现；目标无效时安全跳过。
func _enter_formal_indicator(target: UnitBase) -> void:
	if not is_instance_valid(_formal_indicator) or not is_instance_valid(target):
		return
	_formal_indicator.play_enter(
		target.global_position + Vector3.UP * formal_indicator_height
	)


## 锁定仍有效时把正式特效同步到目标脚下；不触发新动画，也不做第二套合法性判断。
func _update_formal_indicator_position() -> void:
	if not is_instance_valid(_formal_indicator) or _locked_target == null:
		return
	_formal_indicator.update_world_position(
		_locked_target.global_position + Vector3.UP * formal_indicator_height
	)


## 让现有正式特效从最后同步位置退出；不读取已被清空或释放的目标。
func _exit_formal_indicator() -> void:
	if not is_instance_valid(_formal_indicator):
		return
	_formal_indicator.play_exit()


## 组件销毁时立即隐藏并释放正式实例；不等待退出动画，也不访问目标对象。
func _dispose_formal_indicator() -> void:
	if is_instance_valid(_formal_indicator):
		_formal_indicator.hide_immediately()
		_formal_indicator.queue_free()
	_formal_indicator = null


## 输出一次性的正式特效诊断信息，避免每帧刷屏。
func _report_formal_indicator_issue(message: String) -> void:
	if _formal_indicator_issue_reported:
		return
	_formal_indicator_issue_reported = true
	push_warning(message)


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
