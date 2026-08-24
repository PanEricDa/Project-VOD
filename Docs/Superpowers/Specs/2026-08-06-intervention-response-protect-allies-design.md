# Intervention Response & Protect Allies 设计

## 目标

给 Guardian（坦克）一个通用的"优先接走不打自己的敌人"的选敌策略，核心机制复用在现有 `EnemyThreatComponent` 上，不新建额外数据表或遍历系统。

## 动机

- Guardian 是近战坦克，职责是把所有敌人的仇恨集中在自己身上。
- 目前 Guardian 用 `NEAREST` 选敌，只打最近的，不管敌人在打谁。远程 archer 可以全程射 Saber 而 Guardian 完全不管。
- 之前讨论的 `CombatThreatDirectory` 方案被否决——它引入了一张冗余的"谁在打谁"的额外哈希表，而敌人身上已有的 `EnemyThreatComponent` 天然存着同样信息。

## 核心参数：intervention_response

位于 `TargetSelectionPolicy` 资源上，默认 1.0：

- **语义**：保护模式下，对不打自己的敌人的介入意愿。越低越激进。
- 仅在 `PROTECT_ALLIES` 模式下被读取；其他模式忽略。
- 不同角色通过装配不同的 `.tres` 来表达不同激进程度——Guardian 用 0.3，未来某个半坦用 0.6，同一个 `.tres` 可共享给多个角色。

`UnitBase` 不参与此参数——保护意愿不是单位固有属性，而是跟策略绑定的配置。

## 核心机制：威胁比例修正评分

不再二分判断"打我 / 不打我"，而是读一个连续信号：
**我对这个敌人的威胁，占该敌人最高威胁的比例。**

数据来源：
- `candidate` 身上的 `EnemyThreatComponent.get_threat_for(owner)` → 我对它的威胁。
- 该敌人的最高威胁值 → 它最怕谁（遍历表可获取）。

两者相除得到 0~1 的比例 R。

评分修正公式：

```
修正系数 = IR + (1.0 - IR) × R
```

| 我对敌人的威胁状态 | R | IR=0.3 时的修正系数 | 效果 |
|---|---|---|---|
| 完全没碰过 | 0 | 0.30 | 强烈优先 |
| 打过，被别人 OT 了 | 0.6 | 0.72 | 温和优先 |
| 我是最高威胁来源 | 1.0 | 1.00 | 不干预 |

修正系数直接乘到基础距离分上。分数越低越优先。

## 策略层：PROTECT_ALLIES 模式

在 `TargetSelectionPolicy.PriorityMode` 中新增 `PROTECT_ALLIES`：

- `calculate_priority()` 中先算基础距离分。
- 如果候选敌人的 `locked_target` 不是 `owner`，读取修正系数并乘到分数上。
- 如果候选敌人的 `locked_target` 就是 `owner`，分数不变。
- 如果模式不是 `PROTECT_ALLIES`，走原逻辑，`intervention_response` 不被读取。

## 行为层：AllyBehaviorStateMachine 触发

Guardian 的行为机不需要额外改动——它继续通过 `_get_current_target()` → `AITargetingComponent.get_locked_target()` 获取目标。只要 Guardian 装配的 `selection_policy` 是 `PROTECT_ALLIES` 模式，策略层自动在评分时应用保护逻辑。

## 聚怪附带效果

Guardian 优先跑去接零威胁的远程 archer 时，那些仇恨顶端是 Guardian 的近战敌人跟着移动，自然聚到 archer 附近。

## 边界与安全

- `EnemyThreatComponent` 可能不存在（未装配敌人）：降级为二分判断，看 `candidate.get_locked_target() != owner`，修正系数直接用 IR。
- 敌人没有锁定目标：视为"在打别人"，同样参与修正。
- 不创建新组件、不订阅新信号、不修改 `EncounterController`。

## 不在本阶段实现

- 仇恨衰减机制（保持威胁只增不减，必要时再调）。
- 距离过滤（Guardian 不分远近，全部参与保护）。
- 队友血量判断。
- 技能联动（盾击等远程接怪）。

## 配置方案

- Guardian 新建 `UnitSystem/Components/Targeting/AI/Policies/GuardianProtect.tres`：`priority_mode = PROTECT_ALLIES`。
- Guardian.tscn 里 `AITargetingComponent` 覆盖 `selection_policy` 为新资源。
- 其他 Ally 不变，继续用 `DefaultNearestEnemy.tres`。

## 验收条件

- Guardian 装配 PROTECT_ALLIES 后，优先选择"当前目标不是自己"的敌人。
- 完全没碰过的敌人优先级最高，正在拉住的敌人优先级不变。
- `intervention_response` 可从 `.tscn` 独立配置，不同 IR 值产生不同优先度。
- Saber/Priest 用 NEAREST 时行为不受影响。
- 现有 `TargetSelectionPolicyTest`、`AllyBehaviorStateMachineTest` 通过，编辑器扫描干净。
