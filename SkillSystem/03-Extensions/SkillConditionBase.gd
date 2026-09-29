class_name SkillConditionBase
extends Node

const SkillContextType = preload(
	"res://SkillSystem/01-Core/SkillContext.gd"
)

## 特殊技能条件组件的抽象父类。
##
## 阵营、目标有效性、距离与冷却由 SkillBase 统一处理；只有生命阈值、
## 装备要求等真正特殊的规则才需要继承本组件。

## AUTOMATIC_ONLY 仅限制 AI 自主施放；ALL_REQUESTS 同时限制显式指令。
enum ApplicationScope { AUTOMATIC_ONLY, ALL_REQUESTS }

## 条件适用范围；默认仅自动施放，玩家、队伍和脚本的显式请求跳过此软性条件。
## 选择所有施放后，每次请求都必须通过该条件；不影响冷却、消耗等底层合法性检查。
@export_enum("仅自动施放", "所有施放")
var application_scope: int = ApplicationScope.AUTOMATIC_ONLY


## 返回本次请求是否需要检查该条件；context 为当前请求快照，不修改它。
## 空上下文采取保守处理，仍要求检查条件。
func applies_to(context: SkillContextType) -> bool:
	return (
		context == null
		or application_scope != ApplicationScope.AUTOMATIC_ONLY
		or context.request_source == SkillContextType.RequestSource.AI_AUTOMATIC
	)


## 子类判断当前请求是否满足规则；context 提供施法者和已解析目标，返回 false 拒绝请求。
func evaluate(_context: SkillContextType) -> bool:
	return false


## 返回当前规则失败原因；context 与 evaluate 使用同一次请求的数据。
func get_failure_reason(_context: SkillContextType) -> StringName:
	return &"condition_not_implemented"
