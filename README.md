# 神代遗痕 · Vestiges of the divine

> **ProjectVOD** — 3D 俯视角小队战斗游戏 ｜ Godot 4.7（Forward Plus · Jolt Physics）｜ 灰盒原型阶段

一队清道夫深入神战遗迹，回收遗留之物的后英雄奇幻世界。玩家主控 1 名角色，带领 4 名 AI 队友（战法牧体系）对抗怪物群——微缩 MMO 式的仇恨、拉怪与合波战斗。

## 项目概况

**核心战斗闭环已完整实现**：移动 → 索敌 → 仇恨 → 普攻/技能 → 伤害结算 → 死亡 → 房间胜负 → 结算重开。

| 维度 | 现状 |
|---|---|
| 单位 | 玩家 Hero + 5 名友方职业（Saber / Archer / Caster / Guardian / Priest）+ 2 种敌人（哥布林战士/弓手） |
| 技能 | 单场景架构技能系统（一技能一 `.tscn`），已实装 Firebolt（追踪火球）/ HolyLight（自动治疗）/ GuardianShield（盾击+Buff） |
| 仇恨 | 每敌人本地仇恨表：125% 换目标缓冲（Guardian 1.05）、S 形半衰期衰减、治疗仇恨、武器仇恨倍率（盾 1.6）、红黄框 OT 预警 |
| AI | 友军 7 态行为状态机（阵型游荡/战斗三态/技能接近/保护协攻/仇恨敏感犹豫），敌方 4 态 + Pack 协同目标交接 |
| 表现 | 头顶血条（SubViewport 广告牌）、死亡溶解着色器、命中停顿、火球三段特效——全部 CSG 灰盒占位 |
| 测试 | 73 个自研 headless 测试（`extends SceneTree` 独立进程），含目录契约 / UID 审计 / 归档边界守门测试 |
| 工具 | Tools/CombatSimulation 蒙特卡洛数值模拟 + 真实场景浸泡工具 |

命名唯一权威：[`Docs/Vestiges of the divine/GameName.md`](Docs/Vestiges%20of%20the%20divine/GameName.md)。旧名（SipSip / 吨吨游乐园 / 深渊清扫者）仅存在于 Archive 与带日期历史文档中。

## 运行与测试

- **编辑器运行**：Godot 4.7 打开工程，主场景 `Scenes/TestScene2.tscn`（自由战斗）；完整房间流程见 `Scenes/TestCombatRoom.tscn`（英雄+4 伙伴 vs 3 敌群 12 敌）。
- **操作**：WASD 移动 ｜ Shift 冲刺（无敌帧）｜ 左键攻击（连招+缓冲+冲刺取消）｜ 中键/F 锁定目标。

```powershell
# headless 单测（本机 Godot 路径，按需替换）
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path . --script 'res://UnitSystem/Tests/EnemyThreatComponentTest.gd'

# 编辑器扫描（改名/移动资源后重注册 UID 用）
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path . --editor --quit
```

## 目录结构

```
ProjectVOD/
├── UnitSystem/      # 单位框架：Base 继承链、AI/玩家、组件（行为/战斗/索敌/仇恨/状态/UI/相机）、遭遇战
├── SkillSystem/     # 单场景技能系统：01-Core / 02-Delivery / 03-Extensions / 00-Skills / 00-Templates / 05-Tests
├── Item/            # 武器（三级 Resource 数据 + 视觉占位）与投射物（追踪火球/抛物线箭矢）
├── Effects/         # 纯表现层：命中反馈、死亡溶解、技能特效（各配 Preview 场景）
├── GameFlow/        # Pack 遭遇 → 房间裁决 → GameRunController(autoload) → 结算 UI
├── Scenes/          # 两个测试场景（主入口 + 完整房间）
├── Materials/       # 13 份网格占位材质（连接纹理与全部 Visual 的美术中枢）
├── Tools/           # CombatSimulation 数值模拟与浸泡工具
├── Docs/            # 全部文档（见下）
├── Assets/          # 原型网格纹理 / HDR 天空 / 字体
├── addons/          # godot_mcp 插件（编辑器 AI 协作）
└── Archive/         # 历史备份（.gdignore 隔离，工作流不读取）
```

## 文档架构

**现行文档优先级**（高 → 低）：

1. `Docs/Vestiges of the divine/战斗系统总结与拓展报告.md` — **2026-08-21，最新权威**。基于代码现状的完整盘点 + 8 阶段增量路线图（专注资源 → GATHER/RELEASE 连携 → 编排 → 合波 → 内容切片）。
2. `Docs/Vestiges of the divine/` 其余 — 叙事圣经（明暗双线剧情、6 万字潘奇城社会志、中英开场文案）与五大系统框架（InitialGameSystem.md）、概念评审（项目综合评估报告.md）。
3. `Docs/CurrentProgressReport.md` / `CurrentSystemUserGuide.md` / `DevelopmentMemo.md` — 工程现状与配置指南（⚠ 进度报告快照停在 08-01，威胁系列落地内容未回写）。
4. `Docs/Superpowers/Specs|Plans` 与 `Docs/Plans/` — 带日期的设计/实施史料（07-30 → 08-07），**保留原样不回改**，是每个系统决策的完整演化档案。

## 开发规范备忘

- **命名**：文件与目录名 PascalCase（项目级决议；例外 `project.godot`、`addons/`、点目录）；GDScript 标识符按官方风格（类 PascalCase、函数/变量 snake_case）。
- **版本控制**：任何改动动手前先 commit 干净基线；完成一个可验证单元即提交（`feat:/fix:/docs:/chore:` 前缀）。
- **资源铁律**：正式 `.tres/.res` 必须经编辑器 / MCP / `ResourceSaver` 保存（保证有效 UID + Quick Load 可检索）；纯文本写入不算完成。改名/移动资源后跑一次编辑器扫描重注册 UID。
- **场景铁律**：`TestScene*.tscn` / `TestCombatRoom.tscn` 中的单位实例由用户在编辑器手动摆放，AI 不代为增删。
- **Archive 政策**：仅作备份，活动代码/测试/文档不得引用 `res://Archive`（有契约测试 `LegacyFrameworkArchiveContractTest` 守护）。
- **解耦原则**：意图提交、宿主执行；`locked_target` 唯一持有者；伤害只走 `CombatValueResolver` 单出口；表现层纯订阅可整体拆卸。

## 已知事项 / 待办备忘

- [ ] 弓普攻浮动值三方矛盾待定：测试断言 `0.13` ｜ `BowData.tres` 实值 `0.2` ｜ 设计文档 `10%`
- [ ] 刷新 CurrentProgressReport（补写 08-02~08-07 威胁系列、测试数 44→73）
- [ ] 测试 runner 脚本与 CI（73 个测试目前逐个手跑）
- [ ] 调试残留清理（`TargetSelectionPolicy` 的 print、`debug_hitbox_enabled` 默认值、TestScene2 调试数值、3 个 MCP autoload 的导出摘除）
- [ ] `Assets/HDR Sky/` 的 Sky01–03 为零引用孤儿资产（共约 180MB，可删以瘦身）；Sky04 超过 GitHub 50MB 建议值
- [ ] 暂缓系统（07-31 设计文档明确）：暴击、掉落、关卡失败、专注度（Focus）、嘲讽技能
- [ ] 8/21 路线图阶段 1 起：AI 自动战斗稳定化 → 专注+掩护 → 连携语言 → 垂直切片

---

*本仓库基线建立于 2026-08-24（正名整理 + Git 初始化首个提交）。开发章程见用户级《Godot开发章程》，项目级补充见根目录 `CLAUDE.md`。*
