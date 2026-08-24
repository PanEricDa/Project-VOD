class_name UnitBase
extends CharacterBody3D

const STATUS_EFFECT_COMPONENT_PATH: NodePath = ^"StatusEffect"
const STATUS_ATTACK_POWER: int = 0
const STATUS_DEFENSE: int = 1

## 所有可行动单位共用的最小根类。
##
## 本脚本只负责“单位是什么”的基础信息：生命值、阵营关系和能否成为目标。
## 移动、AI、技能、动画和装备应由继承场景或独立组件提供，避免 UnitBase
## 随项目发展逐渐变成难以维护的全能脚本。

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


## 对单位造成伤害并返回实际扣除量。
## 负数、零以及对死亡单位的重复伤害都会被忽略；一次致命伤害只触发一次 died。
## 参数 _threat_multiplier 由伤害发起链携带给敌方覆盖实现；UnitBase 本身不记录仇恨，因此该参数不会改变生命、受击或死亡行为。普通调用默认 1.0。
func apply_damage(
	amount: float,
	source: Node = null,
	_threat_multiplier: float = 1.0
) -> float:
	if amount <= 0.0 or is_dead():
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


## 返回当前运行时生命值。
func get_current_health() -> float:
	return _current_health


## 返回生命值上限，供 UI、技能条件和未来状态系统统一读取。
func get_maximum_health() -> float:
	return maximum_health


## 返回运行时安全的攻击力，负值统一钳制为零以保证战斗公式稳定。
func get_attack_power() -> float:
	var status_effects := get_status_effect_component()
	var modifier_total: float = (
		float(status_effects.call(&"get_modifier_total", STATUS_ATTACK_POWER))
		if is_instance_valid(status_effects)
		else 0.0
	)
	return maxf(attack_power + modifier_total, 0.0)


## 返回运行时安全的防御力，负值统一钳制为零以保证减伤系数有效。
func get_defense() -> float:
	var status_effects := get_status_effect_component()
	var modifier_total: float = (
		float(status_effects.call(&"get_modifier_total", STATUS_DEFENSE))
		if is_instance_valid(status_effects)
		else 0.0
	)
	return maxf(defense + modifier_total, 0.0)


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
