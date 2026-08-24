# Inspector 快速装配指南

完整说明请先阅读：[SkillSystemUserGuide.md](SkillSystemUserGuide.md)。

## 创建技能场景

1. 在 `res://SkillSystem/00-Skills/<技能名>/` 下建立技能专属文件夹。
2. 继承 `res://SkillSystem/01-Core/SkillBase.tscn`，保存为技能场景。
3. 创建或复制一个 `SkillDefinition` 资源，并赋给技能根节点的
   `skill_definition`。
4. 从 `res://SkillSystem/07-Delivery/00-Agents/` 选择交付场景，赋给
   `delivery_agent_scene`。
5. 调整技能场景中的 `CastOrigin` 与 `DeliverySocket`。二者都使用局部坐标，
   运行时会转换成世界坐标。
6. 将技能场景实例放到角色 `SkillHostComponent/SkillSocket` 的直接子级。

## Inspector 资源来源

| Inspector 属性 | 资源目录 |
|---|---|
| `SkillBase.skill_definition` | `00-Skills/<技能名>/` 或 `09-Presets/` |
| `SkillBase.delivery_agent_scene` | `07-Delivery/00-Agents/` |
| `SkillDefinition.condition` | `02-Conditions/` |
| `SkillDefinition.target_selector` | `03-Targeting/` |
| `SkillDefinition.decision_policy` | `04-Decisions/` |
| `SkillDefinition.cost` | `05-Costs/` |
| `SkillDefinition.cast_presentation` | `06-Presentation/` |
| Agent `trajectory` | `07-Delivery/01-Trajectories/` |
| Agent `collision_policy` | `07-Delivery/02-Collisions/` |
| Agent `impact_selector` | `07-Delivery/03-Impacts/` |
| Agent `payloads` | `08-Payloads/` |
| Agent 表现插槽 | `06-Presentation/` |

所有带类型的 Inspector 字段都应选择对应基类的 Resource，不使用无类型开放变量。

## 常用交付配置

### 瞬发治疗或伤害

```text
DirectTrajectory.travel_duration = 0
ArrivalCollisionPolicy
DirectImpactSelector
HealthChangePayload.operation = HEAL 或 DAMAGE
```

过程时间为零时，交付直接到达终点；治疗或伤害由 Payload 决定，而不是由技能骨架决定。

### 直线或快速投射

复制或继承 `BasicDeliveryAgent`，将 `DirectTrajectory.travel_duration` 设置为大于
零的秒数。基础实现使用启动时记录的目标位置，不自动追踪移动目标。

## Ally AI 自动请求

技能装入 `SkillSocket` 后只具备“可以被请求并执行”的能力。角色上的
`AllySkillRequestBridge` 决定何时发起请求：

```text
AllySkillRequestBridge.enabled = true
AllySkillRequestBridge.request_interval = 0.25
AllySkillRequestBridge.request_while_out_of_combat = false
```

- 敌对技能可使用 `ProvidedTargetSelector`，复用 AllyBase 已选定的敌人。
- 治疗技能可使用 `NearestValidTargetSelector`，按 Definition 的友方关系和范围选人。
- `request_while_out_of_combat = true` 可让治疗者在没有敌人时仍尝试施法。
- RequestBridge 决定“何时尝试”，TargetSelector 决定“选择谁”，SkillHost 与
  SkillBase 负责排队、施法、交付和冷却。

## 装配检查

- 技能必须是 `SkillSocket` 的直接子节点。
- `skill_definition` 与 `delivery_agent_scene` 均不可为空。
- 阵营筛选需要施法者和目标正确装配 `FactionComponent`。
- `HealthChangePayload` 需要目标具有 `HealthComponent`。
- 投射交付必须由 SkillBase 生成到世界父节点，不能固定挂在角色模型下。
- SkillHost 只负责调度，不负责移动、索敌或职业 AI 决策。
