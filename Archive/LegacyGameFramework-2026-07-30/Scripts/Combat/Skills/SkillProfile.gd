class_name SkillProfile
extends Resource

## 技能目标阵营仅描述技能期望接收的目标类型。
## 父模块不会搜索目标；具体目标仍由外部调度器或未来职业子模块提供。
enum SkillTargetFaction {
	ENEMY,
	ALLY,
	SELF
}

## 技能交付类型用于 Inspector、调试输出和继承场景的一致性检查。
## 父模块不会根据该枚举生成投射物、AOE 或治疗效果。
enum SkillDeliveryType {
	PROJECTILE,
	GROUND_AOE,
	INSTANT_TARGET
}

## Inspector 中显示的技能名称。
@export var display_name: String = "Skill"

## 技能期望作用的阵营类型。
@export var target_faction: SkillTargetFaction = SkillTargetFaction.ENEMY

## 子模块计划采用的交付方式；当前父类只输出占位交付日志。
@export var delivery_type: SkillDeliveryType = SkillDeliveryType.PROJECTILE

## 可选目标组限制；留空时只检查目标实例和场景树状态。
@export var required_target_group: StringName = &""

@export_category("AI Selection")
## 数值越高越优先被通用宿主选择；同优先级由宿主随机选择。
@export var ai_priority: int = 0

## 为 true 时宿主可以在施法计时期间继续执行自己的移动策略。
@export var can_move_while_casting: bool = false

@export_category("Cast")
## 允许开始和完成施法的水平距离，单位为米。
@export_range(0.0, 50.0, 0.1) var cast_range: float = 5.0

## 施法距离的边界容差，避免目标在边缘轻微抖动时频繁失败。
@export_range(0.0, 5.0, 0.05) var cast_range_tolerance: float = 0.25

## 从正式开始施法到尝试交付技能的持续时间，单位为秒。
@export_range(0.0, 10.0, 0.05) var cast_time: float = 0.5

## 成功交付技能后启动的技能专属冷却，单位为秒。
@export_range(0.0, 120.0, 0.1) var skill_cooldown: float = 6.0

@export_category("Decision Delay")
## 找到合法目标后正常决策等待的最短时间。
@export_range(0.0, 10.0, 0.1) var decision_delay_min: float = 0.3

## 找到合法目标后正常决策等待的最长时间。
@export_range(0.0, 10.0, 0.1) var decision_delay_max: float = 3.0

## 每次请求只判定一次的额外犹豫概率，默认 10%。
@export_range(0.0, 1.0, 0.01) var extra_hesitation_chance: float = 0.10

## 触发额外犹豫时追加的最短时间。
@export_range(0.0, 10.0, 0.1) var extra_hesitation_min: float = 3.0

## 触发额外犹豫时追加的最长时间。
@export_range(0.0, 10.0, 0.1) var extra_hesitation_max: float = 5.0
