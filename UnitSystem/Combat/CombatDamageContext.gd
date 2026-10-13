class_name CombatDamageContext
extends RefCounted
## 单次交付的只读来源快照；不是策划资源，无导出参数。
enum Origin { UNATTRIBUTED, NORMAL, CHAIN, FINISHER }
static var _serial: int = 0
var _data: Dictionary = {"origin": 0, "request_id": 0, "round_id": 0, "skill_id": &"", "hit_id": 0, "scene_scope_id": 0, "source_instance_id": 0, "source_team_id": 0, "focus_yield_multiplier": 0.0}
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

## source 为施加者，scene_scope 为该次交付所属世界；用途、根身份、批次和技能标识由入口提供。
## 无效用途降为未知；身份不得为负。不会保存节点强引用或改变任何单位状态。
static func create(source: Node, scene_scope: Node, source_origin: Origin = Origin.NORMAL, root_request_id: int = 0, chain_round_id: int = 0, diagnostic_skill_id: StringName = &"") -> CombatDamageContext:
	var result := CombatDamageContext.new()
	result._data.origin = source_origin if source_origin in [0, 1, 2, 3] else Origin.UNATTRIBUTED
	result._data.request_id = maxi(root_request_id, 0)
	result._data.round_id = maxi(chain_round_id, 0)
	result._data.skill_id = diagnostic_skill_id
	if is_instance_valid(source):
		result._data.source_instance_id = source.get_instance_id()
		var team: Variant = source.get("team_id")
		result._data.source_team_id = int(team) if team != null else 0
	if is_instance_valid(scene_scope):
		result._data.scene_scope_id = scene_scope.get_instance_id()
	result._data.focus_yield_multiplier = 1.0 if result.origin == Origin.NORMAL else 0.0
	return result

## 分配进程内唯一正身份；仅运行时使用，不生成 ResourceUID。
static func allocate_id() -> int:
	_serial += 1
	return _serial

## 独立复制值快照，禁止通过副本改变父交付归属。
func duplicate_context() -> CombatDamageContext:
	var result := CombatDamageContext.new()
	result._data = _data.duplicate()
	return result

## 为一个真实命中派生；正 hit_id 保留，0 则分配新身份，不改变父上下文。
func for_hit(new_hit_id: int) -> CombatDamageContext:
	var result := duplicate_context()
	result._data.hit_id = new_hit_id if new_hit_id > 0 else allocate_id()
	return result

## 更新子技能诊断名称，同时保留根请求、轮次与收益属性。
func for_skill(new_skill_id: StringName) -> CombatDamageContext:
	var result := duplicate_context()
	result._data.skill_id = new_skill_id
	return result
