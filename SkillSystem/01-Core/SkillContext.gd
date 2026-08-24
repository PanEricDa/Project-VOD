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
var delivery_parent: Node
var request_source: int = 0
## 本次请求快照携带的伤害仇恨倍率。## 由 SkillBase 在请求进入队列时写入；只供伤害交付读取，不会改变伤害数值、治疗数值或目标选择。## 默认 1.0 兼容所有未配置额外仇恨的技能。
var threat_multiplier: float = 1.0
## true 表示调用方已经明确指定本次目标，SkillBase 只验证而不重新执行自动选择。
## false 表示本次请求来自 AI 自动决策，需要依据技能自身的选择模式解析候选。
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
	copy.delivery_parent = (
		delivery_parent if is_instance_valid(delivery_parent) else null
	)
	copy.request_source = request_source
	copy.threat_multiplier = maxf(threat_multiplier, 0.0)
	copy.explicit_target_requested = explicit_target_requested
	return copy
