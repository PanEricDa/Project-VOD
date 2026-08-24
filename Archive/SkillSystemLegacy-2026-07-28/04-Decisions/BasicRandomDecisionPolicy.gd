class_name IndependentBasicRandomDecisionPolicy
extends "res://SkillSystem/04-Decisions/SkillDecisionPolicyBase.gd"

@export_category("Normal Delay")
@export_range(0.0, 10.0, 0.1) var normal_delay_min: float = 0.3
@export_range(0.0, 10.0, 0.1) var normal_delay_max: float = 3.0

@export_category("Extra Hesitation")
@export_range(0.0, 1.0, 0.01) var extra_hesitation_chance: float = 0.10
@export_range(0.0, 10.0, 0.1) var extra_hesitation_min: float = 3.0
@export_range(0.0, 10.0, 0.1) var extra_hesitation_max: float = 5.0


## 只有 AI 请求应用随机决策节奏；手动和强制请求立即进入技能队列。
func get_decision_delay(
	context: SkillContextType,
	random_generator: RandomNumberGenerator
) -> float:
	if not is_instance_valid(context):
		return 0.0
	if context.request_mode != SkillContextType.RequestMode.AI:
		return 0.0
	var normal_min: float = minf(normal_delay_min, normal_delay_max)
	var normal_max: float = maxf(normal_delay_min, normal_delay_max)
	var delay: float = random_generator.randf_range(normal_min, normal_max)
	if random_generator.randf() < clampf(extra_hesitation_chance, 0.0, 1.0):
		var extra_min: float = minf(extra_hesitation_min, extra_hesitation_max)
		var extra_max: float = maxf(extra_hesitation_min, extra_hesitation_max)
		delay += random_generator.randf_range(extra_min, extra_max)
	return maxf(delay, 0.0)
