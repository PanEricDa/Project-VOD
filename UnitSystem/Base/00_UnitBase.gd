class_name UnitBase
extends CharacterBody3D

const STATUS_EFFECT_COMPONENT_PATH: NodePath = ^"StatusEffect"
const STATUS_ATTACK_POWER: int = 0
const STATUS_DEFENSE: int = 1
const STATUS_OUTGOING_DAMAGE: int = 3

## 所有可行动单位共用的最小根类。
##
## 本脚本负责生命、阵营、目标资格及内置被动位移协议；不执行主动移动或AI。
## 外力仅保存请求，实际物理移动仍由PlayerBase/AIUnitBase各自原循环完成。

## 生命值发生实际变化时发送。source 用于记录伤害或治疗的来源；没有来源时为 null。
enum CombatState {
	OUT_OF_COMBAT,
	IN_COMBAT,
}

## 单位进入或离开通用战斗生命周期时发送。具体的索敌、攻击和脱战规则仍由各自控制器决定。
signal combat_state_changed(
	previous_state: CombatState,
	current_state: CombatState
)

signal health_changed(
	previous_health: float,
	current_health: float,
	maximum_health: float,
	source: Node
)
## 单位受到有效伤害时发送，amount 是扣除上限修正后的实际伤害量。
signal damaged(amount: float, source: Node)
## 权威实际扣血事件；event 为只读来源/数值快照，仅正伤害发布一次，不替代旧生命信号。
signal damage_resolved(event: CombatDamageEvent)
## 单位获得有效治疗时发送，amount 是生命上限修正后的实际治疗量。
signal healed(amount: float, source: Node)
## 生命值第一次从大于零降至零时发送。
signal died(source: Node)
## 已死亡单位通过 revive() 恢复时发送。
signal revived(current_health: float, source: Node)

@export_category("Health")
## 单位的生命值上限。运行时会确保该值不低于零。
@export_range(0.0, 1000000.0, 1.0, "or_greater")
var maximum_health: float = 100.0
## 场景进入运行树时的初始生命百分比。
## Inspector 使用 0%～100% 滑块；运行时会乘以 maximum_health 得到实际初始生命。
@export_range(0.0, 100.0, 1.0, "suffix:%")
var starting_health_percentage: float = 100.0
## 是否允许该单位进入死亡生命周期；默认 true 保持正常死亡、死亡动画与删除规则。
## 设为 false 时，任何伤害最多把生命降至 1 点，不会发送 died 或触发死亡相关系统。
@export var can_die: bool = true

@export_category("Combat Stats")
## 单位的基础攻击力；统一结算器通过 getter 读取，以避免运行时负值参与计算。
@export_range(0.0, 1000000.0, 0.1, "or_greater")
var attack_power: float = 10.0
## 单位的基础防御力；统一结算器通过 getter 读取，以避免运行时负值导致异常减伤。
@export_range(0.0, 1000000.0, 0.1, "or_greater")
var defense: float = 0.0

@export_category("Threat")
## 本单位作为新挑战者时夺回敌人目标所需的本地仇恨倍率；单位为相对当前目标仇恨的倍数，默认 1.25 表示必须严格超过 125%。
## 该参数只影响本单位主动挑战敌人当前目标时的换目标门槛，不影响自身被锁定时其他单位的判定，也不改变仇恨累加量。
@export_range(1.0, 10.0, 0.01, "or_greater")
var threat_takeover_ratio: float = 1.25
## 本单位相对仇恨达到 125% 时，AI 主动暂缓一次技能或普攻的概率；取值为 0.0 至 0.89。
## 默认 0.7 表示 125% 时有 70% 概率暂缓，超过后会向 90% 平滑收敛但永不达到；设为 0 可关闭该行为，
## 适合坦克职业。该值仅由友方 AI 的行动许可层读取，不修改仇恨累积、目标选择、伤害或玩家操作。
@export_range(0.0, 0.89, 0.01)
var threat_action_suppression_at_125: float = 0.7

@export_category("Hit Reaction")
## 单位每次承受有效且非致命伤害后禁止水平移动的持续时间，单位为秒。
## 默认 0.07 秒；设为 0 会关闭受击停顿。该值由 UnitBase 统一维护，
## PlayerBase 与 AIUnitBase 只读取状态暂停移动，不会暂停重力、碰撞、动画或技能计时。
@export_range(0.0, 1.0, 0.01)
var hit_movement_lock_duration: float = 0.07

@export_category("Forced Movement")
## 是否允许接收被动位移，默认true，影响全部外力请求，不限制自身移动/动画位移。
## 关闭立即结束当前请求并恢复其新增单位碰撞例外；重新开启不恢复旧请求。
@export var forced_movement_enabled: bool = true:
	set(value):
		forced_movement_enabled = value
		if not value:
			_finish_forced_movement(_forced_active_token, &"disabled")

@export_category("Faction")
## 供编辑器、存档和调试使用的可读阵营标识。
## 当前关系判断只使用 team_id，因此更改显示标识不会意外改变敌我关系。
@export_enum("Neutral", "Player", "Ally", "Enemy")
var faction_id: String = "Neutral"
## 实际用于敌我判断的队伍编号。0 表示中立；相同的非零编号为友方，不同则为敌方。
@export var team_id: int = 0
## 控制索敌或技能系统是否可以把此单位作为目标。
@export var targetable: bool = true

## 当前生命值属于运行时状态，不导出为场景配置，防止它与初始百分比形成两个编辑入口。
var _current_health: float = 0.0
## 非导出的通用战斗生命周期状态，供玩家、友方与敌方的各自逻辑统一读取。
var _combat_state: CombatState = CombatState.OUT_OF_COMBAT
## 受击后剩余的水平移动禁止时间，单位为秒。
## 这是运行时状态而非场景配置；重复受击仅刷新至单次时长，不会无限叠加。
var _hit_movement_lock_remaining: float = 0.0


func _ready() -> void:
	# 在单位进入场景树时建立唯一的运行时生命状态。
	# 这里不发送信号，因为它属于初始化而不是一次治疗或伤害事件。
	maximum_health = maxf(maximum_health, 1.0 if not can_die else 0.0)
	starting_health_percentage = clampf(starting_health_percentage, 0.0, 100.0)
	_current_health = maximum_health * starting_health_percentage / 100.0
	if not died.is_connected(_on_forced_movement_owner_died):
		died.connect(_on_forced_movement_owner_died)


## 对单位造成伤害并返回实际扣除量。
## 负数、零以及对死亡单位的重复伤害都会被忽略；一次致命伤害只触发一次 died。
## damage_context 为可选来源快照，默认未知来源且无专注收益；不修改实际伤害与旧信号。
## 参数 _threat_multiplier 由伤害发起链携带给敌方覆盖实现；UnitBase 本身不记录仇恨，因此该参数不会改变生命、受击或死亡行为。普通调用默认 1.0。
func apply_damage(
	amount: float,
	source: Node = null,
	_threat_multiplier: float = 1.0,
	damage_context: CombatDamageContext = null
) -> float:
	if not is_finite(amount) or amount <= 0.0 or is_dead():
		return 0.0

	var previous_health: float = _current_health
	var minimum_health: float = 0.0 if can_die else 1.0
	var applied_amount: float = minf(
		amount,
		maxf(previous_health - minimum_health, 0.0)
	)
	if applied_amount <= 0.0:
		return 0.0
	_current_health = maxf(previous_health - applied_amount, minimum_health)

	var provenance := damage_context
	if provenance == null:
		var scope: Node = get_tree().current_scene if is_inside_tree() else null
		provenance = CombatDamageContext.create(source, scope, CombatDamageContext.Origin.UNATTRIBUTED)
	var event := CombatDamageEvent.create(provenance, self, previous_health, _current_health)
	if event != null:
		damage_resolved.emit(event)

	health_changed.emit(previous_health, _current_health, maximum_health, source)
	damaged.emit(applied_amount, source)
	if previous_health > 0.0 and is_dead():
		exit_combat()
		died.emit(source)
	else:
		_start_hit_movement_lock()
	return applied_amount


## 返回单位当前是否因一次有效受击而被短暂停止水平移动。
## 该状态只表达“移动执行层应暂停”，不会阻断重力、碰撞、面向、动画或其他计时逻辑。
func is_hit_movement_locked() -> bool:
	return _hit_movement_lock_remaining > 0.0


## 推进受击停顿的剩余时间。
## delta 应传入所属移动控制器的物理帧间隔；PlayerBase 与 AIUnitBase 每个物理帧各调用一次，
## 以保证所有可移动单位采用同一时长规则。传入非正数时不会改变当前状态。
func advance_hit_movement_lock(delta: float) -> void:
	if delta <= 0.0 or _hit_movement_lock_remaining <= 0.0:
		return
	_hit_movement_lock_remaining = maxf(_hit_movement_lock_remaining - delta, 0.0)


## 以当前 Inspector 配置启动或刷新一次受击移动停顿。
## 同帧多次伤害只保留较长剩余时间，避免多目标命中把短反馈错误堆叠成硬控。
func _start_hit_movement_lock() -> void:
	_hit_movement_lock_remaining = maxf(
		_hit_movement_lock_remaining,
		maxf(hit_movement_lock_duration, 0.0)
	)


## 治疗存活单位并返回实际恢复量。
## 常规治疗不会复活死亡单位；需要复活时必须显式调用 revive()，让技能语义保持清晰。
func apply_healing(amount: float, source: Node = null) -> float:
	if amount <= 0.0 or is_dead():
		return 0.0

	var previous_health: float = _current_health
	var applied_amount: float = minf(amount, maximum_health - previous_health)
	if applied_amount <= 0.0:
		return 0.0

	_current_health = previous_health + applied_amount
	health_changed.emit(previous_health, _current_health, maximum_health, source)
	healed.emit(applied_amount, source)
	return applied_amount


## 以指定生命值复活单位。
## 仅死亡单位可以复活；成功返回 true。传入非正数时仍会恢复一个极小的正生命值，
## 确保“复活成功”不会在同一帧仍被 is_dead() 判断为死亡。
func revive(health_amount: float = 1.0, source: Node = null) -> bool:
	if not is_dead() or maximum_health <= 0.0:
		return false

	var previous_health: float = _current_health
	_current_health = clampf(maxf(health_amount, 0.001), 0.001, maximum_health)
	health_changed.emit(previous_health, _current_health, maximum_health, source)
	revived.emit(_current_health, source)
	return true


## 返回单位稳定的世界水平朝向；优先直接Visual的-Z，忽略CharacterRoot/武器姿态动画。
## 无Visual或轴退化时依次回退单位根-Z、Vector3.FORWARD；不修改转向或移动。
func get_facing_direction() -> Vector3:
	var visual := get_node_or_null(^"Visual") as Node3D
	var forward := -visual.global_basis.z if is_instance_valid(visual) else Vector3.ZERO
	forward.y = 0.0
	if not forward.is_finite() or forward.length_squared() < 0.000001:
		forward = -global_basis.z
		forward.y = 0.0
	return forward.normalized() if forward.is_finite() and forward.length_squared() >= 0.000001 else Vector3.FORWARD


## 返回当前运行时生命值。
func get_current_health() -> float:
	return _current_health


## 返回生命值上限，供 UI、技能条件和未来状态系统统一读取。
func get_maximum_health() -> float:
	return maximum_health


## 返回所有伤害共用的输出倍率；基础为1，状态可按百分比增减，不改变攻击力或治疗。
func get_outgoing_damage_multiplier() -> float:
	var status_effects := get_status_effect_component()
	return float(status_effects.call(&"get_modified_value", STATUS_OUTGOING_DAMAGE, 1.0)) if is_instance_valid(status_effects) else 1.0


## 返回运行时安全的攻击力，负值统一钳制为零以保证战斗公式稳定。
func get_attack_power() -> float:
	var status_effects := get_status_effect_component()
	return float(status_effects.call(&"get_modified_value", STATUS_ATTACK_POWER, attack_power)) if is_instance_valid(status_effects) else maxf(attack_power, 0.0)


## 由状态容器统一汇总固定修正与百分比倍率；防御不低于0，不改写基础配置。
func get_defense() -> float:
	var status_effects := get_status_effect_component()
	return float(status_effects.call(&"get_modified_value", STATUS_DEFENSE, defense)) if is_instance_valid(status_effects) else maxf(defense, 0.0)


## 返回本单位作为挑战者时可用于敌方目标切换的安全仇恨倍率；运行时会限制为不低于 1.0，避免低于当前目标即可抢占的异常配置。
func get_threat_takeover_ratio() -> float:
	return maxf(threat_takeover_ratio, 1.0)


## 返回该单位已装配的临时状态效果容器。## 未装配、节点失效或用于极简测试单位时安全返回 null；调用方不得自行替换该节点。
func get_status_effect_component() -> Node:
	return get_node_or_null(STATUS_EFFECT_COMPONENT_PATH)


## 返回 0 到 1 的生命比例。生命上限为零时安全返回 0，避免除零错误。
func get_health_ratio() -> float:
	if maximum_health <= 0.0:
		return 0.0
	return clampf(_current_health / maximum_health, 0.0, 1.0)


## 标记单位已进入战斗。死亡单位不能重新进入战斗，重复调用不会重复发送信号。
func enter_combat() -> void:
	if is_dead() or _combat_state == CombatState.IN_COMBAT:
		return
	_set_combat_state(CombatState.IN_COMBAT)


## 标记单位已离开战斗。该接口可被任何单位专属控制器安全重复调用。
func exit_combat() -> void:
	if _combat_state == CombatState.OUT_OF_COMBAT:
		return
	_set_combat_state(CombatState.OUT_OF_COMBAT)


## 返回当前是否处于通用战斗生命周期。
func is_in_combat() -> bool:
	return _combat_state == CombatState.IN_COMBAT


## 返回当前通用战斗状态枚举，供 UI 与调试工具进行只读查询。
func get_combat_state() -> CombatState:
	return _combat_state


func _set_combat_state(next_state: CombatState) -> void:
	if _combat_state == next_state:
		return
	var previous_state := _combat_state
	_combat_state = next_state
	combat_state_changed.emit(previous_state, _combat_state)


## 当前生命值不大于零时视为死亡。
func is_dead() -> bool:
	return _current_health <= 0.0


## 返回此单位当前是否允许被选为目标。
func is_targetable() -> bool:
	return targetable and not is_dead()


## 判断另一个单位是否为友方。
## 中立队伍 0 不会互相成为友方，避免所有无阵营对象被错误归为同一阵营。
func is_friendly_to(other_value: Variant) -> bool:
	if not is_instance_valid(other_value) or not other_value is UnitBase:
		return false
	var other := other_value as UnitBase
	return (
		team_id != 0
		and other.team_id != 0
		and team_id == other.team_id
	)


## 判断另一个单位是否为敌方。
## 只有双方都属于非零队伍且编号不同，才会建立敌对关系。
func is_hostile_to(other_value: Variant) -> bool:
	if not is_instance_valid(other_value) or not other_value is UnitBase:
		return false
	var other := other_value as UnitBase
	return (
		team_id != 0
		and other.team_id != 0
		and team_id != other.team_id
	)


## 判断关系是否为中立。任意一方 team_id 为 0 时即为中立关系。
func is_neutral_to(other_value: Variant) -> bool:
	if not is_instance_valid(other_value) or not other_value is UnitBase:
		return false
	var other := other_value as UnitBase
	return team_id == 0 or other.team_id == 0


## 内置被动位移：只保存一个请求，由Player/AI原物理循环消费，不自行移动或计时。
## token为本单位递增正身份。通知前提交状态，旧取消/同步回调不会清除新请求。
signal forced_movement_started(token: int)
## reason为arrived/elapsed/blocked/replaced/cancelled/source_invalid/owner_invalid/disabled；disabled表示根开关关闭。
## 终态仅代表本次物理请求结束；阻挡时不保证已到达期望点。
signal forced_movement_finished(token: int, reason: StringName)

var _forced_next_token: int = 0
var _forced_active_token: int = 0
var _forced_source: WeakRef
var _forced_start := Vector3.ZERO
var _forced_destination := Vector3.ZERO
var _forced_duration: float = 0.0
var _forced_elapsed: float = 0.0
var _forced_ignore_unit_collisions: bool = false
var _forced_unit_exceptions: Dictionary[int, WeakRef] = {}
var _forced_collision_tree: SceneTree
var _forced_accepting_requests: bool = false

func _enter_tree() -> void:
	_forced_accepting_requests = true

## 本单位必须在树内且未退出；source必须为在树内存活单位；destination为有限世界坐标，仅XZ生效。
## duration_seconds为正的战斗秒；返回正token代表接受，0为拒绝且保留旧请求；适用于UnitBase，实际运动由Player/AI已有物理循环消费。
## ignore_unit_collisions默认false保留通常碰撞；true在本次请求期间仅忽略UnitBase身体，所有终态恢复自身新增的例外。
func request_forced_movement(source: UnitBase, destination: Vector3, duration_seconds: float, ignore_unit_collisions: bool = false) -> int:
	var body: UnitBase = self
	if not forced_movement_enabled or not _forced_accepting_requests or not is_inside_tree() or not _is_forced_unit_live(body) or not _is_forced_unit_live(source) or not destination.is_finite() or not is_finite(duration_seconds) or duration_seconds <= 0.0 or is_queued_for_deletion():
		return 0
	var previous := _forced_active_token
	_forced_next_token += 1
	var accepted := _forced_next_token
	_forced_active_token = accepted
	_forced_source = weakref(source)
	_forced_start = body.global_position
	_forced_destination = Vector3(destination.x, _forced_start.y, destination.z)
	_forced_duration = duration_seconds
	_forced_elapsed = 0.0
	_set_forced_unit_collision_exclusion(ignore_unit_collisions)
	# 新状态先建立；替换通知内再次请求时，新者自然胜出，不在回调后回写旧状态。
	if previous > 0:
		forced_movement_finished.emit(previous, &"replaced")
	if _forced_active_token == accepted:
		forced_movement_started.emit(accepted)
	return accepted

## 纯查询：是否有尚未结束的请求，不推进或隐式校验时间。
func is_forced_movement_active() -> bool:
	return _forced_active_token > 0

## 返回当前正身份，无请求返回0；调用者回报/取消时必须携带捕获的身份。
func get_forced_movement_token() -> int:
	return _forced_active_token

## 每Player/AI物理帧检查来源和目标生命周期；不推进计时，受击锁期间仍应调用。
func _validate_forced_movement() -> void:
	if not is_forced_movement_active():
		return
	if not _is_forced_unit_live(self):
		_finish_forced_movement(_forced_active_token, &"owner_invalid")
	elif _forced_source == null or not _is_forced_unit_live(_forced_source.get_ref() as UnitBase):
		_finish_forced_movement(_forced_active_token, &"source_invalid")

## delta为本物理帧战斗秒，只在外力分支消费一次；返回下一期望点到实际位置的XZ米数。
## 不直接改位置，不另乘世界流速；末帧由_report_forced_movement_result结算。
func _consume_forced_movement_step(delta: float) -> Vector3:
	if not is_forced_movement_active() or not is_finite(delta) or delta <= 0.0:
		return Vector3.ZERO
	var body: UnitBase = self
	if not _is_forced_unit_live(body):
		return Vector3.ZERO
	_forced_elapsed = minf(_forced_elapsed + delta, _forced_duration)
	var point := _forced_start.lerp(_forced_destination, _forced_elapsed / _forced_duration)
	var step := point - body.global_position
	step.y = 0.0
	return step

## 唯一move_and_slide后回报原token、实际位移米数和水平碰撞；旧身份无效。
## 被挡立即结束，到期不补瞬移；未抵达用elapsed区分，不伪报arrived。
func _report_forced_movement_result(token: int, actual_displacement: Vector3, blocked: bool) -> void:
	if token <= 0 or token != _forced_active_token:
		return
	_validate_forced_movement()
	if token != _forced_active_token:
		return
	if not actual_displacement.is_finite() or blocked:
		_finish_forced_movement(token, &"blocked")
		return
	var body: UnitBase = self
	var remaining := _forced_destination - body.global_position
	remaining.y = 0.0
	if remaining.length_squared() <= 0.0001:
		_finish_forced_movement(token, &"arrived")
	elif _forced_elapsed >= _forced_duration:
		_finish_forced_movement(token, &"elapsed")

## 仅取消匹配的正token；重复/旧请求取消不影响当前请求。
func cancel_forced_movement(token: int) -> void:
	_finish_forced_movement(token, &"cancelled")

## 仅收束匹配的当前token；reason为稳定终态分类，先清状态/新增例外/水平速度再通知，允许回调安全重入。
func _finish_forced_movement(token: int, reason: StringName) -> void:
	if token <= 0 or token != _forced_active_token:
		return
	_forced_active_token = 0
	_forced_source = null
	_forced_elapsed = 0.0
	_forced_duration = 0.0
	# 先恢复本请求临时忽略的单位碰撞，再发终态通知；回调重入可建立自己的新例外。
	_set_forced_unit_collision_exclusion(false)
	var body: UnitBase = self
	if is_instance_valid(body):
		body.velocity.x = 0.0
		body.velocity.z = 0.0
	forced_movement_finished.emit(token, reason)

# 仅操作本请求新添加的按身体例外，不改collision_layer/mask，也不关闭Collider或技能命中Area。
# 启动时扫描一次；之后只监听新增节点，不为每个被拉单位逐物理帧扫描整棵场景。
func _set_forced_unit_collision_exclusion(enabled: bool) -> void:
	if enabled == _forced_ignore_unit_collisions:
		return
	_forced_ignore_unit_collisions = enabled
	if enabled:
		_forced_collision_tree = get_tree()
		if not _forced_collision_tree.node_added.is_connected(_on_forced_collision_node_added):
			_forced_collision_tree.node_added.connect(_on_forced_collision_node_added)
		if not _forced_collision_tree.node_removed.is_connected(_on_forced_collision_node_removed):
			_forced_collision_tree.node_removed.connect(_on_forced_collision_node_removed)
		_collect_forced_unit_collision_exceptions(_forced_collision_tree.root)
		return
	if is_instance_valid(_forced_collision_tree) and _forced_collision_tree.node_added.is_connected(_on_forced_collision_node_added):
		_forced_collision_tree.node_added.disconnect(_on_forced_collision_node_added)
	if is_instance_valid(_forced_collision_tree) and _forced_collision_tree.node_removed.is_connected(_on_forced_collision_node_removed):
		_forced_collision_tree.node_removed.disconnect(_on_forced_collision_node_removed)
	_forced_collision_tree = null
	var body: UnitBase = self
	if is_instance_valid(body):
		for reference: WeakRef in _forced_unit_exceptions.values():
			var other := reference.get_ref() as PhysicsBody3D
			if is_instance_valid(other):
				body.remove_collision_exception_with(other)
	_forced_unit_exceptions.clear()

func _collect_forced_unit_collision_exceptions(node: Node) -> void:
	_on_forced_collision_node_added(node)
	for child: Node in node.get_children():
		_collect_forced_unit_collision_exceptions(child)

func _on_forced_collision_node_added(node: Node) -> void:
	if not _forced_ignore_unit_collisions or not node is UnitBase:
		return
	var body: UnitBase = self
	var other := node as UnitBase
	if not is_instance_valid(body) or other == body or other.is_queued_for_deletion() or not other.is_inside_tree() or body.get_world_3d() != other.get_world_3d():
		return
	var id := other.get_instance_id()
	if _forced_unit_exceptions.has(id) or body.get_collision_exceptions().has(other):
		return
	body.add_collision_exception_with(other)
	_forced_unit_exceptions[id] = weakref(other)

# UnitBase离树时其物理RID尚存，立即撤销自己添加的例外；不能等弱引用失效后才处理，
# 否则Jolt的例外列表会保留已销毁RID，后续查询get_collision_exceptions将报空body。
func _on_forced_collision_node_removed(node: Node) -> void:
	var id := node.get_instance_id()
	if not _forced_unit_exceptions.has(id):
		return
	_forced_unit_exceptions.erase(id)
	var body: UnitBase = self
	if is_instance_valid(body) and node is PhysicsBody3D:
		body.remove_collision_exception_with(node as PhysicsBody3D)

func _is_forced_unit_live(unit: UnitBase) -> bool:
	return is_instance_valid(unit) and unit.is_inside_tree() and not unit.is_queued_for_deletion() and not unit.is_dead()

func _exit_tree() -> void:
	# 在终态通知前关闭入口：父单位可能仍在树内，但离树回调不得重建碰撞例外。
	_forced_accepting_requests = false
	_finish_forced_movement(_forced_active_token, &"owner_invalid")

func _on_forced_movement_owner_died(_source_unit: Node) -> void:
	_finish_forced_movement(_forced_active_token, &"owner_invalid")
