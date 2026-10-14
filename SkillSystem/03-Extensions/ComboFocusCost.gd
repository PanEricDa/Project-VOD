@tool
class_name ComboFocusCost
extends Node
## 连携根技能的专注配置；不参与普通SkillCostBase支付，队伍控制器统一管理预留和提交。
@export_category("Combo Focus")
## 首次释放的基础专注点，默认20；必须有限非负，仅用于本根连携请求。
@export_range(0.0, 1000000.0, 0.1, "or_greater") var base_focus_cost: float = 20.0
## 同轮同伙伴同技能此前每成功释放一次增加的专注点，默认10；失败不计重复，必须有限非负。
@export_range(0.0, 1000000.0, 0.1, "or_greater") var repeat_focus_cost: float = 10.0

## 返回配置问题；空数组表示两个费用均为有限非负值，不归一化非法配置为免费。
func validate_configuration() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_finite(base_focus_cost) or base_focus_cost < 0.0:
		warnings.append("连携基础专注费用必须为有限非负数。")
	if not is_finite(repeat_focus_cost) or repeat_focus_cost < 0.0:
		warnings.append("连携重复附加费用必须为有限非负数。")
	return warnings

func _get_configuration_warnings() -> PackedStringArray:
	return validate_configuration()
