class_name IndependentSkillPresentationBase
extends Resource

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")
const SkillDeliveryResultType = preload("res://SkillSystem/01-Core/SkillDeliveryResult.gd")

## 表现策略抽象基类。返回生成的节点；没有表现时安全返回 null。
func play(
	_parent: Node,
	_world_transform: Transform3D,
	_context: SkillContextType,
	_result: SkillDeliveryResultType = null
) -> Node:
	return null
