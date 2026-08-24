class_name IndependentSkillDecisionPolicyBase
extends Resource

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")

## 决策策略抽象基类。默认无等待，便于手动技能和测试安全使用。
func get_decision_delay(
	_context: SkillContextType,
	_random_generator: RandomNumberGenerator
) -> float:
	return 0.0
