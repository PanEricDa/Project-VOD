class_name SkillContext
extends RefCounted

## 单次技能请求的运行时上下文。
##
## 本对象只保存一次请求需要的数据快照，不保存技能配置，也不反向读取
## AllyBase、PlayerBase 或某个具体职业脚本。这样 SkillSystem 可以独立测试，
## UnitSystem 只需通过公开接口把施法者、候选目标和世界父节点注入进来。

var caster: Node3D
var host: Node
var requested_target: Node3D
var resolved_target: Node3D
var candidate_targets: Array[Node3D] = []
var target_position: Vector3 = Vector3.INF
## 真实交付前捕获的施法者脚下世界位置；INF表示尚未释放，Effect不得逐目标重读施法者位置。
var release_caster_position: Vector3 = Vector3.INF
## 同一释放批次共享的稳定水平朝向；ZERO表示尚未释放，不读取武器动画姿态。
var release_facing_direction: Vector3 = Vector3.ZERO
## 真实交付时冻结技能require_alive；默认true。瞬发执行器据此复查生命，不把尸体技能强改为存活目标。
var require_alive_on_delivery: bool = true
var delivery_parent: Node
## 单次伤害来源快照；空表示尚未创建。复制必须独立，衍生交付继承根归属与收益。
var damage_context: CombatDamageContext
## 可选请求级时间域；普通请求为空，副本/衍生交付共享同一时钟，不写入静态资源。
var execution_clock: SkillExecutionClock
## 角色动作开始时采用的演出只读副本；A/B与动画配置只影响下次，不持有运行进度。
var cinematic_profile_snapshot: SkillCinematicProfile
## 本次根执行正身份，普通兼容为0；仅供动画/交付隔离，不是策划配置。
var execution_id: int = 0
## 本次地面采样局部随机种子；0为独立随机，预览可给固定非0值，不修改全局随机源。
var scatter_seed: int = 0
## 本次冻结的终结评分威力倍率；普通/直接预览默认1，须有限且>=1。正式评分曲线范围1至1.5。
## 沿复制与触发子技能传递，不依靠purpose推断来源；由各Effect开关决定消费，不在交付层重复相乘。
var finisher_multiplier: float = 1.0
## 请求用途；普通默认REGULAR，CHAIN仅用于角色动作根连携，不传给触发子技能。
enum Purpose { REGULAR, CHAIN, FINISHER }
var purpose: int = Purpose.REGULAR
## 可选首选目标意图；技能自行验证关系，默认空，不改变AI长期锁定。
var preferred_target: Node3D
## 根指令生命周期，复制时共享；普通技能为空，子交付继承但不重新收费。
var command_request: SkillCommandRequest
## 本次交付身份；execute前分配，触发子context从0创建自己的token。
var delivery_token_id: int = 0
## 本次执行方式只由请求方决定，不是技能场景的固定类型；默认走角色动作和动画释放帧。
enum ExecutionMode { CHARACTER_ACTION, DIRECT_TRIGGER }

## DIRECT_TRIGGER 跳过角色动作，但仍使用技能自身的验证、消耗、交付和冷却。
var execution_mode: int = ExecutionMode.CHARACTER_ACTION
## 直接触发的世界发射变换；默认原点非有限，调用方必须明确填写；普通动作请求忽略此值。
var activation_transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3.INF)
## 已经过的技能场景路径，只供触发链拒绝循环；普通施放默认为空。
var trigger_scene_paths: Array[String] = []
## 请求来源只描述施放意图，与是否指定目标无关。
## EXPLICIT 包括玩家输入、队伍指令和脚本明确请求；AI_AUTOMATIC 表示 AI 自主选择。
enum RequestSource { EXPLICIT, AI_AUTOMATIC }

## 默认显式请求；自动选择入口必须写入 AI_AUTOMATIC，供条件适用范围判断。
var request_source: int = RequestSource.EXPLICIT
## 本次请求快照携带的伤害仇恨倍率。## 由 SkillBase 在请求进入队列时写入；只供伤害交付读取，不会改变伤害数值、治疗数值或目标选择。## 默认 1.0 兼容所有未配置额外仇恨的技能。
var threat_multiplier: float = 1.0
## true 表示调用方已经明确指定本次目标，SkillBase 只验证而不重新执行自动选择。
## false 表示依据技能自身的选择模式解析候选；它不代表请求一定来自 AI。
var explicit_target_requested: bool = false


## 为一次技能请求创建独立副本，避免调用者在请求进入队列后修改原始上下文。
## 复制时自动清空已释放节点，避免延迟施法请求访问无效目标。
func duplicate_context() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy.caster = caster if is_instance_valid(caster) else null
	copy.host = host if is_instance_valid(host) else null
	copy.requested_target = (
		requested_target if is_instance_valid(requested_target) else null
	)
	copy.resolved_target = (
		resolved_target if is_instance_valid(resolved_target) else null
	)
	for candidate: Node3D in candidate_targets:
		if is_instance_valid(candidate):
			copy.candidate_targets.append(candidate)
	copy.target_position = target_position
	copy.release_caster_position = release_caster_position
	copy.release_facing_direction = release_facing_direction
	copy.require_alive_on_delivery = require_alive_on_delivery
	copy.damage_context = damage_context.duplicate_context() if damage_context != null else null
	copy.delivery_parent = (
		delivery_parent if is_instance_valid(delivery_parent) else null
	)
	copy.cinematic_profile_snapshot = cinematic_profile_snapshot
	copy.execution_clock = execution_clock
	copy.execution_id = execution_id
	copy.scatter_seed = scatter_seed
	copy.finisher_multiplier = finisher_multiplier
	copy.purpose = purpose
	copy.preferred_target = preferred_target if is_instance_valid(preferred_target) else null
	copy.command_request = command_request
	copy.delivery_token_id = delivery_token_id
	copy.execution_mode = execution_mode
	copy.activation_transform = activation_transform
	copy.trigger_scene_paths.assign(trigger_scene_paths)
	copy.request_source = request_source
	copy.threat_multiplier = maxf(threat_multiplier, 0.0)
	copy.explicit_target_requested = explicit_target_requested
	return copy
