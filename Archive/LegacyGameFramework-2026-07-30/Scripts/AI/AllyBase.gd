extends CharacterBody3D

const SkillModuleBaseType = preload("res://Scripts/Combat/Skills/SkillModuleBase.gd")
const SkillProfileType = preload("res://Scripts/Combat/Skills/SkillProfile.gd")
const IndependentSkillHostType = preload("res://SkillSystem/01-Core/SkillHostComponent.gd")
const AllySkillRequestBridgeType = preload("res://Scripts/AI/Components/AllySkillRequestBridge.gd")

## 当锁定编队侧发生变化时发出。-1 表示玩家左侧，1 表示玩家右侧。
## 需要协同站位的子职业可以监听该信号，并通过父类统一入口维护自己的侧向状态。
signal formation_side_changed(new_side: int)

## 当最近的可见敌方目标发生变化时发出，供后续追击、攻击或职业脚本使用。
signal visible_enemy_changed(enemy: CharacterBody3D)

## 已装配技能的通用生命周期转发信号。
## AllyBase 只转发父模块接口，不解释投射物、AOE、治疗或伤害语义。
signal equipped_skill_queued(target: Node3D)
signal equipped_skill_range_required(target: Node3D, cast_range: float, tolerance: float)
signal equipped_skill_cast_started(target: Node3D)
signal equipped_skill_delivered(target: Node3D, target_position: Vector3)
signal equipped_skill_cast_failed(target: Node3D, reason: StringName)
signal equipped_skill_cast_cancelled(target: Node3D)

## Guardian 的高层行为状态。
## WANDER 在玩家前方区域内游走，REPOSITION 返回编队区域，DASH 快速纠正位置，RECOVER 负责冲刺后的平滑过渡。
enum BehaviorState {
	WANDER,
	REPOSITION,
	DASH,
	RECOVER
}

## 顶层活动模式严格隔离玩家编队与敌人战斗定位，禁止同一物理帧计算两套移动目标。
enum ActivityMode {
	FORMATION,
	COMBAT
}

## 普通攻击只细分 COMBAT 内部的移动与攻击阶段，不替代顶层编队/战斗模式。
enum BasicAttackState {
	GUARD,
	APPROACH,
	ATTACK,
	HOLD,
	RETURN_TO_GUARD
}

## 友方角色在编队区域中的侧向站位规则。
## FREE_CROSSING 保留原有自由跨越逻辑；其他模式可以锁定随机侧或固定侧。
enum FormationSideMode {
	FREE_CROSSING,
	LOCKED_RANDOM_SIDE,
	FIXED_LEFT,
	FIXED_RIGHT
}

@export_category("Target")
## 需要陪伴的玩家节点路径。
## 默认从 TestScene 中的 Guardian 实例向同级 hero 节点查找。
@export_node_path("CharacterBody3D") var player_path: NodePath = ^"../Hero"

## 相对于玩家根节点的视觉朝向节点路径。编队正面以该节点的 -Z 方向为准。
## 默认对应 Hero/Visual；只有该节点不存在时才回退到玩家移动方向。
@export var player_facing_node_path: NodePath = ^"Visual"

@export_category("Enemy Detection")
## 是否启用当前友方单位的敌人范围检测。
@export var enemy_detection_enabled: bool = true

## 球形视野的半径，单位为米。该参数会在运行时同步到 CombatSensor 的 SphereShape3D。
@export_range(0.5, 30.0, 0.1, "or_greater") var enemy_vision_range: float = 6.0

## 从范围内候选敌人中重新确认最近目标的间隔，避免每个物理帧重复排序。
@export_range(0.05, 2.0, 0.05, "or_greater") var enemy_target_refresh_interval: float = 0.2

@export_category("Combat Guard Distance")
## 当前职业在没有执行攻击接近时，希望与敌人保持的水平警戒距离。
## 该参数与武器 Profile 的 attack_range 分离，继承职业仍可独立覆盖。
@export_range(0.1, 30.0, 0.1, "or_greater") var combat_guard_distance: float = 2.0

## 警戒距离两侧的迟滞容差，避免角色在边界附近反复前后移动。
@export_range(0.0, 5.0, 0.05) var combat_guard_distance_tolerance: float = 0.2

## 战斗圆环游荡相对于普通 movement_speed 的速度倍率。
## 保留统一基础速度参数，同时让战斗中的轻微换位更加克制并减少距离过冲。
@export_range(0.1, 1.0, 0.05) var combat_wander_speed_multiplier: float = 0.45

@export_category("Basic Attack")
## 当前单位装备的普通攻击模块路径；空路径表示该单位只执行现有警戒站位。
@export_node_path("Node3D") var attack_module_path: NodePath

## 当前单位所有普通攻击共享的冷却时间，单位为秒。
## 计时只在模块成功接受攻击请求时开始，切换目标或取消动画不会清零。
@export_range(0.0, 10.0, 0.05) var basic_attack_global_cooldown: float = 1.0

@export_category("Skill Module")
## 当前单位装配的通用技能模块路径；空路径表示尚未装配技能。
## 技能模块不依赖 AllyBase，只有当前宿主通过其公共接口进行单向调用。
@export_node_path("Node3D") var skill_module_path: NodePath

## 技能插槽只承担模块发现职责；自动扫描严格限制为该节点的直接子节点，
## 避免把模块内部用于表现或交付的嵌套节点误注册为同级技能。
@export_node_path("Node3D") var skill_module_socket_path: NodePath = ^"VisualRoot/SkillModuleSocket"

@export_category("Independent Skill Host")
## 新独立技能系统的通用 Host 路径。该 Host 与旧 SkillModuleSocket 并存，
## 本阶段只接受外部显式请求，不会由 AllyBase 自动选择或释放技能。
@export_node_path("Node") var independent_skill_host_path: NodePath = ^"SkillHostComponent"

## 新系统自动请求桥的路径。父场景默认装配但关闭，由具体职业源场景显式启用。
@export_node_path("Node") var skill_request_bridge_path: NodePath = ^"AllySkillRequestBridge"

## 迁移期间保留旧技能调度入口。只要新请求桥启用，旧入口仍会被强制旁路，
## 因此该字段不能造成同一角色同时运行两套自动技能调度器。
@export var legacy_skill_scheduler_enabled: bool = true

@export_category("Combat Leash")
## 玩家与当前敌人之间允许维持战斗的最大水平距离；超过后伙伴强制脱战并返回编队。
@export_range(1.0, 50.0, 0.5, "or_greater") var maximum_player_target_distance: float = 12.0

## 强制脱战后，敌人必须重新进入玩家该距离内才允许伙伴再次参战。
@export_range(0.5, 50.0, 0.5, "or_greater") var player_target_reengage_distance: float = 10.0

## 强制脱战后暂停搜索敌人的时间，单位为秒；期间感知候选仍正常维护。
@export_range(0.0, 10.0, 0.1) var combat_disengage_search_cooldown: float = 1.5

@export_category("Vision Range Indicator")
## 是否显示伙伴脚下的视野范围圆环。圆环仅用于可视化，不参与物理检测。
@export var vision_indicator_enabled: bool = true

## 圆环线条的径向厚度，单位为米。
@export_range(0.005, 0.25, 0.005, "or_greater") var vision_indicator_thickness: float = 0.025

## 圆环相对角色根节点的高度偏移，略高于地面可减少与地面重叠闪烁。
@export_range(0.0, 1.0, 0.005) var vision_indicator_height: float = 0.025

## 视野内没有敌人时使用的浅灰色半透明颜色。
@export var vision_indicator_idle_color: Color = Color(0.78, 0.78, 0.78, 0.22)

## 视野内存在敌人时使用的橙红色提示颜色。
@export var vision_indicator_alert_color: Color = Color(1.0, 0.22, 0.06, 0.68)

@export_category("Formation")
## 友方角色相对玩家移动方向的纵向编队距离，单位为米。
## 正数表示玩家前方，负数表示玩家身后；具体职业可以在继承场景中覆盖该参数。
@export_range(-10.0, 10.0, 0.1) var front_distance: float = 2.5

## 动态编队中心追随玩家方向变化时的指数平滑强度。
## 数值越低越柔和，数值越高越快切换到新的玩家前方区域。
@export_range(0.1, 20.0, 0.1, "or_greater") var formation_smoothness: float = 6.0

## 超过该距离后，Guardian 会停止局部游走并进入返回编队状态。
@export_range(1.0, 20.0, 0.1, "or_greater") var maximum_player_distance: float = 4.5

## Guardian 落后到该距离时，即使玩家没有转向也允许使用冲刺追赶。
@export_range(1.0, 30.0, 0.1, "or_greater") var emergency_dash_distance: float = 5.5

@export_category("Wander")
## 编队活动区域的最大左右半径，单位为米。
@export_range(0.0, 5.0, 0.05) var wander_lateral_radius: float = 1.1

## 随机站位距离编队中心线的最小横向距离，单位为米。
## 默认值 0 允许经过中心；远程职业可以设置正值，使站位稳定分布在左右两侧。
@export_range(0.0, 5.0, 0.05) var wander_lateral_minimum: float = 0.0

## 当前角色使用的侧向站位模式。
## 父类默认允许自由跨越；子场景可以覆盖为随机锁定或固定左右侧。
@export var formation_side_mode: FormationSideMode = FormationSideMode.FREE_CROSSING

## 判定角色离开当前锁定区域时使用的额外边界余量，单位为米。
## 该迟滞范围可以防止角色在边界附近反复进入和退出。
@export_range(0.0, 3.0, 0.05) var formation_exit_margin: float = 0.4

## 角色持续位于锁定区域外超过该时间后，才会重新随机选择左右侧。
@export_range(0.0, 3.0, 0.05) var side_reselection_delay: float = 0.35

## 编队活动区域沿前后方向的半径，单位为米。
@export_range(0.0, 5.0, 0.05) var wander_forward_radius: float = 0.65

## 重新选择随机游走目标的最短间隔，单位为秒。
@export_range(0.1, 10.0, 0.1, "or_greater") var wander_interval_min: float = 1.5

## 重新选择随机游走目标的最长间隔，单位为秒。
@export_range(0.1, 10.0, 0.1, "or_greater") var wander_interval_max: float = 3.0

## 新旧游走目标之间需要保持的最小距离，避免随机后目标几乎没有变化。
@export_range(0.0, 3.0, 0.05) var minimum_target_change_distance: float = 0.35

@export_category("Movement")
## Guardian 普通移动的最大速度，单位为米/秒。
@export_range(0.1, 20.0, 0.1, "or_greater") var movement_speed: float = 4.2

## 普通移动的加速和减速率，单位为米/秒²。
@export_range(0.1, 100.0, 0.1, "or_greater") var movement_acceleration: float = 20.0

## 距目标小于该距离时开始按比例减速，避免到达后突然停止。
@export_range(0.1, 5.0, 0.05, "or_greater") var slowing_distance: float = 0.2

## 距目标小于该距离时视为到达。
@export_range(0.05, 2.0, 0.05, "or_greater") var arrival_distance: float = 0.15

@export_category("Dash")
## 玩家方向变化超过该角度时，可以触发位置纠正冲刺。
@export_range(1.0, 180.0, 1.0) var dash_turn_angle_threshold: float = 55.0

## Guardian 距离新编队中心超过该值时，玩家转向才会触发冲刺。
@export_range(0.1, 10.0, 0.1, "or_greater") var dash_trigger_distance: float = 1.5

## 玩家持续移动时，Guardian 与实时编队中心之间允许的最大误差，单位为米。
## 冷却结束后若仍超过该距离，会再次冲刺，直到真正回到玩家前方区域。
@export_range(0.1, 20.0, 0.1, "or_greater") var dash_retry_distance: float = 2.5

## 判断玩家是否处于持续移动状态的最小水平速度，单位为米/秒。
## 低于该速度时不会因为编队误差反复冲刺，避免玩家静止时伙伴在游走区域内过度使用冲刺。
@export_range(0.0, 5.0, 0.05) var dash_retry_player_speed_threshold: float = 0.5

## 玩家新方向需要保持的确认时间，避免快速切换按键造成误触发。
@export_range(0.0, 1.0, 0.01) var direction_confirmation_time: float = 0.1

## Guardian 冲刺的最大速度，单位为米/秒。
@export_range(0.1, 40.0, 0.1, "or_greater") var dash_speed: float = 9.0

## 单次 AI 冲刺允许移动的最大距离，单位为米。
@export_range(0.1, 20.0, 0.1, "or_greater") var dash_max_distance: float = 3.0

## 冲刺距离目标小于该值时提前结束，避免越过目标点。
@export_range(0.05, 2.0, 0.05, "or_greater") var dash_arrival_distance: float = 0.35

## 两次 AI 冲刺之间的最短冷却时间，单位为秒。
@export_range(0.0, 10.0, 0.1) var dash_cooldown: float = 1.5

## 冲刺结束后的恢复时间，期间 Guardian 平滑减速且不会立即重新冲刺。
@export_range(0.0, 2.0, 0.05) var dash_recovery_duration: float = 0.2

## 冲刺进入高速状态时的加速度，单位为米/秒²。
@export_range(0.1, 200.0, 0.5, "or_greater") var dash_acceleration: float = 40.0

@export_category("Facing")
## Guardian 视觉模型的转向速度，单位为弧度/秒。
@export_range(0.1, 30.0, 0.1, "or_greater") var rotation_speed: float = 7.0

## 静止或低速时重新对齐玩家前进方向的最短间隔。
@export_range(0.1, 10.0, 0.1) var facing_update_interval_min: float = 1.2

## 静止或低速时重新对齐玩家前进方向的最长间隔。
@export_range(0.1, 10.0, 0.1) var facing_update_interval_max: float = 2.1

## 高于该水平速度时优先面向实际移动方向。
@export_range(0.0, 5.0, 0.05) var movement_facing_speed_threshold: float = 0.35

@onready var visual: Node3D = $VisualRoot
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var combat_sensor: Area3D = $CombatSensor
@onready var combat_sensor_shape: CollisionShape3D = $CombatSensor/VisionShape
@onready var vision_range_indicator: MeshInstance3D = $VisionRangeIndicator

var player: CharacterBody3D
## 玩家视觉朝向节点的缓存引用，用于建立不依赖按键方向的编队坐标系。
var player_facing_node: Node3D
## 当前视野范围内由 CombatSensor 收集到的有效敌方候选单位。
var visible_enemies: Array[CharacterBody3D] = []

## 当前距离最近的可见敌人。此阶段只提供感知结果，不会触发追击或攻击。
var current_visible_enemy: CharacterBody3D

## 控制最近目标刷新频率的内部计时器。
var enemy_target_refresh_timer: float = 0.0
@export_category("Physics")
## 友方单位受到的重力倍率。所有 AllyBase 子职业都可以在 Inspector 中独立覆盖。
@export_range(0.0, 10.0, 0.1, "or_greater") var gravity_multiplier: float = 1.0

## 从项目物理设置读取 Godot 默认重力加速度。
var gravity_force: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var random_generator: RandomNumberGenerator = RandomNumberGenerator.new()
var activity_mode: ActivityMode = ActivityMode.FORMATION
var behavior_state: BehaviorState = BehaviorState.WANDER

## 当前装配的普通攻击模块。模块只负责动画，目标与移动决策仍由 AllyBase 管理。
var attack_module: AIAttackModuleBase

## 当前装配的通用技能模块；具体职业效果由未来继承模块实现。
var skill_module: SkillModuleBaseType

## 新独立技能系统的中介 Host。缺失时所有新接口安全返回 false，旧行为不受影响。
var independent_skill_host: IndependentSkillHostType

## 仅负责把 Ally 的战斗上下文交给新 Host，并把 Host 的移动意图暴露回 AllyBase。
## 桥接器本身不修改速度，也不读取任何 AllyBase 私有字段。
var skill_request_bridge: AllySkillRequestBridgeType

## 当前宿主可调度的全部通用技能模块。模块各自保留物理处理，因而未被选中时
## 仍会独立推进本地冷却；active_skill_module 只表示唯一的请求/施法占用槽。
var registered_skill_modules: Array[SkillModuleBaseType] = []
var active_skill_module: SkillModuleBaseType

## 当前普通攻击子状态；只在 COMBAT 模式且模块有效时参与移动决策。
var basic_attack_state: BasicAttackState = BasicAttackState.GUARD

## 当前单位普通攻击公共冷却的剩余秒数。
var basic_attack_global_cooldown_remaining: float = 0.0

var stable_player_direction: Vector3 = Vector3.FORWARD
var candidate_player_direction: Vector3 = Vector3.FORWARD
var direction_confirmation_elapsed: float = 0.0
var raw_formation_center: Vector3 = Vector3.ZERO
var smoothed_formation_center: Vector3 = Vector3.ZERO
var wander_offset: Vector3 = Vector3.ZERO

## 当前游走目标在玩家局部右方向上的距离。
## 保存局部数值而不是永久世界坐标，使玩家转向后区域能稳定随方向旋转。
var wander_lateral_value: float = 0.0

## 当前游走目标在玩家局部前方向上的距离。
var wander_longitudinal_value: float = 0.0

## 当前锁定侧：-1 表示左侧，1 表示右侧，0 表示尚未选择。
var locked_side: int = 0

## 是否已经实际进入过当前选定的单侧编队区域。
## 只有进入后再次离开，才允许重新抽取侧向。
var has_entered_locked_region: bool = false

## 连续位于当前锁定区域外的累计时间。
var outside_locked_region_elapsed: float = 0.0

var movement_target: Vector3 = Vector3.ZERO
var wander_timer: float = 0.0
## 当前战斗游荡点相对于敌人的水平单位方向；敌人移动时用它重建世界目标点。
var combat_wander_direction: Vector3 = Vector3.ZERO
## 当前战斗游荡点与敌人的目标半径。
var combat_wander_radius: float = 0.0
## 是否已经为当前敌人生成可用的战斗游荡点。
var combat_wander_target_is_valid: bool = false
## 是否正处于强制脱战后的重新参战保护；只有玩家重新接近敌人后才解除。
var combat_reengage_guard_is_active: bool = false
## 强制脱战后暂停目标选择的剩余时间。
var combat_search_cooldown_remaining: float = 0.0
var facing_timer: float = 0.0
var desired_facing_direction: Vector3 = Vector3.FORWARD

var dash_target: Vector3 = Vector3.ZERO
var dash_direction: Vector3 = Vector3.ZERO
var dash_remaining_distance: float = 0.0
var dash_cooldown_remaining: float = 0.0
var recovery_remaining: float = 0.0


## 初始化目标引用、随机数、编队中心和首个游走点。
func _ready() -> void:
	_configure_enemy_detection()
	_resolve_attack_module_from_path()
	_discover_skill_modules_from_socket()
	_resolve_skill_module_from_path()
	_resolve_independent_skill_host()
	_resolve_skill_request_bridge()
	player = get_node_or_null(player_path) as CharacterBody3D
	if player == null:
		push_error(
			"AllyBase: player_path does not reference a CharacterBody3D. "
			+ "Node=" + name
			+ ", Path=" + str(get_path())
			+ ", Configured=" + str(player_path)
		)
		set_physics_process(false)
		return

	player_facing_node = player.get_node_or_null(player_facing_node_path) as Node3D
	if player_facing_node == null:
		push_warning(
			"AllyBase: player_facing_node_path does not reference a Node3D; "
			+ "formation will fall back to player movement direction. "
			+ "Node=" + name
			+ ", Configured=" + str(player_facing_node_path)
		)

	random_generator.randomize()
	stable_player_direction = _read_player_direction()
	candidate_player_direction = stable_player_direction
	raw_formation_center = _calculate_raw_formation_center(stable_player_direction)
	smoothed_formation_center = raw_formation_center
	_initialize_formation_side()
	_select_new_wander_target()
	desired_facing_direction = stable_player_direction


## 固定物理帧更新所有 AI 决策、移动、重力与碰撞。
func _physics_process(delta: float) -> void:
	_update_combat_disengage(delta)
	_update_enemy_detection(delta)
	dash_cooldown_remaining = max(dash_cooldown_remaining - delta, 0.0)
	basic_attack_global_cooldown_remaining = max(
		basic_attack_global_cooldown_remaining - delta,
		0.0
	)
	_update_independent_skill_host_action_block()
	_update_skill_request_bridge_context()

	var independent_skill_owns_movement: bool = _process_independent_skill_intent(delta)
	if not independent_skill_owns_movement:
		match activity_mode:
			ActivityMode.COMBAT:
				_process_combat_mode(delta)
			_:
				_process_formation_mode(delta)

	_apply_gravity(delta)
	_update_visual_facing(delta)
	move_and_slide()

	# 冲刺撞到环境障碍物时立即结束；友方角色不在碰撞掩码中，不会触发此条件。
	if activity_mode == ActivityMode.FORMATION and behavior_state == BehaviorState.DASH and is_on_wall():
		_finish_dash()


## 玩家编队模式的唯一更新入口；只有此分支会计算编队中心、分侧、归队和编队冲刺。
func _process_formation_mode(delta: float) -> void:
	_update_player_direction(delta)
	_update_formation_center(delta)
	_update_formation_side_lock(delta)
	_update_behavior_state()
	_update_facing_timer(delta)

	match behavior_state:
		BehaviorState.WANDER:
			_process_wander(delta)
		BehaviorState.REPOSITION:
			_process_reposition(delta)
		BehaviorState.DASH:
			_process_dash(delta)
		BehaviorState.RECOVER:
			_process_recovery(delta)


## 战斗定位模式的唯一更新入口；不读取或更新任何玩家编队移动目标。
func _process_combat_mode(delta: float) -> void:
	if not is_instance_valid(current_visible_enemy) or not current_visible_enemy.is_inside_tree():
		_enter_formation_mode()
		return

	# 技能调度先于普攻和警戒移动取得本帧的水平移动所有权；重力、朝向插值与
	# move_and_slide 仍由共同物理路径执行，不在此处提前结束整帧。
	if _process_skill_scheduler(delta):
		return
	if is_instance_valid(attack_module):
		_process_basic_attack(delta)
	else:
		_process_guard_distance(delta)
	_update_enemy_facing()


## 按 Inspector 路径解析初始攻击模块；路径为空或节点类型不匹配时保持无装备状态。
func _resolve_attack_module_from_path() -> void:
	if attack_module_path.is_empty():
		set_attack_module(null)
		return
	set_attack_module(get_node_or_null(attack_module_path) as AIAttackModuleBase)


## 统一装配或卸下普通攻击模块，可供场景初始化与未来运行时换装共同调用。
## 卸下时会复位旧模块，但不会清除已经开始的公共冷却。
func set_attack_module(module: AIAttackModuleBase) -> void:
	if attack_module == module:
		return

	if is_instance_valid(attack_module):
		var finished_callable: Callable = Callable(self, "_on_attack_module_finished")
		if attack_module.attack_finished.is_connected(finished_callable):
			attack_module.attack_finished.disconnect(finished_callable)
		attack_module.cancel_attack()
		attack_module.configure_attack_owner(null)

	attack_module = module
	basic_attack_state = BasicAttackState.GUARD
	combat_wander_target_is_valid = false

	if not is_instance_valid(attack_module):
		return

	var new_finished_callable: Callable = Callable(self, "_on_attack_module_finished")
	if not attack_module.attack_finished.is_connected(new_finished_callable):
		attack_module.attack_finished.connect(new_finished_callable)
	attack_module.configure_attack_owner(self)


## 返回当前普通攻击公共冷却剩余秒数，供测试、调试界面或未来技能调度读取。
func get_basic_attack_global_cooldown_remaining() -> float:
	return basic_attack_global_cooldown_remaining


## 返回当前 Ally 装配的新独立技能 Host；没有有效装配时返回 null。
func get_independent_skill_host() -> Node:
	return independent_skill_host if is_instance_valid(independent_skill_host) else null


## 返回当前单位的自动请求桥，供职业装配测试、调试工具和未来运行时开关使用。
func get_skill_request_bridge() -> Node:
	return skill_request_bridge if is_instance_valid(skill_request_bridge) else null


## 将一个明确技能 ID 和目标转发给新 Host。
## 该入口不会自动寻找目标、移动角色或失败重试，因此不会改变原有 AI 决策。
func request_independent_skill(
	skill_id: StringName,
	target: Node3D = null,
	target_position: Vector3 = Vector3.INF,
	request_mode: int = 0
) -> bool:
	if not is_instance_valid(independent_skill_host):
		return false
	return independent_skill_host.request_skill(
		skill_id,
		target,
		target_position,
		request_mode
	)


## 请求新 Host 从当前可用技能中选择一个，但目标仍必须由外部调用方提供。
## 本阶段 AllyBase 自己不会调用该方法。
func request_best_independent_skill(
	target: Node3D = null,
	target_position: Vector3 = Vector3.INF,
	request_mode: int = 1
) -> bool:
	if not is_instance_valid(independent_skill_host):
		return false
	return independent_skill_host.request_best_skill(
		target,
		target_position,
		request_mode
	)


## 解析并配置新 Host。运行父节点使用当前主场景，确保 Delivery 不跟随 Ally 移动。
func _resolve_independent_skill_host() -> void:
	independent_skill_host = get_node_or_null(
		independent_skill_host_path
	) as IndependentSkillHostType
	if not is_instance_valid(independent_skill_host):
		push_error(
			"AllyBase: independent_skill_host_path does not reference "
			+ "an IndependentSkillHostComponent. Node=" + name
			+ ", Configured=" + str(independent_skill_host_path)
		)
		return
	var cooldown_callback := Callable(
		self,
		"_on_independent_skill_host_global_cooldown_started"
	)
	if not independent_skill_host.global_cooldown_started.is_connected(cooldown_callback):
		independent_skill_host.global_cooldown_started.connect(cooldown_callback)
	# 每个继承职业仍通过 AllyBase 的现有 Inspector 字段覆盖公共冷却时长；
	# Host 接收该值后成为新技能路径的权威计时器，迁移观察期继续镜像旧计时器。
	independent_skill_host.global_cooldown_duration = max(basic_attack_global_cooldown, 0.0)
	independent_skill_host.configure_owner(self, get_tree().current_scene)


## 解析父场景装配的请求桥。路径无效时保持新自动技能关闭，不影响旧调度、普攻或移动。
func _resolve_skill_request_bridge() -> void:
	skill_request_bridge = get_node_or_null(
		skill_request_bridge_path
	) as AllySkillRequestBridgeType
	if not is_instance_valid(skill_request_bridge):
		return


## 每帧只把当前战斗事实写入桥接器，不在 AllyBase 中选择具体技能或友方目标。
func _update_skill_request_bridge_context() -> void:
	if not is_instance_valid(skill_request_bridge):
		return
	skill_request_bridge.set_combat_context(
		activity_mode == ActivityMode.COMBAT,
		current_visible_enemy if is_instance_valid(current_visible_enemy) else null
	)


## 消费新 Host 的移动意图，并返回本帧是否已取得水平移动所有权。
## 朝向可以独立更新；接近和施法锁定互斥，且都只修改 X/Z，不接管重力速度。
func _process_independent_skill_intent(delta: float) -> bool:
	if (
		not is_instance_valid(skill_request_bridge)
		or not skill_request_bridge.is_requesting_enabled()
	):
		return false

	var facing_target: Node3D = skill_request_bridge.get_facing_target()
	if is_instance_valid(facing_target):
		var facing_direction: Vector3 = facing_target.global_position - global_position
		facing_direction.y = 0.0
		if facing_direction.length_squared() > 0.0001:
			desired_facing_direction = facing_direction.normalized()

	if skill_request_bridge.is_movement_locked():
		_stop_horizontal_movement(delta)
		return true

	if not skill_request_bridge.has_approach_request():
		return false
	var target: Node3D = skill_request_bridge.get_approach_target()
	if not is_instance_valid(target):
		return false
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	var cast_range: float = skill_request_bridge.get_approach_range()
	var cast_limit: float = cast_range + skill_request_bridge.get_approach_tolerance()
	if distance > cast_limit and distance > 0.0001:
		var direction: Vector3 = offset / distance
		movement_target = _constrain_target(target.global_position - direction * cast_range)
		_move_toward_target(movement_target, delta, movement_speed)
	else:
		# Host 将在下一次状态推进时正式开始施法；本帧先保持位置，避免编队或
		# 战斗游荡把角色从刚刚满足的施法边界重新拉走。
		_stop_horizontal_movement(delta)
	return true


## 新 Host 启动公共冷却时，只延长旧兼容计时器，不反向调用 Host，避免信号递归。
func _on_independent_skill_host_global_cooldown_started(duration: float) -> void:
	basic_attack_global_cooldown_remaining = max(
		basic_attack_global_cooldown_remaining,
		max(duration, 0.0)
	)


## 旧普攻或旧技能成功开始时，把同一次公共冷却事件同步给新 Host。
func _start_independent_skill_host_global_cooldown(duration: float) -> void:
	if not is_instance_valid(independent_skill_host):
		return
	independent_skill_host.start_global_cooldown(max(duration, 0.0))


## 每帧只同步既有动作是否正在占用施法时机，不接管移动、朝向或目标选择。
func _update_independent_skill_host_action_block() -> void:
	if not is_instance_valid(independent_skill_host):
		return
	var normal_attack_active: bool = (
		is_instance_valid(attack_module)
		and attack_module.is_attacking()
	)
	var legacy_skill_active: bool = (
		is_instance_valid(active_skill_module)
		and active_skill_module.is_casting()
	)
	independent_skill_host.set_cast_blocked(
		normal_attack_active or legacy_skill_active
	)


## 只有新系统真正进入 CASTING 才阻止旧动作开始；排队和决策等待不会影响旧行为。
func _is_independent_skill_casting() -> bool:
	if not is_instance_valid(independent_skill_host):
		return false
	var active_independent_skill: Node3D = (
		independent_skill_host.get_active_skill() as Node3D
	)
	return (
		is_instance_valid(active_independent_skill)
		and bool(active_independent_skill.call("is_casting"))
	)


## 按 Inspector 路径解析初始技能模块；空路径或类型不匹配时保持无技能状态。
func _resolve_skill_module_from_path() -> void:
	if skill_module_path.is_empty():
		set_skill_module(null)
		return
	set_skill_module(get_node_or_null(skill_module_path) as SkillModuleBaseType)


## 启动时仅检查技能插槽的直接子节点。路径无效时安全跳过，运行时仍可通过
## register_skill_module() 显式挂载模块。
func _discover_skill_modules_from_socket() -> void:
	var socket: Node3D = get_node_or_null(skill_module_socket_path) as Node3D
	if not is_instance_valid(socket):
		return
	for child: Node in socket.get_children():
		var module: SkillModuleBaseType = child as SkillModuleBaseType
		if is_instance_valid(module):
			register_skill_module(module)


## 注册通用技能并注入宿主。重复实例被明确拒绝，保证信号不会重复连接，
## 同时允许运行时在 _ready() 之后添加新模块。
func register_skill_module(module: SkillModuleBaseType) -> bool:
	if not is_instance_valid(module) or registered_skill_modules.has(module):
		return false
	registered_skill_modules.append(module)
	_connect_skill_module_signals(module)
	module.configure_skill_owner(self)
	return true


## 卸载模块时只清理该模块自身的请求、连接与宿主引用。若它占用活动槽则先
## 取消并释放；公共战斗冷却属于单位历史状态，任何清理路径都不得重置它。
func unregister_skill_module(module: SkillModuleBaseType) -> bool:
	if not is_instance_valid(module) or not registered_skill_modules.has(module):
		return false
	if active_skill_module == module:
		active_skill_module = null
	module.cancel_skill()
	_disconnect_skill_module_signals(module)
	module.reset_module()
	module.configure_skill_owner(null)
	registered_skill_modules.erase(module)
	if skill_module == module:
		skill_module = null
	return true


## 返回注册表快照，防止调用方在遍历时直接修改宿主内部数组。
func get_registered_skill_modules() -> Array[SkillModuleBaseType]:
	return registered_skill_modules.duplicate()


func get_active_skill_module() -> SkillModuleBaseType:
	return active_skill_module if is_instance_valid(active_skill_module) else null


## 装配、替换或卸下通用技能模块。
## 依赖方向保持为 AllyBase 调用 SkillModuleBase；技能模块不会读取当前宿主的字段。
func set_skill_module(module: SkillModuleBaseType) -> void:
	if skill_module == module:
		return

	if is_instance_valid(skill_module):
		unregister_skill_module(skill_module)

	skill_module = module
	if not is_instance_valid(skill_module):
		return

	register_skill_module(skill_module)


## 返回当前装配的技能模块；未装配时返回 null。
func get_skill_module() -> SkillModuleBaseType:
	return skill_module if is_instance_valid(skill_module) else null


## 将目标请求转发给已装配技能；不负责自动选目标或决定释放时机。
func request_equipped_skill(
	target: Node3D,
	target_position: Vector3 = Vector3.INF
) -> bool:
	if not is_instance_valid(skill_module):
		return false
	if is_instance_valid(active_skill_module) and active_skill_module != skill_module:
		return false
	if not skill_module.request_skill(target, target_position):
		return false
	active_skill_module = skill_module
	return true


## 在公共冷却结束且当前普攻没有占用动作时，允许已排队技能正式开始施法。
## 成功开始后，cast_started 信号会同步启动当前单位的公共冷却。
func begin_equipped_skill_cast() -> bool:
	if not is_instance_valid(skill_module):
		return false
	if _is_independent_skill_casting():
		return false
	if is_instance_valid(active_skill_module) and active_skill_module != skill_module:
		return false
	if basic_attack_global_cooldown_remaining > 0.0:
		return false
	if is_instance_valid(attack_module) and attack_module.is_attacking():
		return false
	var claimed_active_slot: bool = not is_instance_valid(active_skill_module)
	if claimed_active_slot:
		active_skill_module = skill_module
	if skill_module.begin_cast():
		return true
	if claimed_active_slot and active_skill_module == skill_module:
		active_skill_module = null
	return false


## 取消当前技能请求；技能模块已经开始的专属冷却由模块自身保留。
func cancel_equipped_skill() -> void:
	if is_instance_valid(skill_module):
		skill_module.cancel_skill()
		if active_skill_module == skill_module:
			active_skill_module = null


## 从候选集中选择最高 AI 优先级。并列最高时只使用 AllyBase 自身的随机源，
## 便于测试固定种子，也确保同一单位的选择节奏保持统一。
func select_skill_module(
	available_modules: Array[SkillModuleBaseType]
) -> SkillModuleBaseType:
	if available_modules.is_empty():
		return null
	var highest_priority: int = -2147483648
	var highest_modules: Array[SkillModuleBaseType] = []
	for module: SkillModuleBaseType in available_modules:
		if not is_instance_valid(module):
			continue
		var priority: int = module.get_ai_priority()
		if priority > highest_priority:
			highest_priority = priority
			highest_modules.assign([module])
		elif priority == highest_priority:
			highest_modules.append(module)
	if highest_modules.is_empty():
		return null
	return highest_modules[random_generator.randi_range(0, highest_modules.size() - 1)]


## 父类只提供不会引入职业知识的默认选目标规则。ALLY 被明确保留给治疗者等
## 子类覆盖，枚举比较来自 SkillProfile 类型而非脆弱的整数常量。
func select_target_for_skill(module: SkillModuleBaseType) -> Node3D:
	if not is_instance_valid(module):
		return null
	match module.get_target_faction():
		SkillProfileType.SkillTargetFaction.ENEMY:
			if is_instance_valid(current_visible_enemy) and current_visible_enemy.is_inside_tree():
				return current_visible_enemy
		SkillProfileType.SkillTargetFaction.SELF:
			return self
		SkillProfileType.SkillTargetFaction.ALLY:
			return null
	return null


## 推进唯一活动技能的通用状态机，并返回本帧是否独占水平移动。DECISION_WAIT
## 故意返回 false；QUEUED 接近时独占移动；CASTING 则由配置决定是否允许原有
## 战斗移动继续参与。
func _process_skill_scheduler(delta: float) -> bool:
	if (
		not legacy_skill_scheduler_enabled
		or (
			is_instance_valid(skill_request_bridge)
			and skill_request_bridge.is_requesting_enabled()
		)
		or activity_mode != ActivityMode.COMBAT
		or registered_skill_modules.is_empty()
	):
		return false

	if is_instance_valid(active_skill_module):
		var active_target: Node3D = active_skill_module.get_current_target()
		if not is_instance_valid(active_target) or not active_target.is_inside_tree():
			_cancel_and_release_active_skill()
			return false
	else:
		active_skill_module = null
		var available: Array[SkillModuleBaseType] = []
		var targets: Dictionary = {}
		for module: SkillModuleBaseType in registered_skill_modules:
			if not is_instance_valid(module) or not module.can_request_skill():
				continue
			var target: Node3D = select_target_for_skill(module)
			if not is_instance_valid(target) or not target.is_inside_tree():
				continue
			available.append(module)
			targets[module] = target
		var selected: SkillModuleBaseType = select_skill_module(available)
		if not is_instance_valid(selected):
			return false
		if not selected.request_skill(targets[selected] as Node3D):
			return false
		active_skill_module = selected

	var state: int = int(active_skill_module.get_skill_state())
	match state:
		SkillModuleBaseType.SkillState.DECISION_WAIT:
			return false
		SkillModuleBaseType.SkillState.QUEUED:
			return _process_queued_skill(delta)
		SkillModuleBaseType.SkillState.CASTING:
			_face_active_skill_target()
			if active_skill_module.can_move_during_cast():
				return false
			_stop_horizontal_movement(delta)
			return true
		_:
			# READY/COOLDOWN 表示请求已在模块内部结束；宿主只释放活动槽，
			# 不干预模块本地冷却计时。
			active_skill_module = null
			return false


## QUEUED 阶段使用水平距离计算施法半径上的约束位置。只有真正接近或成功
## begin_cast() 才占用移动；公共冷却和正在播放的普攻只阻止开施法。
func _process_queued_skill(delta: float) -> bool:
	var target: Node3D = active_skill_module.get_current_target()
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	var cast_limit: float = (
		active_skill_module.get_cast_range()
		+ active_skill_module.get_cast_range_tolerance()
	)
	if distance > cast_limit:
		var direction: Vector3 = offset / distance
		movement_target = _constrain_target(
			target.global_position - direction * active_skill_module.get_cast_range()
		)
		_move_toward_target(movement_target, delta, movement_speed)
		return true
	if basic_attack_global_cooldown_remaining > 0.0:
		return false
	if is_instance_valid(attack_module) and attack_module.is_attacking():
		return false
	if _is_independent_skill_casting():
		return false
	_face_active_skill_target()
	if active_skill_module.begin_cast():
		_stop_horizontal_movement(delta)
		return true
	return false


func _face_active_skill_target() -> void:
	if not is_instance_valid(active_skill_module):
		return
	var target: Node3D = active_skill_module.get_current_target()
	if not is_instance_valid(target):
		return
	var direction: Vector3 = target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		desired_facing_direction = direction.normalized()


func _cancel_and_release_active_skill() -> void:
	if is_instance_valid(active_skill_module):
		active_skill_module.cancel_skill()
	active_skill_module = null


## 连接技能父模块的公共信号；不连接或假设任何具体职业子类信号。
func _connect_skill_module_signals(module: SkillModuleBaseType) -> void:
	var bindings: Array[Array] = [
		[module.skill_queued, Callable(self, "_on_equipped_skill_queued").bind(module)],
		[module.cast_range_required, Callable(self, "_on_equipped_skill_range_required").bind(module)],
		[module.cast_started, Callable(self, "_on_equipped_skill_cast_started").bind(module)],
		[module.skill_delivered, Callable(self, "_on_equipped_skill_delivered").bind(module)],
		[module.cast_failed, Callable(self, "_on_equipped_skill_cast_failed").bind(module)],
		[module.cast_cancelled, Callable(self, "_on_equipped_skill_cast_cancelled").bind(module)],
	]
	for binding: Array in bindings:
		var source_signal: Signal = binding[0] as Signal
		var callback: Callable = binding[1] as Callable
		if not source_signal.is_connected(callback):
			source_signal.connect(callback)


## 卸装前断开所有技能信号，防止旧模块继续控制当前宿主的公共冷却或转发事件。
func _disconnect_skill_module_signals(module: SkillModuleBaseType) -> void:
	var bindings: Array[Array] = [
		[module.skill_queued, Callable(self, "_on_equipped_skill_queued").bind(module)],
		[module.cast_range_required, Callable(self, "_on_equipped_skill_range_required").bind(module)],
		[module.cast_started, Callable(self, "_on_equipped_skill_cast_started").bind(module)],
		[module.skill_delivered, Callable(self, "_on_equipped_skill_delivered").bind(module)],
		[module.cast_failed, Callable(self, "_on_equipped_skill_cast_failed").bind(module)],
		[module.cast_cancelled, Callable(self, "_on_equipped_skill_cast_cancelled").bind(module)],
	]
	for binding: Array in bindings:
		var source_signal: Signal = binding[0] as Signal
		var callback: Callable = binding[1] as Callable
		if source_signal.is_connected(callback):
			source_signal.disconnect(callback)


func _on_equipped_skill_queued(target: Node3D, _module: SkillModuleBaseType) -> void:
	equipped_skill_queued.emit(target)


func _on_equipped_skill_range_required(
	target: Node3D,
	cast_range: float,
	tolerance: float,
	_module: SkillModuleBaseType
) -> void:
	equipped_skill_range_required.emit(target, cast_range, tolerance)


## 公共冷却在技能正式开始施法时立即计时，和现有普攻发动时的语义一致。
func _on_equipped_skill_cast_started(target: Node3D, _module: SkillModuleBaseType) -> void:
	basic_attack_global_cooldown_remaining = max(basic_attack_global_cooldown, 0.0)
	_start_independent_skill_host_global_cooldown(basic_attack_global_cooldown)
	_update_independent_skill_host_action_block()
	equipped_skill_cast_started.emit(target)


func _on_equipped_skill_delivered(
	target: Node3D,
	target_position: Vector3,
	module: SkillModuleBaseType
) -> void:
	if active_skill_module == module:
		active_skill_module = null
	equipped_skill_delivered.emit(target, target_position)


func _on_equipped_skill_cast_failed(
	target: Node3D,
	reason: StringName,
	module: SkillModuleBaseType
) -> void:
	equipped_skill_cast_failed.emit(target, reason)
	# 射程外失败会由模块回到同目标决策等待，仍占用活动槽以避免另一技能插队。
	if active_skill_module == module and reason != &"out_of_range":
		active_skill_module = null


func _on_equipped_skill_cast_cancelled(
	target: Node3D,
	module: SkillModuleBaseType
) -> void:
	equipped_skill_cast_cancelled.emit(target)
	if active_skill_module == module:
		active_skill_module = null


## 读取玩家可靠的水平移动方向。
## 玩家有速度时使用实时速度；停止时读取玩家控制器保存的最后移动方向。
## 初始化球形敌人感知器，并将 Inspector 中的视野半径应用到独立的碰撞形状副本。
## 复制 Shape 资源可以避免不同职业覆盖 enemy_vision_range 时互相修改共享资源。
func _configure_enemy_detection() -> void:
	combat_sensor.monitoring = enemy_detection_enabled
	combat_sensor.monitorable = false

	if combat_sensor_shape.shape is SphereShape3D:
		var vision_shape: SphereShape3D = combat_sensor_shape.shape.duplicate() as SphereShape3D
		vision_shape.radius = enemy_vision_range
		combat_sensor_shape.shape = vision_shape

	var entered_callable: Callable = Callable(self, "_on_combat_sensor_body_entered")
	if not combat_sensor.body_entered.is_connected(entered_callable):
		combat_sensor.body_entered.connect(entered_callable)

	var exited_callable: Callable = Callable(self, "_on_combat_sensor_body_exited")
	if not combat_sensor.body_exited.is_connected(exited_callable):
		combat_sensor.body_exited.connect(exited_callable)

	_configure_vision_range_indicator()


## 根据感知半径创建一个水平 TorusMesh 细圆环，并配置不受光照影响的半透明材质。
## 圆环半径始终与 SphereShape3D 的水平截面半径一致，调整 enemy_vision_range 后无需手动缩放。
func _configure_vision_range_indicator() -> void:
	vision_range_indicator.visible = vision_indicator_enabled
	vision_range_indicator.position.y = vision_indicator_height
	vision_range_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not vision_indicator_enabled:
		return

	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = max(enemy_vision_range - vision_indicator_thickness, 0.001)
	ring_mesh.outer_radius = enemy_vision_range
	ring_mesh.rings = 96
	ring_mesh.ring_segments = 6
	vision_range_indicator.mesh = ring_mesh

	var ring_material: StandardMaterial3D = StandardMaterial3D.new()
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	vision_range_indicator.material_override = ring_material
	_update_vision_indicator_color()


## 根据当前是否存在可见敌人切换圆环颜色。
## 使用材质副本确保每个伙伴都能独立显示自己的感知状态。
func _update_vision_indicator_color() -> void:
	if not vision_indicator_enabled:
		return

	var ring_material: StandardMaterial3D = vision_range_indicator.material_override as StandardMaterial3D
	if ring_material == null:
		return

	ring_material.albedo_color = (
		vision_indicator_alert_color
		if is_instance_valid(current_visible_enemy)
		else vision_indicator_idle_color
	)


## 将进入 Enemy 物理层、并带有 enemy_targets 分组的 CharacterBody3D 加入候选列表。
## 同时检查物理层和分组，避免其他用途的 Enemy 层碰撞体被识别为攻击目标。
func _on_combat_sensor_body_entered(body: Node3D) -> void:
	if not enemy_detection_enabled or not body.is_in_group("enemy_targets"):
		return

	var enemy: CharacterBody3D = body as CharacterBody3D
	if enemy != null and not visible_enemies.has(enemy):
		visible_enemies.append(enemy)
		enemy_target_refresh_timer = 0.0


## 敌人离开球形视野时从候选列表移除，并请求立即刷新最近目标。
func _on_combat_sensor_body_exited(body: Node3D) -> void:
	var enemy: CharacterBody3D = body as CharacterBody3D
	if enemy == null:
		return

	visible_enemies.erase(enemy)
	enemy_target_refresh_timer = 0.0


## 按固定间隔清理失效候选并选择距离最近的敌人。
## 当前方法只更新感知结果，不接管现有编队移动。
func _update_enemy_detection(delta: float) -> void:
	if not enemy_detection_enabled:
		_set_current_visible_enemy(null)
		return
	if combat_search_cooldown_remaining > 0.0:
		return

	enemy_target_refresh_timer -= delta
	if enemy_target_refresh_timer > 0.0:
		return

	enemy_target_refresh_timer = enemy_target_refresh_interval
	var nearest_enemy: CharacterBody3D
	var nearest_distance_squared: float = INF

	for index: int in range(visible_enemies.size() - 1, -1, -1):
		var enemy: CharacterBody3D = visible_enemies[index]
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			visible_enemies.remove_at(index)
			continue
		if not _is_enemy_allowed_by_player_distance(enemy):
			continue

		var distance_squared: float = global_position.distance_squared_to(enemy.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_enemy = enemy

	if nearest_enemy != null and combat_reengage_guard_is_active:
		combat_reengage_guard_is_active = false
	_set_current_visible_enemy(nearest_enemy)


## 更新强制脱战冷却，并检查玩家是否已经明确远离当前战斗目标。
## 只有超过 12 米这类距离脱战才启用重新参战保护，普通目标消失不会触发。
func _update_combat_disengage(delta: float) -> void:
	combat_search_cooldown_remaining = max(
		combat_search_cooldown_remaining - delta,
		0.0
	)
	if activity_mode != ActivityMode.COMBAT:
		return
	if not is_instance_valid(player) or not is_instance_valid(current_visible_enemy):
		return

	var player_to_target: Vector3 = current_visible_enemy.global_position - player.global_position
	player_to_target.y = 0.0
	if player_to_target.length() <= maximum_player_target_distance:
		return

	combat_reengage_guard_is_active = true
	combat_search_cooldown_remaining = max(combat_disengage_search_cooldown, 0.0)
	_set_current_visible_enemy(null)


## 返回当前目标筛选使用的玩家距离上限。
## 正常状态使用 12 米；强制脱战保护期间改用 10 米，构成稳定的迟滞区。
func _get_player_target_selection_limit() -> float:
	var normal_limit: float = max(maximum_player_target_distance, 0.0)
	if not combat_reengage_guard_is_active:
		return normal_limit
	return min(max(player_target_reengage_distance, 0.0), normal_limit)


## 判断候选敌人是否位于玩家当前允许参与战斗的水平距离内。
func _is_enemy_allowed_by_player_distance(enemy: CharacterBody3D) -> bool:
	if not is_instance_valid(player) or not is_instance_valid(enemy):
		return false
	var player_to_enemy: Vector3 = enemy.global_position - player.global_position
	player_to_enemy.y = 0.0
	return player_to_enemy.length() <= _get_player_target_selection_limit()


## 统一更新当前可见敌人，并只在目标真正变化时发送信号。
func _set_current_visible_enemy(enemy: CharacterBody3D) -> void:
	if current_visible_enemy == enemy:
		return

	if is_instance_valid(attack_module) and attack_module.is_attacking():
		attack_module.cancel_attack()
	# ENEMY 技能绑定旧目标时，目标变化意味着原请求失效；SELF 等目标则由
	# 调度器自己的结构有效性检查继续处理。
	if (
		is_instance_valid(active_skill_module)
		and active_skill_module.get_target_faction()
			== SkillProfileType.SkillTargetFaction.ENEMY
		and active_skill_module.get_current_target() != enemy
	):
		_cancel_and_release_active_skill()
	basic_attack_state = BasicAttackState.GUARD
	current_visible_enemy = enemy
	combat_wander_target_is_valid = false
	if is_instance_valid(current_visible_enemy):
		_enter_combat_mode()
	else:
		_enter_formation_mode()
	_update_vision_indicator_color()
	visible_enemy_changed.emit(current_visible_enemy)


## 返回当前互斥活动模式：0 为玩家编队，1 为敌人战斗定位。
func get_activity_mode() -> int:
	return int(activity_mode)


## 进入战斗时清除尚未完成的编队冲刺与恢复，避免旧速度或目标继续影响战斗定位。
func _enter_combat_mode() -> void:
	if activity_mode == ActivityMode.COMBAT:
		return

	activity_mode = ActivityMode.COMBAT
	behavior_state = BehaviorState.WANDER
	basic_attack_state = BasicAttackState.GUARD
	dash_remaining_distance = 0.0
	dash_direction = Vector3.ZERO
	dash_target = Vector3.ZERO
	recovery_remaining = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	combat_wander_target_is_valid = false
	if is_instance_valid(navigation_agent):
		navigation_agent.target_position = global_position


## 目标消失后重新同步玩家朝向和编队中心，再生成普通游荡点。
## 此同步只在模式切换时执行一次，不会与战斗距离逻辑同帧竞争 movement_target。
func _enter_formation_mode() -> void:
	if activity_mode == ActivityMode.FORMATION:
		return

	activity_mode = ActivityMode.FORMATION
	_cancel_and_release_active_skill()
	behavior_state = BehaviorState.WANDER
	if is_instance_valid(attack_module) and attack_module.is_attacking():
		attack_module.cancel_attack()
	basic_attack_state = BasicAttackState.GUARD
	combat_wander_target_is_valid = false
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_instance_valid(player):
		return

	stable_player_direction = _read_player_direction()
	candidate_player_direction = stable_player_direction
	direction_confirmation_elapsed = 0.0
	raw_formation_center = _calculate_raw_formation_center(stable_player_direction)
	smoothed_formation_center = raw_formation_center
	wander_offset = _calculate_wander_offset_world()
	if is_instance_valid(navigation_agent):
		_select_new_wander_target()


## 根据当前水平距离返回距离带所需动作：1 接近、0 保持、-1 后退。
## 该方法只负责稳定的距离判定，方便职业逻辑和自动化测试复用。
func get_guard_distance_motion(current_distance: float) -> int:
	return _get_distance_motion(
		current_distance,
		combat_guard_distance,
		combat_guard_distance_tolerance
	)


## 使用统一迟滞规则判断当前位置相对于指定距离带需要接近、保持还是远离。
func _get_distance_motion(
	current_distance: float,
	desired_distance: float,
	distance_tolerance: float
) -> int:
	var safe_distance: float = max(desired_distance, 0.0)
	var safe_tolerance: float = clamp(distance_tolerance, 0.0, safe_distance)
	if current_distance > safe_distance + safe_tolerance:
		return 1
	if current_distance < safe_distance - safe_tolerance:
		return -1
	return 0


## 返回由普通移动速度与战斗游荡倍率共同决定的实际绕行速度。
func get_combat_wander_speed() -> float:
	return max(movement_speed * combat_wander_speed_multiplier, 0.0)


## 处理装备普通攻击模块后的接近、攻击、等待和可选回到警戒距离流程。
## 该方法是装备存在时 COMBAT 模式唯一的水平移动入口，避免警戒游荡与攻击接近竞争目标点。
func _process_basic_attack(delta: float) -> void:
	if not is_instance_valid(attack_module):
		_process_guard_distance(delta)
		return

	var attack_range: float = attack_module.get_attack_range()
	var attack_tolerance: float = attack_module.get_attack_range_tolerance()
	if attack_range <= 0.0:
		basic_attack_state = BasicAttackState.GUARD
		_process_guard_distance(delta)
		return

	var enemy_offset: Vector3 = current_visible_enemy.global_position - global_position
	enemy_offset.y = 0.0
	var current_distance: float = enemy_offset.length()
	var radial_direction: Vector3 = _get_radial_direction_from_enemy(enemy_offset)

	match basic_attack_state:
		BasicAttackState.GUARD:
			if basic_attack_global_cooldown_remaining <= 0.0 and attack_module.can_attack():
				basic_attack_state = BasicAttackState.APPROACH
				combat_wander_target_is_valid = false
				_process_basic_attack_approach(
					delta,
					enemy_offset,
					current_distance,
					attack_range,
					attack_tolerance
				)
			else:
				_process_guard_distance(delta)
		BasicAttackState.APPROACH:
			_process_basic_attack_approach(
				delta,
				enemy_offset,
				current_distance,
				attack_range,
				attack_tolerance
			)
		BasicAttackState.ATTACK:
			_stop_horizontal_movement(delta)
			if not attack_module.is_attacking():
				_finish_basic_attack_state()
		BasicAttackState.HOLD:
			if current_distance > attack_range + attack_tolerance:
				basic_attack_state = BasicAttackState.APPROACH
				combat_wander_target_is_valid = false
				_process_basic_attack_approach(
					delta,
					enemy_offset,
					current_distance,
					attack_range,
					attack_tolerance
				)
			elif basic_attack_global_cooldown_remaining <= 0.0 and attack_module.can_attack():
				_try_start_basic_attack(delta)
			else:
				_process_combat_wander(
					delta,
					radial_direction,
					attack_range,
					attack_tolerance
				)
		BasicAttackState.RETURN_TO_GUARD:
			_process_guard_distance(delta)
			if (
				get_guard_distance_motion(current_distance) == 0
				and basic_attack_global_cooldown_remaining <= 0.0
				and attack_module.can_attack()
			):
				basic_attack_state = BasicAttackState.APPROACH
				combat_wander_target_is_valid = false


## 使用武器 Profile 的距离和速度接近敌人；进入范围后尝试发动攻击。
func _process_basic_attack_approach(
	delta: float,
	enemy_offset: Vector3,
	current_distance: float,
	attack_range: float,
	attack_tolerance: float
) -> void:
	if current_distance <= attack_range + attack_tolerance:
		if basic_attack_global_cooldown_remaining <= 0.0:
			_try_start_basic_attack(delta)
		else:
			basic_attack_state = BasicAttackState.HOLD
		return

	if current_distance <= 0.0001:
		_stop_horizontal_movement(delta)
		return

	var direction_to_enemy: Vector3 = enemy_offset / current_distance
	var desired_position: Vector3 = (
		current_visible_enemy.global_position
		- direction_to_enemy * attack_range
	)
	movement_target = _constrain_target(desired_position)
	var approach_speed: float = (
		movement_speed * attack_module.get_approach_speed_multiplier()
	)
	_move_toward_target(movement_target, delta, approach_speed)


## 尝试发动一次普通攻击；仅成功请求才启动共享公共冷却。
func _try_start_basic_attack(delta: float) -> bool:
	if not is_instance_valid(attack_module):
		return false
	if _is_independent_skill_casting():
		return false
	if is_instance_valid(active_skill_module) and active_skill_module.is_casting():
		return false
	if basic_attack_global_cooldown_remaining > 0.0 or not attack_module.can_attack():
		return false
	if not attack_module.request_attack(current_visible_enemy):
		basic_attack_state = BasicAttackState.GUARD
		return false

	basic_attack_state = BasicAttackState.ATTACK
	basic_attack_global_cooldown_remaining = max(basic_attack_global_cooldown, 0.0)
	_start_independent_skill_host_global_cooldown(basic_attack_global_cooldown)
	_update_independent_skill_host_action_block()
	combat_wander_target_is_valid = false
	_stop_horizontal_movement(delta)
	return true


## 攻击动画结束后根据当前 Profile 选择留在近战范围或返回职业警戒距离。
func _on_attack_module_finished(_target: CharacterBody3D) -> void:
	_finish_basic_attack_state()


func _finish_basic_attack_state() -> void:
	if not is_instance_valid(attack_module):
		basic_attack_state = BasicAttackState.GUARD
		return
	basic_attack_state = (
		BasicAttackState.RETURN_TO_GUARD
		if attack_module.should_return_to_guard_after_attack()
		else BasicAttackState.HOLD
	)
	combat_wander_target_is_valid = false


## 攻击动画期间只平滑消除主动水平速度；重力、朝向和 move_and_slide 仍正常运行。
func _stop_horizontal_movement(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, movement_acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, movement_acceleration * delta)


## 没有攻击模块或攻击流程要求返回时，维持当前职业的战斗警戒距离。
func _process_guard_distance(delta: float) -> bool:
	if activity_mode != ActivityMode.COMBAT:
		return false
	if not is_instance_valid(current_visible_enemy) or not current_visible_enemy.is_inside_tree():
		return false

	var enemy_offset: Vector3 = current_visible_enemy.global_position - global_position
	enemy_offset.y = 0.0
	var current_distance: float = enemy_offset.length()
	if current_distance <= 0.0001:
		velocity.x = move_toward(velocity.x, 0.0, movement_acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, movement_acceleration * delta)
		return true

	var distance_motion: int = get_guard_distance_motion(current_distance)
	if distance_motion == 0:
		_process_combat_wander(
			delta,
			_get_radial_direction_from_enemy(enemy_offset),
			combat_guard_distance,
			combat_guard_distance_tolerance
		)
		return true

	# 无论接近还是后退，都选择当前目标同一径向上的理想距离点，避免突然绕到目标另一侧。
	var direction_to_enemy: Vector3 = enemy_offset / current_distance
	var desired_position: Vector3 = (
		current_visible_enemy.global_position
		- direction_to_enemy * combat_guard_distance
	)
	desired_position = _constrain_target(desired_position)
	movement_target = desired_position
	_move_toward_target(movement_target, delta, movement_speed)
	return true


## 将“伙伴指向敌人”的偏移转换为“敌人指向伙伴”的圆环径向，避免目标点生成到敌人另一侧。
func _get_radial_direction_from_enemy(enemy_offset: Vector3) -> Vector3:
	var radial_direction: Vector3 = -enemy_offset
	radial_direction.y = 0.0
	if radial_direction.length_squared() <= 0.0001:
		return Vector3.BACK
	return radial_direction.normalized()


## 在敌人周围的攻击距离圆环上更新轻微随机游荡。
## 计时、速度、加速度与普通游荡共享，仅目标点改为以敌人为圆心计算。
func _process_combat_wander(
	delta: float,
	current_radial_direction: Vector3,
	desired_radius: float,
	radius_tolerance: float
) -> void:
	if not combat_wander_target_is_valid:
		_select_new_combat_wander_target(
			current_radial_direction,
			desired_radius,
			radius_tolerance
		)
	else:
		_update_combat_wander_target_world()

	if _is_wander_target_refresh_due(delta):
		_select_new_combat_wander_target(
			current_radial_direction,
			desired_radius,
			radius_tolerance
		)

	_move_toward_target(movement_target, delta, get_combat_wander_speed())


## 为战斗游荡选择新的圆环点。
## 普通游荡的侧向半径在这里作为沿圆周移动的弧长尺度，前向半径作为受容差限制的径向扰动。
func _select_new_combat_wander_target(
	current_radial_direction: Vector3,
	desired_radius: float,
	radius_tolerance: float
) -> void:
	var previous_target: Vector3 = movement_target
	var radial_jitter_limit: float = min(wander_forward_radius, radius_tolerance)

	for attempt: int in range(8):
		var lateral_arc_offset: float = random_generator.randf_range(
			-wander_lateral_radius,
			wander_lateral_radius
		)
		var radial_offset: float = random_generator.randf_range(
			-radial_jitter_limit,
			radial_jitter_limit
		)
		var candidate: Vector3 = _calculate_combat_wander_position(
			current_visible_enemy.global_position,
			current_radial_direction,
			lateral_arc_offset,
			radial_offset,
			desired_radius,
			radius_tolerance
		)
		if candidate.distance_to(previous_target) >= minimum_target_change_distance or attempt == 7:
			var candidate_offset: Vector3 = candidate - current_visible_enemy.global_position
			candidate_offset.y = 0.0
			combat_wander_radius = candidate_offset.length()
			combat_wander_direction = candidate_offset.normalized()
			movement_target = _constrain_target(candidate)
			break

	combat_wander_target_is_valid = true
	_reset_wander_timer()


## 将普通游荡的米制侧向参数转换为圆周角度，并生成保持攻击半径的世界坐标。
## lateral_arc_offset 表示沿圆周的近似弧长，radial_offset 表示攻击距离内的轻微径向变化。
func _calculate_combat_wander_position(
	enemy_position: Vector3,
	radial_direction: Vector3,
	lateral_arc_offset: float,
	radial_offset: float,
	desired_radius: float,
	radius_tolerance: float
) -> Vector3:
	var safe_radial: Vector3 = radial_direction
	safe_radial.y = 0.0
	if safe_radial.length_squared() <= 0.0001:
		safe_radial = Vector3.BACK
	safe_radial = safe_radial.normalized()

	var tangent: Vector3 = Vector3(-safe_radial.z, 0.0, safe_radial.x)
	var offset_direction: Vector3 = (
		safe_radial * max(desired_radius, 0.001)
		+ tangent * lateral_arc_offset
	).normalized()
	var minimum_radius: float = max(desired_radius - radius_tolerance, 0.001)
	var maximum_radius: float = max(desired_radius + radius_tolerance, minimum_radius)
	var target_radius: float = clamp(
		desired_radius + radial_offset,
		minimum_radius,
		maximum_radius
	)
	return enemy_position + offset_direction * target_radius


## 敌人移动后保持战斗游荡点相对敌人的方向和半径，不让目标点遗留在旧世界位置。
func _update_combat_wander_target_world() -> void:
	if not combat_wander_target_is_valid or not is_instance_valid(current_visible_enemy):
		return
	movement_target = _constrain_target(
		current_visible_enemy.global_position
		+ combat_wander_direction * combat_wander_radius
	)


func _read_player_direction() -> Vector3:
	# 编队首先采用玩家视觉模型的世界正前方，因此锁定敌人或原地转向时，阵型也会随角色正面旋转。
	if is_instance_valid(player_facing_node):
		var visual_forward: Vector3 = -player_facing_node.global_basis.z
		visual_forward.y = 0.0
		if visual_forward.length_squared() > 0.0001:
			return visual_forward.normalized()

	# 视觉节点缺失时才使用实际速度与最后按键方向作为兼容兜底。
	var horizontal_velocity: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if horizontal_velocity.length_squared() > 0.01:
		return horizontal_velocity.normalized()

	var saved_direction: Variant = player.get("last_movement_direction")
	if saved_direction is Vector3 and (saved_direction as Vector3).length_squared() > 0.01:
		var direction: Vector3 = saved_direction
		direction.y = 0.0
		return direction.normalized()

	return stable_player_direction


## 对玩家方向变化进行短时间确认，并在显著转向时请求冲刺。
func _update_player_direction(delta: float) -> void:
	var observed_direction: Vector3 = _read_player_direction()

	if candidate_player_direction.angle_to(observed_direction) > deg_to_rad(5.0):
		candidate_player_direction = observed_direction
		direction_confirmation_elapsed = 0.0
	else:
		direction_confirmation_elapsed += delta

	if direction_confirmation_elapsed < direction_confirmation_time:
		return

	var turn_angle: float = rad_to_deg(stable_player_direction.angle_to(candidate_player_direction))
	if turn_angle < 1.0:
		return

	stable_player_direction = candidate_player_direction
	direction_confirmation_elapsed = 0.0

	# 明显转向且新编队区域距离较远时，立即冲刺到玩家新的前方区域。
	if turn_angle >= dash_turn_angle_threshold and dash_cooldown_remaining <= 0.0 and behavior_state != BehaviorState.DASH:
		var new_center: Vector3 = _calculate_raw_formation_center(stable_player_direction)
		if global_position.distance_to(new_center) >= dash_trigger_distance:
			_start_dash(new_center + wander_offset)



## 计算并平滑更新玩家前方编队中心。
func _update_formation_center(delta: float) -> void:
	raw_formation_center = _calculate_raw_formation_center(stable_player_direction)
	var weight: float = 1.0 - exp(-formation_smoothness * delta)
	smoothed_formation_center = smoothed_formation_center.lerp(raw_formation_center, weight)

	# 每个物理帧使用玩家当前方向把局部游走坐标转换为世界偏移。
	# 玩家转向后，已锁定的左侧或右侧会随编队坐标系一起旋转，不会遗留旧世界方向。
	wander_offset = _calculate_wander_offset_world()


## 根据玩家位置和稳定前进方向计算未平滑的战术编队中心。
func _calculate_raw_formation_center(direction: Vector3) -> Vector3:
	return player.global_position + direction * front_distance


## 根据距离和当前状态决定游走、返回或紧急冲刺。
func _update_behavior_state() -> void:
	if behavior_state == BehaviorState.DASH or behavior_state == BehaviorState.RECOVER:
		return

	var player_distance: float = global_position.distance_to(player.global_position)
	var formation_error: float = global_position.distance_to(raw_formation_center)
	var player_horizontal_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var can_retry_dash: bool = (
		dash_cooldown_remaining <= 0.0
		and player_horizontal_speed >= dash_retry_player_speed_threshold
		and formation_error >= dash_retry_distance
	)

	if player_distance >= emergency_dash_distance and dash_cooldown_remaining <= 0.0:
		_start_dash(raw_formation_center + wander_offset)
	elif can_retry_dash:
		# 玩家持续移动时以实时编队中心为主要目标，不等待方向再次变化。
		# 每次冲刺仍受最大距离和冷却约束，因此会分段、平滑地追上玩家。
		_start_dash(raw_formation_center + wander_offset)
	elif player_distance >= maximum_player_distance:
		behavior_state = BehaviorState.REPOSITION
	else:
		behavior_state = BehaviorState.WANDER


## 在玩家前方活动区域内更新随机游走目标并进行平滑移动。
func _process_wander(delta: float) -> void:
	if _is_wander_target_refresh_due(delta):
		_select_new_wander_target()

	movement_target = _constrain_target(smoothed_formation_center + wander_offset)
	_move_toward_target(movement_target, delta, movement_speed)


## 普通游荡与战斗游荡共享的换点条件：计时结束且已接近当前目标点。
func _is_wander_target_refresh_due(delta: float) -> bool:
	wander_timer -= delta
	return (
		wander_timer <= 0.0
		and global_position.distance_to(movement_target) <= slowing_distance
	)


## 普通游荡与战斗游荡共享相同的随机刷新间隔。
func _reset_wander_timer() -> void:
	wander_timer = random_generator.randf_range(
		min(wander_interval_min, wander_interval_max),
		max(wander_interval_min, wander_interval_max)
	)


## Guardian 落后时直接返回编队中心，不再等待随机游走计时。
func _process_reposition(delta: float) -> void:
	movement_target = _constrain_target(smoothed_formation_center + wander_offset)
	_move_toward_target(movement_target, delta, movement_speed)

	if global_position.distance_to(player.global_position) < maximum_player_distance * 0.8:
		behavior_state = BehaviorState.WANDER
		_select_new_wander_target()


## 根据侧向模式初始化当前角色的锁定侧。
func _initialize_formation_side() -> void:
	match formation_side_mode:
		FormationSideMode.LOCKED_RANDOM_SIDE:
			_apply_locked_side(_choose_locked_side(), false)
		FormationSideMode.FIXED_LEFT:
			_apply_locked_side(-1, false)
		FormationSideMode.FIXED_RIGHT:
			_apply_locked_side(1, false)
		_:
			_apply_locked_side(0, false)

	has_entered_locked_region = false
	outside_locked_region_elapsed = 0.0


## 将保存的玩家局部游走坐标转换为世界空间偏移。
func _calculate_wander_offset_world() -> Vector3:
	var player_right: Vector3 = Vector3(
		-stable_player_direction.z,
		0.0,
		stable_player_direction.x
	)
	return (
		player_right * wander_lateral_value
		+ stable_player_direction * wander_longitudinal_value
	)


## 检测随机锁定角色是否进入或离开当前选定的单侧编队区域。
## 只有进入区域后又持续离开外层缓冲边界，才会重新随机选择左右侧。
func _update_formation_side_lock(delta: float) -> void:
	if formation_side_mode != FormationSideMode.LOCKED_RANDOM_SIDE:
		return

	var player_right: Vector3 = Vector3(
		-stable_player_direction.z,
		0.0,
		stable_player_direction.x
	)
	var relative_position: Vector3 = global_position - player.global_position
	relative_position.y = 0.0

	var lateral_position: float = relative_position.dot(player_right)
	var longitudinal_position: float = relative_position.dot(stable_player_direction)
	var signed_lateral_position: float = lateral_position * float(locked_side)
	var minimum_lateral: float = min(wander_lateral_minimum, wander_lateral_radius)

	var inside_inner_region: bool = (
		signed_lateral_position >= minimum_lateral
		and signed_lateral_position <= wander_lateral_radius
		and abs(longitudinal_position - front_distance) <= wander_forward_radius
	)

	if inside_inner_region:
		has_entered_locked_region = true
		outside_locked_region_elapsed = 0.0
		return

	if not has_entered_locked_region:
		return

	var inside_outer_region: bool = (
		signed_lateral_position >= max(minimum_lateral - formation_exit_margin, 0.0)
		and signed_lateral_position <= wander_lateral_radius + formation_exit_margin
		and abs(longitudinal_position - front_distance)
			<= wander_forward_radius + formation_exit_margin
	)

	if inside_outer_region:
		outside_locked_region_elapsed = 0.0
		return

	outside_locked_region_elapsed += delta
	if outside_locked_region_elapsed < side_reselection_delay:
		return

	# 确认离开后重新抽取侧向。新结果可以与原侧相同，也可以切换到另一侧。
	_apply_locked_side(_choose_locked_side(), true)


## 返回角色在需要锁定编队侧向时应当选择的方向。
## -1 表示玩家左侧，1 表示玩家右侧；父类默认保持随机选择。
## 子职业可以覆写此方法实现职业间的编队协调，而无需复制整套游荡和重选区域算法。
func _choose_locked_side() -> int:
	return -1 if random_generator.randf() < 0.5 else 1


## 统一应用新的锁定侧，并同步维护与选侧相关的内部状态。
## refresh_target 为 true 时会立即在新侧生成游荡目标；初始化阶段传入 false，随后由 _ready 统一生成目标。
## 所有主动选侧端与跟随选侧端都通过此入口修改状态，避免各自遗漏计时器或目标刷新。
func _apply_locked_side(new_side: int, refresh_target: bool = true) -> void:
	var normalized_side: int = clampi(new_side, -1, 1)
	var side_was_changed: bool = locked_side != normalized_side

	locked_side = normalized_side
	has_entered_locked_region = false
	outside_locked_region_elapsed = 0.0

	if refresh_target and is_instance_valid(player) and is_instance_valid(navigation_agent):
		_select_new_wander_target()

	if side_was_changed:
		formation_side_changed.emit(locked_side)


## 从当前模式允许的编队区域中选择一个新的随机局部偏移。
func _select_new_wander_target() -> void:
	var previous_offset: Vector3 = wander_offset
	var selected_lateral: float = wander_lateral_value
	var selected_longitudinal: float = wander_longitudinal_value
	var minimum_lateral: float = min(wander_lateral_minimum, wander_lateral_radius)

	for attempt: int in range(8):
		var candidate_lateral: float
		var candidate_longitudinal: float

		if formation_side_mode == FormationSideMode.FREE_CROSSING:
			# 自由模式保留原有椭圆采样，可作为 Guardian 常规行为或特殊彩蛋逻辑。
			var angle: float = random_generator.randf_range(0.0, TAU)
			var radius: float = sqrt(random_generator.randf())
			candidate_lateral = cos(angle) * radius * wander_lateral_radius
			candidate_longitudinal = sin(angle) * radius * wander_forward_radius

			if minimum_lateral > 0.0 and abs(candidate_lateral) < minimum_lateral:
				var free_side: float = -1.0 if candidate_lateral < 0.0 else 1.0
				if abs(candidate_lateral) < 0.001:
					free_side = -1.0 if random_generator.randf() < 0.5 else 1.0
				candidate_lateral = free_side * minimum_lateral
		else:
			# 锁定或固定模式只在当前选定的一侧生成目标，绝不会跨越中心线。
			if locked_side == 0:
				_initialize_formation_side()
			var lateral_magnitude: float = random_generator.randf_range(
				minimum_lateral,
				wander_lateral_radius
			)
			candidate_lateral = lateral_magnitude * float(locked_side)
			candidate_longitudinal = random_generator.randf_range(
				-wander_forward_radius,
				wander_forward_radius
			)

		var player_right: Vector3 = Vector3(
			-stable_player_direction.z,
			0.0,
			stable_player_direction.x
		)
		var candidate_offset: Vector3 = (
			player_right * candidate_lateral
			+ stable_player_direction * candidate_longitudinal
		)

		if candidate_offset.distance_to(previous_offset) >= minimum_target_change_distance or attempt == 7:
			selected_lateral = candidate_lateral
			selected_longitudinal = candidate_longitudinal
			break

	wander_lateral_value = selected_lateral
	wander_longitudinal_value = selected_longitudinal
	wander_offset = _calculate_wander_offset_world()
	movement_target = _constrain_target(smoothed_formation_center + wander_offset)
	_reset_wander_timer()
	navigation_agent.target_position = movement_target


## 将活动目标约束在玩家当前地面高度。
## 不再施加友方最小距离限制，玩家与 Guardian 可以自由穿过或短暂重叠。
func _constrain_target(target_position: Vector3) -> Vector3:
	target_position.y = player.global_position.y
	return target_position


## 使用 NavigationAgent3D 的下一个路径点生成平滑速度。
## 当前导航地图尚未同步或路径结束时，会安全回退为直接朝目标移动。
func _move_toward_target(target_position: Vector3, delta: float, maximum_speed: float) -> void:
	navigation_agent.target_position = target_position
	var next_position: Vector3 = target_position
	if not navigation_agent.is_navigation_finished():
		next_position = navigation_agent.get_next_path_position()

	# 导航服务器尚未同步、导航网格为空或角色位于网格外时，下一路径点可能等于当前位置。
	# 此时回退为直接平面移动，保证开放测试场景中 AI 仍能自然工作；有效路径出现后会自动优先使用导航结果。
	if next_position.distance_to(global_position) <= arrival_distance and target_position.distance_to(global_position) > arrival_distance:
		next_position = target_position

	var offset: Vector3 = next_position - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	var desired_velocity: Vector3 = Vector3.ZERO

	if distance > arrival_distance:
		var speed_factor: float = clamp(distance / slowing_distance, 0.0, 1.0)
		desired_velocity = offset.normalized() * maximum_speed * speed_factor
		desired_facing_direction = offset.normalized()

	velocity.x = move_toward(velocity.x, desired_velocity.x, movement_acceleration * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, movement_acceleration * delta)


## 开始一次面向新编队区域的位置纠正冲刺。
func _start_dash(target_position: Vector3) -> void:
	var offset: Vector3 = target_position - global_position
	offset.y = 0.0
	if offset.length_squared() <= 0.01:
		return

	behavior_state = BehaviorState.DASH
	dash_target = target_position
	dash_direction = offset.normalized()
	dash_remaining_distance = min(dash_max_distance, offset.length())
	desired_facing_direction = dash_direction


## 平滑加速执行冲刺，并根据目标距离和最大距离结束。
func _process_dash(delta: float) -> void:
	var target_offset: Vector3 = dash_target - global_position
	target_offset.y = 0.0

	if target_offset.length() <= dash_arrival_distance or dash_remaining_distance <= 0.01:
		_finish_dash()
		return

	var speed_for_frame: float = min(dash_speed, dash_remaining_distance / max(delta, 0.000001))
	velocity.x = move_toward(velocity.x, dash_direction.x * speed_for_frame, dash_acceleration * delta)
	velocity.z = move_toward(velocity.z, dash_direction.z * speed_for_frame, dash_acceleration * delta)
	dash_remaining_distance = max(dash_remaining_distance - Vector2(velocity.x, velocity.z).length() * delta, 0.0)


## 结束冲刺并进入短暂恢复状态。
func _finish_dash() -> void:
	behavior_state = BehaviorState.RECOVER
	recovery_remaining = dash_recovery_duration
	dash_cooldown_remaining = dash_cooldown
	dash_remaining_distance = 0.0
	dash_direction = Vector3.ZERO


## 冲刺后平滑减速，避免从高速瞬间切换为普通游走速度。
func _process_recovery(delta: float) -> void:
	recovery_remaining = max(recovery_remaining - delta, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, movement_acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, movement_acceleration * delta)

	if recovery_remaining <= 0.0:
		behavior_state = BehaviorState.WANDER
		_select_new_wander_target()


## 更新低速状态下重新对齐玩家前进方向的随机计时。
func _update_facing_timer(delta: float) -> void:
	facing_timer -= delta
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()

	if horizontal_speed > movement_facing_speed_threshold:
		desired_facing_direction = Vector3(velocity.x, 0.0, velocity.z).normalized()
	elif facing_timer <= 0.0:
		desired_facing_direction = stable_player_direction
		facing_timer = random_generator.randf_range(
			min(facing_update_interval_min, facing_update_interval_max),
			max(facing_update_interval_min, facing_update_interval_max)
		)


## 当感知范围内存在有效敌人时，将朝向优先级提升到移动与编队朝向之上。
## 这里只改变 VisualRoot 的期望朝向，不旋转 CharacterBody3D 根节点，也不改变当前移动目标。
## 敌人离开视野后，本方法不再覆盖方向，角色会自动恢复原有的移动或待机朝向逻辑。
func _update_enemy_facing() -> void:
	if not is_instance_valid(current_visible_enemy) or not current_visible_enemy.is_inside_tree():
		return

	var enemy_direction: Vector3 = current_visible_enemy.global_position - global_position
	enemy_direction.y = 0.0
	if enemy_direction.length_squared() <= 0.0001:
		return

	desired_facing_direction = enemy_direction.normalized()


## 平滑旋转 Visual，使身体和盾牌共同面向期望方向。
func _update_visual_facing(delta: float) -> void:
	if desired_facing_direction.length_squared() <= 0.001:
		return

	var target_yaw: float = atan2(-desired_facing_direction.x, -desired_facing_direction.z)
	visual.rotation.y = lerp_angle(
		visual.rotation.y,
		target_yaw,
		min(rotation_speed * delta, 1.0)
	)


## 应用项目默认重力并保持稳定贴地。
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity_force * gravity_multiplier * delta
	else:
		velocity.y = -0.1


## 宿主退出场景树时主动释放唯一活动请求，并断开所有模块连接。这里不触碰
## 公共冷却；节点即将销毁时只消除跨节点引用和未完成动作。
func _exit_tree() -> void:
	if is_instance_valid(skill_request_bridge):
		skill_request_bridge.clear_combat_context()
	_cancel_and_release_active_skill()
	var modules: Array[SkillModuleBaseType] = registered_skill_modules.duplicate()
	for module: SkillModuleBaseType in modules:
		if is_instance_valid(module):
			unregister_skill_module(module)
