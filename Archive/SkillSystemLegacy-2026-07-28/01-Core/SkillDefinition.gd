class_name IndependentSkillDefinition
extends Resource

enum TargetRelation {
	ANY,
	SELF,
	FRIENDLY,
	HOSTILE,
	NEUTRAL,
}

@export_category("Identity")
@export var skill_id: StringName = &"default_skill"
@export var display_name: String = "Default Skill"
@export var ai_priority: int = 0

@export_category("Targeting")
@export var target_relation: TargetRelation = TargetRelation.ANY
@export var require_targetable: bool = true

@export_category("Cast")
@export_range(0.0, 100.0, 0.1, "or_greater") var cast_range: float = 5.0
@export_range(0.0, 10.0, 0.05, "or_greater") var cast_range_tolerance: float = 0.25
@export_range(0.0, 30.0, 0.05, "or_greater") var cast_time: float = 0.5
@export var can_move_while_casting: bool = false

@export_category("Cooldown")
@export_range(0.0, 600.0, 0.1, "or_greater") var skill_cooldown: float = 6.0
## 启用时，交付场景缺失或启动被拒绝也会施加技能冷却惩罚。
@export var cooldown_on_failed_delivery: bool = false

@export_category("Policies")
## 每个策略槽都使用对应抽象基类作为静态类型。
## 这样 Inspector 只允许选择兼容的 Resource，避免把表现、消耗或其他资源误装到目标选择器槽位。
@export var condition: IndependentSkillConditionBase
@export var target_selector: IndependentSkillTargetSelectorBase
@export var decision_policy: IndependentSkillDecisionPolicyBase
@export var cost: IndependentSkillCostBase
@export var cast_presentation: IndependentSkillPresentationBase
