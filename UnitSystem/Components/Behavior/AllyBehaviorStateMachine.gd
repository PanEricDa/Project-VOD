class_name AllyBehaviorStateMachine
extends Node

## 友方 AI 的统一行为状态机。
##
## 本组件是 Formation、Combat 移动和 Return 的唯一仲裁者。它只提交移动与朝向
## 意图，实际导航、速度、冲刺、重力和 move_and_slide() 仍由 AIUnitBase 执行。

signal state_changed(
	previous_state: BehaviorState,
	current_state: BehaviorState
)
signal formation_side_changed(new_side: int)

enum BehaviorState {
	FORMATION_WANDER,
	FORMATION_REPOSITION,
	COMBAT_APPROACH,
	COMBAT_HOLD,
	COMBAT_ATTACK,
	RETURN,
	CUSTOM,
}

enum CombatActionPolicy {
	BASIC_ONLY,
	SKILL_PRIORITY_THEN_BASIC,
	SKILL_ONLY_WITH_BASIC_WHEN_DISABLED,
}

const DEFAULT_FORMATION_CENTER_OFFSET := Vector2(0.0, 2.5)
const DEFAULT_LATERAL_RADIUS: float = 1.1
const DEFAULT_LATERAL_MINIMUM: float = 0.0
const DEFAULT_FORWARD_RADIUS: float = 0.65
const DEFAULT_SIDE_MODE := FormationPositionData.SideMode.FREE_CROSSING
## 技能接近过程中，只有距离至少缩短该值才视为取得了有效进展。
## 该阈值用于过滤导航抖动和浮点误差，不属于角色可调的战斗数值。
const SKILL_APPROACH_PROGRESS_EPSILON: float = 0.05
## 连续没有取得有效距离进展的最长时间。
## 超时后结束本次技能请求，让 AI 回到正常决策，避免永久占用 SkillHost。
const SKILL_APPROACH_STALL_TIMEOUT: float = 1.5
## 仇恨行动节流概率的固定收敛上限；高仇恨单位仍会保留极低概率发动行动，不会完全停摆。
const THREAT_ACTION_SUPPRESSION_ASYMPTOTE: float = 0.9
## 以相对仇恨 125% 为配置锚点；单位根节点的概率字段在该比率时精确生效。
const THREAT_ACTION_SUPPRESSION_REFERENCE_RATIO: float = 1.25

@export_category("Follow Target")
## 相对于玩家根节点解析的正面朝向节点。
@export var follow_target_facing_node_path: String = "Visual"

@export_category("Formation Position")
## 由 AllyBase 根节点转交的阵型位置数据；不作为子节点 Inspector 配置项。
var formation_position: FormationPositionData

@export_category("Formation")
@export_range(0.1, 20.0, 0.1, "or_greater")
var formation_smoothness: float = 6.0
@export_range(1.0, 20.0, 0.1, "or_greater")
var maximum_player_distance: float = 4.5
@export_range(1.0, 30.0, 0.1, "or_greater")
var emergency_dash_distance: float = 5.5

@export_category("Wander")
@export_range(0.0, 3.0, 0.05)
var formation_exit_margin: float = 0.4
@export_range(0.0, 3.0, 0.05)
var side_reselection_delay: float = 0.35
@export_range(0.1, 10.0, 0.1, "or_greater")
var wander_interval_min: float = 1.5
@export_range(0.1, 10.0, 0.1, "or_greater")
var wander_interval_max: float = 3.0
@export_range(0.0, 3.0, 0.05)
var minimum_target_change_distance: float = 0.35

@export_category("Formation Reservation")
## 新 Formation 落脚点与同队 AI 当前/预定位置之间保留的最小水平距离。
@export_range(0.0, 5.0, 0.05)
var minimum_reserved_spacing: float = 0.65
## 单次原游荡刷新最多生成的候选数量；不创建额外计时或逐帧扫描。
@export_range(1, 32, 1)
var maximum_candidate_attempts: int = 8

@export_category("Dash Decision")
@export_range(1.0, 180.0, 1.0)
var dash_turn_angle_threshold: float = 55.0
@export_range(0.1, 10.0, 0.1, "or_greater")
var dash_trigger_distance: float = 1.5
@export_range(0.1, 20.0, 0.1, "or_greater")
var dash_retry_distance: float = 2.5
@export_range(0.0, 5.0, 0.05)
var dash_retry_player_speed_threshold: float = 0.5
@export_range(0.0, 1.0, 0.01)
var direction_confirmation_time: float = 0.1

@export_category("Formation Facing")
@export_range(0.1, 10.0, 0.1)
var facing_update_interval_min: float = 1.2
@export_range(0.1, 10.0, 0.1)
var facing_update_interval_max: float = 2.1
@export_range(0.0, 5.0, 0.05)
var movement_facing_speed_threshold: float = 0.35

@export_category("Combat Position")
## 没有攻击模块时，伙伴围绕目标维持的默认战斗距离。
@export_range(0.1, 30.0, 0.1, "or_greater")
var preferred_combat_distance: float = 2.0
@export_range(0.0, 5.0, 0.05)
var combat_distance_tolerance: float = 0.25
## 装备近战武器后，进入攻击距离前使用的接近速度倍率。
@export_range(0.1, 5.0, 0.05, "or_greater")
var combat_approach_speed_multiplier: float = 1.2
@export_range(0.0, 5.0, 0.05)
var combat_wander_radius: float = 1.1
@export_range(0.0, 1.0, 0.05)
var combat_wander_speed_multiplier: float = 0.45

## 由 AllyBase 根节点转交的战斗策略配置；不作为子节点 Inspector 配置项。
var combat_action_policy: int = CombatActionPolicy.BASIC_ONLY
## 由 AllyBase 根节点转交；不作为子节点 Inspector 配置项。
var automatic_skill_cast_enabled: bool = true
## 由 AllyBase 根节点转交；不作为子节点 Inspector 配置项。
var shared_action_cooldown_duration: float = 1.0

@export_category("Combat Disengage")
## 伙伴战斗活动相对玩家的最大水平距离，单位为米；默认 12m。
## 当前敌方目标或伙伴自身任一超过该距离时，都会取消战斗并复用既有编队归队流程，防止追击与风筝把伙伴带出玩家战斗区域。
@export_range(1.0, 50.0, 0.5, "or_greater")
var maximum_combat_player_distance: float = 12.0
## 强制脱战后暂停自动索敌的时间；结束后直接恢复原有选敌策略。
@export_range(0.0, 10.0, 0.1)
var disengage_targeting_cooldown: float = 1.5

var _owner_body: AIUnitBase
var _targeting_component: AITargetingComponent
var _combat_system: AICombatSystem
var _skill_host: SkillHostComponent
var _player: CharacterBody3D
var _explicit_follow_target: CharacterBody3D
var _player_facing_node: Node3D
var _random_generator := RandomNumberGenerator.new()

var _current_state: BehaviorState = BehaviorState.FORMATION_WANDER
var _previous_state: BehaviorState = BehaviorState.FORMATION_WANDER
var _custom_state_id: StringName = &""
var _custom_state_context: Dictionary = {}
var _configured: bool = false
var _formation_position_pending_apply: bool = false

var _stable_player_direction: Vector3 = Vector3.FORWARD
var _candidate_player_direction: Vector3 = Vector3.FORWARD
var _direction_confirmation_elapsed: float = 0.0
var _raw_formation_center: Vector3 = Vector3.ZERO
var _smoothed_formation_center: Vector3 = Vector3.ZERO
var _movement_target: Vector3 = Vector3.ZERO
var _wander_offset: Vector3 = Vector3.ZERO
var _wander_lateral_value: float = 0.0
var _wander_longitudinal_value: float = 0.0
var _wander_timer: float = 0.0
var _facing_timer: float = 0.0
var _combat_wander_target: Vector3 = Vector3.ZERO
var _combat_wander_target_valid: bool = false
var _shared_action_cooldown_remaining: float = 0.0
## 技能模块在施法阶段可申请锁定移动；状态机只保存该意图，不直接理解任意技能的内部状态。
var _skill_movement_locked: bool = false
## 当前排队技能实际要求靠近的已解析目标。该目标可能是友军，不能用敌方锁定目标替代。
var _skill_approach_target: Node3D
var _skill_approach_range: float = 0.0
var _skill_approach_best_distance: float = INF
var _skill_approach_no_progress_elapsed: float = 0.0

var _locked_side: int = 0
var _has_entered_locked_region: bool = false
var _outside_locked_region_elapsed: float = 0.0


## 向 Inspector 提供只读的运行时跟随目标信息。
##
## 这里使用动态属性而不是 @export，确保设计师只能观察当前结果，不能通过 Inspector
## 改写跟随算法。属性不带 PROPERTY_USAGE_STORAGE，因此不会被保存进场景或继承场景。
func _get_property_list() -> Array[Dictionary]:
	return [
		{
			"name": "Debug",
			"type": TYPE_NIL,
			"hint_string": "debug_",
			"usage": PROPERTY_USAGE_GROUP,
		},
		{
			"name": "debug_current_follow_target",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_NODE_TYPE,
			"hint_string": "CharacterBody3D",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		},
	]


## 动态调试属性始终直接读取真实运行状态，不维护第二份可能失步的缓存。
func _get(property: StringName) -> Variant:
	if property == &"debug_current_follow_target":
		return _player if is_instance_valid(_player) else null
	return null


## 在 Inspector 中提示阵型资源缺失或数据非法，但运行时仍使用安全默认值。
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if formation_position == null:
		warnings.append(
			"Formation Position is missing. Built-in fallback values will be used."
		)
	elif not _is_valid_formation_position_data(formation_position):
		warnings.append(
			"Formation Position contains invalid offsets, ranges, or side mode."
		)
	return warnings


## 注入运动宿主和可选索敌组件。索敌缺失时 Formation 仍可独立运行。
func configure(
	owner_body: AIUnitBase,
	targeting_component: AITargetingComponent,
	combat_system: AICombatSystem = null,
	skill_host: SkillHostComponent = null
) -> bool:
	_owner_body = owner_body
	_targeting_component = targeting_component
	_combat_system = combat_system
	_skill_host = skill_host
	## 配置期间先保持未启用状态。自动解析跟随目标会复用公开 setter；
	## 若此时提前标记为已配置，setter 与本方法会各初始化一次，连续生成两轮阵型目标。
	_configured = false
	if not is_instance_valid(_owner_body):
		return false
	_random_generator.randomize()
	_configure_action_executors()
	if not is_instance_valid(_player):
		## 默认跟随对象同样必须通过唯一公开入口写入，避免形成第二条目标设定路径。
		set_follow_target(_find_player_faction_unit())
	_configured = true
	_initialize_runtime_state()
	return true


## 显式指定当前应跟随的单位。传入 null 时恢复自动寻找唯一 Player 阵营单位。
## 该接口可用于未来临时跟随队长、护送目标或其他 AI 角色。
func set_follow_target(target: CharacterBody3D) -> void:
	_explicit_follow_target = target
	if (
		is_instance_valid(_explicit_follow_target)
		and _explicit_follow_target.is_inside_tree()
	):
		_player = _explicit_follow_target
	else:
		## 当前默认参数为唯一 Player 阵营单位；未来也可由外部传入任意指定单位。
		_explicit_follow_target = null
		_player = _find_player_faction_unit()
	_resolve_player_facing_node()
	## 远程 Inspector 正在观察该节点时，立即刷新只读跟随对象。
	notify_property_list_changed()
	if _configured:
		_initialize_runtime_state()


## 保留旧名称作为兼容别名；新代码应使用 set_follow_target() 表达真实语义。
func set_player(player: CharacterBody3D) -> void:
	set_follow_target(player)


## 返回当前实际跟随目标；不存在有效目标时安全返回 null。
func get_follow_target() -> CharacterBody3D:
	return _player if is_instance_valid(_player) else null


## 每个物理帧由 AllyBase 调用一次；只有当前状态可以提交本帧移动意图。
func physics_tick(delta: float) -> void:
	if not _configured:
		return
	_update_protection(delta)
	_shared_action_cooldown_remaining = maxf(
		_shared_action_cooldown_remaining - delta,
		0.0
	)
	if is_instance_valid(_skill_host):
		_skill_host.set_external_global_cooldown_blocked(
			_shared_action_cooldown_remaining > 0.0
		)
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		## 原目标失效时，统一经公开接口恢复到默认 Player 阵营目标。
		set_follow_target(null)
	if not is_instance_valid(_player):
		_owner_body.clear_movement_target()
		return

	_update_player_direction(delta)
	if _is_formation_or_return_state():
		if _formation_position_pending_apply:
			_apply_pending_formation_position()
		else:
			_update_formation_center(delta)

	if _current_state == BehaviorState.CUSTOM:
		_update_custom_state(_custom_state_id, delta)
		return

	var target: UnitBase = _get_current_target()
	if target != null and _should_force_disengage(target):
		_force_disengage()
		return
	## 已排队技能的真实目标移动优先于敌方锁定目标和阵型移动。
	## 实际位移仍复用 AIUnitBase 的统一 locomotion 入口。
	if _update_skill_approach_movement(delta):
		return

	# 自动技能机会不等同于敌方战斗锁定。没有敌人时仍要允许 Host 使用
	# SkillBase 自身的目标关系复选和选择模式寻找本次动作目标。
	# 行为层只传递可选的战斗优先目标，不复制任何技能阵营或距离判断。
	if target == null and _try_request_automatic_skill(null):
		# AI 决策等待期间可以继续正常编队；真正开始施法后，Host 会通过
		# movement_lock_requested 同步锁住移动，此时必须阻止本帧再次提交阵型目标。
		if _skill_movement_locked:
			_owner_body.clear_movement_target()
			return

	if target != null:
		if not is_in_combat():
			_transition_to(BehaviorState.COMBAT_APPROACH)
		_update_combat_state(target, delta)
		return

	if is_in_combat():
		_cancel_combat_action()
		_transition_to(BehaviorState.RETURN)
		return

	if _current_state == BehaviorState.RETURN:
		_update_return_state()
		return

	_update_formation_side_lock(delta)
	_update_formation_state(delta)


func get_current_state() -> BehaviorState:
	return _current_state


func get_current_state_name() -> StringName:
	return StringName(BehaviorState.keys()[int(_current_state)])


func is_in_combat() -> bool:
	return (
		_current_state == BehaviorState.COMBAT_APPROACH
		or _current_state == BehaviorState.COMBAT_HOLD
		or _current_state == BehaviorState.COMBAT_ATTACK
	)


## 返回当前实际采用的战斗距离。
##
## 有有效武器时由 WeaponData 覆盖；无武器单位继续使用原状态机参数，因此未装配
## 战斗模块的现有角色不会改变警戒游荡行为。
func get_effective_combat_distance() -> float:
	if (
		combat_action_policy == CombatActionPolicy.SKILL_ONLY_WITH_BASIC_WHEN_DISABLED
		and is_instance_valid(_skill_host)
		and _skill_host.is_skill_casting_enabled()
		and not _skill_host.get_registered_skills().is_empty()
	):
		var preferred_cast_range: float = _skill_host.get_preferred_cast_range()
		if preferred_cast_range > 0.0:
			## cast_range 表示最大合法距离，不是导航目标必须精确落在的半径。
			## 导航会在 arrival_distance 内提前停下；若直接把最大距离作为目标，
			## 单位可能永远停在范围外的极窄环带。使用既有到达距离自动生成内缩量，
			## 让站位、游荡和施法判定共享一个稳定的安全区。
			var range_safety_margin: float = (
				maxf(_owner_body.arrival_distance, 0.0) + 0.05
				if is_instance_valid(_owner_body)
				else 0.2
			)
			return maxf(
				preferred_cast_range - range_safety_margin,
				0.1
			)
	if _combat_system != null and _combat_system.get_equipped_weapon() != null:
		return _combat_system.get_attack_range()
	return preferred_combat_distance


## 返回与当前有效战斗距离来自同一数据源的容差。
func get_effective_combat_distance_tolerance() -> float:
	## 纯技能单位的站位半径由 SkillBase.cast_range 决定，不能再混入备用武器的
	## attack_range_tolerance。否则 AI 可能停在“战斗状态机认为已进入范围、技能本身
	## 仍判定超出范围”的窄环带内，技能会永久保持 QUEUED，表现为随机停止施法和移动。
	if (
		combat_action_policy
			== CombatActionPolicy.SKILL_ONLY_WITH_BASIC_WHEN_DISABLED
		and is_instance_valid(_skill_host)
		and _skill_host.is_skill_casting_enabled()
		and not _skill_host.get_registered_skills().is_empty()
	):
		## 导航会在 arrival_distance 内停止，因此状态切换容差必须覆盖同一到达阈值。
		## 理想半径已经向内收缩 arrival_distance + 0.05；即使取到该容差外沿，
		## 站位仍会保留约 0.04m 的施法范围安全余量。
		return (
			maxf(_owner_body.arrival_distance, 0.0) + 0.01
			if is_instance_valid(_owner_body)
			else 0.16
		)
	if _combat_system != null and _combat_system.get_equipped_weapon() != null:
		return _combat_system.get_attack_range_tolerance()
	return combat_distance_tolerance


func get_locked_side() -> int:
	return _locked_side


func get_stable_player_direction() -> Vector3:
	return _stable_player_direction


func get_current_movement_target() -> Vector3:
	return _movement_target


## 在运行时更换共享阵型位置资源。
##
## Combat 与 Custom 状态只记录新选择，不读取或应用其中的数据；进入 Return 或
## Formation 后才统一刷新中心和游荡目标。
func set_formation_position(data: FormationPositionData) -> bool:
	if not _is_valid_formation_position_data(data):
		return false
	formation_position = data
	_formation_position_pending_apply = true
	update_configuration_warnings()
	if (
		_configured
		and is_instance_valid(_player)
		and _is_formation_or_return_state()
	):
		_apply_pending_formation_position()
	return true


## 返回当前选择的共享阵型位置资源；使用内建回退时返回 null。
func get_formation_position() -> FormationPositionData:
	return formation_position


func request_formation_side(
	side: int,
	refresh_target: bool = true
) -> void:
	_apply_locked_side(clampi(side, -1, 1), refresh_target)


## 请求进入未来扩展行为。默认实现不接受任何标识，避免空状态夺走移动控制。
func request_custom_state(
	custom_state_id: StringName,
	context: Dictionary = {}
) -> bool:
	if custom_state_id.is_empty() or not _supports_custom_state(custom_state_id):
		return false
	_custom_state_id = custom_state_id
	_custom_state_context = context.duplicate(true)
	_transition_to(BehaviorState.CUSTOM)
	return true


## 自定义行为完成后统一返回编队流程。
func exit_custom_state() -> void:
	if _current_state == BehaviorState.CUSTOM:
		_transition_to(BehaviorState.RETURN)


## 子类只需覆写这一组大接口，即可承载未来非战斗行为。
func _supports_custom_state(_requested_custom_state_id: StringName) -> bool:
	return false


func _enter_custom_state(
	_requested_custom_state_id: StringName,
	_context: Dictionary
) -> void:
	pass


func _update_custom_state(
	_requested_custom_state_id: StringName,
	_delta: float
) -> void:
	pass


func _exit_custom_state(_requested_custom_state_id: StringName) -> void:
	pass


func _transition_to(next_state: BehaviorState) -> void:
	if _current_state == next_state:
		return
	var old_state: BehaviorState = _current_state
	var was_in_combat: bool = _is_combat_behavior_state(old_state)
	var will_be_in_combat: bool = _is_combat_behavior_state(next_state)
	if old_state == BehaviorState.CUSTOM:
		_exit_custom_state(_custom_state_id)
	_previous_state = old_state
	_current_state = next_state
	var applied_pending_position: bool = false
	if (
		_formation_position_pending_apply
		and _is_formation_or_return_state()
		and is_instance_valid(_player)
	):
		_apply_pending_formation_position()
		applied_pending_position = true
	if next_state == BehaviorState.CUSTOM:
		_enter_custom_state(_custom_state_id, _custom_state_context)
	elif old_state == BehaviorState.CUSTOM:
		_custom_state_id = &""
		_custom_state_context.clear()
	if (
		next_state == BehaviorState.FORMATION_WANDER
		and not applied_pending_position
	):
		_select_new_formation_wander_target()
	elif next_state == BehaviorState.COMBAT_HOLD:
		_wander_timer = 0.0
		_combat_wander_target_valid = false
	## 行为状态机是 Ally 战斗意图的唯一裁决者；在此处同步到 UnitBase，
	## 使房间流程、UI 与后续全局系统无需理解 Ally 的内部状态枚举。
	if not was_in_combat and will_be_in_combat:
		_owner_body.enter_combat()
	elif was_in_combat and not will_be_in_combat:
		_owner_body.exit_combat()
	state_changed.emit(old_state, _current_state)


## 判断给定 Ally 行为状态是否属于持续战斗生命周期。
## 接近、持距与攻击期间均视为战斗中；冷却和绕行由 COMBAT_HOLD 覆盖，
## 不以“本帧是否播放攻击动画”作为脱战依据。
func _is_combat_behavior_state(state: BehaviorState) -> bool:
	return (
		state == BehaviorState.COMBAT_APPROACH
		or state == BehaviorState.COMBAT_HOLD
		or state == BehaviorState.COMBAT_ATTACK
	)


func _get_current_target() -> UnitBase:
	_update_protection_release()
	if not is_instance_valid(_targeting_component):
		return null
	return _targeting_component.get_locked_target()


func _should_force_disengage(target: UnitBase) -> bool:
	var maximum_distance: float = maxf(maximum_combat_player_distance, 0.0)
	var target_offset: Vector3 = target.global_position - _player.global_position
	target_offset.y = 0.0
	var owner_offset: Vector3 = _owner_body.global_position - _player.global_position
	owner_offset.y = 0.0
	return (
		target_offset.length() > maximum_distance
		or owner_offset.length() > maximum_distance
	)


func _force_disengage() -> void:
	if is_instance_valid(_targeting_component):
		_targeting_component.suspend_detection(
			maxf(disengage_targeting_cooldown, 0.0),
			true
		)
	_cancel_combat_action()
	## 强制脱战只负责清理战斗职责，移动立即交回原有编队跟随状态。
	##
	## 不在这里维护第二套返回速度或冲刺条件；FORMATION_REPOSITION 会继续复用
	## emergency_dash_distance、dash 冷却以及普通编队重定位的全部既有规则。
	_transition_to(BehaviorState.FORMATION_REPOSITION)
	_refresh_formation_center_immediately()
	_update_formation_state(0.0)


func _update_combat_state(target: UnitBase, delta: float) -> void:
	if _current_state == BehaviorState.COMBAT_APPROACH:
		_update_combat_approach(target)
	elif _current_state == BehaviorState.COMBAT_HOLD:
		_update_combat_hold(target, delta)
	elif _current_state == BehaviorState.COMBAT_ATTACK:
		_update_combat_attack(target, delta)


func _update_combat_approach(target: UnitBase) -> void:
	var direction_to_target: Vector3 = (
		target.global_position - _owner_body.global_position
	)
	direction_to_target.y = 0.0
	var distance: float = direction_to_target.length()
	if distance <= 0.0001:
		direction_to_target = Vector3.FORWARD
	else:
		direction_to_target /= distance
	var preferred_distance: float = maxf(
		get_effective_combat_distance(),
		0.1
	)
	var tolerance: float = maxf(
		get_effective_combat_distance_tolerance(),
		0.0
	)
	## 武器的 attack_range 表示“最大可发动距离”，而不是必须精确站在该半径上。
	## 进入最大距离后即可交给 HOLD 判断攻击，避免浮点边界或目标贴近时永远无法出手。
	if distance <= preferred_distance + tolerance:
		_owner_body.clear_movement_target()
		_owner_body.set_desired_facing(direction_to_target)
		_transition_to(BehaviorState.COMBAT_HOLD)
		return
	_movement_target = (
		target.global_position - direction_to_target * preferred_distance
	)
	_movement_target.y = _owner_body.global_position.y
	_owner_body.set_movement_target(
		_movement_target,
		_owner_body.movement_speed * (
			combat_approach_speed_multiplier
			if _combat_system != null
				and _combat_system.get_equipped_weapon() != null
			else 1.0
		),
		false
	)
	_owner_body.set_desired_facing(direction_to_target)


func _update_combat_hold(target: UnitBase, delta: float) -> void:
	var distance: float = _horizontal_distance(
		_owner_body.global_position,
		target.global_position
	)
	var maximum_distance: float = (
		maxf(get_effective_combat_distance(), 0.1)
		+ maxf(get_effective_combat_distance_tolerance(), 0.0)
	)

	## 迟滞：退出 HOLD 需要的额外距离，避免位移抖动导致不停切换。
	var hysteresis: float = maxf(_owner_body.arrival_distance, 0.0) + maxf(combat_distance_tolerance, 0.0)

	if distance > maximum_distance + hysteresis:
		_transition_to(BehaviorState.COMBAT_APPROACH)
		_update_combat_approach(target)
		return
	if _should_defer_threat_sensitive_action(target):
		## 暂缓只消耗已有的共享行动机会；索敌、面向和战斗游荡保持原样运行。
		_start_shared_action_cooldown()
		_submit_combat_orbit_movement(target, delta)
		return
	## 近战攻击只要求目标没有超出最大距离。即使目标已经贴近，优先发动当前可用
	## 攻击；只有处于公共冷却或动画忙碌时，才通过下方持距逻辑轻微回到理想半径。
	if _try_request_automatic_skill(target):
		_submit_combat_orbit_movement(target, delta)
		return
	if _should_block_basic_attack_for_skills():
		_submit_combat_orbit_movement(target, delta)
		return
	if (
		_combat_system != null
		and _shared_action_cooldown_remaining <= 0.0
		and _combat_system.get_equipped_weapon() != null
		and _combat_system.request_basic_attack(target)
	):
		_submit_active_basic_attack_movement(target, delta)
		_transition_to(BehaviorState.COMBAT_ATTACK)
		return
	_submit_combat_orbit_movement(target, delta)


## 攻击期间继续复用 HOLD 的低速环绕移动，但攻击动画、公共冷却和面向控制仍由
## 原战斗链路负责；这不会启用 AI 的动画事件攻击位移。
func _update_combat_attack(target: UnitBase, delta: float) -> void:
	if _combat_system == null:
		_transition_to(BehaviorState.COMBAT_APPROACH)
		return

	var facing_direction: Vector3 = (
		target.global_position - _owner_body.global_position
	)
	facing_direction.y = 0.0
	if facing_direction.length_squared() > 0.0001:
		_owner_body.set_desired_facing(facing_direction.normalized())

	if _combat_system.is_attacking():
		_submit_active_basic_attack_movement(target, delta)
		return

	var distance: float = _horizontal_distance(
		_owner_body.global_position,
		target.global_position
	)
	var maximum_distance: float = (
		get_effective_combat_distance()
		+ get_effective_combat_distance_tolerance()
	)
	_transition_to(
		BehaviorState.COMBAT_APPROACH
		if distance > maximum_distance
		else BehaviorState.COMBAT_HOLD
	)


func _configure_action_executors() -> void:
	if is_instance_valid(_combat_system):
		_combat_system.set_use_external_global_cooldown(true)
		if not _combat_system.attack_started.is_connected(_on_basic_attack_started):
			_combat_system.attack_started.connect(_on_basic_attack_started)
	if is_instance_valid(_skill_host):
		_skill_host.set_use_external_global_cooldown(true)
		if not _skill_host.action_requested.is_connected(
			_on_skill_action_requested
		):
			_skill_host.action_requested.connect(
				_on_skill_action_requested
			)
		if not _skill_host.approach_requested.is_connected(
			_on_skill_approach_requested
		):
			_skill_host.approach_requested.connect(
				_on_skill_approach_requested
			)
		if not _skill_host.skill_released.is_connected(
			_on_skill_released
		):
			_skill_host.skill_released.connect(_on_skill_released)
		if not _skill_host.movement_lock_requested.is_connected(
			_on_skill_movement_lock_requested
		):
			_skill_host.movement_lock_requested.connect(
				_on_skill_movement_lock_requested
			)
	if is_instance_valid(_combat_system):
		if not _combat_system.external_action_released.is_connected(
			_on_external_action_released
		):
			_combat_system.external_action_released.connect(
				_on_external_action_released
			)
		if not _combat_system.external_action_finished.is_connected(
			_on_external_action_finished
		):
			_combat_system.external_action_finished.connect(
				_on_external_action_finished
			)
		if not _combat_system.external_action_cancelled.is_connected(
			_on_external_action_cancelled
		):
			_combat_system.external_action_cancelled.connect(
				_on_external_action_cancelled
			)


func _try_request_automatic_skill(preferred_target: UnitBase) -> bool:
	if (
		combat_action_policy == CombatActionPolicy.BASIC_ONLY
		or
		not is_instance_valid(_skill_host)
		or not automatic_skill_cast_enabled
		or not _skill_host.is_skill_casting_enabled()
		or _shared_action_cooldown_remaining > 0.0
		or _skill_host.get_registered_skills().is_empty()
	):
		return false
	if _skill_host.get_active_skill() != null:
		# 只有技能尚未交付、正在请求角色动作或正在施法时才占用普攻。
		# 成功释放后的随机犹豫只限制该技能再次释放，普攻可在共享行动冷却结束后正常填充。
		return _skill_host.is_active_skill_action_in_progress()
	return _skill_host.request_best_skill(preferred_target)


## 根据相对仇恨计算本次行动的暂缓概率。
## relative_threat_ratio 是本单位仇恨除以同一敌人最高其他竞争者仇恨的只读比率；100% 及以下返回 0，
## 125% 时精确返回 UnitBase 的 threat_action_suppression_at_125，之后向 90% 平滑收敛但永不达到。
## 此方法不掷骰、不写入冷却，可供未来专注值等属性在同一概率公式上叠加修正。
func get_threat_action_suppression_probability(
	relative_threat_ratio: float
) -> float:
	if not is_instance_valid(_owner_body) or relative_threat_ratio <= 1.0:
		return 0.0
	var probability_at_125: float = clampf(
		_owner_body.threat_action_suppression_at_125,
		0.0,
		THREAT_ACTION_SUPPRESSION_ASYMPTOTE - 0.001
	)
	if probability_at_125 <= 0.0:
		return 0.0
	var exponent_rate: float = -log(
		1.0 - probability_at_125 / THREAT_ACTION_SUPPRESSION_ASYMPTOTE
	) / (THREAT_ACTION_SUPPRESSION_REFERENCE_RATIO - 1.0)
	return clampf(
		THREAT_ACTION_SUPPRESSION_ASYMPTOTE * (
			1.0 - exp(-exponent_rate * (relative_threat_ratio - 1.0))
		),
		0.0,
		THREAT_ACTION_SUPPRESSION_ASYMPTOTE
	)


## 判断当前战斗目标是否使本单位主动暂缓一次自动行动。
## 只读取目标敌人的 EnemyThreatComponent；目标没有仇恨组件、没有其他有效竞争者、共享冷却未结束或
## 技能已经进入排队/施法动作时都会安全放行。返回 true 时调用方必须只启动共享行动冷却，不能取消目标、技能或移动。
func _should_defer_threat_sensitive_action(target: UnitBase) -> bool:
	if (
		not is_instance_valid(_owner_body)
		or not is_instance_valid(target)
		or _shared_action_cooldown_remaining > 0.0
		or (
			is_instance_valid(_skill_host)
			and _skill_host.is_active_skill_action_in_progress()
		)
		or not target.has_method(&"get_threat_component")
	):
		return false
	var threat_component: Node = target.call(&"get_threat_component") as Node
	if (
		not is_instance_valid(threat_component)
		or not threat_component.has_method(
			&"get_threat_ratio_against_highest_competitor"
		)
	):
		return false
	var relative_threat_ratio: float = float(
		threat_component.call(
			&"get_threat_ratio_against_highest_competitor",
			_owner_body
		)
	)
	var suppression_probability: float = (
		get_threat_action_suppression_probability(relative_threat_ratio)
	)
	return (
		suppression_probability > 0.0
		and _random_generator.randf() < suppression_probability
	)


func _should_block_basic_attack_for_skills() -> bool:
	if (
		combat_action_policy != CombatActionPolicy.SKILL_ONLY_WITH_BASIC_WHEN_DISABLED
		or not is_instance_valid(_skill_host)
		or not automatic_skill_cast_enabled
		or _skill_host.get_registered_skills().is_empty()
	):
		return false
	return _skill_host.is_skill_casting_enabled()


func _on_basic_attack_started(_target: UnitBase, _attack_index: int) -> void:
	_start_shared_action_cooldown()


func _on_skill_released(_context: SkillContext) -> void:
	_start_shared_action_cooldown()


## SkillHost 只提出通用动作请求；状态机把它转交给现有 AICombatSystem 动画入口。
func _on_skill_action_requested(
	_skill: SkillBase,
	target: Node3D,
	effective_cast_time: float
) -> void:
	_clear_skill_approach_request()
	var melee_action := _skill.get_node_or_null(^"MeleeAction") as MeleeSkillAction
	var action_payload: Dictionary = melee_action.get_action_payload(_skill.threat_multiplier) if melee_action != null else {}
	if is_instance_valid(target):
		var facing: Vector3 = (
			target.global_position - _owner_body.global_position
		)
		facing.y = 0.0
		if facing.length_squared() > 0.0001:
			## 动作动画会在 request_external_action() 内立即开始，因此必须先完成世界朝向对齐。
			_owner_body.snap_visual_facing(facing.normalized())
	if (
		not is_instance_valid(_combat_system)
		or not _combat_system.request_external_action(effective_cast_time, target as UnitBase, action_payload)
	):
		_skill_host.cancel_active_skill(&"action_driver_rejected")
		return
	var launch_transform := _combat_system.get_action_launch_transform()
	if not _skill_host.confirm_active_action_started(launch_transform):
		_combat_system.cancel_external_action()
		_skill_host.cancel_active_skill(&"action_confirmation_failed")


## 范围外技能继续复用既有 COMBAT_APPROACH，不建立第二套移动算法。
func _on_skill_approach_requested(
	context: SkillContext,
	required_range: float
) -> void:
	if context == null or not is_instance_valid(context.resolved_target):
		_clear_skill_approach_request()
		return
	var next_target: Node3D = context.resolved_target
	var next_range: float = maxf(required_range, 0.0)
	## SkillBase 在 QUEUED 阶段可能每个物理帧重复报告同一接近请求。
	## 只有目标或要求距离真实变化时才重置进展统计，否则计时器永远无法达到超时。
	if (
		next_target != _skill_approach_target
		or not is_equal_approx(next_range, _skill_approach_range)
	):
		_skill_approach_best_distance = INF
		_skill_approach_no_progress_elapsed = 0.0
	_skill_approach_target = next_target
	_skill_approach_range = next_range
	if is_in_combat():
		_transition_to(BehaviorState.COMBAT_APPROACH)


func _on_external_action_released() -> void:
	if not is_instance_valid(_skill_host):
		return
	if not _skill_host.release_active_action(
		_combat_system.get_action_launch_transform()
	):
		_combat_system.cancel_external_action()


func _on_external_action_finished() -> void:
	_clear_skill_approach_request()
	if is_instance_valid(_skill_host):
		_skill_host.finish_active_action()


func _on_external_action_cancelled() -> void:
	_clear_skill_approach_request()
	if is_instance_valid(_skill_host):
		_skill_host.cancel_active_skill(&"action_driver_cancelled")


## 技能本身决定施法时是否可移动；状态机仅将这项通用意图落实为不提交导航目标。
func _on_skill_movement_lock_requested(locked: bool) -> void:
	_skill_movement_locked = locked
	if _skill_movement_locked and is_instance_valid(_owner_body):
		_owner_body.clear_movement_target()


func _start_shared_action_cooldown() -> void:
	_shared_action_cooldown_remaining = maxf(
		_shared_action_cooldown_remaining,
		maxf(shared_action_cooldown_duration, 0.0)
	)


func set_automatic_skill_cast_enabled(enabled: bool) -> void:
	automatic_skill_cast_enabled = enabled


func is_automatic_skill_cast_enabled() -> bool:
	return automatic_skill_cast_enabled


## 执行排队技能的目标专用接近请求。
##
## SkillBase 已经完成阵营、优先级和目标有效性解析；行为层只消费结果并提交移动。
## 目标半径按现有 arrival_distance 向内收缩，避免停在最大施法距离边缘。
func _update_skill_approach_movement(delta: float) -> bool:
	if not is_instance_valid(_skill_approach_target):
		_clear_skill_approach_request()
		return false
	if (
		not is_instance_valid(_skill_host)
		or _skill_host.get_active_skill() == null
	):
		_clear_skill_approach_request()
		return false

	var offset: Vector3 = (
		_skill_approach_target.global_position
		- _owner_body.global_position
	)
	offset.y = 0.0
	var distance: float = offset.length()
	var direction: Vector3 = (
		offset / distance
		if distance > 0.0001
		else Vector3.FORWARD
	)
	var range_safety_margin: float = (
		maxf(_owner_body.arrival_distance, 0.0) + 0.05
	)
	var desired_range: float = maxf(
		_skill_approach_range - range_safety_margin,
		0.0
	)
	if distance <= _skill_approach_range + 0.05:
		_skill_approach_best_distance = distance
		_skill_approach_no_progress_elapsed = 0.0
		_owner_body.clear_movement_target()
		_owner_body.set_desired_facing(direction)
		return true

	## 只要水平距离取得了足够进展，就刷新最佳距离并清空停滞计时。
	## 目标轻微抖动不会被误判为进展；目标持续远离或导航完全无法移动时，计时会累积。
	if (
		not is_finite(_skill_approach_best_distance)
		or distance
			<= _skill_approach_best_distance - SKILL_APPROACH_PROGRESS_EPSILON
	):
		_skill_approach_best_distance = distance
		_skill_approach_no_progress_elapsed = 0.0
	else:
		_skill_approach_no_progress_elapsed += maxf(delta, 0.0)
		if _skill_approach_no_progress_elapsed >= SKILL_APPROACH_STALL_TIMEOUT:
			_owner_body.clear_movement_target()
			## 使用 Host 的公开取消入口，使 Skill、Host、移动锁和动作占用继续走
			## 同一条既有清理链；不在状态机中直接改写任何技能内部字段。
			_skill_host.cancel_active_skill(&"approach_stalled")
			_clear_skill_approach_request()
			return true

	_movement_target = (
		_skill_approach_target.global_position
		- direction * desired_range
	)
	_movement_target.y = _owner_body.global_position.y
	_owner_body.set_movement_target(_movement_target)
	_owner_body.set_desired_facing(direction)
	return true


func _clear_skill_approach_request() -> void:
	_skill_approach_target = null
	_skill_approach_range = 0.0
	_skill_approach_best_distance = INF
	_skill_approach_no_progress_elapsed = 0.0


## COMBAT_HOLD 与 COMBAT_ATTACK 共用的轻量持距游荡。
##
## 该方法只提交已有的导航目标和低速倍率，不创建新状态、计时器或速度算法。
## 根据已装备武器的普攻移动倍率提交攻击期间移动；倍率为 0 时清除导航目标实现站立攻击，其余值继续复用现有环绕路径。
func _submit_active_basic_attack_movement(target: UnitBase, delta: float) -> void:
	var movement_speed_multiplier: float = (
		_combat_system.get_attack_movement_speed_multiplier()
		if is_instance_valid(_combat_system)
		else 1.0
	)
	if movement_speed_multiplier <= 0.0:
		_owner_body.clear_movement_target()
		return
	_submit_combat_orbit_movement(target, delta, movement_speed_multiplier)


func _submit_combat_orbit_movement(
	target: UnitBase,
	delta: float,
	movement_speed_multiplier: float = 1.0
) -> void:
	if _skill_movement_locked:
		_owner_body.clear_movement_target()
		return
	var target_to_owner: Vector3 = (
		_owner_body.global_position - target.global_position
	)
	target_to_owner.y = 0.0
	var distance: float = target_to_owner.length()
	var outward: Vector3 = (
		target_to_owner / distance
		if distance > 0.0001
		else Vector3.BACK
	)
	_wander_timer -= delta
	if (
		not _combat_wander_target_valid
		or (
			_wander_timer <= 0.0
			and _owner_body.global_position.distance_to(
				_combat_wander_target
			) <= _owner_body.slowing_distance
		)
	):
		_select_new_combat_wander_target(target, outward)
	_movement_target = _combat_wander_target

	var orbit_speed: float = (
		_owner_body.movement_speed
		* clampf(combat_wander_speed_multiplier, 0.0, 1.0)
		* clampf(movement_speed_multiplier, 0.0, 1.0)
	)
	_owner_body.set_movement_target(_movement_target, orbit_speed, false)
	_owner_body.set_desired_facing(-outward)


func _select_new_combat_wander_target(
	target: UnitBase,
	outward: Vector3
) -> void:
	var tangent := Vector3(-outward.z, 0.0, outward.x)
	var wander_radius: float = maxf(combat_wander_radius, 0.0)
	## 避免抽到接近 0 的切向偏移。那种候选与当前位置的差值可能小于
	## AIUnitBase.arrival_distance，表现为“目标存在但速度始终为零”。
	var minimum_tangent_offset: float = minf(
		wander_radius,
		maxf(
			wander_radius * 0.35,
			_owner_body.arrival_distance + 0.05
		)
	)
	var tangent_offset: float = 0.0
	if wander_radius > 0.0:
		var tangent_sign: float = (
			-1.0 if _random_generator.randf() < 0.5 else 1.0
		)
		tangent_offset = tangent_sign * _random_generator.randf_range(
			minimum_tangent_offset,
			wander_radius
		)
	var preferred_distance: float = maxf(
		get_effective_combat_distance(),
		0.1
	)
	var tolerance: float = maxf(
		get_effective_combat_distance_tolerance(),
		0.0
	)
	var radial_offset: float = _random_generator.randf_range(
		-tolerance,
		tolerance
	)
	## 将横向米制偏移转换为圆周角度，而不是直接扩大与目标之间的实际距离。
	## 这与旧 AllyBase 的战斗游荡规则一致：范围越大表示绕行弧度越大，
	## 但目标点仍始终处于允许的战斗距离环带内。
	var offset_direction: Vector3 = (
		outward * preferred_distance
		+ tangent * tangent_offset
	).normalized()
	var minimum_radius: float = maxf(
		preferred_distance - tolerance,
		0.1
	)
	var maximum_radius: float = maxf(
		preferred_distance + tolerance,
		minimum_radius
	)
	var target_radius: float = clampf(
		preferred_distance + radial_offset,
		minimum_radius,
		maximum_radius
	)
	_combat_wander_target = (
		target.global_position
		+ offset_direction * target_radius
	)
	_combat_wander_target.y = _owner_body.global_position.y
	_combat_wander_target_valid = true
	_reset_wander_timer()


## 在 GCD 周期触发一次保护扫描，发现 OT 敌人时通过索敌组件的目标持有闸门锁定它。
func _update_protection(_delta: float) -> void:
	if not is_instance_valid(_targeting_component):
		return
	if _targeting_component.is_target_held():
		return
	if _shared_action_cooldown_remaining > 0.0:
		return
	var policy := _targeting_component.selection_policy
	if policy == null or not policy.has_method(&"wants_target_re_evaluation"):
		return
	if not policy.wants_target_re_evaluation():
		return
	var perceived: Array[UnitBase] = []
	for node: Node3D in _targeting_component.get_perceived_candidates():
		if node is UnitBase:
			perceived.append(node as UnitBase)
	var best_candidate: UnitBase
	var best_priority: float = INF
	for candidate: UnitBase in perceived:
		if not policy.is_candidate_valid(
			_owner_body,
			candidate,
			_targeting_component.get_targeting_radius()
		):
			continue
		var candidate_targeting: Node = candidate.get_node_or_null(^"AITargetingComponent")
		if not is_instance_valid(candidate_targeting) or not candidate_targeting.has_method(&"get_locked_target"):
			continue
		var locked: Variant = candidate_targeting.call("get_locked_target")
		if locked == _owner_body:
			continue
		var priority: float = policy.calculate_priority(_owner_body, candidate)
		if priority < best_priority:
			best_priority = priority
			best_candidate = candidate
	if is_instance_valid(best_candidate):
		_targeting_component.hold_target(best_candidate)


## 每帧检查目标持有是否应结束：目标转向自己（保护完成）或目标失效时恢复普通检索。
func _update_protection_release() -> void:
	if not is_instance_valid(_targeting_component) or not _targeting_component.is_target_held():
		return
	var held_target := _targeting_component.get_locked_target() as UnitBase
	if not is_instance_valid(held_target):
		_targeting_component.release_target_hold()
		return
	if held_target.is_dead() or not held_target.is_targetable() or not held_target.is_inside_tree():
		_targeting_component.release_target_hold()
		return
	var held_targeting: Node = held_target.get_node_or_null(^"AITargetingComponent")
	if not is_instance_valid(held_targeting) or not held_targeting.has_method(&"get_locked_target"):
		_targeting_component.release_target_hold()
		return
	var locked: Variant = held_targeting.call("get_locked_target")
	if locked == _owner_body:
		_targeting_component.release_target_hold()


func _cancel_combat_action() -> void:
	_clear_skill_approach_request()
	if is_instance_valid(_targeting_component) and _targeting_component.is_target_held():
		_targeting_component.release_target_hold()
	if _combat_system != null:
		_combat_system.cancel_current_action()
	if is_instance_valid(_skill_host):
		_skill_host.cancel_active_skill(&"combat_cancelled")
	_skill_movement_locked = false


func _update_return_state() -> void:
	var player_distance: float = _horizontal_distance(
		_owner_body.global_position,
		_player.global_position
	)
	if player_distance < maximum_player_distance * 0.8:
		_transition_to(BehaviorState.FORMATION_WANDER)
		return
	_movement_target = _constrain_target(_smoothed_formation_center)
	_owner_body.set_movement_target(_movement_target)


func _update_formation_state(delta: float) -> void:
	if _owner_body.is_dashing() or _owner_body.is_recovering():
		return
	var player_distance: float = _horizontal_distance(
		_owner_body.global_position,
		_player.global_position
	)
	var formation_error: float = _horizontal_distance(
		_owner_body.global_position,
		_raw_formation_center
	)
	var player_speed := Vector2(
		_player.velocity.x,
		_player.velocity.z
	).length()

	if player_distance >= emergency_dash_distance and _owner_body.can_dash():
		_owner_body.request_dash(_raw_formation_center + _wander_offset)
		_transition_to(BehaviorState.FORMATION_REPOSITION)
		return
	if (
		_owner_body.can_dash()
		and player_speed >= dash_retry_player_speed_threshold
		and formation_error >= dash_retry_distance
	):
		_owner_body.request_dash(_raw_formation_center + _wander_offset)
		_transition_to(BehaviorState.FORMATION_REPOSITION)
		return

	if player_distance >= maximum_player_distance:
		_transition_to(BehaviorState.FORMATION_REPOSITION)
	elif (
		_current_state == BehaviorState.FORMATION_REPOSITION
		and player_distance < maximum_player_distance * 0.8
	):
		_transition_to(BehaviorState.FORMATION_WANDER)

	_update_formation_idle_facing(delta)
	_submit_formation_movement(delta)


func _submit_formation_movement(delta: float) -> void:
	if _current_state == BehaviorState.FORMATION_WANDER:
		if _is_wander_target_refresh_due(delta):
			_select_new_formation_wander_target()
	_movement_target = _constrain_target(
		_smoothed_formation_center + _wander_offset
	)
	_owner_body.set_movement_target(_movement_target)


## 在需要解析或原跟随对象失效时递归查找 Player 阵营单位。
## 此查询只发生在装配、恢复自动跟随或对象失效时，不会成为每帧扫描开销。
func _find_player_faction_unit() -> CharacterBody3D:
	var scene_root: Node = get_tree().current_scene
	if not is_instance_valid(scene_root):
		scene_root = get_tree().root
	return _find_player_faction_unit_recursive(scene_root)


func _find_player_faction_unit_recursive(node: Node) -> CharacterBody3D:
	var unit := node as UnitBase
	if unit != null and unit.faction_id == "Player":
		return unit
	for child: Node in node.get_children():
		var found: CharacterBody3D = _find_player_faction_unit_recursive(child)
		if is_instance_valid(found):
			return found
	return null


func _resolve_player_facing_node() -> void:
	_player_facing_node = null
	if is_instance_valid(_player):
		_player_facing_node = _player.get_node_or_null(
			NodePath(follow_target_facing_node_path)
		) as Node3D


func _initialize_runtime_state() -> void:
	_current_state = BehaviorState.FORMATION_WANDER
	_previous_state = BehaviorState.FORMATION_WANDER
	_custom_state_id = &""
	_custom_state_context.clear()
	_stable_player_direction = _read_player_direction()
	_candidate_player_direction = _stable_player_direction
	_direction_confirmation_elapsed = 0.0
	if is_instance_valid(_player):
		_raw_formation_center = _calculate_raw_formation_center(
			_stable_player_direction
		)
		_smoothed_formation_center = _raw_formation_center
	_initialize_formation_side()
	_formation_position_pending_apply = false
	_select_new_formation_wander_target()
	_owner_body.set_desired_facing(_stable_player_direction)


func _read_player_direction() -> Vector3:
	if is_instance_valid(_player_facing_node):
		var visual_forward: Vector3 = -_player_facing_node.global_basis.z
		visual_forward.y = 0.0
		if visual_forward.length_squared() > 0.0001:
			return visual_forward.normalized()
	if is_instance_valid(_player):
		var horizontal_velocity := Vector3(
			_player.velocity.x,
			0.0,
			_player.velocity.z
		)
		if horizontal_velocity.length_squared() > 0.01:
			return horizontal_velocity.normalized()
		var saved_direction: Variant = _player.get("last_movement_direction")
		if saved_direction is Vector3:
			var direction: Vector3 = saved_direction
			direction.y = 0.0
			if direction.length_squared() > 0.01:
				return direction.normalized()
	return _stable_player_direction


func _update_player_direction(delta: float) -> void:
	var observed_direction: Vector3 = _read_player_direction()
	if _candidate_player_direction.angle_to(observed_direction) > deg_to_rad(5.0):
		_candidate_player_direction = observed_direction
		_direction_confirmation_elapsed = 0.0
	else:
		_direction_confirmation_elapsed += delta
	if _direction_confirmation_elapsed < direction_confirmation_time:
		return
	var turn_angle: float = rad_to_deg(
		_stable_player_direction.angle_to(_candidate_player_direction)
	)
	if turn_angle < 1.0:
		return
	_stable_player_direction = _candidate_player_direction
	_direction_confirmation_elapsed = 0.0
	if (
		_current_state == BehaviorState.FORMATION_WANDER
		or _current_state == BehaviorState.FORMATION_REPOSITION
	):
		if (
			turn_angle >= dash_turn_angle_threshold
			and _owner_body.can_dash()
		):
			var new_center: Vector3 = _calculate_raw_formation_center(
				_stable_player_direction
			)
			if (
				_horizontal_distance(_owner_body.global_position, new_center)
				>= dash_trigger_distance
			):
				_owner_body.request_dash(new_center + _wander_offset)
				_transition_to(BehaviorState.FORMATION_REPOSITION)


func _update_formation_center(delta: float) -> void:
	_raw_formation_center = _calculate_raw_formation_center(
		_stable_player_direction
	)
	var weight: float = 1.0 - exp(-formation_smoothness * delta)
	_smoothed_formation_center = _smoothed_formation_center.lerp(
		_raw_formation_center,
		weight
	)
	_wander_offset = _calculate_wander_offset_world()


func _calculate_raw_formation_center(direction: Vector3) -> Vector3:
	var player_right := Vector3(-direction.z, 0.0, direction.x)
	var center_offset: Vector2 = _get_formation_center_offset()
	return (
		_player.global_position
		+ player_right * center_offset.x
		+ direction * center_offset.y
	)


func _update_formation_idle_facing(delta: float) -> void:
	_facing_timer -= delta
	var horizontal_speed := Vector2(
		_owner_body.velocity.x,
		_owner_body.velocity.z
	).length()
	if horizontal_speed <= movement_facing_speed_threshold and _facing_timer <= 0.0:
		_owner_body.set_desired_facing(_stable_player_direction)
		_facing_timer = _random_generator.randf_range(
			minf(facing_update_interval_min, facing_update_interval_max),
			maxf(facing_update_interval_min, facing_update_interval_max)
		)


func _is_wander_target_refresh_due(delta: float) -> bool:
	_wander_timer -= delta
	return (
		_wander_timer <= 0.0
		and _horizontal_distance(
			_owner_body.global_position,
			_movement_target
		) <= _owner_body.slowing_distance
	)


func _reset_wander_timer() -> void:
	_wander_timer = _random_generator.randf_range(
		minf(wander_interval_min, wander_interval_max),
		maxf(wander_interval_min, wander_interval_max)
	)


func _initialize_formation_side() -> void:
	match _get_formation_side_mode():
		FormationPositionData.SideMode.LOCKED_RANDOM_SIDE:
			_apply_locked_side(_choose_random_side(), false)
		FormationPositionData.SideMode.FIXED_LEFT:
			_apply_locked_side(-1, false)
		FormationPositionData.SideMode.FIXED_RIGHT:
			_apply_locked_side(1, false)
		_:
			_apply_locked_side(0, false)
	_has_entered_locked_region = false
	_outside_locked_region_elapsed = 0.0


func _choose_random_side() -> int:
	return -1 if _random_generator.randf() < 0.5 else 1


func _apply_locked_side(new_side: int, refresh_target: bool) -> void:
	var normalized_side: int = clampi(new_side, -1, 1)
	var side_changed: bool = _locked_side != normalized_side
	_locked_side = normalized_side
	_has_entered_locked_region = false
	_outside_locked_region_elapsed = 0.0
	if refresh_target and _configured and is_instance_valid(_player):
		_select_new_formation_wander_target()
	if side_changed:
		formation_side_changed.emit(_locked_side)


func _calculate_wander_offset_world() -> Vector3:
	var player_right := Vector3(
		-_stable_player_direction.z,
		0.0,
		_stable_player_direction.x
	)
	return (
		player_right * _wander_lateral_value
		+ _stable_player_direction * _wander_longitudinal_value
	)


func _select_new_formation_wander_target() -> void:
	if not is_instance_valid(_player):
		return
	var occupied_positions: Array[Vector3] = (
		_collect_formation_occupied_positions()
	)
	var previous_local := Vector2(
		_wander_lateral_value,
		_wander_longitudinal_value
	)
	var selected_local: Vector2 = previous_local
	var best_local: Vector2 = previous_local
	var best_clearance: float = -1.0
	var has_best_candidate: bool = false
	var attempt_count: int = maxi(maximum_candidate_attempts, 1)
	var required_spacing: float = maxf(minimum_reserved_spacing, 0.0)
	var required_change: float = maxf(
		minimum_target_change_distance,
		0.0
	)

	for _attempt: int in range(attempt_count):
		var candidate_local: Vector2 = (
			_generate_formation_local_candidate()
		)
		var candidate_world: Vector3 = (
			_formation_local_candidate_to_world(candidate_local)
		)
		var clearance: float = _calculate_candidate_clearance(
			candidate_world,
			occupied_positions
		)
		if not has_best_candidate or clearance > best_clearance:
			best_local = candidate_local
			best_clearance = clearance
			has_best_candidate = true
		if (
			clearance >= required_spacing
			and candidate_local.distance_to(previous_local)
				>= required_change
		):
			selected_local = candidate_local
			has_best_candidate = false
			break

	## 所有候选都拥挤或变化不足时，不把单位强推到区域外；使用本轮最宽松候选。
	if has_best_candidate:
		selected_local = best_local

	_wander_lateral_value = selected_local.x
	_wander_longitudinal_value = selected_local.y
	_wander_offset = _calculate_wander_offset_world()
	_movement_target = _constrain_target(
		_smoothed_formation_center + _wander_offset
	)
	_reset_wander_timer()


## 生成一个资源局部坐标中的 Formation 候选点，不查询其他单位。
##
## Vector2.x 表示左右，Vector2.y 表示前后；该方法独立后可在测试中替换随机来源，
## 而占用判断仍运行真实实现。
func _generate_formation_local_candidate() -> Vector2:
	var lateral_radius: float = _get_formation_lateral_radius()
	var lateral_minimum: float = minf(
		_get_formation_lateral_minimum(),
		lateral_radius
	)
	var forward_radius: float = _get_formation_forward_radius()
	if (
		_get_formation_side_mode()
		== FormationPositionData.SideMode.FREE_CROSSING
	):
		var angle: float = _random_generator.randf_range(0.0, TAU)
		var radius: float = sqrt(_random_generator.randf())
		var lateral: float = cos(angle) * radius * lateral_radius
		var longitudinal: float = sin(angle) * radius * forward_radius
		if (
			lateral_minimum > 0.0
			and absf(lateral) < lateral_minimum
		):
			lateral = (
				-1.0 if lateral < 0.0 else 1.0
			) * lateral_minimum
		return Vector2(lateral, longitudinal)

	if _locked_side == 0:
		_locked_side = _choose_random_side()
	return Vector2(
		_random_generator.randf_range(
			lateral_minimum,
			lateral_radius
		) * float(_locked_side),
		_random_generator.randf_range(
			-forward_radius,
			forward_radius
		)
	)


func _formation_local_candidate_to_world(
	candidate_local: Vector2
) -> Vector3:
	var player_right := Vector3(
		-_stable_player_direction.z,
		0.0,
		_stable_player_direction.x
	)
	return _constrain_target(
		_smoothed_formation_center
		+ player_right * candidate_local.x
		+ _stable_player_direction * candidate_local.y
	)


## 返回候选点到最近占用位置的水平距离；没有占用时返回 INF。
func _calculate_candidate_clearance(
	candidate_world: Vector3,
	occupied_positions: Array[Vector3]
) -> float:
	var clearance: float = INF
	for occupied_position: Vector3 in occupied_positions:
		clearance = minf(
			clearance,
			_horizontal_distance(
				candidate_world,
				occupied_position
			)
		)
	return clearance


## 仅在原 Formation 游荡刷新时扫描一次同队 AI 的实际和预定位置。
func _collect_formation_occupied_positions() -> Array[Vector3]:
	var occupied_positions: Array[Vector3] = []
	if (
		not is_instance_valid(_owner_body)
		or _owner_body.team_id == 0
	):
		return occupied_positions
	var scene_root: Node = get_tree().current_scene
	if not is_instance_valid(scene_root):
		scene_root = get_tree().root
	_append_same_team_ai_occupancy(
		scene_root,
		occupied_positions
	)
	return occupied_positions


func _append_same_team_ai_occupancy(
	node: Node,
	occupied_positions: Array[Vector3]
) -> void:
	var ai_unit := node as AIUnitBase
	if (
		ai_unit != null
		and ai_unit != _owner_body
		and ai_unit.team_id != 0
		and ai_unit.team_id == _owner_body.team_id
	):
		occupied_positions.append(ai_unit.global_position)
		var ally_unit := ai_unit as AllyBase
		if ally_unit != null:
			var behavior := (
				ally_unit.get_behavior_state_machine()
			)
			if (
				behavior != null
				and _state_uses_formation_position(
					behavior.get_current_state()
				)
			):
				occupied_positions.append(
					behavior.get_current_movement_target()
				)
	for child: Node in node.get_children():
		_append_same_team_ai_occupancy(
			child,
			occupied_positions
		)


func _state_uses_formation_position(
	state: BehaviorState
) -> bool:
	return (
		state == BehaviorState.FORMATION_WANDER
		or state == BehaviorState.FORMATION_REPOSITION
		or state == BehaviorState.RETURN
	)


func _update_formation_side_lock(delta: float) -> void:
	if (
		_get_formation_side_mode()
		!= FormationPositionData.SideMode.LOCKED_RANDOM_SIDE
	):
		return
	var player_right := Vector3(
		-_stable_player_direction.z,
		0.0,
		_stable_player_direction.x
	)
	var relative_position: Vector3 = (
		_owner_body.global_position - _raw_formation_center
	)
	relative_position.y = 0.0
	var lateral_position: float = relative_position.dot(player_right)
	var longitudinal_position: float = relative_position.dot(
		_stable_player_direction
	)
	var signed_lateral: float = lateral_position * float(_locked_side)
	var minimum_lateral: float = minf(
		_get_formation_lateral_minimum(),
		_get_formation_lateral_radius()
	)
	var inside_inner: bool = (
		signed_lateral >= minimum_lateral
		and signed_lateral <= _get_formation_lateral_radius()
		and absf(longitudinal_position)
			<= _get_formation_forward_radius()
	)
	if inside_inner:
		_has_entered_locked_region = true
		_outside_locked_region_elapsed = 0.0
		return
	if not _has_entered_locked_region:
		return
	var inside_outer: bool = (
		signed_lateral >= maxf(minimum_lateral - formation_exit_margin, 0.0)
		and signed_lateral
			<= _get_formation_lateral_radius() + formation_exit_margin
		and absf(longitudinal_position)
			<= _get_formation_forward_radius() + formation_exit_margin
	)
	if inside_outer:
		_outside_locked_region_elapsed = 0.0
		return
	_outside_locked_region_elapsed += delta
	if _outside_locked_region_elapsed >= side_reselection_delay:
		_apply_locked_side(_choose_random_side(), true)


## 检查运行时传入的资源是否能安全参与随机范围和坐标计算。
func _is_valid_formation_position_data(
	data: FormationPositionData
) -> bool:
	return (
		data != null
		and data.center_offset.is_finite()
		and data.lateral_radius >= 0.0
		and data.lateral_minimum >= 0.0
		and data.forward_radius >= 0.0
		and int(data.side_mode)
			>= int(FormationPositionData.SideMode.FREE_CROSSING)
		and int(data.side_mode)
			<= int(FormationPositionData.SideMode.FIXED_RIGHT)
	)


func _get_formation_center_offset() -> Vector2:
	if _is_valid_formation_position_data(formation_position):
		return formation_position.center_offset
	return DEFAULT_FORMATION_CENTER_OFFSET


func _get_formation_lateral_radius() -> float:
	if _is_valid_formation_position_data(formation_position):
		return maxf(formation_position.lateral_radius, 0.0)
	return DEFAULT_LATERAL_RADIUS


func _get_formation_lateral_minimum() -> float:
	if _is_valid_formation_position_data(formation_position):
		return maxf(formation_position.lateral_minimum, 0.0)
	return DEFAULT_LATERAL_MINIMUM


func _get_formation_forward_radius() -> float:
	if _is_valid_formation_position_data(formation_position):
		return maxf(formation_position.forward_radius, 0.0)
	return DEFAULT_FORWARD_RADIUS


func _get_formation_side_mode() -> FormationPositionData.SideMode:
	if _is_valid_formation_position_data(formation_position):
		return formation_position.side_mode
	return DEFAULT_SIDE_MODE


func _is_formation_or_return_state() -> bool:
	return (
		_current_state == BehaviorState.FORMATION_WANDER
		or _current_state == BehaviorState.FORMATION_REPOSITION
		or _current_state == BehaviorState.RETURN
	)


## 仅在进入 Formation/Return 后应用 Combat 期间暂存的位置选择。
func _apply_pending_formation_position() -> void:
	if (
		not _formation_position_pending_apply
		or not _is_formation_or_return_state()
		or not is_instance_valid(_player)
	):
		return
	_initialize_formation_side()
	_combat_wander_target_valid = false
	_refresh_formation_center_immediately()
	_formation_position_pending_apply = false
	if _current_state == BehaviorState.RETURN:
		_movement_target = _constrain_target(_smoothed_formation_center)
	else:
		_select_new_formation_wander_target()


## 重新计算当前资源对应的中心并立即同步平滑中心。
##
## 该方法只从 Formation/Return 路径调用，避免 Combat 逐帧读取阵型资源。
func _refresh_formation_center_immediately() -> void:
	if not is_instance_valid(_player):
		return
	_raw_formation_center = _calculate_raw_formation_center(
		_stable_player_direction
	)
	_smoothed_formation_center = _raw_formation_center
	_wander_offset = _calculate_wander_offset_world()


func _constrain_target(target_position: Vector3) -> Vector3:
	target_position.y = _player.global_position.y
	return target_position


func _horizontal_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()
