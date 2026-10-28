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
## 本次施法达到cast_effect_start_ratio提示时点；context为原动作身份，每次至多一次。
## 与施法视觉共用有效施法时间和战斗时钟；缺少视觉资产仍通知，不表示释放或命中。
signal cast_cue_reached(context: SkillContext)
signal release_started(context: SkillContext)
signal delivery_started(context: SkillContext)
## 成功释放时请求镜头表现；profile只读，source/target可空或随后失效，world_transform为有限世界快照。
## 本信号不代表命中、不等待订阅者、不直接改变相机。
signal camera_effect_requested(profile: CameraEffectProfile, source: Node3D, target: Node3D, world_transform: Transform3D)
## 纯释放实例进树前事实，instance只允许表现时钟登记，不得改变战斗。
signal release_instance_prepared(presentation: SkillPresentationContext, instance: Node)
## 成功释放表现启动，presentation保持同一施放身份，不代表命中。
signal release_presentation_started(presentation: SkillPresentationContext)
## 全部待发项目结束，不等于伤害或主视觉结束。
signal emission_finished(context: SkillContext)
## 主爆炸进树前事实，用于演出时钟和完成屏障，不执行伤害。
signal impact_presentation_prepared(context: SkillContext, instance: Node3D)
## 已成功发出第index颗，point为世界冻结目标点。
signal projectile_launched(context: SkillContext, index: int, point: Vector3)
## 第index颗已落地并结算，本次主表现可继续。
signal projectile_landed(context: SkillContext, index: int, point: Vector3)
signal delivery_finished(context: SkillContext, result: SkillDeliveryResult)
## 某次交付最终失败，始终携带原context；不依赖装备技能当前状态，不表示可退款。
signal delivery_failed(context: SkillContext, reason: StringName)
signal skill_failed(context: SkillContext, reason: StringName)
signal skill_cancelled(context: SkillContext, reason: StringName)
signal cooldown_started(duration: float)
signal cooldown_finished()

## 技能主要用途的显示分类；编号需保持稳定，不参与伤害、治疗、目标或施放规则判断。
enum SkillType {
	DAMAGE = 0,
	HEALING = 1,
	BUFF = 2,
	DEBUFF = 3,
}

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
## 技能主要用途：伤害、治疗、强化友方或弱化/干扰敌方（含嘲讽）；默认伤害。
## 混合技能按主要用途选择；仅决定技能名称提示背景，不改变效果、仇恨、AI 优先级或结算规则。
@export_enum("伤害技能:0", "治疗技能:1", "强化技能:2", "弱化技能:3")
var skill_type: int = SkillType.DAMAGE
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
## 开启后在动画 release_action 时再次验证目标有效性及“施法距离+释放容差”；失败时取消本次释放。
@export var validate_target_on_release: bool = true
## 已开始施法后，释放帧允许在 cast_range 外额外延伸的水平距离，单位米；默认0保持原射程。
## 仅在validate_target_on_release开启时生效，不扩大选取、启动或接近距离，也不绕过死亡与其他目标合法性检查。
@export_range(0.0, 100.0, 0.1, "or_greater") var release_range_tolerance_m: float = 0.0

@export_category("Action")
## 可选普通技能动作Animation；默认空沿用角色武器的默认施法动作。只影响CHARACTER_ACTION，触发交付不等待动画。
## 与终结镜头配置独立；配置后动作仍按本次有效施法时间缩放，现有近战和位移数据保持共用。
@export var action_animation: Animation

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
@export_subgroup("Cast")
## 可选的施法开始特效场景；动作实际确认开始时在所选锚点生成一次，空则不播放。
## 不承担伤害或成功释放通知；取消/失败立即清理，成功释放结束蓄力，普通一次性资产依自身动画/计时器自然回收。
@export var cast_effect_scene: PackedScene
## 施法特效锚点，默认动作发射点以兼容旧技能；脚下/目标锚点附着相应单位，目标位置锚点固定在世界。
## 仅影响Cast视觉的位置与跟随，不改变施法目标、施法时间或Release通道。
@export var cast_effect_anchor: PresentationAnchor = PresentationAnchor.ACTION_ORIGIN
## 施法视觉和cast_cue_reached提示的归一化进度；0为开始、0.5为本次有效施法时间一半、1为释放时刻。
## 默认0兼容旧内容；缺少视觉资产仍发提示，仅影响本技能表现时点及订阅它的连携输入节奏，不改变释放/命中。
## 以战斗时钟和施法速度换算后的本次时长计时；暂停不推进，取消不补发；不移动音效、镜头或释放时停。
@export_range(0.0, 1.0, 0.05) var cast_effect_start_ratio: float = 0.0
@export_subgroup("Cinematic")
## 可选专属动作与A/B演出配置；默认空保持普通技能，终结用途由请求入口而非此资源决定。
@export var cinematic_profile: SkillCinematicProfile
@export_subgroup("Camera")
## 可选镜头策略；默认空，供关卡表现组件在实际施法时消费，不改变技能。
@export var camera_effect_profile: CameraEffectProfile
@export_subgroup("Release")
## 可选的成功释放视觉场景；交付接受时在所选锚点生成一次，不承担命中/数值结算；空则不播放。
@export var release_effect_scene: PackedScene
## Release 表现的世界锚点。默认沿用动作发射点；目标瞬发和地面技能可以
## 直接通过 Inspector 改用已解析目标或上下文目标位置，不需要技能专用脚本。
@export var release_effect_anchor: PresentationAnchor = \
	PresentationAnchor.ACTION_ORIGIN
## 一次性成功释放音频；默认空不发声，交付接受时从锚点世界位置播放，不参与战斗结算。
@export var release_audio_stream: AudioStream
## 可选释放强调资源；默认空不暂停，实际暂停由关卡装配组件负责。
@export var release_accent_profile: ReleaseAccentProfile
## 兼容旧场景/脚本名称，仅代理唯一镜头槽，不在Inspector重复显示或保存。
var release_camera_effect: CameraEffectProfile:
	get: return camera_effect_profile
	set(value): camera_effect_profile = value
@export_subgroup("Cancel")
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
## 当前execute是否已接受；区分未启动与接受后的最终失败，不作为动作锁。
var _release_accepted: bool = false
## 只保留尚未终结的指令交付context；按自身token核对，不按当前技能状态识别旧弹。
var _inflight_command_contexts: Dictionary = {}
var _cooldown_remaining: float = 0.0
## AI 自动施放成功后、独立技能冷却开始前的剩余等待时间，单位为秒。
## 显式请求不进入此状态；该值仅由 SkillBase 维护，且不会占用 SkillHost 活动技能槽。
var _post_release_hesitation_remaining: float = 0.0
var _presentation_context: SkillPresentationContext
var _last_action_transform: Transform3D = Transform3D.IDENTITY
## 只跟踪Cast/Cancel表现；成功Release实例由世界/附着对象及自身结束协议管理。
var _runtime_effect_instances: Array[Node] = []
## 当前施法期特效；取消时清理，一次性资产成功释放后按自身协议回收。
var _cast_effect_instance: Node3D
## 当前动作尚未播放的Cast视觉延迟；不占用技能逻辑或参与费用，终止动作时清空。
var _cast_effect_pending: bool = false
var _cast_effect_delay_remaining: float = 0.0
## SkillBase 自己的随机来源；只用于成功释放后的等待采样，不影响外部 AI、目标或战斗随机逻辑。
var _random := RandomNumberGenerator.new()

@onready var _delivery_runner: SkillDeliveryRunner = (
	get_node_or_null(^"DeliveryRunner") as SkillDeliveryRunner
)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_random.randomize()
	var player := get_node_or_null(^"RuntimeEffects") as SkillReleasePresentationPlayer
	if is_instance_valid(player):
		player.camera_effect_requested.connect(_on_camera_effect_requested)
		player.release_instance_prepared.connect(_on_release_instance_prepared)
		player.release_presentation_started.connect(_on_release_presentation_started)
	else:
		push_warning("Skill RuntimeEffects presentation player is missing; gameplay remains enabled.")
	if is_instance_valid(_delivery_runner):
		_delivery_runner.emission_finished.connect(func(ctx: SkillContext) -> void: emission_finished.emit(ctx))
		_delivery_runner.impact_presentation_prepared.connect(func(ctx: SkillContext, instance: Node3D) -> void: impact_presentation_prepared.emit(ctx, instance))
		_delivery_runner.projectile_launched.connect(func(ctx: SkillContext, index: int, point: Vector3) -> void: projectile_launched.emit(ctx, index, point))
		_delivery_runner.projectile_landed.connect(func(ctx: SkillContext, index: int, point: Vector3) -> void: projectile_landed.emit(ctx, index, point))
		_delivery_runner.delivery_started.connect(_on_runner_delivery_started)
		_delivery_runner.delivery_finished.connect(_on_runner_delivery_finished)
		_delivery_runner.delivery_failed.connect(_on_runner_delivery_failed)


var _pending_ground_release: Dictionary = {}

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _pending_ground_release.is_empty():
		var pending := _pending_ground_release
		_pending_ground_release = {}
		if pending.context == _current_context and _state in [SkillState.QUEUED,SkillState.CASTING]:
			_commit_release(pending.context,pending.transform)
	var cast_delta := delta
	if _current_context != null and _current_context.execution_clock != null:
		cast_delta = _current_context.execution_clock.get_delta(delta)
	_advance_cast_presentation(cast_delta)
	if _is_chain_root(_current_context):
		# 原有计时照常推进，连携不启动/清空它们，也不以计时替代动作占用。
		if _post_release_hesitation_remaining > 0.0:
			_post_release_hesitation_remaining = maxf(_post_release_hesitation_remaining - delta, 0.0)
			if _post_release_hesitation_remaining <= 0.0:
				_cooldown_remaining = maxf(skill_cooldown, 0.0)
		elif _cooldown_remaining > 0.0:
			_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
			if _cooldown_remaining <= 0.0: cooldown_finished.emit()
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


## 接受现有普通技能请求；context 的目标和候选仍由技能自身验证，范围外目标进入 QUEUED。
## 保留此接口供既有调用方使用，新来源统一从 activate() 进入。
func request_skill(context: SkillContext) -> bool:
	return activate(context)


## 激活一个技能实例；CHARACTER_ACTION 请求角色动作，DIRECT_TRIGGER 从上下文给出的世界位置直接交付。
## DIRECT_TRIGGER 要求显式目标及有限发射变换，仍检查本技能条件、目标、消耗和冷却。
func activate(context: SkillContext) -> bool:
	if not _can_accept_purpose(context):
		return false
	if context == null:
		return false
	var direct: bool = context.execution_mode == SkillContext.ExecutionMode.DIRECT_TRIGGER
	if context.execution_mode not in [
		SkillContext.ExecutionMode.CHARACTER_ACTION,
		SkillContext.ExecutionMode.DIRECT_TRIGGER,
	]:
		return false
	if direct and (not context.explicit_target_requested or not context.activation_transform.is_finite()):
		return false
	var source := context.duplicate_context() as SkillContext
	if direct:
		source.request_source = SkillContext.RequestSource.EXPLICIT
	var prepared := _prepare_context(source)
	if prepared == null:
		return false
	if direct and not _is_target_in_cast_range(prepared.resolved_target, prepared):
		return false
	prepared.threat_multiplier = maxf(threat_multiplier, 0.0)
	_current_context = prepared
	_state = SkillState.QUEUED
	if direct:
		return _commit_release(prepared, prepared.activation_transform)
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
	_presentation_context = SkillPresentationContext.create(self, _current_context, cast_transform)
	_schedule_cast_presentation(cast_transform)
	cast_started.emit(_current_context)
	return true


## 当前动作是否仍可真实释放；只读、不付款、不生成交付，复用正式释放的目标/容差规则。
func can_release_action() -> bool:
	return _state == SkillState.CASTING and _current_context != null and _is_release_target_valid(_current_context)

func _is_release_target_valid(context: SkillContext) -> bool:
	return context != null and (not validate_target_on_release or (
		_is_candidate_valid(context.resolved_target,false)
		and _is_target_in_cast_range(context.resolved_target,context,release_range_tolerance_m)))

## 动画 Release 方法轨道调用的交付入口。
func release_action(launch_transform: Transform3D) -> bool:
	if (
		_state != SkillState.CASTING
		or _current_context == null
		or not launch_transform.is_finite()
	):
		return false
	# 真实释放marker是施法进度终点；补齐低帧率下未获物理tick的短施法视觉，不另起成功事件。
	_advance_cast_presentation(_cast_effect_delay_remaining)
	return _commit_release(_current_context, launch_transform)


## 两种激活入口共用的真实释放步骤；调用方必须已通过请求预检并占用本技能实例。
## 消耗提交失败会退还已提交部分；成功时沿用当前信号与自身冷却规则。
func _commit_release(context: SkillContext, launch_transform: Transform3D) -> bool:
	if (
		context == null
		or context != _current_context
		or not launch_transform.is_finite()
		or not is_instance_valid(_delivery_runner)
		or delivery == null
	):
		return false
	if delivery is ArcProjectileDeliveryConfig and delivery.destination_mode == ArcProjectileDeliveryConfig.DestinationMode.RANDOM_GROUND_CIRCLE and not Engine.is_in_physics_frame():
		# 动作或触发可从渲染回调发来；只排本实例原context，下一物理帧再采样地面和提交成本。
		_pending_ground_release = {"context":context,"transform":launch_transform}
		return true
	_last_action_transform = launch_transform
	if not _is_release_target_valid(_current_context):
		_fail_active(&"target_invalid_on_release", false)
		return false

	if is_instance_valid(_current_context.resolved_target):
		_current_context.target_position = _current_context.resolved_target.global_position
	if _is_chain_root(context) and not context.command_request.authorize_release():
		_fail_active(&"command_authorization_failed", false)
		return false
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

	_stop_cast_presentation(true)
	release_started.emit(_current_context)
	# 公开通知可同步取消/重入或移除施法者；旧释放只能退自己的成本，不能消耗/清理新请求。
	if _current_context != context:
		for cost: SkillCostBase in committed_costs:
			if is_instance_valid(cost): cost.refund(context)
		return false
	if not is_instance_valid(context.caster) or not context.caster.is_inside_tree() or context.caster.is_queued_for_deletion() or (context.caster is UnitBase and (context.caster as UnitBase).is_dead()):
		_refund_costs(committed_costs)
		_fail_active(&"owner_invalid_on_release", false)
		return false
	# 普通成本/释放前通知可能改变世界或承诺；交付接受前再次核对自己的真实预留。
	if _is_chain_root(context) and not context.command_request.authorize_release():
		_refund_costs(committed_costs)
		_fail_active(&"command_authorization_failed", false)
		return false
	if context.command_request != null:
		context.delivery_token_id = CombatDamageContext.allocate_id()
		if not context.command_request.retain_delivery(context.delivery_token_id):
			_refund_costs(committed_costs)
			_fail_active(&"command_lifetime_closed", false)
			return false
		_inflight_command_contexts[context.delivery_token_id] = context
	# 成本与释放通知完成后、Runner通知前冻结整批原点/朝向；每次释放均重新捕获。
	context.require_alive_on_delivery = require_alive
	context.release_caster_position = context.caster.global_position
	if context.caster is UnitBase:
		context.release_facing_direction = (context.caster as UnitBase).get_facing_direction()
	else:
		var horizontal := -context.caster.global_basis.z
		horizontal.y = 0.0
		context.release_facing_direction = horizontal.normalized() if horizontal.length_squared() > 0.000001 else Vector3.FORWARD
	var effects := _collect_effects()
	_release_accepted = false
	if not _delivery_runner.execute(
		delivery,
		_current_context,
		launch_transform,
		effects
	):
		_finish_command_delivery(context)
		_refund_costs(committed_costs)
		_fail_active(&"delivery_start_failed", true)
		return false

	var released_context: SkillContext = context
	_current_context = null
	_presentation_context = null
	if _is_chain_root(released_context):
		_state = _idle_timing_state()
	elif released_context.request_source == SkillContext.RequestSource.AI_AUTOMATIC:
		_start_post_release_hesitation()
	else:
		_start_cooldown()
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
	_stop_cast_presentation()
	_spawn_presentation(cancel_effect_scene, _last_action_transform)
	_current_context = null
	_presentation_context = null
	_state = _idle_timing_state() if _is_chain_root(cancelled_context) else SkillState.READY
	skill_cancelled.emit(cancelled_context, reason)


func reset_skill() -> void:
	if is_instance_valid(_delivery_runner) and _delivery_runner.is_busy():
		_delivery_runner.cancel(&"skill_reset")
	_current_context = null
	_presentation_context = null
	_cooldown_remaining = 0.0
	_post_release_hesitation_remaining = 0.0
	_state = SkillState.READY
	_clear_runtime_effect_references()


func can_request(context: SkillContext) -> bool:
	return _can_accept_purpose(context) and _prepare_context(context) != null


## 在当前位置可立即开始的只读预检；复用目标/条件/成本/范围，供终结可用性使用，不寻路排队。
func can_start_in_place(context: SkillContext) -> bool:
	if not _can_accept_purpose(context) or get_effective_cast_time() < 0: return false
	var prepared := _prepare_context(context)
	return prepared != null and _is_target_in_cast_range(prepared.resolved_target, prepared)

## 只停止本根请求尚未发射的项目；已发交付保持，不取消其他并行施放。
func stop_pending_emission(request_id: int) -> void:
	if is_instance_valid(_delivery_runner): _delivery_runner.stop_pending_emission(request_id)

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


## 返回 AI 自动施放成功后、独立技能冷却开始前的剩余犹豫时间，单位为秒。
## 非释放后等待状态时安全返回零；调用方只可读取，不能借此修改技能状态。
func get_post_release_hesitation_remaining() -> float:
	return _post_release_hesitation_remaining


## 返回直接挂载的唯一动画位移组件；重复组件配置无效，不按节点名猜测。
func get_motion_component() -> SkillMotionComponent:
	var found: SkillMotionComponent = null
	for child: Node in get_children():
		if child is SkillMotionComponent:
			if found != null: return null
			found = child
	return found


## 返回动作层只读负载；位移事实由组件自动附加，无组件/无专属动作时保留旧空字典。
## 行为层不需要知道技能内部节点名；参数与时钟由本次请求提供。
func get_action_payload() -> Dictionary:
	if cinematic_profile != null and _current_context != null and _current_context.execution_mode == SkillContext.ExecutionMode.CHARACTER_ACTION:
		var profile := _current_context.cinematic_profile_snapshot if _current_context.cinematic_profile_snapshot != null else cinematic_profile
		var budget := profile.action_animation.length + 1.0
		if delivery is ArcProjectileDeliveryConfig:
			var config := delivery as ArcProjectileDeliveryConfig
			var count := config.shot_count
			if config.destination_mode == ArcProjectileDeliveryConfig.DestinationMode.UNIT_TARGET and config.target_expansion != null:
				count *= maxi(1, config.target_expansion.select_targets(_current_context, _current_context.resolved_target as UnitBase).size())
			budget = maxf(budget, get_effective_cast_time() + (count - 1) * config.shot_interval_seconds + 1.0)
		return {"action_animation":profile.action_animation, "execution_clock":_current_context.execution_clock, "wait_for_emission":delivery is ArcProjectileDeliveryConfig, "action_budget_seconds":budget, "skill_motion_enabled":get_motion_component() != null}
	for child: Node in get_children():
		if child is MeleeSkillAction:
			var payload := (child as MeleeSkillAction).get_action_payload(threat_multiplier)
			if _current_context != null and _current_context.damage_context != null:
				payload[&"damage_context"] = _current_context.damage_context.duplicate_context()
			payload["skill_motion_enabled"] = get_motion_component() != null
			if action_animation != null:
				payload["action_animation"] = action_animation
			return payload
	var ordinary_payload: Dictionary = {"skill_motion_enabled":true} if get_motion_component() != null else {}
	if action_animation != null:
		ordinary_payload["action_animation"] = action_animation
	return ordinary_payload


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


## 不占用动作的通用预检；返回新context或null，保留原目标/条件/非专注成本验证，不支付。
func prepare_request(context: SkillContext) -> SkillContext:
	return _prepare_context(context)


## 更新尚未开始动画的排队请求；保持同一根身份，重新使用通用目标/条件检查，不生成取消事件。
func refresh_queued_request(context: SkillContext) -> bool:
	if _state != SkillState.QUEUED or _current_context == null or context == null or _current_context.command_request != context.command_request:
		return false
	var prepared := _prepare_context(context)
	if prepared == null: return false
	prepared.threat_multiplier = maxf(threat_multiplier, 0.0)
	_current_context = prepared
	try_request_action()
	return true


func _is_chain_root(context: SkillContext) -> bool:
	return context != null and context.purpose == SkillContext.Purpose.CHAIN and context.execution_mode == SkillContext.ExecutionMode.CHARACTER_ACTION and context.request_source == SkillContext.RequestSource.EXPLICIT and context.command_request != null and context.command_request.get_skill() == self and context.command_request.get_caster() == _skill_owner


func _can_accept_purpose(context: SkillContext) -> bool:
	if _is_chain_root(context):
		return _state in [SkillState.READY, SkillState.COOLDOWN, SkillState.POST_RELEASE_HESITATION]
	return _state == SkillState.READY and context != null and (context.purpose == SkillContext.Purpose.REGULAR or (context.purpose == SkillContext.Purpose.FINISHER and context.execution_mode == SkillContext.ExecutionMode.CHARACTER_ACTION and context.request_source == SkillContext.RequestSource.EXPLICIT))


func _idle_timing_state() -> SkillState:
	if _post_release_hesitation_remaining > 0.0: return SkillState.POST_RELEASE_HESITATION
	if _cooldown_remaining > 0.0: return SkillState.COOLDOWN
	return SkillState.READY


func _prepare_context(source: SkillContext) -> SkillContext:
	if (
		source == null
		or source.purpose not in [SkillContext.Purpose.REGULAR, SkillContext.Purpose.CHAIN, SkillContext.Purpose.FINISHER]
		or (source.purpose in [SkillContext.Purpose.CHAIN, SkillContext.Purpose.FINISHER] and (source.execution_mode != SkillContext.ExecutionMode.CHARACTER_ACTION or source.request_source != SkillContext.RequestSource.EXPLICIT))
		or not is_instance_valid(_skill_owner)
		or not _skill_owner.is_inside_tree()
		or delivery == null
		or not delivery.validate_configuration().is_empty()
	):
		return null
	if cinematic_profile != null and source.execution_mode == SkillContext.ExecutionMode.CHARACTER_ACTION and not cinematic_profile.validate_configuration().is_empty():
		return null
	var prepared := source.duplicate_context() as SkillContext
	if prepared.cinematic_profile_snapshot == null and cinematic_profile != null and prepared.execution_mode == SkillContext.ExecutionMode.CHARACTER_ACTION:
		prepared.cinematic_profile_snapshot = cinematic_profile.duplicate() as SkillCinematicProfile
	prepared.caster = _skill_owner
	prepared.host = _skill_host
	if is_instance_valid(_delivery_parent):
		prepared.delivery_parent = _delivery_parent
	if not is_instance_valid(prepared.delivery_parent):
		return null
	if prepared.damage_context == null:
		prepared.damage_context = CombatDamageContext.create(_skill_owner, prepared.delivery_parent, CombatDamageContext.Origin.FINISHER if prepared.purpose == SkillContext.Purpose.FINISHER else CombatDamageContext.Origin.NORMAL, CombatDamageContext.allocate_id(), 0, skill_id)
	else:
		prepared.damage_context = prepared.damage_context.for_skill(skill_id)
	prepared.resolved_target = _resolve_target(prepared)
	if not _is_candidate_valid(prepared.resolved_target, false):
		return null
	for condition: SkillConditionBase in _collect_conditions():
		if not condition.applies_to(prepared):
			continue
		if not condition.evaluate(prepared):
			return null
	for cost: SkillCostBase in _collect_costs():
		if not cost.can_pay(prepared):
			return null
	return prepared


func _resolve_target(context: SkillContext) -> Node3D:
	if is_instance_valid(context.preferred_target) and TargetResolver.is_candidate_valid(_skill_owner, context.preferred_target, target_relations, require_targetable, require_alive):
		return context.preferred_target
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


## target_value为待检目标；context默认取当前请求，直接触发时由其发射位置作为距离起点。
## additional_range_m为本次检查额外允许的水平米数；默认0，只有真实释放检查传入技能容差，不影响启动射程。
func _is_target_in_cast_range(target_value: Variant, context: SkillContext = null, additional_range_m: float = 0.0) -> bool:
	if (
		not is_instance_valid(target_value)
		or not target_value is Node3D
		or not is_instance_valid(_skill_owner)
	):
		return false
	var target := target_value as Node3D
	var origin: Vector3 = _skill_owner.global_position
	var active_context := context if context != null else _current_context
	if (
		active_context != null
		and active_context.execution_mode == SkillContext.ExecutionMode.DIRECT_TRIGGER
		and active_context.activation_transform.is_finite()
	):
		origin = active_context.activation_transform.origin
	var offset: Vector3 = target.global_position - origin
	offset.y = 0.0
	return offset.length() <= maxf(cast_range, 0.0) + maxf(additional_range_m, 0.0) + 0.05


## 查找根技能唯一费用组件；缺失、重复或非法返回null，普通技能无需配置。
func get_combo_focus_cost() -> ComboFocusCost:
	var found: ComboFocusCost = null
	for child: Node in get_children():
		if child is ComboFocusCost:
			if found != null: return null
			found = child as ComboFocusCost
	return found if found != null and found.validate_configuration().is_empty() else null


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
) -> Node3D:
	if (
		effect_scene == null
		or not world_transform.is_finite()
		or _current_context == null
		or not is_instance_valid(_current_context.delivery_parent)
	):
		return null
	var instance: Node = effect_scene.instantiate()
	if not instance is Node3D:
		if is_instance_valid(instance):
			instance.free()
		return null
	var effect := instance as Node3D
	# 纯表现归属：世界锚点下的蓄力/特效也以弱引用标记施放者，供镜头排除本人表现；无战斗权限。
	if is_instance_valid(_skill_owner): effect.set_meta(&"presentation_source_ref",weakref(_skill_owner))
	if effect.has_method(&"configure_cast"):
		effect.set("autoplay", false)
	_current_context.delivery_parent.add_child(effect)
	effect.global_transform = world_transform
	_runtime_effect_instances.append(effect)
	return effect


## 新型蓄力组件可选实现 configure_cast(source, world_origin, duration)：
## source 为施法者，world_origin 为动作发射变换，duration 为本次实际施法秒数。
## 旧特效仍沿用自身自动播放，不要求实现此接口。
func _schedule_cast_presentation(origin: Transform3D) -> void:
	_stop_cast_presentation()
	var ratio := clampf(cast_effect_start_ratio, 0.0, 1.0) if is_finite(cast_effect_start_ratio) else 0.0
	_cast_effect_delay_remaining = maxf(get_effective_cast_time(), 0.0) * ratio
	_cast_effect_pending = true
	_last_action_transform = origin
	_advance_cast_presentation(0.0)


# 只使用战斗delta，不创建跨动作的异步定时回调；每次动作只跨越一次阈值。
func _advance_cast_presentation(delta: float) -> void:
	if not _cast_effect_pending or _state != SkillState.CASTING: return
	_cast_effect_delay_remaining = maxf(_cast_effect_delay_remaining - maxf(delta, 0.0), 0.0)
	if _cast_effect_delay_remaining > 0.000001: return
	_cast_effect_pending = false
	var cue_context := _current_context
	_spawn_cast_presentation(_last_action_transform)
	if cue_context != null and _current_context == cue_context and _state == SkillState.CASTING:
		cast_cue_reached.emit(cue_context)


func _spawn_cast_presentation(origin: Transform3D) -> void:
	_stop_cast_presentation()
	if cast_effect_scene == null: return
	var pose := origin
	var attach: Node3D
	var player := get_node_or_null(^"RuntimeEffects") as SkillReleasePresentationPlayer
	if is_instance_valid(player):
		# 复用既有锚点解析；只准备位置，不启动Release音效、成功事实或强调时停。
		var snapshot := player.prepare_release(_current_context, origin, cast_effect_scene,
			int(cast_effect_anchor), null, null)
		pose = snapshot.get("world_transform", origin)
		var attach_ref := snapshot.get("attach_parent_ref") as WeakRef
		attach = attach_ref.get_ref() as Node3D if attach_ref != null else null
	var effect := _spawn_presentation(cast_effect_scene, pose)
	if not is_instance_valid(effect): return
	_cast_effect_instance = effect
	if _current_context != null and effect.has_method(&"set_execution_clock"):
		effect.call(&"set_execution_clock", _current_context.execution_clock)
	if is_instance_valid(attach) and attach.is_inside_tree() and not attach.is_queued_for_deletion():
		effect.reparent(attach, true)
	if effect.has_method(&"configure_cast"):
		# 可伸缩蓄力资产仍接收原动作发射变换，不把脚下锚点误当成武器位置。
		effect.call(&"configure_cast", _skill_owner, origin, get_effective_cast_time())
		if effect.has_method(&"play"):
			effect.call(&"play")


# 成功释放只结束configure_cast蓄力；keep_one_shot为真时一次性资产继续自回收，避免短施法截断视觉。
# 取消、失败、重置和下一次施法仍使用默认false，立即清理当前仍在施法阶段的资产。
func _stop_cast_presentation(keep_one_shot: bool = false) -> void:
	_cast_effect_pending = false
	_cast_effect_delay_remaining = 0.0
	if is_instance_valid(_cast_effect_instance):
		# 只把存活对象传入强类型数组；先移除，再调用可能自行销毁的stop接口。
		_runtime_effect_instances.erase(_cast_effect_instance)
		var charge := _cast_effect_instance.has_method(&"configure_cast")
		if not keep_one_shot or charge:
			if _cast_effect_instance.has_method(&"stop"):
				_cast_effect_instance.call(&"stop")
			if is_instance_valid(_cast_effect_instance):
				_cast_effect_instance.queue_free()
	# 原生一次性资产可能早于技能自行回收；用索引清除失效项，不以失效对象调用erase。
	for index: int in range(_runtime_effect_instances.size()-1, -1, -1):
		if not is_instance_valid(_runtime_effect_instances[index]):
			_runtime_effect_instances.remove_at(index)
	_cast_effect_instance = null


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
	_stop_cast_presentation()
	var failed_context: SkillContext = _current_context
	_current_context = null
	_presentation_context = null
	## 必须先完成技能自身的终止状态迁移，再向 Host 发出失败信号。
	##
	## Host 会在信号回调中检查技能是否已经离开 QUEUED、ACTION_REQUESTED 或
	## CASTING。若先发送信号、后改状态，Host 会误判请求仍在运行，从而永久保留
	## active_skill，后续自动施法便无法再次开始。
	if delivery_failure and cooldown_on_failed_release and not _is_chain_root(failed_context):
		_start_cooldown()
	else:
		_state = _idle_timing_state() if _is_chain_root(failed_context) else SkillState.READY
	skill_failed.emit(failed_context, reason)


## Runner在产生任何接受后的效果前通知；只接当前execute，恰好一次向Host转发。
func _on_runner_delivery_started(context: SkillContext) -> void:
	if context != _current_context or _release_accepted: return
	_release_accepted = true
	_state = SkillState.RELEASED
	var player := get_node_or_null(^"RuntimeEffects") as SkillReleasePresentationPlayer
	var snapshot: Dictionary = {}
	if is_instance_valid(player):
		if _presentation_context == null:
			_presentation_context = SkillPresentationContext.create(self, context, _last_action_transform)
		var fact := _presentation_context
		snapshot = player.prepare_release(context, _last_action_transform,
			fact.visual_scene if fact != null else release_effect_scene,
			fact.release_effect_anchor if fact != null else int(release_effect_anchor),
			fact.audio_stream if fact != null else release_audio_stream,
			fact.get_camera_profile() if fact != null else camera_effect_profile, fact)
	# 原有Host/专注提交先完成；表现只使用此前准备的快照，不重新读_current_context。
	delivery_started.emit(context)
	if is_instance_valid(player) and player.is_inside_tree() and not player.is_queued_for_deletion():
		player.play_release(snapshot)

# RuntimeEffects的同步请求只向根节点转发；不让消费者依赖内部节点路径。
func _on_camera_effect_requested(profile: CameraEffectProfile, source: Node3D,
		target: Node3D, world_transform: Transform3D) -> void:
	camera_effect_requested.emit(profile, source, target, world_transform)


func _on_runner_delivery_finished(
	context: SkillContext,
	result: SkillDeliveryResult
) -> void:
	delivery_finished.emit(context, result)
	_finish_command_delivery(context)


func _on_runner_delivery_failed(
	context: SkillContext,
	reason: StringName
) -> void:
	delivery_failed.emit(context, reason)
	if _state in [
		SkillState.RELEASED,
		SkillState.POST_RELEASE_HESITATION,
		SkillState.COOLDOWN,
	]:
		skill_failed.emit(context, reason)
	_finish_command_delivery(context)


func _finish_command_delivery(context: SkillContext) -> void:
	if context == null or context.command_request == null or not _inflight_command_contexts.has(context.delivery_token_id): return
	_inflight_command_contexts.erase(context.delivery_token_id)
	context.command_request.finish_delivery(context.delivery_token_id)


func _clear_runtime_effect_references() -> void:
	_stop_cast_presentation()
	for effect: Node in _runtime_effect_instances:
		if is_instance_valid(effect):
			effect.queue_free()
	_runtime_effect_instances.clear()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var motion_count := 0
	for child: Node in get_children():
		if child is SkillMotionComponent:
			motion_count += 1
			warnings.append_array(child.validate_configuration())
	if motion_count > 1: warnings.append("每个技能只允许一个SkillMotionComponent。")
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
	elif not _presentation_script_is_configured():
		warnings.append("RuntimeEffects requires SkillReleasePresentationPlayer; gameplay still runs without presentation.")
	return warnings


# 编辑器非tool子脚本可能是占位对象，沿Script继承链检查，允许合法播放器子类。
func _presentation_script_is_configured() -> bool:
	var node := get_node_or_null(^"RuntimeEffects")
	var script: Script = node.get_script() if node != null else null
	while script != null:
		if script.get_global_name() == &"SkillReleasePresentationPlayer":
			return true
		script = script.get_base_script()
	return false

func _exit_tree() -> void:
	for context in _inflight_command_contexts.values():
		_finish_command_delivery(context)
	_inflight_command_contexts.clear()
	_clear_runtime_effect_references()
	_current_context = null
	_presentation_context = null
## 当前动作的只读快照；无活动动作时为空，禁止以此控制技能流程。
func get_current_presentation_context() -> SkillPresentationContext: return _presentation_context

func _on_release_instance_prepared(presentation: SkillPresentationContext, instance: Node) -> void:
	release_instance_prepared.emit(presentation, instance)

func _on_release_presentation_started(presentation: SkillPresentationContext) -> void:
	release_presentation_started.emit(presentation)