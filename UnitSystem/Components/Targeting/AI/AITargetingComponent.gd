class_name AITargetingComponent
extends Area3D

## AI 单位的持续球形感知与稳定锁敌组件。
##
## 本组件只回答“当前锁定谁”，不驱动移动、朝向、攻击或技能。候选资格与优先级
## 统一委托给 TargetSelectionPolicy，使单位行为与目标决策保持解耦。

signal locked_target_changed(
	previous_target: UnitBase,
	current_target: UnitBase
)

## 已锁定目标比首次索敌范围多保留的固定距离。
## 该值属于系统稳定性规则，不暴露给单位逐个配置。
const RETENTION_DISTANCE_BUFFER: float = 1.0
## 调试圆环的固定水平线宽，避免大范围单位的圆环随半径一起变粗。
const DEBUG_RING_WIDTH: float = 0.025
const DEBUG_IDLE_COLOR := Color(0.72, 0.75, 0.80, 0.32)
const DEBUG_LOCKED_COLOR := Color(1.0, 0.24, 0.08, 0.48)

@export_category("Detection")
## 关闭后停止感知，并在下一次刷新时清除当前目标。
@export var detection_enabled: bool = true:
	set(value):
		detection_enabled = value
		if not is_node_ready():
			return
		_sync_detection_configuration()
		if not detection_enabled:
			clear_locked_target()
## 重新验证目标和读取当前重叠单位的时间间隔。
@export_range(0.05, 5.0, 0.05, "or_greater")
var refresh_interval: float = 0.2

@export_category("Debug")
## 仅控制运行时调试圆环是否可见，不影响感知、锁定或目标筛选。
@export var debug_range_visible: bool = true:
	set(value):
		debug_range_visible = value
		_sync_debug_range_ring()

@export_category("Selection")
## 统一的目标筛选与评分配置；所有策略资源都使用同一个脚本类型。
@export var selection_policy: TargetSelectionPolicy

@onready var _detection_shape_node: CollisionShape3D = $DetectionShape
@onready var _debug_range_ring: MeshInstance3D = $DebugRangeRing

var _owner_unit: UnitBase
var _locked_target: UnitBase
var _refresh_elapsed: float = 0.0
var _detection_suspend_remaining: float = 0.0
var _configured: bool = false
var _missing_policy_warning_emitted: bool = false
var _targeting_radius: float = 6.0
var _retention_radius: float = 7.0
## 可选的运行时目标决策提供者。
## 仅用于在既有候选者中调整优先级；它不能直接写入 _locked_target，缺失或失效时严格回退至 selection_policy。
var _target_decision_provider: Node
## 由上层运行时注入的本地索敌失败兜底查询；它不保存目标、不出现在 Inspector，且绝不覆盖有效的本地目标。
var _fallback_target_resolver: Callable
## 目标持有闸门：由行为层在保护目标期间开启，期间 refresh_target 不重新选目标。
var _hold_active: bool = false


func _ready() -> void:
	# 组件必须由持有者显式注入 UnitBase；配置前不运行自动扫描。
	set_physics_process(false)


## 注入组件持有者与该单位唯一的索敌半径，并建立实例私有的球形感知资源。
## 保持半径由组件固定增加一米计算，不要求设计者维护第二个距离参数。
func configure(owner_unit: UnitBase, targeting_radius: float) -> bool:
	if not is_instance_valid(owner_unit):
		push_error(
			"AITargetingComponent: configure() requires a valid UnitBase owner."
		)
		_disable_after_configuration_failure()
		return false
	if not is_instance_valid(_detection_shape_node):
		push_error(
			"AITargetingComponent: DetectionShape node is missing. Node="
			+ str(get_path())
		)
		_disable_after_configuration_failure()
		return false
	var source_shape := _detection_shape_node.shape as SphereShape3D
	if source_shape == null:
		push_error(
			"AITargetingComponent: DetectionShape must use SphereShape3D. Node="
			+ str(get_path())
		)
		_disable_after_configuration_failure()
		return false

	var private_shape := source_shape.duplicate() as SphereShape3D
	if private_shape == null:
		push_error(
			"AITargetingComponent: failed to duplicate SphereShape3D. Node="
			+ str(get_path())
		)
		_disable_after_configuration_failure()
		return false
	_detection_shape_node.shape = private_shape
	_owner_unit = owner_unit
	_targeting_radius = maxf(targeting_radius, 0.1)
	_retention_radius = _targeting_radius + RETENTION_DISTANCE_BUFFER
	_configured = true
	_refresh_elapsed = 0.0
	_detection_suspend_remaining = 0.0
	_prepare_debug_range_ring()
	_sync_detection_configuration()
	_warn_about_missing_policy_once()
	set_physics_process(true)
	return true


func _physics_process(delta: float) -> void:
	if not _configured:
		return
	_detection_suspend_remaining = maxf(
		_detection_suspend_remaining - delta,
		0.0
	)
	if is_detection_suspended():
		clear_locked_target()
		return
	if not detection_enabled:
		refresh_target()
		return

	_refresh_elapsed += delta
	var safe_interval: float = maxf(refresh_interval, 0.05)
	if _refresh_elapsed < safe_interval:
		return
	_refresh_elapsed = 0.0
	refresh_target()


## 立即验证当前锁定；仅在当前目标失效时重新请求 Policy 选择。
func refresh_target() -> void:
	if not _configured or not is_instance_valid(_owner_unit):
		return
	if _owner_unit.is_dead():
		# 死亡只清空当前锁定，不改写 detection_enabled 或暂停计时。
		clear_locked_target()
		return
	_sync_detection_configuration()
	if is_detection_suspended():
		clear_locked_target()
		return
	if not detection_enabled:
		clear_locked_target()
		return
	if selection_policy == null:
		_warn_about_missing_policy_once()
		clear_locked_target()
		return
	if _hold_active:
		if _is_held_target_valid():
			return
		_hold_active = false
	if _has_valid_target_decision_provider():
		var resolved_target := _resolve_provider_target()
		if is_instance_valid(resolved_target):
			_set_locked_target(resolved_target)
			return

	if (
		is_instance_valid(_locked_target)
		and selection_policy.is_candidate_valid(
			_owner_unit,
			_locked_target,
			_retention_radius
		)
	):
		return

	var candidates: Array[UnitBase] = []
	for body: Node3D in get_overlapping_bodies():
		var candidate := body as UnitBase
		if candidate != null:
			candidates.append(candidate)

	var local_target := selection_policy.select_target(
		_owner_unit,
		candidates,
		_targeting_radius
	)
	if is_instance_valid(local_target):
		_set_locked_target(local_target)
		return
	_set_locked_target(_resolve_fallback_target())


## 设置可选的运行时目标决策提供者。
## provider 必须实现 resolve_target()；传入 null、失效节点或缺少方法的节点会安全恢复原 selection_policy 决策，不产生第二份锁定目标。
func set_target_decision_provider(provider: Node) -> void:
	if (
		is_instance_valid(provider)
		and provider.has_method(&"resolve_target")
	):
		_target_decision_provider = provider
		return
	_target_decision_provider = null


## 设置本地感知与既有策略均未选中目标时使用的运行时兜底查询。
## resolver 必须接受唯一参数 owner_unit: UnitBase 并返回 UnitBase 或 null；无效 Callable 会安全清除旧查询。
## 该接口不保存第二个目标，返回目标仍会经过存活、可选取与敌对关系验证。
func set_fallback_target_resolver(resolver: Callable) -> void:
	_fallback_target_resolver = resolver if resolver.is_valid() else Callable()


## 清除运行时目标兜底查询；调用后索敌仅使用本地感知、保持范围与既有 TargetSelectionPolicy。
## 本方法不强制清空当前锁定，下一次常规刷新会按标准本地规则重新验证它。
func clear_fallback_target_resolver() -> void:
	_fallback_target_resolver = Callable()


## 判断当前可选提供者是否仍可安全参与本帧目标优先级计算。
## 节点被删除、离开场景树或缺少约定方法时统一视为不可用，调用方将自动回退原有策略。
func _has_valid_target_decision_provider() -> bool:
	return (
		is_instance_valid(_target_decision_provider)
		and _target_decision_provider.is_inside_tree()
		and _target_decision_provider.has_method(&"resolve_target")
	)


## 读取当前可见候选快照并请求外部提供者排序。
## 返回值只能是本帧候选者，或仍在保持半径内的当前锁定目标；其余返回值全部回退原 selection_policy，防止外部逻辑绕过感知和阵营过滤。
func _resolve_provider_target() -> UnitBase:
	var candidates: Array[UnitBase] = []
	for perceived_node: Node3D in get_perceived_candidates():
		var candidate := perceived_node as UnitBase
		if candidate != null:
			candidates.append(candidate)
	var resolved_value: Variant = _target_decision_provider.call(
		&"resolve_target",
		_owner_unit,
		get_locked_target(),
		candidates,
		selection_policy,
		_targeting_radius,
		_retention_radius
	)
	var resolved_target := resolved_value as UnitBase
	if _is_provider_result_valid(resolved_target, candidates):
		return resolved_target
	return selection_policy.select_target(
		_owner_unit,
		candidates,
		_targeting_radius
	)


## 验证提供者结果未越过感知、保持距离和既有候选资格边界。
## 该保护层只负责结果合法性，不决定仇恨、距离或职业优先级。
func _is_provider_result_valid(
	resolved_target: UnitBase,
	candidates: Array[UnitBase]
) -> bool:
	if not is_instance_valid(resolved_target) or selection_policy == null:
		return false
	if candidates.has(resolved_target):
		return selection_policy.is_candidate_valid(
			_owner_unit,
			resolved_target,
			_targeting_radius
		)
	return (
		resolved_target == get_locked_target()
		and selection_policy.is_candidate_valid(
			_owner_unit,
			resolved_target,
			_retention_radius
		)
	)


## 在本地保持、策略候选均无结果后请求上层兜底目标。
## 兜底查询只能返回对持有者敌对、仍存活且可被选取的 UnitBase；它允许目标暂时位于本地感知半径外。
func _resolve_fallback_target() -> UnitBase:
	if not _fallback_target_resolver.is_valid() or not is_instance_valid(_owner_unit):
		return null
	var resolved_value: Variant = _fallback_target_resolver.call(_owner_unit)
	var resolved_target := resolved_value as UnitBase
	return resolved_target if _is_valid_external_target(resolved_target) else null


func get_locked_target() -> UnitBase:
	return _locked_target if is_instance_valid(_locked_target) else null


func has_locked_target() -> bool:
	return is_instance_valid(_locked_target)


## 行为层锁定保护目标：设置当前锁定并暂停重新选目标，直到 release_target_hold()。
func hold_target(target: UnitBase) -> bool:
	if (
		not _configured
		or not is_instance_valid(target)
		or target == _owner_unit
		or target.is_dead()
		or not target.is_targetable()
	):
		return false
	_set_locked_target(target)
	_hold_active = true
	return true


## 解除目标持有，恢复 refresh_target 的正常重新选目标流程。
func release_target_hold() -> void:
	_hold_active = false


## 返回当前是否处于目标持有状态。
func is_target_held() -> bool:
	return _hold_active


## 返回该单位用于首次发现敌人的唯一可配置半径。
func get_targeting_radius() -> float:
	return _targeting_radius


## 运行时切换首次索敌半径，并同步保留半径与物理检测形状。
## 该接口供行为层在进出战斗等状态变化时调用，不影响其他索敌配置。
func set_targeting_radius(new_radius: float) -> void:
	_targeting_radius = maxf(new_radius, 0.1)
	_retention_radius = _targeting_radius + RETENTION_DISTANCE_BUFFER
	_sync_detection_configuration()
	_sync_debug_range_ring()


## 返回内部稳定锁定半径；该值始终等于索敌半径加一米。
func get_retention_radius() -> float:
	return _retention_radius


## 返回当前感知区域内、且位于首次索敌半径中的只读候选快照。
##
## Area3D 的物理形状使用较大的保持半径，以便稳定维护已经锁定的目标；技能候选
## 不能因此读取到首次索敌半径以外的单位，所以这里必须再次按水平距离过滤。
## 本方法不判断阵营、不排序，也绝不修改 locked_target。
func get_perceived_candidates(
	maximum_distance: float = -1.0
) -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	if (
		not _configured
		or not detection_enabled
		or is_detection_suspended()
		or not is_instance_valid(_owner_unit)
	):
		return candidates
	var query_radius: float = (
		_targeting_radius
		if maximum_distance < 0.0
		else minf(maxf(maximum_distance, 0.0), _targeting_radius)
	)
	var query_radius_squared: float = query_radius * query_radius
	var seen_ids: Dictionary = {}
	for body: Node3D in get_overlapping_bodies():
		if (
			not is_instance_valid(body)
			or body == _owner_unit
			or not body.is_inside_tree()
		):
			continue
		var instance_id: int = body.get_instance_id()
		if seen_ids.has(instance_id):
			continue
		var offset: Vector3 = body.global_position - _owner_unit.global_position
		offset.y = 0.0
		if offset.length_squared() > query_radius_squared:
			continue
		seen_ids[instance_id] = true
		candidates.append(body)
	return candidates


func clear_locked_target() -> void:
	_hold_active = false
	_set_locked_target(null)


func _is_valid_external_target(target: UnitBase) -> bool:
	return (
		is_instance_valid(target)
		and target.is_inside_tree()
		and target.is_targetable()
		and is_instance_valid(_owner_unit)
		and _owner_unit.is_hostile_to(target)
	)


## 临时停止自动和手动索敌，但不修改 Inspector 中持久化的总开关。
##
## 重复调用只会延长现有暂停，不会意外缩短剩余时间。clear_target 为 true 时
## 立即释放当前锁定，使行为层可以安全进入脱战归队状态。
func suspend_detection(
	duration: float,
	clear_target: bool = true
) -> void:
	_detection_suspend_remaining = maxf(
		_detection_suspend_remaining,
		maxf(duration, 0.0)
	)
	_refresh_elapsed = 0.0
	if clear_target:
		clear_locked_target()


func get_detection_suspend_remaining() -> float:
	return _detection_suspend_remaining


func is_detection_suspended() -> bool:
	return _detection_suspend_remaining > 0.0


## 立即解除临时索敌暂停；仅改变运行时状态，不会修改 Inspector 中的 detection_enabled 配置。
func resume_detection() -> void:
	_detection_suspend_remaining = 0.0
	_refresh_elapsed = 0.0


## 运行时替换同类型策略资源；用于未来的玩家策略或职业策略切换。
func set_selection_policy(
	policy: TargetSelectionPolicy,
	refresh_immediately: bool = true
) -> void:
	selection_policy = policy
	_missing_policy_warning_emitted = false
	if selection_policy == null:
		_warn_about_missing_policy_once()
		clear_locked_target()
		return
	if refresh_immediately:
		clear_locked_target()
		refresh_target()


## 校验持有中的目标是否仍可作为合法索敌目标；死亡、不可选中、离树或超出保留半径时失效。
func _is_held_target_valid() -> bool:
	if (
		not is_instance_valid(_locked_target)
		or not _locked_target.is_inside_tree()
	):
		return false
	if selection_policy != null:
		return selection_policy.is_candidate_valid(
			_owner_unit,
			_locked_target,
			_retention_radius
		)
	return (
		not _locked_target.is_dead()
		and _locked_target.is_targetable()
	)


func _set_locked_target(target: UnitBase) -> void:
	var normalized_target: UnitBase = target if is_instance_valid(target) else null
	var previous_target: UnitBase = (
		_locked_target if is_instance_valid(_locked_target) else null
	)
	if previous_target == normalized_target:
		_locked_target = normalized_target
		return
	_locked_target = normalized_target
	_sync_debug_range_ring()
	locked_target_changed.emit(previous_target, _locked_target)


func _sync_detection_configuration() -> void:
	_targeting_radius = maxf(_targeting_radius, 0.1)
	_retention_radius = _targeting_radius + RETENTION_DISTANCE_BUFFER
	refresh_interval = maxf(refresh_interval, 0.05)
	monitoring = detection_enabled
	if not is_instance_valid(_detection_shape_node):
		return
	var sphere_shape := _detection_shape_node.shape as SphereShape3D
	if sphere_shape != null:
		sphere_shape.radius = _retention_radius
	_sync_debug_range_ring()


## 为每个单位复制独立的圆环网格和材质。
## 这样运行时调整一个单位的半径或锁定颜色，不会污染共享场景资源或其他实例。
func _prepare_debug_range_ring() -> void:
	if not is_instance_valid(_debug_range_ring):
		return
	var source_mesh := _debug_range_ring.mesh as TorusMesh
	var source_material := (
		_debug_range_ring.material_override as StandardMaterial3D
	)
	if source_mesh == null or source_material == null:
		_debug_range_ring.visible = false
		return
	var private_mesh := source_mesh.duplicate() as TorusMesh
	var private_material := source_material.duplicate() as StandardMaterial3D
	if private_mesh == null or private_material == null:
		_debug_range_ring.visible = false
		return
	_debug_range_ring.mesh = private_mesh
	_debug_range_ring.material_override = private_material


## 同步调试圆环的开关、半径和锁定状态颜色。
## 该方法只更新视觉资源，绝不改变 Area3D、碰撞形状或目标状态。
func _sync_debug_range_ring() -> void:
	if not is_instance_valid(_debug_range_ring):
		return
	_debug_range_ring.visible = debug_range_visible
	if not debug_range_visible:
		return
	var torus := _debug_range_ring.mesh as TorusMesh
	var material := (
		_debug_range_ring.material_override as StandardMaterial3D
	)
	if torus == null or material == null:
		_debug_range_ring.visible = false
		return
	var desired_inner_radius: float = maxf(
		_targeting_radius - DEBUG_RING_WIDTH,
		0.01
	)
	if not is_equal_approx(torus.outer_radius, _targeting_radius):
		torus.outer_radius = _targeting_radius
	if not is_equal_approx(torus.inner_radius, desired_inner_radius):
		torus.inner_radius = desired_inner_radius
	var desired_color: Color = (
		DEBUG_LOCKED_COLOR if has_locked_target() else DEBUG_IDLE_COLOR
	)
	if not material.albedo_color.is_equal_approx(desired_color):
		material.albedo_color = desired_color


func _warn_about_missing_policy_once() -> void:
	if selection_policy != null or _missing_policy_warning_emitted:
		return
	_missing_policy_warning_emitted = true
	push_warning(
		"AITargetingComponent: selection_policy is missing; targeting remains "
		+ "disabled. Node="
		+ str(get_path())
	)


func _disable_after_configuration_failure() -> void:
	_configured = false
	_owner_unit = null
	_detection_suspend_remaining = 0.0
	monitoring = false
	set_physics_process(false)
	clear_locked_target()
