# 编号化技能系统目录与使用说明设计

## 目标

将 `res://SkillSystem/` 整理为与技能配置流程一致的连续编号目录，并编写一套面向实际使用者的简明中文说明。使用者应能从 `00-Skills` 开始，按照目录编号依次找到创建、配置和装配技能所需的资源。

本次工作只整理独立技能系统的文件路径、引用和文档，不改变技能运行逻辑、参数默认值或角色行为。

## 最终目录

```text
res://SkillSystem/
├── 00-Skills
├── 01-Core
├── 02-Conditions
├── 03-Targeting
├── 04-Decisions
├── 05-Costs
├── 06-Presentation
├── 07-Delivery
│   ├── 00-Agents
│   ├── 01-Trajectories
│   ├── 02-Collisions
│   └── 03-Impacts
├── 08-Payloads
├── 09-Presets
├── 10-Docs
└── 11-Tests
```

`00-Skills` 保留现有名称和内容。其余顶层目录按配置顺序重命名，不额外拆分现有脚本职责。

## 目录职责

| 编号 | 目录 | 使用者在此完成的工作 |
|---|---|---|
| 00 | `00-Skills` | 为具体技能创建专属文件夹，存放技能场景、Definition 和 Delivery |
| 01 | `01-Core` | 继承 `SkillBase.tscn`，理解 Host、Context、Definition 和 Result |
| 02 | `02-Conditions` | 设置技能是否满足释放条件 |
| 03 | `03-Targeting` | 设置技能选择谁作为目标 |
| 04 | `04-Decisions` | 设置 AI 请求技能前的随机等待与犹豫 |
| 05 | `05-Costs` | 设置法力、资源或无消耗策略 |
| 06 | `06-Presentation` | 设置施法、飞行或命中表现的场景播放策略 |
| 07 | `07-Delivery` | 设置技能从起点到终点的交付方式 |
| 08 | `08-Payloads` | 设置伤害、治疗或其他 Gameplay 结果 |
| 09 | `09-Presets` | 复制可复用的默认 Definition 或组合预设 |
| 10 | `10-Docs` | 阅读配置说明、架构和扩展点 |
| 11 | `11-Tests` | 保存独立技能系统的自动测试与测试夹具 |

## 标准技能配置流程

使用说明以以下九步作为主线：

1. 在 `00-Skills/<SkillName>/` 创建技能专属目录。
2. 继承 `01-Core/SkillBase.tscn`，保存为 `<SkillName>Skill.tscn`。
3. 创建 `<SkillName>SkillDefinition.tres`，填写身份、目标关系、施法距离、施法时间和冷却。
4. 按 `02-Conditions`、`03-Targeting`、`04-Decisions`、`05-Costs`、`06-Presentation` 的顺序配置 Definition 插槽。
5. 从 `07-Delivery/00-Agents` 继承或选择交付代理，保存为 `<SkillName>Delivery.tscn`。
6. 按需要配置 `01-Trajectories`、`02-Collisions`、`03-Impacts`，并从 `08-Payloads` 装入结果资源。
7. 在技能场景中连接 `skill_definition` 与 `delivery_agent_scene`，设置 `CastOrigin` 和 `DeliverySocket`。
8. 把技能场景实例化为角色 `SkillHostComponent/SkillSocket` 的直接子节点。
9. 对 AI 角色启用 `AllySkillRequestBridge`，根据敌对或友方技能选择战斗内或战斗外请求模式。

## 标准技能专属文件

每个无需专属代码的普通技能保持三个文件：

```text
00-Skills/<SkillName>/
├── <SkillName>Skill.tscn
├── <SkillName>SkillDefinition.tres
└── <SkillName>Delivery.tscn
```

只有以下情况才新增技能专属脚本：

- 现有 Condition、TargetSelector、Decision、Cost、Presentation、Delivery Agent 或 Payload 无法表达需求；
- 新行为可抽象为通用组件，并能被两个以上技能复用；
- 投射物具有自己的飞行、碰撞、范围选择或命中处理规则。

角色职业、AllyBase 或具体角色场景不得写入技能执行脚本的反向依赖。

## 使用说明结构

主说明文件创建为：

```text
res://SkillSystem/10-Docs/SkillSystemUserGuide.md
```

内容按实际操作顺序排列：

1. 五分钟快速开始；
2. 编号目录地图；
3. 标准三文件技能结构；
4. Definition 配置；
5. Delivery 配置；
6. 角色 Host 与 Socket 装配；
7. AI 自动请求配置；
8. HolyLight、Firebolt 和基础瞬发技能示例；
9. 何时需要新增脚本；
10. 常见错误与检查表。

现有 `README.md` 改为短入口，只保留系统简介、最短流程和主说明链接。现有架构、扩展点和历史设计文档移动到 `10-Docs`，内容中的路径同步更新。

## 路径迁移策略

目录迁移采用一次受控迁移：

1. 记录 `TestScene.tscn` 和关键源场景 SHA-256；
2. 在项目外创建迁移前压缩备份和校验清单；
3. 保留并随文件移动所有 `.uid`；
4. 重命名目录；
5. 更新项目内全部 `.gd`、`.tscn`、`.tres` 和 `.md` 中的 `res://SkillSystem/...` 引用；
6. 扫描旧目录名，要求运行资源中无残留旧路径；
7. 运行全部 SkillSystem 测试和相关项目集成测试；
8. 执行 Godot 4.7 编辑器扫描；
9. 再次核对 `TestScene.tscn` 哈希。

不创建兼容复制目录、符号链接或重复脚本。迁移完成后只保留编号化路径，避免两套路径长期并存。

## 安全边界

- 不修改或添加 `res://Scenes/TestScene.tscn` 中的任何单位实例。
- 不改变 Skill、Host、Delivery、Payload 或 AI 请求桥的运行逻辑。
- 不修改 HolyLight、Firebolt 的数值和表现参数。
- 不移动 `Effects`、`Scenes/Projectiles`、角色场景或项目公共 Combat Components。
- 不删除旧技能系统文件。
- 如果完整测试在迁移前已有失败，必须记录基线并区分既有失败与迁移回归。
- 路径迁移失败时使用项目外备份恢复，不执行破坏性 Git 操作。

## 验收标准

- FileSystem 中的 `SkillSystem` 顶层目录严格按 `00` 到 `11` 排序。
- `07-Delivery` 子目录严格按 `00` 到 `03` 排序。
- 所有新路径均能被 Godot 4.7 正确加载。
- HolyLight 和 Firebolt 的资源、场景与角色装配保持有效。
- Mage2 Firebolt 从角色世界空间 Socket 发射。
- Healer HolyLight 自动请求保持有效。
- SkillSystem 全部测试通过。
- Godot 编辑器扫描无新增 ERROR 或 WARNING。
- `TestScene.tscn` 内容和哈希不因迁移发生变化。
- `SkillSystemUserGuide.md` 可独立指导使用者完成一个无需专属脚本的新技能。
