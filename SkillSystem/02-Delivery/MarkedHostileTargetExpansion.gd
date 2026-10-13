@tool
class_name MarkedHostileTargetExpansion
extends SkillTargetExpansion

## 筛选敌方单位时要求的命名状态 ID；默认空表示不筛选任何附加目标，
## 只影响本次释放的额外目标与使用该查询的 AI 条件。
@export var status_id: StringName = &""


## 返回当前战斗中仍存活、可选取且带配置状态的敌方单位；context 提供施法者
## 和交付场景根节点。优先使用 EncounterController 的 ENGAGED 敌人；没有该控制器时
## 只读取同一场景根节点下的 enemy_targets 组，避免跨测试场景或房间误选。
func marked_targets(context: SkillContext) -> Array[UnitBase]:
	var marked: Array[UnitBase] = []
	if (
		context == null or not is_instance_valid(context.caster)
		or not is_instance_valid(context.delivery_parent) or status_id.is_empty()
	):
		return marked
	var candidates: Array[Node] = []
	var encounter := context.delivery_parent.get_node_or_null(^"EncounterController")
	if is_instance_valid(encounter) and encounter.has_method(&"get_engaged_enemies"):
		for enemy: Variant in encounter.call(&"get_engaged_enemies"):
			if enemy is Node:
				candidates.append(enemy as Node)
	else:
		for enemy: Node in context.delivery_parent.get_tree().get_nodes_in_group(&"enemy_targets"):
			if context.delivery_parent == enemy or context.delivery_parent.is_ancestor_of(enemy):
				candidates.append(enemy)
	for candidate: Node in candidates:
		if not candidate is UnitBase:
			continue
		var unit := candidate as UnitBase
		if not TargetResolver.is_candidate_valid(
			context.caster, unit, TargetResolver.TargetRelationFlag.HOSTILE, true, true
		):
			continue
		var status := unit.get_status_effect_component()
		if is_instance_valid(status) and status.has_named_status(status_id):
			marked.append(unit)
	marked.sort_custom(func(a: UnitBase, b: UnitBase) -> bool:
		return a.get_instance_id() < b.get_instance_id()
	)
	return marked


## 以 primary 为第一目标，再追加所有带状态的敌人，每个实例仅出现一次；
## 此快照在投射物生成前计算，之后不因状态变化追加目标。
func select_targets(context: SkillContext, primary: UnitBase) -> Array[UnitBase]:
	var targets: Array[UnitBase] = []
	if is_instance_valid(primary):
		targets.append(primary)
	for target: UnitBase in marked_targets(context):
		if target != primary:
			targets.append(target)
	return targets
