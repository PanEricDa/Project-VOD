# 通用自动技能目标解析设计

## 目标

修复自动技能只能依赖敌方锁定目标的问题，使 `SkillBase` 已有的
`target_source`、`target_relation`、`cast_range`、`require_targetable`
与 Conditions 成为唯一的技能目标筛选规则。

## 根因

当前 `AllyBehaviorStateMachine` 仅在持有敌方战斗目标时调用自动技能，
而 `SkillHostComponent.request_best_skill()` 又为所有技能传入同一个敌方目标和
空的 `candidate_targets`。因此 `PROVIDED + HOSTILE` 的 Firebolt 可以工作，
`AUTO_NEAREST + FRIENDLY` 的 HolyLight 无候选可选。

## 设计

- `UnitBase` 在进入场景树时自动加入内部能力组
  `skill_target_candidates`。该组只表示“可以作为技能候选”，不表达阵营。
- `SkillHostComponent` 从能力组收集有效 `Node3D`，原样写入
  `SkillContext.candidate_targets`。
- `SkillHostComponent` 不判断友军、敌军、距离或具体技能类型。
- `SkillBase` 继续使用现有 Inspector 参数解析目标。
- `TargetRelation.FRIENDLY` 表示“同队的其他单位”；施法者自身必须使用已有的
  `TargetRelation.SELF`，避免 AUTO_NEAREST 永远优先选择距离为零的自己。
- `AllyBehaviorStateMachine` 在 Formation 和 Combat 中都可以询问
  `SkillHostComponent` 是否存在可用自动技能，不再以敌方锁定作为调用前提。
- 敌方 `AITargetingComponent` 保持不变，继续只管理战斗锁定、追击和脱战。
- 技能进入施法阶段后继续复用已有动作请求、动画方法轨道、Delivery 和公共冷却。

## 非目标

- 不新增 TargetSelector、友军列表或职业专用治疗代码。
- 不修改 Firebolt 或 HolyLight 的阵营配置。
- 不修改 TestScene，也不自动添加任何单位。
- 本次只保证范围内自动目标。范围外技能接近仍沿用现有
  `cast_range_required` 接口，后续可独立增强行为状态。

## 验证

- Host 能为 AUTO_NEAREST 技能提供场景中的原始候选。
- HolyLight 使用现有 FRIENDLY 参数选择其他友方，不选择自身或敌方。
- Firebolt 仍能使用 PROVIDED + HOSTILE 目标。
- Priest 在没有敌人的 Formation 状态下，可以治疗范围内友军。
- 全部相关 Godot 4.7 headless 测试和编辑器扫描无新增错误。
