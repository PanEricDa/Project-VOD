# 技能系统使用说明

这套技能系统面向 Godot 4.7，采用“技能场景 + Definition + Delivery”的组合方式。普通技能通常不需要新增脚本，只需在 Inspector 中选择已有组件并完成角色装配。

## 一、五分钟快速开始

创建一个新技能时，按以下顺序操作：

1. 在 `res://SkillSystem/00-Skills/` 下创建技能专属文件夹。
2. 继承 `res://SkillSystem/01-Core/SkillBase.tscn`，保存技能场景。
3. 创建一个 `SkillDefinition.tres`，配置目标、施法和冷却。
4. 按 `02` 至 `06` 的顺序给 Definition 装入条件、目标选择、AI 决策、消耗和施法表现。
5. 从 `07-Delivery/00-Agents` 选择交付方式，创建 Delivery 场景。
6. 给 Delivery 配置弹道、碰撞、影响目标和 Payload。
7. 把 Definition 与 Delivery 装回技能场景。
8. 把技能场景实例化到角色的 `SkillHostComponent/SkillSocket`。
9. AI 角色需要自动施法时，启用 `AllySkillRequestBridge`。

标准技能文件夹只有三个文件：

```text
00-Skills/MySkill/
├── MySkill.tscn
├── MySkillDefinition.tres
└── MySkillDelivery.tscn
```

## 二、编号目录地图

| 编号 | 文件夹 | 用途 |
|---|---|---|
| `00` | `00-Skills` | 具体技能的三个组装文件 |
| `01` | `01-Core` | SkillBase、SkillHost、Definition、Context、Result |
| `02` | `02-Conditions` | 是否允许释放 |
| `03` | `03-Targeting` | 选择哪个目标 |
| `04` | `04-Decisions` | AI 何时提出释放请求 |
| `05` | `05-Costs` | 法力或其他资源消耗 |
| `06` | `06-Presentation` | 视觉、音效和场景表现 |
| `07` | `07-Delivery` | 起点、过程、终点和命中交付 |
| `08` | `08-Payloads` | 伤害、治疗等 Gameplay 结果 |
| `09` | `09-Presets` | 可复制的默认配置 |
| `10` | `10-Docs` | 说明、架构和扩展文档 |
| `11` | `11-Tests` | 自动测试与测试夹具 |

`07-Delivery` 内部继续按照交付流程排列：

```text
07-Delivery/
├── 00-Agents          # 负责启动和管理一次交付
├── 01-Trajectories    # 决定如何从起点移动到终点
├── 02-Collisions      # 决定何时算到达或碰撞
└── 03-Impacts         # 决定最终影响哪些目标
```

## 三、三个核心文件

### 1. Skill 场景

技能场景继承 `01-Core/SkillBase.tscn`，负责：

- 保存 `skill_definition`；
- 保存 `delivery_agent_scene`；
- 提供 `CastOrigin`；
- 提供 `DeliverySocket`；
- 提供技能自身的施法动画和表现挂点。

普通技能不要在这里编写索敌、移动、伤害或角色职业逻辑。

### 2. SkillDefinition 资源

Definition 保存技能的静态规则：

| Inspector 字段 | 含义 | 资源来源 |
|---|---|---|
| `skill_id` | 稳定的技能标识 | 手动填写，使用英文小写下划线 |
| `display_name` | 编辑器和调试显示名称 | 手动填写 |
| `ai_priority` | 多技能可用时的基础优先级 | 手动填写 |
| `target_relation` | SELF、FRIENDLY、HOSTILE 等 | Definition 枚举 |
| `require_targetable` | 是否要求目标可被选中 | Definition |
| `cast_range` | 开始施法所需距离 | Definition |
| `cast_range_tolerance` | 距离误差缓冲 | Definition |
| `cast_time` | 进入 CASTING 后的等待时间 | Definition |
| `can_move_while_casting` | 施法期间能否移动 | Definition |
| `skill_cooldown` | 成功交付后的技能独立冷却 | Definition |
| `condition` | 是否满足释放条件 | `02-Conditions` |
| `target_selector` | 如何获得目标 | `03-Targeting` |
| `decision_policy` | AI 请求前等待多久 | `04-Decisions` |
| `cost` | 是否能支付以及何时提交消耗 | `05-Costs` |
| `cast_presentation` | 施法阶段播放什么表现 | `06-Presentation` |

技能冷却只在 Delivery 成功启动后开始。公共冷却由 Host 独立管理，两者同时计时。

### 3. Delivery 场景

Delivery 负责“技能释放以后发生什么”。当前有两类通用 Agent：

- `BasicDeliveryAgent`：适合瞬发、定时直达、直接伤害和直接治疗。
- `TrackingProjectileDeliveryAgent`：适合生成具有独立追踪、碰撞、爆炸逻辑的投射物。

Delivery 启动失败时，技能默认不会进入技能冷却；可通过 Definition 的 `cooldown_on_failed_delivery` 改变这一规则。

## 四、Definition 配置顺序

### 02 — Condition

`AlwaysSkillCondition` 表示没有额外释放条件。

以后增加“血量低于一定比例”“目标带有某状态”等规则时，应新增继承自 `SkillConditionBase` 的通用 Resource，而不是把判断写进具体角色脚本。

### 03 — Targeting

当前常用选择器：

- `ProvidedTargetSelector`：使用外部已经提供的目标。敌对技能通常复用 AllyBase 当前感知到的敌人。
- `NearestValidTargetSelector`：在施法范围内搜索最近的合法目标。治疗等友方技能可以使用。

Definition 的 `target_relation` 才是敌我关系的最终规则。TargetSelector 负责“从哪里找到候选者”，两者不是重复判断。

### 04 — Decisions

`BasicRandomDecisionPolicy` 只影响 AI 请求：

- `normal_delay_min/max`：正常随机等待；
- `extra_hesitation_chance`：额外犹豫概率；
- `extra_hesitation_min/max`：触发犹豫后的附加等待。

手动请求和强制请求默认不应用随机等待。

### 05 — Costs

`NoSkillCost` 表示无需资源。未来增加法力消耗时，应新增通用 Cost Resource，并通过 `can_pay()`、`commit()` 和 `refund()` 接口工作。

### 06 — Presentation

`SceneSkillPresentation` 可以实例化一个独立特效场景，并调用其 `play()` 方法。特效场景可以包含粒子、灯光、AnimationPlayer 和音频，但不能反向读取具体职业脚本。

## 五、Delivery 配置

### BasicDeliveryAgent

Inspector 插槽来源：

| Delivery 字段 | 目录 |
|---|---|
| `trajectory` | `07-Delivery/01-Trajectories` |
| `collision_policy` | `07-Delivery/02-Collisions` |
| `impact_selector` | `07-Delivery/03-Impacts` |
| `payloads` | `08-Payloads` |
| 表现插槽 | `06-Presentation` |

当前基础组合：

```text
DirectTrajectory
ArrivalCollisionPolicy
DirectImpactSelector
HealthChangePayload
```

`DirectTrajectory.travel_duration = 0` 表示目标瞬发；大于零时表示按指定时间直线到达。

### TrackingProjectileDeliveryAgent

主要参数：

- `projectile_scene`：真正的投射物场景；
- `projectile_speed`：飞行速度；
- `turn_speed_degrees`：每秒最大转向角度；
- `maximum_lifetime`：最大飞行时间；
- `impact_radius`：交给投射物的影响半径；
- `aim_height`：相对目标根节点的瞄准高度。

投射物必须实现 Agent 要求的 `launch(...) -> bool` 接口，并发出 `projectile_impacted(position)` 信号。飞行、碰撞、爆炸范围和最终命中规则属于投射物，不属于 SkillBase。

## 六、三个示例

### 示例 A：目标瞬发治疗

参考 `00-Skills/HolyLight`：

```text
target_relation = FRIENDLY
target_selector = NearestValidTargetSelector
delivery = BasicDeliveryAgent
trajectory = DirectTrajectory，travel_duration = 0
impact_selector = DirectImpactSelector
payload = HealthChangePayload，operation = HEAL
```

治疗表现由 Delivery 的命中表现插槽播放在目标身上。

### 示例 B：目标瞬发伤害

复制基础 Delivery 组合，只把：

```text
HealthChangePayload.operation = DAMAGE
HealthChangePayload.amount = 所需数值
target_relation = HOSTILE
```

这类技能通常不需要任何新脚本。

### 示例 C：追踪投射技能

参考 `00-Skills/Firebolt`：

```text
target_relation = HOSTILE
target_selector = ProvidedTargetSelector
delivery = TrackingProjectileDeliveryAgent
projectile_scene = 一个实现追踪与碰撞的投射物场景
```

Firebolt 复用通用 Agent 和已有 FireBall 投射物，因此没有 Firebolt 专属 GDScript。

## 七、装配到角色

### AllyBase 继承角色

AllyBase 已经包含：

```text
AllyBase
├── SkillHostComponent (Node3D)
│   └── SkillSocket (Node3D)
└── AllySkillRequestBridge
```

操作步骤：

1. 打开职业源场景。
2. 把技能场景拖入 `SkillHostComponent/SkillSocket`。
3. 确保技能是 `SkillSocket` 的直接子节点，否则 Host 不会自动发现。
4. 自动施法职业设置 `AllySkillRequestBridge.enabled = true`。
5. 敌对技能通常保持 `request_while_out_of_combat = false`。
6. 治疗等非战斗技能可设置 `request_while_out_of_combat = true`。
7. 已完全使用新技能系统的职业设置 `legacy_skill_scheduler_enabled = false`。

Host 会自动注入施法者和当前世界交付父节点。不要在职业脚本中手动生成投射物。

### 其他角色

非 AllyBase 角色需要实例化 `01-Core/SkillHostComponent.tscn`，然后调用：

```gdscript
skill_host.configure_owner(caster, delivery_parent)
```

手动释放可以调用 Host 的 `request_skill()`；AI 可以调用 `request_best_skill()`。

## 八、空间位置规则

- `SkillHostComponent`、`SkillSocket` 和技能场景都是 `Node3D`，因此技能会继承角色世界位置和朝向。
- `CastOrigin` 是施法蓄力表现位置。
- `DeliverySocket` 是投射物或交付 Agent 的世界起点。
- 投射物启动后应放入世界交付父节点，不能继续作为角色子节点，否则会被角色移动拖动。
- 调整发射位置时优先修改具体技能场景的 `CastOrigin` 和 `DeliverySocket` 本地位置。

## 九、什么时候需要新增脚本

不需要脚本：

- 只调整施法距离、时间、冷却和优先级；
- 在已有 TargetSelector 之间切换；
- 使用已有伤害或治疗 Payload；
- 使用已有 Basic 或 Tracking Delivery；
- 更换特效、音效或投射物场景。

需要新增通用 Resource 脚本：

- 新释放条件；
- 新目标选择算法；
- 新 AI 决策；
- 新资源消耗；
- 新 Payload；
- 新表现播放策略。

需要新增 Delivery 或投射物脚本：

- 新弹道；
- 持续区域、链式传播或特殊碰撞；
- 投射物自身决定范围、命中对象和碰撞结果。

优先创建可复用组件。不要为每个技能复制一份只改数值的脚本。

## 十、常见问题

### Host 找不到技能

- 技能必须是 `SkillSocket` 的直接子节点；
- Host 的 `auto_discover_skills` 必须开启；
- 技能场景必须继承 `SkillBase.tscn`。

### AI 不会释放

- 检查 `AllySkillRequestBridge.enabled`；
- 检查战斗内/战斗外请求设置；
- 检查目标关系和 FactionComponent；
- 检查施法距离；
- 检查技能冷却与公共冷却；
- 检查是否仍启用了冲突的旧调度器。

### 技能始终从世界原点生成

- 确认 Host、SkillSocket 和技能根节点为 `Node3D`；
- 确认技能仍挂在角色的空间层级中；
- 检查 `DeliverySocket` 的世界坐标；
- 不要把空间型技能放在普通 `Node` 容器下。

### 请求成功但没有效果

- 检查 `delivery_agent_scene`；
- 检查 Delivery 的必要策略资源；
- 检查投射物 `launch()` 是否返回 `true`；
- 检查目标是否包含 Payload 需要的 HealthComponent；
- 查看 `delivery_failed` 和 `payload_failed` 信号。

### 修改文件夹后脚本报错

项目使用 `res://` 项目内路径。移动脚本或资源时必须同步更新所有 `extends`、场景和 Resource 引用，并保留 `.uid`。不要只用系统文件管理器移动单个文件后忽略引用。

## 十一、发布前检查表

- 技能三个文件均位于 `00-Skills/<SkillName>`；
- Skill 场景继承 `01-Core/SkillBase.tscn`；
- Definition 和 Delivery 均已赋值；
- `skill_id` 唯一；
- 目标关系、Selector 和 FactionComponent 匹配；
- CastOrigin 和 DeliverySocket 位置正确；
- 成功交付后技能冷却与公共冷却启动；
- 技能已放入角色 SkillSocket 直接子级；
- AI 请求桥配置正确；
- Godot Output 没有新增 ERROR 或 WARNING。
