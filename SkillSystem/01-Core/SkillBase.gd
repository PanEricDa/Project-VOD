@tool
class_name SkillBase
extends Node

## 单场景技能的根节点。
##
## 设计师只需要在本节点 Inspector 中配置普通技能。固定子节点负责运行交付和
## 临时表现，不重复暴露 NodePath、Definition 或每技能 Delivery 场景。

signal action_requested(
	skill: SkillBase,
	target: Node3D,
	effective_cast_time: float
)
signal cast_range_required(context: SkillContext, cast_range: float)
signal cast_started(context: SkillContext)
signal release_started(context: SkillContext)
signal delivery_started(context: SkillContext)
signal delivery_finished(context: SkillContext, result: SkillDeliveryResult)
signal skill_failed(context: SkillContext, reason: StringName)
signal skill_cancelled(context: SkillContext, reason: StringName)
signal cooldown_started(duration: float)
signal cooldown_finished()

enum PresentationAnchor {
	ACTION_ORIGIN,
	RESOLVED_TARGET,
	TARGET_POSITION,
	CASTER_FEET,
}

enum SkillState {
	READY,
	QUEUED,
	ACTION_REQUESTED,
	CASTING,
	RELEASED,
	COOLDOWN,
	POST_RELEASE_HESITATION,
}

@export_category("Identity")
## 技能在同一 SkillHost 内的唯一标识；运行时请求、冷却查询与未来 UI 均以此字段定位，重复会导致装配警告。
@export var skill_id: StringName = &"default_skill"
## 供 Inspector、调试信息和未来技能栏显示的名称；仅影响文本表现，不参与目标或伤害计算。
@export var display_name: String = "Default Skill"
## 可选的技能图标资源；当前不影响运行逻辑，预留给未来技能栏与提示界面使用。
@export var icon: Texture2D
## AI 自动选择多个可用技能时的优先级；数值越大越优先，数值相同则保持当前注册顺序。
@export var ai_priority: int = 0

@export_category("Targeting")
## 允许目标关系的复选集合；可同时选择自己、友方、敌方和中立单位。
@export_flags("Self", "Friendly", "Hostile", "Neutral")
var target_relations: int = TargetResolver.TargetRelationFlag.HOSTILE
## 自动 AI 请求使用的唯一目标选择方式；显式外部请求不会被此项替换目标。
@export var target_selection_mode: TargetResolver.TargetSelectionMode = \
	TargetResolver.TargetSelectionMode.CURRENT_COMBAT_TARGET
@export_range(0.0, 100.0, 0.1, "or_greater")
## 施法者到目标的水平最大距离，单位为米；超出时技能会请求接近而非立即释放。
var cast_range: float = 5.0
## 开启后仅接受 UnitBase 中标记为可被选取的目标；关闭可用于地面锚点或特殊不可选单位。
@export var require_targetable: bool = true
## 开启后拒绝死亡目标；治疗复活或尸体类技能需要明确关闭此项。
@export var require_alive: bool = true
## 开启后在动画 release_action 时再次验证目标有效性与施法距离；失败时取消本次释放。
@export var validate_target_on_release: bool = true

@export_category("Casting")
@export_range(0.0, 30.0, 0.05, "or_greater")
## 基础施法时间，单位为秒；角色动作会按此值与施法速度倍率同步缩放，0 表示 release_action 必须在动画起点。
var base_cast_time: float = 0.5
## 是否允许角色在施法动作期间继续移动；关闭时 SkillHost 会请求行为层暂时停止主动移动。
@export var can_move_while_casting: bool = false
## 是否允许角色在施法动作期间继续调整朝向；当前仅作为通用施法契约，具体朝向由角色行为层执行。
@export var can_turn_while_casting: bool = true
## 目标在排队或施法期间失效时是否取消；关闭后仍会在 release_action 的验证开关允许时进行最后检查。
@export var cancel_when_target_invalid: bool = true

@export_category("Cooldown")
@export_range(0.0, 600.0, 0.1, "or_greater")
## 技能成功交付后开始的独立冷却时间，单位为秒；与单位公共冷却独立计时。
var skill_cooldown: float = 6.0
## 交付启动失败时是否仍进入技能冷却；默认关闭，失败会立即回到可再次请求状态。
@export var cooldown_on_failed_release: bool = false

@export_category("Threat")
## 此技能每次成功造成伤害后对敌方本地仇恨表的倍率。## 默认 1.0 表示仇恨与实际扣血一比一；仅影响 DAMAGE 的仇恨贡献，不提高伤害、治疗、命中率或技能冷却。## 设为 0 会让该技能的伤害不产生仇恨；该配置由本技能的全部伤害交付共享。
@export_range(0.0, 100.0, 0.05, "or_greater")
var threat_multiplier: float = 1.0

@export_category("AI Usage")
## 是否允许 AI 自动请求此技能；关闭后仍可由外部明确请求，不会从自动候选中选取。
@export var automatic_cast_enabled: bool = true
## 技能成功释放后，AI 进入下一轮技能冷却前的常规等待最小值，单位为秒；与最大值之间随机取样。
## 该等待不延迟本场战斗的首发施法，也不占用单位公共冷却或阻止普通攻击。
@export_range(0.0, 10.0, 0.1)
var decision_delay_min: float = 0.3
## 技能成功释放后，AI 进入下一轮技能冷却前的常规等待最大值，单位为秒；小于最小值时运行时会自动交换边界。
## 该等待只阻止同一技能重复请求，不会阻止普通攻击或其他既有行动链路。
@export_range(0.0, 10.0, 0.1)
var decision_delay_max: float = 3.0
## 技能成功释放后触发额外犹豫等待的概率，取值 0 至 1；默认 0.1 即 10% 概率。
## 额外等待叠加在常规释放后等待上，不影响本次已经开始的施法、Delivery 或公共冷却。
@export_range(0.0, 1.0, 0.01)
var extra_hesitation_chance: float = 0.1
## 成功释放后额外犹豫触发时附加等待的最小值，单位为秒；与最大值之间随机取样。
## 该数值仅参与下一轮技能冷却前的等待，不会延迟首发施法。
@export_range(0.0, 10.0, 0.1)
var extra_hesitation_min: float = 3.0
## 成功释放后额外犹豫触发时附加等待的最大值，单位为秒；小于最小值时运行时会自动交换边界。
## 小于最小值时运行时会自动交换边界；该值不会影响普通攻击、移动或本次 Delivery。
@export_range(0.0, 10.0, 0.1)
var extra_hesitation_max: float = 5.0

@export_category("Presentation")
## 可选的施法开始特效场景；动作确认开始时在角色动作发射点生成，不承担伤害或投射物逻辑。
@export var cast_effect_scene: PackedScene
## 可选的技能释放特效场景；release_action 时根据下方锚点规则生成，不承担命中或数值结算。
@export var release_effect_scene: PackedScene
## Release 表现的世界锚点。默认沿用动作发射点；目标瞬发和地面技能可以
## 直接通过 Inspector 改用已解析目标或上下文目标位置，不需要技能专用脚本。
@export var release_effect_anchor: PresentationAnchor = \
	PresentationAnchor.ACTION_ORIGIN
## 可选的施法取消特效场景；技能在完成释放前被取消时于最近动作位置生成。
@export var cancel_effect_scene: PackedScene

@export_category("Delivery")
## 本技能唯一的交付配置资源；决定投射物、目标瞬发或地面区域等交付方式，资源类型必须继承 SkillDeliveryConfig。
@export var delivery: SkillDeliveryConfig

var _state: SkillState = SkillState.READY
var _skill_owner: Node3D
var _skill_host: Node
var _delivery_parent: Node
var _current_context: SkillContext
var _cooldown_remaining: float = 0.0
## 成功释放后、独立技能冷却开始前的剩余等待时间，单位为秒。
## 此值仅由 SkillBase 维护，避免 SkillHost 因等待而持有未开始施法的活动技能。
var _post_release_hesitation_remaining: float = 0.0
var _last_action_transform: Transform3D = Transform3D.IDENTITY
var _runtime_effect_instances: Array[Node] = []
## SkillBase 自己的随机来源；只用于成功释放后的等待采样，不影响外部 AI、目标或战斗随机逻辑。
var _random := RandomNumberGenerator.new()

@onready var _delivery_runner: SkillDeliveryRunner = (
	get_node_or_null(^"DeliveryRunner") as SkillDeliveryRunner
)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_random.randomize()
	if is_instance_valid(_delivery_runner):
		_delivery_runner.delivery_finished.connect(_on_runner_delivery_finished)
		_delivery_runner.delivery_failed.connect(_on_runner_delivery_failed)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _state == SkillState.POST_RELEASE_HESITATION:
		_post_release_hesitation_remaining = maxf(
			_post_release_hesitation_remaining - delta,
			0.0
		)
		if _post_release_hesitation_remaining <= 0.0:
			_start_cooldown()
		return
	if _state != SkillState.COOLDOWN:
		return
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if _cooldown_remaining <= 0.0:
		_state = SkillState.READY
		cooldown_finished.emit()


## 注入施法者、宿主和世界交付父节点，不读取具体单位内部字段。
func configure_owner(caster: Node3D, host: Node, delivery_parent: Node) -> void:
	if _skill_owner != caster and _state not in [SkillState.READY, SkillState.COOLDOWN]:
		cancel_skill(&"owner_changed")
	_skill_owner = caster
	_skill_host = host
	_delivery_parent = delivery_parent


## 接受一次技能请求。范围外的有效目标进入 QUEUED，而不是被拒绝。
func request_skill(context: SkillContext) -> bool:
	if _state != SkillState.READY:
		return false
	var prepared := _prepare_context(context)
	if prepared == null:
		return false
	prepared.threat_multiplier = maxf(threat_multiplier, 0.0)
	_current_context = prepared
	_state = SkillState.QUEUED
	try_request_action()
	return true


## 当排队目标进入施法距离时，向角色动作系统提出唯一一次动作请求。
func try_request_action() -> bool:
	if _state != SkillState.QUEUED or _current_context == null:
		return false
	if not _is_candidate_valid(_current_context.resolved_target, false):
		_fail_active(&"target_invalid", false)
		return false
	if not _is_target_in_cast_range(_current_context.resolved_target):
		cast_range_required.emit(_current_context, maxf(cast_range, 0.0))
		return false
	var effective_cast_time: float = get_effective_cast_time()
	if effective_cast_time < 0.0:
		_fail_active(&"invalid_cast_configuration", false)
		return false
	_state = SkillState.ACTION_REQUESTED
	action_requested.emit(
		self,
		_current_context.resolved_target,
		effective_cast_time
	)
	return true


## 角色动作系统确认动画已经成功开始，并提供当前世界发射变换。
func confirm_action_started(cast_transform: Transform3D) -> bool:
	if _state != SkillState.ACTION_REQUESTED or not cast_transform.is_finite():
		return false
	_state = SkillState.CASTING
	_last_action_transform = cast_transform
	_spawn_presentation(cast_effect_scene, cast_transform)
	cast_started.emit(_current_context)
	return true


## 动画 Release 方法轨道调用的交付入口。
func release_action(launch_transform: Transform3D) -> bool:
	if (
		_state != SkillState.CASTING
		or _current_context == null
		or not launch_transform.is_finite()
		or not is_instance_valid(_delivery_runner)
		or delivery == null
	):
		return false
	_last_action_transform = launch_transform
	if (
		validate_target_on_release
		and (
			not _is_candidate_valid(_current_context.resolved_target, false)
			or not _is_target_in_cast_range(_current_context.resolved_target)
		)
	):
		_fail_active(&"target_invalid_on_release", false)
		return false

	if is_instance_valid(_current_context.resolved_target):
		_current_context.target_position = _current_context.resolved_target.global_position
	var costs := _collect_costs()
	for cost: SkillCostBase in costs:
		if not cost.can_pay(_current_context):
			_fail_active(&"cost_unavailable", false)
			return false
	var committed_costs: Array[SkillCostBase] = []
	for cost: SkillCostBase in costs:
		if not cost.commit(_current_context):
			_refund_costs(committed_costs)
			_fail_active(&"cost_commit_failed", false)
			return false
		committed_costs.append(cost)

	_spawn_release_presentation(release_effect_scene, launch_transform)
	release_started.emit(_current_context)
	var effects := _collect_effects()
	if not _delivery_runner.execute(
		delivery,
		_current_context,
		launch_transform,
		effects
	):
		_refund_costs(committed_costs)
		_fail_active(&"delivery_start_failed", true)
		return false

	var released_context: SkillContext = _current_context
	_state = SkillState.RELEASED
	delivery_started.emit(released_context)
	_current_context = null
	_start_post_release_hesitation()
	return true


## 动作结束只关闭尚未释放的请求；已经成功交付的技能继续独立冷却。
func finish_action() -> void:
	if _state in [
		SkillState.QUEUED,
		SkillState.ACTION_REQUESTED,
		SkillState.CASTING,
	]:
		cancel_skill(&"action_finished_before_release")


func cancel_skill(reason: StringName = &"cancelled") -> void:
	if _state not in [
		SkillState.QUEUED,
		SkillState.ACTION_REQUESTED,
		SkillState.CASTING,
	]:
		return
	var cancelled_context: SkillContext = _current_context
	_spawn_presentation(cancel_effect_scene, _last_action_transform)
	_current_context = null
	_state = SkillState.READY
	skill_cancelled.emit(cancelled_context, reason)


func reset_skill() -> void:
	if is_instance_valid(_delivery_runner) and _delivery_runner.is_busy():
		_delivery_runner.cancel(&"skill_reset")
	_current_context = null
	_cooldown_remaining = 0.0
	_post_release_hesitation_remaining = 0.0
	_state = SkillState.READY
	_clear_runtime_effect_references()


func can_request(context: SkillContext) -> bool:
	return _state == SkillState.READY and _prepare_context(context) != null


func is_ready() -> bool:
	return _state == SkillState.READY


func is_casting() -> bool:
	return _state in [SkillState.ACTION_REQUESTED, SkillState.CASTING]


func get_state() -> SkillState:
	return _state


func get_current_context() -> SkillContext:
	return _current_context


func get_cooldown_remaining() -> float:
	return _cooldown_remaining


## 返回成功释放后、独立技能冷却开始前的剩余犹豫时间，单位为秒。
## 非释放后等待状态时安全返回零；调用方只可读取，不能借此修改技能状态。
func get_post_release_hesitation_remaining() -> float:
	return _post_release_hesitation_remaining


func get_effective_cast_time() -> float:
	var multiplier: float = 1.0
	if (
		is_instance_valid(_skill_owner)
		and _skill_owner.has_method(&"get_cast_speed_multiplier")
	):
		multiplier = float(_skill_owner.call(&"get_cast_speed_multiplier"))
	if not is_finite(multiplier) or multiplier <= 0.0:
		return -1.0
	return maxf(base_cast_time, 0.0) / multiplier


func _prepare_context(source: SkillContext) -> SkillContext:
	if (
		source == null
		or not is_instance_valid(_skill_owner)
		or not _skill_owner.is_inside_tree()
		or delivery == null
		or not delivery.validate_configuration().is_empty()
	):
		return null
	var prepared := source.duplicate_context() as SkillContext
	prepared.caster = _skill_owner
	prepared.host = _skill_host
	if is_instance_valid(_delivery_parent):
		prepared.delivery_parent = _delivery_parent
	if not is_instance_valid(prepared.delivery_parent):
		return null
	prepared.resolved_target = _resolve_target(prepared)
	if not _is_candidate_valid(prepared.resolved_target, false):
		return null
	for condition: SkillConditionBase in _collect_conditions():
		if not condition.evaluate(prepared):
			return null
	for cost: SkillCostBase in _collect_costs():
		if not cost.can_pay(prepared):
			return null
	return prepared


func _resolve_target(context: SkillContext) -> Node3D:
	if context.explicit_target_requested:
		return (
			context.requested_target
			if TargetResolver.is_candidate_valid(
				_skill_owner,
				context.requested_target,
				target_relations,
				require_targetable,
				require_alive
			)
			else null
		)
	var candidates: Array[Node3D] = context.candidate_targets.duplicate()
	if (
		target_relations & TargetResolver.TargetRelationFlag.SELF
		and _skill_owner not in candidates
	):
		candidates.append(_skill_owner)
	return TargetResolver.resolve_target(
		_skill_owner,
		candidates,
		context.requested_target,
		target_relations,
		target_selection_mode,
		require_targetable,
		require_alive
	)


func _is_candidate_valid(candidate_value: Variant, include_range: bool) -> bool:
	if not TargetResolver.is_candidate_valid(
		_skill_owner,
		candidate_value,
		target_relations,
		require_targetable,
		require_alive
	):
		return false
	var candidate := candidate_value as Node3D
	return not include_range or _is_target_in_cast_range(candidate)


func _is_target_in_cast_range(target_value: Variant) -> bool:
	if (
		not is_instance_valid(target_value)
		or not target_value is Node3D
		or not is_instance_valid(_skill_owner)
	):
		return false
	var target := target_value as Node3D
	var offset: Vector3 = target.global_position - _skill_owner.global_position
	offset.y = 0.0
	return offset.length() <= maxf(cast_range, 0.0) + 0.05


func _collect_conditions() -> Array[SkillConditionBase]:
	var components: Array[SkillConditionBase] = []
	for child: Node in get_children():
		if child is SkillConditionBase:
			components.append(child as SkillConditionBase)
	return components


func _collect_costs() -> Array[SkillCostBase]:
	var components: Array[SkillCostBase] = []
	for child: Node in get_children():
		if child is SkillCostBase:
			components.append(child as SkillCostBase)
	return components


func _collect_effects() -> Array[SkillEffectBase]:
	var components: Array[SkillEffectBase] = []
	for child: Node in get_children():
		if child is SkillEffectBase:
			components.append(child as SkillEffectBase)
	return components


func _refund_costs(costs: Array[SkillCostBase]) -> void:
	for cost: SkillCostBase in costs:
		if is_instance_valid(cost):
			cost.refund(_current_context)


func _spawn_presentation(
	effect_scene: PackedScene,
	world_transform: Transform3D
) -> void:
	if (
		effect_scene == null
		or not world_transform.is_finite()
		or _current_context == null
		or not is_instance_valid(_current_context.delivery_parent)
	):
		return
	var instance: Node = effect_scene.instantiate()
	if not instance is Node3D:
		if is_instance_valid(instance):
			instance.free()
		return
	var effect := instance as Node3D
	_current_context.delivery_parent.add_child(effect)
	effect.global_transform = world_transform
	_runtime_effect_instances.append(effect)


## 根据 Release 锚点同时决定特效的父节点和坐标空间。
##
## ACTION_ORIGIN 是一次性的世界发射坐标，适合枪口火焰、法球生成等表现。
## RESOLVED_TARGET 是持续附着目标的局部坐标，适合治疗、增益和目标身上的状态表现。
## TARGET_POSITION 是一次性的世界落点，适合地面范围法术。
##
## 这里不能只替换 action_transform.origin：那样会错误保留武器插槽的倾斜 Basis，
## 同时仍把目标特效挂在世界节点下，导致目标移动后特效遗留在旧坐标。
func _spawn_release_presentation(
	effect_scene: PackedScene,
	action_transform: Transform3D
) -> void:
	if _current_context == null:
		return
	match release_effect_anchor:
		PresentationAnchor.CASTER_FEET:
			if is_instance_valid(_skill_owner):
				_spawn_caster_feet_presentation(effect_scene, action_transform)
				return
		PresentationAnchor.RESOLVED_TARGET:
			if is_instance_valid(_current_context.resolved_target):
				_spawn_attached_presentation(
					effect_scene,
					_current_context.resolved_target
				)
				return
		PresentationAnchor.TARGET_POSITION:
			if _current_context.target_position.is_finite():
				_spawn_presentation(
					effect_scene,
					Transform3D(
						Basis.IDENTITY,
						_current_context.target_position
					)
				)
				return
	_spawn_presentation(effect_scene, action_transform)


## 将“施法者脚底”特效附着到施法者，并以施法者到当前目标的世界水平朝向作为特效正前方。
## 参数 action_transform 只在没有可用目标方向时作为退回朝向；不会把武器插槽的俯仰或局部动作旋转传给地面特效。
func _spawn_caster_feet_presentation(
	effect_scene: PackedScene,
	action_transform: Transform3D
) -> void:
	if effect_scene == null or not is_instance_valid(_skill_owner):
		return
	var instance: Node = effect_scene.instantiate()
	if not instance is Node3D:
		if is_instance_valid(instance):
			instance.free()
		return
	var effect := instance as Node3D
	_skill_owner.add_child(effect)
	effect.global_transform = Transform3D(
		_get_caster_target_facing_basis(action_transform.basis),
		_skill_owner.global_position
	)
	_runtime_effect_instances.append(effect)


## 计算脚底定向特效的世界水平 Basis；优先使用施法者到已解析目标的方向，确保不受 Visual、武器插槽或动作局部旋转影响。
## 参数 fallback_basis 仅在目标不存在或与施法者重合时提供退回方向，并会自动去除俯仰与侧倾。
func _get_caster_target_facing_basis(fallback_basis: Basis) -> Basis:
	var direction := Vector3.ZERO
	if _current_context != null and is_instance_valid(_current_context.resolved_target):
		direction = _current_context.resolved_target.global_position - _skill_owner.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = -fallback_basis.z
		direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return Basis.IDENTITY
	var normalized_direction := direction.normalized()
	return Basis(
		Vector3.UP,
		atan2(-normalized_direction.x, -normalized_direction.z)
	)


## 把目标类表现直接挂到已解析目标的根节点。
##
## 单位根节点约定在脚底中心，因此局部原点 Vector3.ZERO 就是治疗光环的地面起点。
## 使用局部单位 Basis，不读取法杖、ProjectileOrigin 或施法动画的旋转。
func _spawn_attached_presentation(
	effect_scene: PackedScene,
	target: Node3D
) -> void:
	if effect_scene == null or not is_instance_valid(target):
		return
	var instance: Node = effect_scene.instantiate()
	if not instance is Node3D:
		if is_instance_valid(instance):
			instance.free()
		return
	var effect := instance as Node3D
	target.add_child(effect)
	effect.transform = Transform3D.IDENTITY
	_runtime_effect_instances.append(effect)


func _start_cooldown() -> void:
	_post_release_hesitation_remaining = 0.0
	_cooldown_remaining = maxf(skill_cooldown, 0.0)
	_state = SkillState.COOLDOWN
	cooldown_started.emit(_cooldown_remaining)
	if _cooldown_remaining <= 0.0:
		_state = SkillState.READY
		cooldown_finished.emit()


## 在成功启动 Delivery 后结算一次 AI 释放后犹豫。
## 该方法只由成功交付路径调用；交付失败、取消或未释放的排队请求不会进入该状态。
func _start_post_release_hesitation() -> void:
	_post_release_hesitation_remaining = _calculate_post_release_hesitation()
	if _post_release_hesitation_remaining <= 0.0:
		_start_cooldown()
		return
	_state = SkillState.POST_RELEASE_HESITATION


## 根据 Inspector 中的常规等待与低概率额外犹豫计算本次释放后的总等待，单位为秒。
## 所有边界都在读取时归一化，因此最小值和最大值在 Inspector 中颠倒时仍保持稳定。
func _calculate_post_release_hesitation() -> float:
	var minimum: float = minf(decision_delay_min, decision_delay_max)
	var maximum: float = maxf(decision_delay_min, decision_delay_max)
	var delay: float = _random.randf_range(minimum, maximum)
	if _random.randf() < clampf(extra_hesitation_chance, 0.0, 1.0):
		var extra_minimum: float = minf(
			extra_hesitation_min,
			extra_hesitation_max
		)
		var extra_maximum: float = maxf(
			extra_hesitation_min,
			extra_hesitation_max
		)
		delay += _random.randf_range(extra_minimum, extra_maximum)
	return maxf(delay, 0.0)


func _fail_active(reason: StringName, delivery_failure: bool) -> void:
	var failed_context: SkillContext = _current_context
	_current_context = null
	## 必须先完成技能自身的终止状态迁移，再向 Host 发出失败信号。
	##
	## Host 会在信号回调中检查技能是否已经离开 QUEUED、ACTION_REQUESTED 或
	## CASTING。若先发送信号、后改状态，Host 会误判请求仍在运行，从而永久保留
	## active_skill，后续自动施法便无法再次开始。
	if delivery_failure and cooldown_on_failed_release:
		_start_cooldown()
	else:
		_state = SkillState.READY
	skill_failed.emit(failed_context, reason)


func _on_runner_delivery_finished(
	context: SkillContext,
	result: SkillDeliveryResult
) -> void:
	delivery_finished.emit(context, result)


func _on_runner_delivery_failed(
	context: SkillContext,
	reason: StringName
) -> void:
	if _state in [
		SkillState.RELEASED,
		SkillState.POST_RELEASE_HESITATION,
		SkillState.COOLDOWN,
	]:
		skill_failed.emit(context, reason)


func _clear_runtime_effect_references() -> void:
	for effect: Node in _runtime_effect_instances:
		if is_instance_valid(effect):
			effect.queue_free()
	_runtime_effect_instances.clear()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if skill_id.is_empty():
		warnings.append("Skill ID cannot be empty.")
	if delivery == null:
		warnings.append("Skill requires a typed DeliveryConfig.")
	elif not delivery.validate_configuration().is_empty():
		warnings.append_array(delivery.validate_configuration())
	if get_node_or_null(^"DeliveryRunner") == null:
		warnings.append("SkillBase requires its fixed DeliveryRunner child.")
	if get_node_or_null(^"RuntimeEffects") == null:
		warnings.append("SkillBase requires its fixed RuntimeEffects child.")
	return warnings


func _exit_tree() -> void:
	_clear_runtime_effect_references()
	_current_context = null
