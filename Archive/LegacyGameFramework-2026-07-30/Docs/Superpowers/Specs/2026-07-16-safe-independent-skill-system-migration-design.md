# 旧技能系统向独立 SkillSystem 安全迁移设计

## 1. 目标与边界

将运行中的旧 `SkillModuleBase` 技能路径分阶段迁移到 `res://SkillSystem`，最终让新系统成为唯一运行路径。

本设计只替换技能相关职责：技能请求、技能选择、施法状态、施法距离协调、技能冷却和技能交付。以下现有能力继续保留：

- AllyBase 的 CombatSensor 和敌人感知；
- 进入与离开战斗状态；
- 编队、游荡、重力、朝向和移动；
- 普通攻击模块及其攻击距离行为；
- 玩家目标与伙伴脱战规则。

本轮迁移不物理删除旧脚本、旧场景、旧 Profile 或旧测试。旧系统在零运行引用后标记弃用，并经过独立观察期；删除工作必须重新审批。

## 2. 现状审计

### 2.1 当前运行中的旧技能

只有 Mage 源场景实际装配旧技能：

```text
Mage
└── VisualRoot/SkillModuleSocket/FireballSkill
```

`Mage.tscn` 的 `skill_module_path` 指向该实例。TestScene 中的 Mage 通过源场景继承该配置，因此不得直接编辑 TestScene 实例。

### 2.2 未运行的旧资源

`HealingSkill.tscn`、`BasicHealingProfile.tres` 和默认旧 Skill Profile 仍存在，但当前角色源场景没有引用它们。迁移期间保留并标记弃用。

### 2.3 新系统已具备的能力

- `SkillHostComponent` 注册和选择技能；
- 单一活动技能槽；
- 技能公共冷却；
- AI/手动/强制请求模式；
- 施法等待、排队、施法、交付和技能冷却；
- `approach_requested`、`facing_requested`、`movement_lock_requested` 接口；
- 类型化的 Condition、TargetSelector、Decision、Cost 和 Presentation Resource；
- ProvidedTargetSelector 与 NearestValidTargetSelector；
- AllyBase 已安全装载 Host，并具备手动请求和基础冷却同步接口。

### 2.4 新系统尚缺的能力

- AI 自动发起技能请求的通用组件；
- AllyBase 对 Host 的接近、朝向和移动锁定请求的正式消费；
- 新系统版本的 Fireball Skill；
- 从旧公共冷却双计时向单一权威计时的迁移；
- 源场景级的新旧系统互斥切换开关。

## 3. 方案比较

### 方案 A：永久保留旧调度器并桥接新 Host

短期改动最少，但长期存在两套活动技能状态、两套冷却和两套失败恢复路径。错误风险会随技能数量增加，不采用。

### 方案 B：一次性删除旧系统并切换所有调用

最终结构最干净，但当前项目不是 Git 仓库，且 TestScene 依赖 Mage 源场景；一旦场景路径或施法移动出现问题，回退成本过高，不采用。

### 方案 C：旁路建设、互斥切换、观察后弃用

先补齐新系统，保持默认旧行为；逐个角色启用新路径；同一角色任何时刻只允许一套技能调度器运行。完成验证后移除源场景旧实例引用，但保留旧文件与代码作为观察期回退路径。

采用方案 C。

## 4. 最终架构

```text
AllyBase CombatSensor / Combat State
                 │
                 │ 当前战斗状态与首选敌人
                 ▼
AllySkillRequestBridge
├── 控制 AI 请求节奏
├── 保证旧/新路径互斥
├── 把首选敌人传给新 Host
└── 缓存接近、朝向和移动锁定请求
                 │
                 ▼
SkillHostComponent
├── 选择最高优先级可用技能
├── 管理单一活动技能
├── 管理公共冷却
└── 推进技能状态
                 │
                 ▼
SkillBase
├── TargetSelector
├── Condition / Cost / Decision
├── Cast / Cooldown
└── Delivery / Payload / Presentation
```

依赖方向固定为：

```text
AllyBase → AllySkillRequestBridge → SkillHostComponent
```

`SkillSystem` 不反向引用 AllyBase、Mage、Healer 或任何职业脚本。

## 5. 新增系统组件

### 5.1 AllySkillRequestBridge

位置：

```text
res://Scripts/AI/Components/AllySkillRequestBridge.gd
res://Scenes/Components/AI/AllySkillRequestBridge.tscn
```

它是项目 AI 与独立技能系统之间的薄适配器，不包含具体职业和具体技能知识。

职责：

- 接收 AllyBase 提供的 `combat_active` 和 `preferred_enemy`；
- 按 Inspector 间隔调用 `SkillHostComponent.request_best_skill()`；
- 敌对技能可通过 ProvidedTargetSelector 复用 `preferred_enemy`；
- 友方技能可忽略外部敌人并由自己的 TargetSelector 解析目标；
- 监听 Host 的接近、朝向和移动锁定请求；
- 战斗结束、目标失效或组件停用时取消活动请求并清空移动所有权；
- 不直接修改 CharacterBody3D 速度，也不读取 AllyBase 私有字段。

第一版 Inspector 参数：

```text
enabled
skill_host_path
request_interval
request_while_out_of_combat
cancel_on_combat_exit
```

公开接口：

```text
set_combat_context(active, preferred_target)
clear_combat_context()
get_approach_request()
get_facing_target()
is_movement_locked()
```

### 5.2 AllyBase 消费职责

AllyBase 仍是移动唯一所有者，只消费桥接组件暴露的意图：

- 有有效接近请求时，计算施法半径边缘目标并移动；
- 有朝向目标时更新 `desired_facing_direction`；
- 施法锁定移动时平滑停止水平速度；
- 技能不占用移动时继续原有战斗游荡；
- 重力与 `move_and_slide()` 始终走原有共同路径。

桥接组件与普通攻击不会在同一帧同时写入移动目标。技能接近拥有高于普攻与警戒游荡的优先级，脱战和返回编队拥有最高优先级。

### 5.3 唯一公共冷却来源

迁移完成后的公共冷却权威来源为 `SkillHostComponent`：

- 普攻成功发动时调用 Host 的 `start_global_cooldown()`；
- 技能开始施法时 Host 自行启动同一公共冷却；
- 普攻和技能开始条件均读取 Host 的 `is_global_cooldown_ready()`；
- `basic_attack_global_cooldown` 继续作为每个单位可覆盖的默认持续时间；
- AllyBase 初始化 Host 时把该单位的 `basic_attack_global_cooldown` 同步为 Host 默认持续时间，确保继承职业的独立覆盖继续生效；
- 旧 `basic_attack_global_cooldown_remaining` 在迁移观察期只作为兼容镜像，不再参与最终决策；
- 确认所有测试与实际表现稳定后，兼容镜像的删除另行审批。

## 6. 技能目标策略

### 6.1 敌对技能

Mage Fireball 使用 `ProvidedTargetSelector`。桥接组件把 AllyBase 已有的 `current_visible_enemy` 传给 Host，新系统继续验证 HOSTILE、targetable 和施法距离，不重复搜索敌人。

### 6.2 友方技能

HolyLight 使用 `NearestValidTargetSelector`。桥接组件可以带着敌人上下文发起 `request_best_skill()`，但 HolyLight 选择器不会采用该敌人，而是根据 FRIENDLY 规则在范围内选择最近的其他友方。

第一版不检查目标缺血；满血目标仍可成功释放并播放表现，符合当前测试要求。

## 7. Fireball 新系统迁移

新 Fireball 放在：

```text
res://SkillSystem/00-Skills/Fireball/
```

它复用当前已验证的：

- 火球投射物场景；
- 蓄力视觉；
- 飞行视觉；
- 爆炸视觉；
- 追踪、弧线、碰撞和爆炸半径参数。

新 Skill Definition 保持现有体验参数：6m 施法距离、0.25m 容差、0.75s 施法时间、5s 技能冷却、0.3–3s 正常决策延迟、10% 额外拖延概率和 3–5s 额外拖延。

迁移阶段不移动或重命名现有投射物与特效文件。新 Delivery 使用适配层调用已验证的投射物公开 `launch()` 接口，避免同时重写技能系统和投射物系统。

## 8. 分阶段迁移与门禁

### 阶段 0：基线与可回退快照

- 记录全部相关文件路径与引用；
- 运行全部现有测试和项目 headless 冒烟；
- 在项目目录之外生成迁移前压缩快照和文件哈希；
- 任何基线失败先修复，不进入迁移。

### 阶段 1：旁路补齐新系统

- 新增 AllySkillRequestBridge；
- 补齐 AllyBase 对 Host 意图的消费；
- 新路径默认关闭；
- 旧火球行为完全不变；
- 通过组件、Host、移动所有权、公共冷却和取消流程测试后才继续。

### 阶段 2：HolyLight 低风险验证

- Healer 启用新请求桥；
- 测试阶段将 `request_while_out_of_combat = true`，因此只要范围内存在其他友方就可以请求 HolyLight，不要求先感知敌人；
- 只装载 HolyLight，不涉及旧技能；
- 验证范围内友方可触发施法、目标不存在时安全失败、脱战取消和公共冷却；
- 由用户在现有 TestScene 手动测试，不由 Codex 添加或替换单位。

### 阶段 3：新 Fireball 旁路验证

- 创建新 Fireball Skill；
- Mage 同时保留旧 Fireball 节点和新 Fireball 节点；
- 通过互斥开关保证只有旧路径自动运行；
- 使用自动测试和独立预览验证新 Fireball，不改变当前实际战斗行为。

### 阶段 4：Mage 可回退切换

- 在 Mage 源场景关闭旧调度入口并启用新请求桥；
- 旧 Fireball 实例暂时保留但不运行；
- 验证索敌、随机延迟、接近、面向、蓄力、投射物、公共冷却、脱战和重进战；
- 用户确认实际表现前，不移除旧实例。

### 阶段 5：源场景零旧引用

- 用户确认新 Fireball 后，从 Mage 源场景移除旧 Fireball 实例和旧路径覆盖；
- TestScene 不做任何修改；其现有 Mage 实例通过源场景继承新行为；
- 扫描所有 `.tscn/.tres/.gd`，确认运行场景不再引用旧 SkillModule；
- 旧文件、旧测试和 AllyBase 兼容代码仍保留并标记 Deprecated。

### 阶段 6：观察期

- HolyLight 与 Fireball 均使用新系统运行；
- 观察重复请求、卡施法槽、公共冷却漂移、脱战后残留移动请求和场景重载；
- 发现问题时恢复源场景互斥开关或使用迁移前快照，不修改 TestScene；
- 观察通过后才另立“旧技能系统物理清理”计划。

## 9. 互斥与安全规则

- 同一角色任何时刻只能启用一个自动技能调度入口；
- 新桥默认 `enabled = false`，只在具体职业源场景显式开启；
- Mage 切换前旧系统保持默认行为；
- 活动技能存在时不允许另一路请求占用角色；
- 脱战、角色退出场景、技能卸载和目标失效均必须释放活动槽与移动请求；
- 修改 Mage 和 Healer 只修改各自源场景，不修改 TestScene 单位实例；
- 不移动、不重命名、不删除旧资产；
- 每个阶段必须有独立测试和回退点，不把基础设施、Fireball 切换和旧代码清理合并为一次修改。

## 10. 测试体系

### 组件测试

- 请求间隔与启停；
- 战斗内外策略；
- 首选敌人转发；
- 无合法技能时安全失败；
- approach/facing/movement lock 生命周期；
- 脱战和节点退出取消。

### Ally 集成测试

- 技能接近独占移动；
- 施法锁定不影响重力；
- 普攻与技能共享同一公共冷却；
- 普攻、技能、返回编队不会同帧竞争；
- Guardian、Warrior、Ranger 未装技能时行为不变。

### 技能测试

- HolyLight 最近其他友方选择和瞬时治疗交付；
- Fireball 参数与旧体验一致；
- 火球从正确 CastOrigin 生成并追踪当前目标；
- 施法失败不错误启动技能冷却；
- 成功交付才启动技能冷却。

### 场景与回归测试

- AllyBase、Healer、Mage 源场景装配路径；
- TestScene 文件内容不发生修改；
- 全部 `SkillSystem/Tests` 与项目 `Tests` 通过；
- Godot 4.7 headless 项目扫描无新增 ERROR/WARNING；
- 实际编辑器运行由用户确认视觉、节奏和行为。

## 11. 完成标准

- HolyLight 与 Fireball 均通过新 SkillHost 自动运行；
- Mage 源场景不再引用旧 FireballSkill；
- 没有运行场景引用旧 SkillModuleBase 或旧 Skill Profile；
- AllyBase 的感知、普攻、编队、脱战和重力行为保持不变；
- 新系统成为唯一运行技能路径；
- 旧文件仍存在并有明确 Deprecated 记录；
- 物理删除旧系统不属于本迁移任务。
