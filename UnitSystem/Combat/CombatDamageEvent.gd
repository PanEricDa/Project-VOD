class_name CombatDamageEvent
extends RefCounted
## 实际扣血的只读业务快照；只在单位权威入口发布。
var _data: Dictionary = {}
var _claims: Dictionary = {}
## 本笔实际扣血的唯一身份，不等于逻辑命中身份。
var event_id: int:
	get: return _data.event_id
## 伤害用途枚举，只由请求创建入口决定，不根据角色当前动作推断。
var origin: int:
	get: return _data.origin
## 根请求身份；0 为非技能兼容入口，触发子技能继承。
var request_id: int:
	get: return _data.request_id
## 费用/评分批次身份；本类不维护评分窗口，0 表示无批次。
var round_id: int:
	get: return _data.round_id
## 本段技能标识，仅诊断使用，不决定收益。
var skill_id: StringName:
	get: return _data.skill_id
## 单目标真实命中身份；同命中数值拆分共享，0 为尚未分配。
var hit_id: int:
	get: return _data.hit_id
## 发起请求所属场景实例身份，0 为无可用场景。
var scene_scope_id: int:
	get: return _data.scene_scope_id
## 施加伤害的单位实例身份快照，删除节点后仍有效。
var source_instance_id: int:
	get: return _data.source_instance_id
## 发起时队伍编号快照，0 表示未知或中立。
var source_team_id: int:
	get: return _data.source_team_id
## 专注收益属性；普通来源 1，其余 0，不改变伤害或仇恨。
var focus_yield_multiplier: float:
	get: return _data.focus_yield_multiplier
## 受击目标的实例身份快照。
var target_instance_id: int:
	get: return _data.target_instance_id
## 受击时队伍编号快照。
var target_team_id: int:
	get: return _data.target_team_id
## 本笔生命实际减少量，不含过量伤害。
var actual_damage: float:
	get: return _data.actual_damage
## 本笔扣血之前的生命值快照。
var health_before: float:
	get: return _data.health_before
## 本笔扣血之后的生命值快照。
var health_after: float:
	get: return _data.health_after

## context 为来源快照，target 为扣血时仍有效目标，before/after 是本笔真实生命值。
## 非有限、非正差值或无效目标返回 null；事件不保留单位节点。
static func create(context: CombatDamageContext, target: Node, before: float, after: float) -> CombatDamageEvent:
	if context == null or not is_instance_valid(target) or not is_finite(before) or not is_finite(after) or after < 0.0 or before <= after:
		return null
	var result := CombatDamageEvent.new()
	for key in ["origin", "request_id", "round_id", "skill_id", "scene_scope_id", "source_instance_id", "source_team_id", "focus_yield_multiplier"]:
		result._data[key] = context.get(key)
	result._data.event_id = CombatDamageContext.allocate_id()
	result._data.hit_id = context.hit_id if context.hit_id > 0 else CombatDamageContext.allocate_id()
	result._data.target_instance_id = target.get_instance_id()
	var team: Variant = target.get("team_id")
	result._data.target_team_id = int(team) if team != null else 0
	result._data.actual_damage = before - after
	result._data.health_before = before
	result._data.health_after = after
	return result

## consumer_key 必须是某个消费者实例的非空唯一键；同一事件同一消费者只允许一次。
## 本地防重不改变业务快照，也不阻止其他消费者独立接收。
func claim(consumer_key: StringName) -> bool:
	if consumer_key.is_empty() or _claims.has(consumer_key):
		return false
	_claims[consumer_key] = true
	return true
