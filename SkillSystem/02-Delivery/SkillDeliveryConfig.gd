@tool
class_name SkillDeliveryConfig
extends Resource

## Delivery 静态配置的抽象父类。
##
## Resource 只保存可在 Inspector 中编辑的数据，不保存飞行计时、当前投射物等
## 运行状态。全部运行状态统一由 SkillDeliveryRunner 持有。


## 返回可稳定显示在 Inspector 和测试中的配置问题。
## 抽象父类本身不可直接执行，因此默认返回一条明确警告。
func validate_configuration() -> PackedStringArray:
	return PackedStringArray(["SkillDeliveryConfig is abstract."])
