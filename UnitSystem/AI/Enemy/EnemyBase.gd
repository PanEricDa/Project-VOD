class_name EnemyBase
extends AIUnitBase

## 敌方单位父类：装配通用索敌、战斗与敌方状态机，不在此复制移动或攻击算法。

signal locked_target_changed(previous_target: UnitBase, current_target: UnitBase)
signal behavior_state_changed(
	previous_state: EnemyBehaviorStateMachine.State,
	current_state: EnemyBehaviorStateMachine.State
)

@onready var _behavior_state_machine: EnemyBehaviorStateMachine = $BehaviorStateMachine
@onready var _threat_component: Node = $ThreatComponent

## 统一仇恨事件脚本。
## EnemyBase 只负责把实际伤害转换为事件并提交；仇恨数值与表的修改仍完全由 ThreatComponent 管理。
const THREAT_EVENT_SCRIPT := preload(
	"res://UnitSystem/Components/Threat/ThreatEvent.gd"
)


func _ready() -> void:
	super._ready()
	if not is_instance_valid(_targeting_component):
		push_error("EnemyBase: AITargetingComponent is missing. Node=" + str(get_path()))
		return
	if not is_instance_valid(_threat_component):
		push_error("EnemyBase: ThreatComponent is missing. Node=" + str(get_path()))
	elif not bool(_threat_component.call("configure", self)):
		push_error(
			"EnemyBase: ThreatComponent configuration failed. Node="
			+ str(get_path())
		)
	else:
		_targeting_component.set_target_decision_provider(_threat_component)
		var threat_callback := Callable(self, "_on_threat_changed")
		if (
			_threat_component.has_signal(&"threat_changed")
			and not _threat_component.is_connected(&"threat_changed", threat_callback)
		):
			_threat_component.connect(&"threat_changed", threat_callback)
	if not _targeting_component.locked_target_changed.is_connected(_on_locked_target_changed):
		_targeting_component.locked_target_changed.connect(_on_locked_target_changed)
	if not is_instance_valid(_behavior_state_machine):
		push_error("EnemyBase: BehaviorStateMachine is missing. Node=" + str(get_path()))
		return
	if not _behavior_state_machine.configure(self, _targeting_component, get_combat_system()):
		push_error("EnemyBase: BehaviorStateMachine configuration failed. Node=" + str(get_path()))
		return
	if not _behavior_state_machine.state_changed.is_connected(_on_behavior_state_changed):
		_behavior_state_machine.state_changed.connect(_on_behavior_state_changed)


func _update_ai_movement(delta: float) -> void:
	if is_instance_valid(_behavior_state_machine):
		_behavior_state_machine.physics_tick(delta)
	else:
		super._update_ai_movement(delta)


func get_targeting_component() -> AITargetingComponent:
	return _targeting_component if is_instance_valid(_targeting_component) else null


## 注入由 EncounterController 提供的同 Pack 目标兜底查询。
## resolver 接受请求目标的 EnemyBase 并返回可锁定的 UnitBase 或 null；它只在本地索敌没有结果时参与决策。
func set_pack_target_fallback_resolver(resolver: Callable) -> void:
	if is_instance_valid(_targeting_component):
		_targeting_component.set_fallback_target_resolver(resolver)


## 移除同 Pack 目标兜底查询，恢复为只依赖本地感知与既有仇恨策略的索敌。
## 本方法不修改仇恨、生命或战斗状态；由 EncounterController 在 Pack 生命周期边界调用。
func clear_pack_target_fallback_resolver() -> void:
	if is_instance_valid(_targeting_component):
		_targeting_component.clear_fallback_target_resolver()


## 立即按当前本地感知与可选 Pack 兜底查询刷新一次锁定目标。
## 此接口不驱动移动或攻击，只用于 EncounterController 在 Pack 激活时同步成员的目标决策。
func refresh_targeting() -> void:
	if is_instance_valid(_targeting_component):
		_targeting_component.refresh_target()


func get_behavior_state_machine() -> EnemyBehaviorStateMachine:
	return _behavior_state_machine if is_instance_valid(_behavior_state_machine) else null


## 返回敌人已装配的本地仇恨组件。
## 调用方只能使用其 submit_threat() 等公开接口，不能直接访问或修改内部仇恨表。
func get_threat_component() -> Node:
	return _threat_component if is_instance_valid(_threat_component) else null


## 对敌人结算伤害并把实际扣除量转换为基础仇恨事件。
## amount 为进入 UnitBase 的原始伤害；source 必须传入实际施加伤害的 UnitBase，投射物应传递其施法者而非自身节点。
## 参数 threat_multiplier 是本次伤害的仇恨倍率，默认 1.0；它只放大提交到本敌人 ThreatComponent 的威胁，不修改生命扣除、死亡或命中结果。
func apply_damage(
	amount: float,
	source: Node = null,
	threat_multiplier: float = 1.0
) -> float:
	var applied_amount: float = super.apply_damage(amount, source, threat_multiplier)
	var source_unit := source as UnitBase
	if (
		applied_amount > 0.0
		and is_instance_valid(source_unit)
		and is_instance_valid(_threat_component)
	):
		var damage_event: Variant = THREAT_EVENT_SCRIPT.create_damage(
			source_unit,
			applied_amount,
			threat_multiplier
		)
		_threat_component.call("submit_threat", damage_event)
	if is_dead() and is_instance_valid(_threat_component):
		_threat_component.call("clear_threat")
	return applied_amount


func _on_locked_target_changed(previous_target: UnitBase, current_target: UnitBase) -> void:
	locked_target_changed.emit(previous_target, current_target)


## 某个来源的本地仇恨变化后立即刷新既有索敌组件。
## 参数仅用于满足 ThreatComponent 信号约定；目标仍完全由 AITargetingComponent 保存和发送。
func _on_threat_changed(
	_source: UnitBase,
	_previous_value: float,
	_current_value: float
) -> void:
	if is_instance_valid(_targeting_component):
		_targeting_component.refresh_target()


func _on_behavior_state_changed(
	previous_state: EnemyBehaviorStateMachine.State,
	current_state: EnemyBehaviorStateMachine.State
) -> void:
	if (
		current_state == EnemyBehaviorStateMachine.State.RETURN_HOME
		and is_instance_valid(_threat_component)
	):
		_threat_component.call("clear_threat")
	behavior_state_changed.emit(previous_state, current_state)
