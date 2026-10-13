@tool
class_name SkillTargetExpansion
extends Resource

## 一次技能释放前的可配置目标扩展策略；默认只保留主要目标。


## 根据本次请求和主要目标返回去重后的目标列表；context 不得在此被修改，
## primary 必须是有效的 UnitBase，调用方在实际发射前再次验证目标生命周期。
func select_targets(_context: SkillContext, primary: UnitBase) -> Array[UnitBase]:
	var targets: Array[UnitBase] = []
	if is_instance_valid(primary):
		targets.append(primary)
	return targets
