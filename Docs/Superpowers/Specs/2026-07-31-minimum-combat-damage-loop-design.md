# 最小伤害—生命—死亡闭环设计

## 1. 目标

在当前 UnitSystem、武器战斗系统和 SkillSystem 上补齐第一版真实战斗闭环：

1. 玩家、AI 近战和 AI 远程在既有命中判定成功后造成伤害。
2. 技能伤害与治疗复用相同的基础数值入口。
3. 单位生命降至零后进入明确的死亡状态，不再成为合法目标，并停止当前行动。
4. 保留现有动画、Hitbox、投射物、技能交付、索敌和反馈系统，不建立平行战斗链路。

本设计只覆盖最小可玩战斗所需内容，不提前实现完整属性系统。

## 2. 已确认的架构选择

采用“轻量统一结算器”方案：

- `UnitBase` 保存生命值和最小战斗属性。
- `WeaponData` 保存普通攻击的基础数值和分段倍率。
- 技能 Effect 保存该技能自己的基础数值和攻击力倍率。
- 一个无节点、无场景、无外部资源的静态结算脚本统一计算伤害与治疗。
- 现有 Hitbox、Projectile 和 Skill Delivery 只负责确认交付目标，不保存单位属性算法。

明确不采用：

- 每种武器、投射物或技能各自实现伤害公式。
- 为第一版增加 `StatsComponent`、`DamageRequest.tres` 或 Modifier 管线。
- 把伤害、死亡、索敌和关卡失败合并到一个大型组件。

## 3. 数据归属

### 3.1 UnitBase

文件：

`res://UnitSystem/Base/00_UnitBase.gd`

新增最小战斗属性：

```gdscript
@export_category("Combat Stats")
@export_range(0.0, 1000000.0, 0.1, "or_greater")
var attack_power: float = 10.0

@export_range(0.0, 1000000.0, 0.1, "or_greater")
var defense: float = 0.0
```

新增只读公共接口：

```gdscript
func get_attack_power() -> float
func get_defense() -> float
```

`UnitBase` 继续维护：

- `maximum_health`
- `starting_health_percentage`
- `apply_damage()`
- `apply_healing()`
- `revive()`
- `health_changed`
- `damaged`
- `healed`
- `died`
- `revived`

`is_targetable()` 必须同时满足：

```text
Inspector 中允许成为目标，并且单位仍然存活
```

不直接改写导出的 `targetable` 字段，避免死亡后破坏场景原始配置，也让 `revive()` 后可以自然恢复目标资格。

### 3.2 WeaponData

文件：

`res://Item/Weapon/WeaponData.gd`

新增普通攻击数值：

```gdscript
@export_category("Basic Attack")
@export_range(0.0, 1000000.0, 0.1, "or_greater")
var basic_attack_base_damage: float = 5.0

@export_range(0.0, 100.0, 0.05, "or_greater")
var basic_attack_power_ratio: float = 1.0

@export var combo_damage_multipliers: Array[float] = []
```

公共接口：

```gdscript
func get_combo_damage_multiplier(attack_index: int) -> float
```

规则：

- `attack_index` 沿用当前从 `1` 开始的攻击段编号。
- 数组第 0 项对应第一击。
- 缺少对应项、索引非法或倍率小于零时，安全使用 `1.0`。
- 单段攻击和远程武器可以保留空数组。
- `MeleeWeaponData` 与 `RangedWeaponData` 自动继承这些字段，不重复声明。

### 3.3 技能 Effect

文件：

`res://SkillSystem/03-Extensions/HealthChangeSkillEffect.gd`

现有 `operation` 保留。现有固定 `amount` 迁移为语义明确的：

```gdscript
@export var base_amount: float = 10.0
@export var power_ratio: float = 0.0
```

规则：

- `DAMAGE`：计算基础值与施法者攻击力，并应用目标防御。
- `HEAL`：计算基础值与施法者攻击力，不应用目标防御。
- `power_ratio = 0.0` 时保持纯固定值技能。
- 施法者不是 `UnitBase` 时只使用 `base_amount`，不使技能流程报错。
- Effect 仍然只调用公开接口，不依赖 AllyBase、EnemyBase 或具体技能场景。

现有正式技能资源必须通过 Godot 正式保存完成字段迁移，保持有效 UID 和 Inspector 强类型检索能力。

## 4. 统一结算器

新增：

`res://UnitSystem/Combat/CombatValueResolver.gd`

它是带 `class_name` 的纯静态工具脚本，不需要：

- 场景节点
- Autoload
- Inspector 配置
- 每个单位单独装配
- `.tres` 数据实例

公共接口：

```gdscript
static func calculate_damage(
	source: UnitBase,
	target: UnitBase,
	base_damage: float,
	power_ratio: float = 1.0,
	multiplier: float = 1.0
) -> float

static func apply_damage(
	source: UnitBase,
	target: UnitBase,
	base_damage: float,
	power_ratio: float = 1.0,
	multiplier: float = 1.0
) -> float

static func calculate_healing(
	source: UnitBase,
	base_amount: float,
	power_ratio: float = 0.0,
	multiplier: float = 1.0
) -> float

static func apply_healing(
	source: UnitBase,
	target: UnitBase,
	base_amount: float,
	power_ratio: float = 0.0,
	multiplier: float = 1.0
) -> float
```

第一版公式：

```text
攻击原值 = max(基础伤害 + 来源攻击力 × 攻击力倍率, 0)
防御倍率 = 100 / (100 + max(目标防御, 0))
最终伤害 = 攻击原值 × 防御倍率 × max(额外倍率, 0)

治疗原值 = max(基础治疗 + 来源攻击力 × 攻击力倍率, 0)
最终治疗 = 治疗原值 × max(额外倍率, 0)
```

结算结果不强制最低为 `1`。零攻击值可以合法造成零伤害，避免未来无敌、禁用攻击或调试配置产生隐藏例外。

`apply_damage()` 和 `apply_healing()` 返回目标实际变化量，而不是理论计算量。

## 5. 命中数据流

### 5.1 玩家近战

```text
PlayerAttackController
→ MeleeHitboxComponent 确认命中
→ 使用当前 WeaponData 和 combo_index 结算伤害
→ 保留并发送原 attack_hit 信号
→ UnitBase 发送 damaged / health_changed / died
```

伤害结算发生在 `attack_hit` 对外发送前，使反馈或 UI 监听者在收到命中信号时可以读到更新后的生命值。

### 5.2 AI 近战

```text
AIMeleeCombatSystem
→ MeleeHitboxComponent
→ AIAttackController.report_attack_hit()
→ AICombatSystem.report_attack_hit()
→ 统一结算
```

### 5.3 AI 远程

```text
AIRangedCombatSystem
→ 投射物 projectile_hit
→ AIAttackController.report_attack_hit()
→ AICombatSystem.report_attack_hit()
→ 统一结算
```

投射物继续只维护飞行和命中规则。它不复制攻击力、防御或伤害公式，也不直接依赖具体角色类。

### 5.4 技能

```text
Skill Delivery 确认目标
→ HealthChangeSkillEffect
→ CombatValueResolver
→ UnitBase
```

普通攻击与技能共享数值结算基础，但不合并动画、冷却、释放许可或目标选择逻辑。

## 6. 命中信号与伤害信号的边界

现有 `attack_hit` 保持“攻击确实命中了目标”的语义。即使最终伤害为零，它仍然可以触发卡刀、音效或命中特效。

实际生命变化由目标的信号表达：

- `damaged(amount, source)`
- `healed(amount, source)`
- `health_changed(...)`
- `died(source)`

不为第一版新增重复的 `damage_applied` 全局信号。

同一攻击窗口的单目标去重继续由现有 Hitbox 或 Projectile 负责，结算器不再维护第二套去重表。

## 7. 死亡职责

### 7.1 UnitBase

负责：

- 生命降至零并只发送一次 `died`。
- 死亡后 `is_targetable()` 返回 `false`。
- 拒绝重复伤害和普通治疗。
- 通过显式 `revive()` 恢复。

不负责：

- 播放死亡动画。
- 删除场景实例。
- 判定关卡失败。
- 生成掉落。

### 7.2 PlayerBase 和 AIUnitBase

监听自身 `died` 并执行运行行为收束：

- 取消当前普通攻击。
- 取消当前技能或外部动作。
- 停止主动水平移动。
- 清除当前锁定目标。
- AI 状态机停止继续作战决策。

监听 `revived` 后恢复组件运行资格，但不自动锁定目标或恢复被取消的动作。

### 7.3 关卡系统

玩家死亡立即失败、全队死亡失败、敌人清场、奖励和复活规则由后续 Encounter/Run 系统消费 `died` 信号决定。本阶段不把这些规则写入单位类。

## 8. 错误处理

- 空来源允许固定值伤害或治疗正常执行。
- 无效、已释放或死亡目标返回 `0.0`，不抛出运行错误。
- 负数基础值、倍率、攻击力和防御在计算边界归零。
- 未装备武器或武器数据无效时，攻击动画可以按现有规则取消或失败，但不得产生伤害。
- 技能 Effect 的目标不支持生命接口时返回 `false`，让 SkillSystem 使用既有失败处理。
- 命中检测配置错误仍由对应 Hitbox/Projectile 报告，不由数值结算器掩盖。

## 9. 测试边界

实施前先修复或更新当前框架中已经失效的测试基线，使测试结果能代表现行系统。

必须覆盖：

1. 攻击力、防御、倍率和连击倍率公式。
2. 零值、负值、空来源、死亡目标和过量伤害。
3. 玩家近战命中只结算一次。
4. AI 近战命中只结算一次。
5. AI 投射物命中通过相同出口结算。
6. 技能伤害计算防御，技能治疗不计算防御。
7. 死亡只触发一次，死亡单位不可再次成为目标。
8. 死亡会取消攻击、技能与 AI 决策；复活不会恢复被取消动作。
9. 原有卡刀、屏幕震动和命中特效接口不被破坏。
10. Godot 4.7 headless 测试、脚本编译和编辑器错误检查通过。

所有验证使用独立测试场景或现有用户已放置单位进行只读观察。不得由 Codex 向 `res://Scenes/TestScene.tscn` 添加、删除或修改任何单位实例。

## 10. 暂缓范围

本阶段不实现：

- 暴击、闪避、命中率与元素克制。
- Buff、Debuff、护盾和临时属性修正。
- 威胁值、仇恨和职业优先级。
- 击退、硬直、无敌帧和死亡动画。
- 掉落、经验、奖励三选一和关卡失败。
- Focus 对攻击、移动或技能的影响。
- 完整数据驱动属性表、角色成长资源或存档迁移。

## 11. 完成标准

当玩家、AI 近战、AI 远程与技能能够通过统一结算改变 `UnitBase` 生命值，致命伤害能可靠停止单位行动并移除目标资格，且现有战斗反馈、索敌、动画和技能流程无回归时，本阶段完成。
