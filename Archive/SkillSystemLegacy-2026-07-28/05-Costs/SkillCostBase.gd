class_name IndependentSkillCostBase
extends Resource

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")

## 费用策略抽象基类。默认拒绝，避免缺少真实费用实现时错误释放技能。
func can_pay(_context: SkillContextType) -> bool:
	return false


func commit(_context: SkillContextType) -> bool:
	return false


## 退款接口由 SkillBase 在 Delivery 启动失败时最多调用一次。
func refund(_context: SkillContextType) -> void:
	pass


func get_failure_reason(_context: SkillContextType) -> StringName:
	return &"cost_not_implemented"
