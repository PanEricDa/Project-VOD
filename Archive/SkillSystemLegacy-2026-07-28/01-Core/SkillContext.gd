class_name IndependentSkillContext
extends RefCounted

## 单次技能请求的独立运行上下文。
## 该对象只保存一次请求的数据，禁止把这些字段写入可共享的技能 Resource。

enum RequestMode {
	MANUAL,
	AI,
	FORCED,
}

var request_mode: RequestMode = RequestMode.MANUAL
var caster: Node3D
var host: Node
var requested_target: Node3D
var resolved_target: Node3D
var target_position: Vector3 = Vector3.INF
var cast_origin: Vector3 = Vector3.ZERO
var delivery_parent: Node
var metadata: Dictionary = {}

## 以下字段是技能 Definition 在本次请求开始时的目标规则快照。
## 选择器只依赖上下文即可完成筛选，不需要反向依赖具体 SkillBase 节点或某个角色脚本。
var target_relation: int = 0
var require_targetable: bool = true
var cast_range: float = 0.0
var cast_range_tolerance: float = 0.0


## 创建上下文副本。节点引用保持指向同一运行实例，Dictionary 则独立复制，
## 避免选择器或技能修改副本时污染调用方保存的原始请求。
func duplicate_context() -> RefCounted:
	var copy: RefCounted = get_script().new() as RefCounted
	copy.set("request_mode", request_mode)
	copy.set("caster", caster)
	copy.set("host", host)
	copy.set("requested_target", requested_target)
	copy.set("resolved_target", resolved_target)
	copy.set("target_position", target_position)
	copy.set("cast_origin", cast_origin)
	copy.set("delivery_parent", delivery_parent)
	copy.set("metadata", metadata.duplicate(true))
	copy.set("target_relation", target_relation)
	copy.set("require_targetable", require_targetable)
	copy.set("cast_range", cast_range)
	copy.set("cast_range_tolerance", cast_range_tolerance)
	return copy
