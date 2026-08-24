class_name AllyBase
extends AIUnitBase

## 新友方单位父类。
##
## 当前只装配非战斗编队行为。索敌、攻击、技能和战斗站位会在后续阶段通过
## 独立组件接入，不会重新写回此脚本。

@export_category("Formation")
## 该友方单位在脱离战斗或返回编队时使用的阵型位置数据。
## 设计师只需要在单位根节点配置一次。
@export var formation_position: FormationPositionData

signal formation_side_changed(new_side: int)
## 自主锁定目标发生变化时转发，供后续朝向、追击、攻击或策略系统监听。
signal locked_target_changed(
	previous_target: UnitBase,
	current_target: UnitBase
)
## 统一行为状态发生变化时转发，供调试界面、职业逻辑和未来动画层监听。
signal behavior_state_changed(
	previous_state: AllyBehaviorStateMachine.BehaviorState,
	current_state: AllyBehaviorStateMachine.BehaviorState
)

@export_category("Combat Actions")
@export_enum("Basic Only", "Skill Priority Then Basic", "Skill Only With Basic When Disabled")
var combat_action_policy: int = AllyBehaviorStateMachine.CombatActionPolicy.BASIC_ONLY
@export var automatic_skill_cast_enabled: bool = true
@export_range(0.0, 10.0, 0.05)
var shared_action_cooldown_duration: float = 1.0

@onready var _behavior_state_machine: AllyBehaviorStateMachine = \
	$BehaviorStateMachine
@onready var _skill_host: SkillHostComponent = \
	get_node_or_null(^"SkillHost") as SkillHostComponent


func _ready() -> void:
	super._ready()
	if not is_instance_valid(_targeting_component):
		push_error(
			"AllyBase: AITargetingComponent is missing. Node="
			+ str(get_path())
		)
		return
	## SkillHost 只读取索敌组件的公开候选接口，不保存额外 NodePath，也不会反向
	## 修改持续战斗锁定。未装配技能时仍可安全完成此运行时注入。
	if is_instance_valid(_skill_host):
		_skill_host.set_target_candidate_provider(_targeting_component)
	var target_callback := Callable(self, "_on_locked_target_changed")
	if not _targeting_component.locked_target_changed.is_connected(
		target_callback
	):
		_targeting_component.locked_target_changed.connect(target_callback)

	if not is_instance_valid(_behavior_state_machine):
		push_error(
			"AllyBase: BehaviorStateMachine is missing. Node="
			+ str(get_path())
		)
		return
	if formation_position != null:
		_behavior_state_machine.set_formation_position(formation_position)
	_behavior_state_machine.combat_action_policy = combat_action_policy
	_behavior_state_machine.automatic_skill_cast_enabled = automatic_skill_cast_enabled
	_behavior_state_machine.shared_action_cooldown_duration = shared_action_cooldown_duration
	if not _behavior_state_machine.configure(
		self,
		_targeting_component,
		get_combat_system(),
		_skill_host
	):
		push_error(
			"AllyBase: BehaviorStateMachine configuration failed. Node="
			+ str(get_path())
		)
		return
	var side_callback := Callable(self, "_on_formation_side_changed")
	if not _behavior_state_machine.formation_side_changed.is_connected(
		side_callback
	):
		_behavior_state_machine.formation_side_changed.connect(side_callback)
	var state_callback := Callable(self, "_on_behavior_state_changed")
	if not _behavior_state_machine.state_changed.is_connected(state_callback):
		_behavior_state_machine.state_changed.connect(state_callback)


func _update_ai_movement(delta: float) -> void:
	if is_instance_valid(_behavior_state_machine):
		_behavior_state_machine.physics_tick(delta)
	else:
		super._update_ai_movement(delta)


## 返回统一行为状态机，供未来职业状态和调试工具通过开放接口访问。
func get_behavior_state_machine() -> AllyBehaviorStateMachine:
	return (
		_behavior_state_machine
		if is_instance_valid(_behavior_state_machine)
		else null
	)


## 返回独立索敌组件，供后续战斗行为读取目标或切换策略。
func get_targeting_component() -> AITargetingComponent:
	return _targeting_component if is_instance_valid(_targeting_component) else null


## 供沉默、剧情或特殊状态在单位层统一禁用/恢复技能释放；不需要直接引用具体技能场景。
func set_skill_casting_enabled(enabled: bool) -> void:
	if is_instance_valid(_skill_host):
		_skill_host.set_skill_casting_enabled(enabled)


## 返回技能释放许可状态；未装配 SkillHost 的单位视为不具备技能释放能力。
func is_skill_casting_enabled() -> bool:
	return (
		is_instance_valid(_skill_host)
		and _skill_host.is_skill_casting_enabled()
	)


## 控制该单位是否由行为状态机自动请求已装配技能，不会卸载或改写技能本身。
func set_automatic_skill_cast_enabled(enabled: bool) -> void:
	if is_instance_valid(_behavior_state_machine):
		_behavior_state_machine.set_automatic_skill_cast_enabled(enabled)


## 返回当前自主锁定目标；没有有效目标或组件缺失时安全返回 null。
func get_locked_target() -> UnitBase:
	if not is_instance_valid(_targeting_component):
		return null
	return _targeting_component.get_locked_target()


func get_locked_formation_side() -> int:
	if not is_instance_valid(_behavior_state_machine):
		return 0
	return _behavior_state_machine.get_locked_side()


func request_formation_side(side: int, refresh_target: bool = true) -> void:
	if is_instance_valid(_behavior_state_machine):
		_behavior_state_machine.request_formation_side(side, refresh_target)


func _on_formation_side_changed(new_side: int) -> void:
	formation_side_changed.emit(new_side)


func _on_locked_target_changed(
	previous_target: UnitBase,
	current_target: UnitBase
) -> void:
	locked_target_changed.emit(previous_target, current_target)


func _on_behavior_state_changed(
	previous_state: AllyBehaviorStateMachine.BehaviorState,
	current_state: AllyBehaviorStateMachine.BehaviorState
) -> void:
	behavior_state_changed.emit(previous_state, current_state)
