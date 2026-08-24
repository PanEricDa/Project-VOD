# Animation-Driven Skill Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让角色通用施法动画的方法轨道驱动当前技能释放，并彻底移除 Skill 对具体动画名称的依赖。

**Architecture:** SkillHost 只把已经计算完成的 `effective_cast_time` 作为动作请求数据传给 UnitSystem。AI 动作控制器从当前已装载的角色/武器动画库解析固定的 `basic_cast_1`，使用传入数据缩放播放速度，并通过动画事件轨道释放当前活动技能。

**Tech Stack:** Godot 4.7、GDScript、AnimationPlayer、AnimationLibrary、现有 SkillSystem 与 UnitSystem。

## Global Constraints

- 所有字段与方法使用英文标识，新增代码提供详细简体中文注释。
- 不修改 `Scenes/TestScene.tscn`，不自动添加或调整其中的单位实例。
- 动画缩放只能使用动作请求传入的 `effective_cast_time`，不得回访 Skill、Host 或 Unit 字段。
- 项目不是 Git 仓库，不创建提交，以测试和编辑器扫描作为交付依据。

---

### Task 1: 固化无动画名称的 SkillHost 动作契约

**Files:**
- Modify: `SkillSystem/01-Core/SkillBase.gd`
- Modify: `SkillSystem/01-Core/SkillHostComponent.gd`
- Modify: `SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd`
- Modify: `SkillSystem/05-Tests/SingleSceneSkillHostTest.gd`

**Interfaces:**
- Produces: `action_requested(skill: SkillBase, target: Node3D, effective_cast_time: float)`
- Removes: `SkillBase.action_animation_name`

- [ ] **Step 1: 编写失败测试**

验证 SkillBase 导出字段中不存在 `action_animation_name`，并验证 Host 转发的动作请求只包含
Skill、目标和已经计算好的施法时间。

- [ ] **Step 2: 运行测试并确认 RED**

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script res://SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd
& $godot --headless --path 'G:\Godot\SipSip' --script res://SkillSystem/05-Tests/SingleSceneSkillHostTest.gd
```

预期：旧字段或旧四参数信号导致测试失败。

- [ ] **Step 3: 实现最小契约调整**

删除 `action_animation_name`，将 SkillBase 与 SkillHost 的 `action_requested` 信号和回调统一为
三项数据。保留 `effective_cast_time` 的既有计算入口。

- [ ] **Step 4: 运行测试并确认 GREEN**

重复 Step 2，两个测试必须通过且没有 warning。

### Task 2: 让 AI 动作控制器解析通用施法动画

**Files:**
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`
- Modify: `UnitSystem/Components/Combat/AI/AICombatSystem.gd`
- Modify: `UnitSystem/Components/Combat/AI/AIAttackController.gd`
- Modify: `UnitSystem/Tests/AISkillActionAnimationTest.gd`

**Interfaces:**
- Consumes: `effective_cast_time: float`
- Produces: `request_external_action(effective_cast_time: float) -> bool`
- Animation resolution order: `weapon/basic_cast_1`, then `character/basic_cast_1`

- [ ] **Step 1: 编写失败测试**

覆盖以下行为：

- 控制器不接收动画名称。
- 控制器自动选择 `weapon/basic_cast_1`。
- 没有武器动作时回退 `character/basic_cast_1`。
- 播放速度只根据请求参数和 `release_action` 标记计算。
- 无效时间、无动画或标记数量错误时请求失败并输出错误。

- [ ] **Step 2: 运行测试并确认 RED**

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/AISkillActionAnimationTest.gd
```

预期：旧接口仍要求动画名称，通用解析测试失败。

- [ ] **Step 3: 实现通用动作解析**

在 AIAttackController 内部解析固定候选名称。解析成功后读取唯一
`release_action()` 时间点，并只使用传入的 `effective_cast_time` 计算播放速度。
所有失败分支调用 `push_error()` 输出动作名和具体失败原因，然后返回 `false`。

- [ ] **Step 4: 运行测试并确认 GREEN**

重复 Step 2，测试必须通过。

### Task 3: 迁移 Firebolt、HolyLight 与 Staff 动画资产

**Files:**
- Modify: `SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn`
- Modify: `SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn`
- Modify: `Item/Weapon/Staff/StaffAnimationLibrary.res`
- Modify: `UnitSystem/AI/Ally/Animations/CasterAnimationLibrary.res`
- Modify: `SkillSystem/05-Tests/SingleSceneFireboltTest.gd`
- Modify: `SkillSystem/05-Tests/SingleSceneHolyLightTest.gd`
- Modify: `UnitSystem/Tests/CasterSkillActionAssemblyTest.gd`

**Interfaces:**
- Staff action: `weapon/basic_cast_1`
- Caster fallback action: `character/basic_cast_1`
- Required method marker: `release_action()`
- Optional method marker: `finish_action()`

- [ ] **Step 1: 编写失败资产契约测试**

验证两个技能场景都没有动画名称配置，Staff 和 Caster 的通用施法动画均拥有唯一
`release_action()` 标记。

- [ ] **Step 2: 运行测试并确认 RED**

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script res://SkillSystem/05-Tests/SingleSceneFireboltTest.gd
& $godot --headless --path 'G:\Godot\SipSip' --script res://SkillSystem/05-Tests/SingleSceneHolyLightTest.gd
& $godot --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/CasterSkillActionAssemblyTest.gd
```

预期：旧技能动画字段或旧动画名称导致失败。

- [ ] **Step 3: 正式保存动画资源**

使用 Godot 编辑器 API 修改并通过 `ResourceSaver.save()` 正式保存两个现有外部
AnimationLibrary，保留其 UID。不得用纯文本伪造或覆盖二进制 `.res`。

- [ ] **Step 4: 运行测试并确认 GREEN**

重复 Step 2，三个测试必须通过。

### Task 4: 集成与错误路径验证

**Files:**
- Modify: `UnitSystem/Tests/CasterFireboltRuntimeTest.gd`
- Create: `UnitSystem/Tests/PriestHolyLightActionAssemblyTest.gd`

**Interfaces:**
- Verifies: 通用动作请求、动画缩放、事件轨道释放和失败报错。

- [ ] **Step 1: 编写 Priest 失败集成测试**

实例化 Priest，验证 HolyLight 正确注册，并在显式提供有效友方目标的情况下能够通过
Staff 的 `basic_cast_1` 进入动作释放链路。此测试不承担自动寻找友方目标的职责。

- [ ] **Step 2: 运行测试并确认 RED 或既有迁移后的 GREEN**

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/PriestHolyLightActionAssemblyTest.gd
& $godot --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/CasterFireboltRuntimeTest.gd
```

- [ ] **Step 3: 修正剩余接口错位**

只修正本计划定义的动作链路，不加入友方候选目标扫描或非战斗施法逻辑。

- [ ] **Step 4: 执行完整验证**

运行全部 `SkillSystem/05-Tests/*Test.gd`、本计划涉及的 UnitSystem 测试，并执行：

```powershell
& $godot --headless --editor --path 'G:\Godot\SipSip' --quit
```

要求退出码为 0，当前 Godot Output 与 Debugger 无新增 error 或 warning。

