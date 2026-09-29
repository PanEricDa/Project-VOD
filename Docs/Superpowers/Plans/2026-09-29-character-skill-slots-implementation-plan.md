# 角色技能槽 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已有 SkillHost 上实现默认两个常规技能槽及一个可空终结技槽，迁移现有角色而不改变技能内容。

**Architecture:** 技能仍是 SkillSocket 的直接子节点，Host 通过节点引用表达装备。注册与装备分离，AI 及显式请求按装备资格过滤，所有施放继续复用原有链路。

**Tech Stack:** Godot 4.7、GDScript、继承场景、现有 SceneTree headless 契约测试；不引入依赖。

**Spec:** `Docs/Superpowers/Specs/2026-09-29-character-skill-slots-design.md`。

**状态：** 用户已授权执行，实施记录见文末。计划步骤保留原文作为验收依据。

## Global Constraints

- 不修改 `Scenes/TestScene.tscn` 中的任何单位实例。
- 普攻、移动、闪避仍是行动，不进入技能槽。
- 不实现爆发编排、专注消耗、评分、终结技内容、技能背包、解锁、战斗中换装。
- 不删除或重新实例化现有技能节点，不改变技能数值、AI 优先级、Condition、特效或动作参数。
- 增加的参数、公开方法及其参数必须在声明附近提供简体中文说明。
- 现有未提交改动须完整保留；不把其他工作混入本功能提交。
- 不新增正式 .tres/.res；若确需创建，必须遵守 AGENTS.md 的正式保存、有效 UID 和强类型索引验证要求。

## Review Focus

1. 删除或注销技能后，查询、自动选技及 Host 退出均不得访问失效对象：任务 1/2。
2. 空槽与重复引用不能改变原始槽号，同优先级不得变成槽号优先：任务 1/2。
3. 超远程终结技不能拉远日常站位，但活动终结技应使用自己的施放距离：任务 2。
4. 同一角色场景实例化两次，装备引用和冷却不能串到另一实例：任务 3。
5. 既有用户参数覆盖及测试用例不能因“重新装配”丢失或通过放宽断言掩盖回归：任务 3。

## 执行前准备与验证命令约定

获得执行授权后，再读取执行、TDD、验证及工作树相关技能。工作树须保留当前实际基线；当前多个实现依赖尚未提交（含 GreaterHeal），不能从旧 HEAD 新建工作树后假定内容齐备。先检查可复用工作树和差异；若隔离会遗漏用户工作，先明确解决基线问题，不自动提交所有改动或丢弃它们。

记录 `git status --short`、受影响文件 diff、已有测试结果。先运行现有 `SkillSystem/05-Tests` 与 `UnitSystem/Tests` 的 SceneTree 测试；既有失败单独记录，不扩大本功能修复范围。

本机路径已只读确认存在，以下命令在未来执行阶段使用，不代表本轮已运行：

```powershell
$slotGodot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
$slotProject = 'G:\Godot\ProjectVOD'
& $slotGodot --headless --editor --path $slotProject --quit
& $slotGodot --headless --path $slotProject --script 'res://SkillSystem/05-Tests/SkillSlotContractTest.gd'
& $slotGodot --headless --path $slotProject --script 'res://SkillSystem/05-Tests/SkillSlotRoutingTest.gd'
& $slotGodot --headless --path $slotProject --script 'res://UnitSystem/Tests/CharacterSkillSlotAssemblyTest.gd'
```

若使用工作树，仅将 `$slotProject` 改成返回的实际目录。每个命令单独检查退出码和输出；测试成功标准为对应 `TestName: PASS`、退出码 0，且无新增解析错误、失效实例访问或资源错误。首个命令用于导入与生成脚本 UID，不得当作行为测试。

新测试遵循现有 `_expect` 收集失败、`_finish` 输出 PASS 或 quit(1) 的 SceneTree 模式。红灯阶段使用 `get`/`call` 检查缺失字段或方法，避免只得到全项目解析失败而未触达目标断言。以下断言片段表达测试要求，fixture 复用当前 TestUnit 和最小技能场景模式。

## 文件范围

- 修改：`SkillSystem/01-Core/SkillHostComponent.gd`。
- 修改：`UnitSystem/AI/Ally/Units/{Guardian,Priest,Caster}.tscn`。
- 新增：`SkillSystem/05-Tests/SkillSlotContractTest.gd`、`SkillSlotRoutingTest.gd` 及 Godot 生成的 `.uid`。
- 新增：`UnitSystem/Tests/CharacterSkillSlotAssemblyTest.gd` 及 `.uid`。
- 迁移已确认直接依赖 Host 的夹具：`SkillSystem/05-Tests/SingleSceneSkillHostTest.gd`、`SkillConditionScopeTest.gd`、`UnitSystem/Tests/UnitDeathLifecycleTest.gd`。
- 回归现有角色调用：`UnitSystem/Tests/PriestHolyLightActionAssemblyTest.gd`、`SkillApproachRecoveryTest.gd`，通常只需角色场景迁移即可，不预先修改断言。
- 更新：`SkillSystem/04-Docs/SkillSystemUserGuide.md`。
- 不修改 SkillBase、SkillContext、Delivery、Effects 或行为状态机；若发现确需接口变更，先报告偏离设计的原因。

## Task 1：槽位数据、读取与校验

**Files:** Host 脚本；新增 SkillSlotContractTest 及 UID。

**Interfaces:** 消费 `register_skill(skill: SkillBase) -> bool`、`unregister_skill(skill: SkillBase) -> bool` 和固定 SkillSocket；提供 `regular_skills: Array[SkillBase] = [null, null]`、`finisher_skill: SkillBase = null`、`get_regular_skill(slot_index: int) -> SkillBase`、`get_equipped_regular_skills() -> Array[SkillBase]`、`get_finisher_skill() -> SkillBase`。

- [ ] **1. 编写失败测试。** 测试名称与核心断言如下；每个生命周期变体使用独立 fixture，避免污染后续测试。

```gdscript
# test_defaults_and_sparse_slots
_expect(host.get("regular_skills").size() == 2, "Two default regular slots")
_expect(host.call("get_finisher_skill") == null, "Empty finisher")
# 设置 [null, skill_a, null]，a 已挂到 socket 并注册
_expect(host.call("get_regular_skill", 0) == null, "Keep empty slot")
_expect(host.call("get_regular_skill", 1) == skill_a, "Stable index")
_expect(host.call("get_regular_skill", -1) == null, "Negative index safe")
_expect(host.call("get_regular_skill", 3) == null, "Overflow safe")
# test_duplicate_and_cross_role_references：设置 [a, a, foreign_skill]
_expect(host.call("get_regular_skill", 1) == null, "Duplicate slot rejected")
_expect(host.call("get_regular_skill", 2) == null, "Foreign skill rejected")
# 再把 finisher_skill 设为 a
_expect(host.call("get_finisher_skill") == null, "Regular slot wins conflict")
```

补充 `test_registration_and_lifetime`：未注册、重复 ID 注册失败、注销、queue_free 当帧及释放后均返回 null；释放后再次注册新技能及释放 Host 不报错。`test_read_list_is_copy`：清空返回列表，原槽保持不变。`test_editor_warnings`：结构有效的引用在尚未运行 discover_skills 时不报告“未注册”；重复、外部父节点警告包含位置及修复说明，合法空槽无警告。

- [ ] **2. 运行 SkillSlotContractTest，确认红灯来自新字段、接口或槽位规则缺失。** 保存失败输出，不接受无关导入错误作为红灯证据。
- [ ] **3. 实现上述字段、查询和结构校验。** 有效性先判存活/待删除，再判本地父节点，再判注册；重复普通引用首槽有效，常规优先于终结技。编辑器警告独立于注册列表，按规格第 11 节处理字段/元素变化刷新。注册、查找及退出清理防御失效对象，不修改未装备技能的参数或状态。
- [ ] **4. 运行 SkillSlotContractTest 与 SingleSceneSkillHostTest。** 预期新测试通过，旧路由行为此时尚未切换，旧 Host 测试保持基线。实际 Inspector 修改数组元素，验证警告刷新；保存角色引用的完整验证归任务 3。
- [ ] **5. 审查并提交本任务差异。** 建议消息 `feat(skill): add explicit character skill slots`。Host 已有用户未提交改动，仅提交本任务新增差异；无法安全拆分时保留未提交并在交付说明，不提交整份混合文件。

## Task 2：路由、AI 候选和站位接入

**Files:** Host；新增 SkillSlotRoutingTest 及 UID；迁移 SingleSceneSkillHostTest、SkillConditionScopeTest、UnitDeathLifecycleTest 中动态创建/注册的技能夹具。

**Interfaces:** 消费任务 1 查询接口；保留现有 `request_skill(skill_id: StringName, target: Node3D, candidate_targets: Array[Node3D] = [], target_position: Vector3 = Vector3.INF, source: int = SkillContext.RequestSource.EXPLICIT) -> bool`。新增 `request_finisher(target: Node3D, candidate_targets: Array[Node3D] = [], target_position: Vector3 = Vector3.INF) -> bool` 和规格第 10 节的 `_request_resolved_skill(...) -> bool`。

- [ ] **1. 编写失败测试。** a、b 为常规槽，spare 已注册未装备，finisher 为独立终结技。所有 fixture 使用可命中的有效目标、零额外犹豫和显式重置，隔离随机性。

```gdscript
# test_equipment_filters_ai：a 优先级 10，b 为 20，spare/finisher 为 999
_expect(host.request_best_skill(enemy), "Accept regular AI request")
_expect(host.get_active_skill() == b, "High priority equipped regular wins")
# test_explicit_boundaries：每次用独立或清理后的 fixture
_expect(not host.request_skill(spare.skill_id, enemy), "Reject unmounted skill")
_expect(not host.request_skill(finisher.skill_id, enemy), "Reject finisher on normal entry")
_expect(host.call("request_finisher", enemy), "Dedicated finisher entry accepts")
_expect(host.get_active_skill() == finisher, "Use same finisher instance")
```

增加 `test_equal_priority_keeps_registration_order`：a、b 同优先级，注册 a 在前，槽位为 [b,a]，仍选 a。`test_rejection_is_side_effect_free`：空终结技、无效目标、冷却、公共冷却、动作占用、禁用、死亡分别拒绝；action_requested 为 0、无新增 active skill、技能原有冷却未改变。合法终结技在 automatic_cast_enabled=false 时可显式请求，在 true 时依旧不参与 AI。Condition 的 AI_ONLY 与 ALL_REQUESTS 按原作用域断言。

增加 `test_range_uses_equipment_and_active_action`：a 范围 5、b 范围 8（更高优先级）、spare/finisher 范围 100；空闲返回 8，b 冷却中仍为 8；禁用 b 自动施放后为 5；合法活动终结技返回 100，完成动作后回到 5；没有自动常规装备则为 0。增加 `test_freed_registered_skill_does_not_break_ai`：释放 spare 后选技、注册和退出仍安全。

- [ ] **2. 运行 SkillSlotRoutingTest。** 确认旧注册即候选逻辑或缺少终结入口导致失败。
- [ ] **3. 实现请求装备检查与共用内部请求链。** AI 和空闲站位仍遍历注册顺序，但只接受有效常规装备；保留 candidate snapshot 一次读取、Condition、priority、source、活动技能范围分支及现有冷却逻辑。普通显式与终结显式入口分流后复用内部函数，不能让 request_finisher 再调用受常规装备限制的 request_skill。
- [ ] **4. 更新动态 Host 测试夹具。** 技能仍挂本地 SkillSocket 并注册，再显式赋值 regular_skills；不修改直接调用 SkillBase 的夹具。UnitDeathLifecycleTest 的装配 helper 同样装槽，不能让死亡测试因“未装备”提前失败而产生假阳性。
- [ ] **5. 运行两个新技能槽测试、SingleSceneSkillHostTest、SkillConditionScopeTest。** 预期全部 PASS；UnitDeathLifecycleTest 完整回归在任务 3 场景迁移后再执行。对仅依赖旧角色场景未装槽产生的临时失败明确记录，不更改生产回退逻辑。
- [ ] **6. 审查并提交本任务新增差异。** 建议消息 `feat(skill): route casting through equipped slots`，遵循任务 1 的混合工作区保护要求。

## Task 3：角色迁移、持久化和整体回归

**Files:** Guardian/Priest/Caster 源场景；新增 CharacterSkillSlotAssemblyTest 及 UID；SkillSystemUserGuide。

**Interfaces:** 消费任务 1/2 的全部公开接口；不新增产品接口。

- [ ] **1. 编写失败装配测试。** Guardian 槽 0/1 指向原 Shield/Taunt；Priest 指向原 HolyLight/GreaterHeal；Caster 为 Firebolt/null；Archer、Saber 为 null/null；所有终结槽为空。使用原节点路径比较对象身份，不只比较技能 ID。

```gdscript
# test_priest_slots_keep_existing_nodes
_expect(host.call("get_regular_skill", 0) == priest.get_node("SkillHost/SkillSocket/HolyLightSkill"), "Keep HolyLight instance")
_expect(host.call("get_regular_skill", 1) == priest.get_node("SkillHost/SkillSocket/GreaterHealSkill"), "Keep GreaterHeal instance")
# test_two_instances_are_isolated：two_priest 已实例化、注册完成
_expect(host.call("get_regular_skill", 0) != other_host.call("get_regular_skill", 0), "Separate instances")
# 第一实例启动技能冷却后，第二实例仍 ready；清空第一实例数组不改变第二实例槽位。
```

`test_save_reload_preserves_slot_references`：将正确 owner 的独立测试角色 PackedScene 保存到 `user://skill_slot_contract_roundtrip.tscn`，忽略资源缓存重新加载、实例化、入树；槽位仍引用新实例自己的子节点，并保留空槽。删除这个明确命名的测试临时文件，不写正式资源或 TestScene。

- [ ] **2. 运行 CharacterSkillSlotAssemblyTest。** 预期现有 Guardian/Priest/Caster 未配置槽位时失败。
- [ ] **3. 迁移三个角色源场景。** 只添加 Host 的槽位引用覆盖；保留原节点名、层级、技能参数和 Priest Delivery 子资源。用当前 Godot 的实际保存结果确认节点引用序列化，不凭手写 NodePath 文本推断正确。Archer/Saber 使用继承默认空槽，不需新增覆盖。
- [ ] **4. 实际加载与执行三个新测试。** 保存重载和双实例测试全部通过；检查新增脚本 UID 已由 Godot 生成。对比迁移前后场景 diff，除 Host 引用外无其他行为参数变化。
- [ ] **5. 更新用户指南。** 增加“挂载 .tscn → 拖节点入槽”的操作步骤、空槽/重复警告、注册与装备差异、默认 2+1、自动选技边界、终结入口、非运行时换装说明。明确当前没有终结技能内容或爆发执行器。
- [ ] **6. 整体回归并人工 Inspector 验证。** 按下列命令运行技能及单位测试，逐项记录结果；在角色源场景 Inspector 中调整槽位顺序、清空/恢复引用、制造/恢复重复引用，确认警告及保存重载正确。测试后恢复已确定的迁移表配置，不修改 TestScene。

```powershell
$slotTestFiles = Get-ChildItem -LiteralPath "$slotProject\SkillSystem\05-Tests", "$slotProject\UnitSystem\Tests" -Filter '*Test.gd'
foreach ($slotTestFile in $slotTestFiles) {
    if (-not (Select-String -LiteralPath $slotTestFile.FullName -Pattern '^extends SceneTree' -Quiet)) { continue }
    $slotRelative = $slotTestFile.FullName.Substring($slotProject.Length + 1).Replace('\', '/')
    & $slotGodot --headless --path $slotProject --script "res://$slotRelative"
    if ($LASTEXITCODE -ne 0) { throw "Failed: $slotRelative" }
}
git diff --check
git diff -- Scenes/TestScene.tscn
```

必须覆盖：UnitBaseSkillHostAssemblyTest、AllySkillCombatPolicyTest、CasterSkillActionAssemblyTest、PriestHolyLightActionAssemblyTest、SkillApproachRecoveryTest、RepeatedSkillCastingLifecycleTest、UnitDeathLifecycleTest、GreaterHealSkillTest、GuardianTauntSkillTest、GuardianTauntConditionTest、TargetHealthConditionTest，以及任务 2 的测试。不将“脚本退出 0 但出现新增运行时错误”判为通过。TestScene 的差异应与执行前基线一致，不能把用户原有差异当成本次删除目标。

- [ ] **7. 代码审查与提交。** 检查只新增两个 Inspector 字段、无状态机/数值/条件改写、无重复实例、中文说明完整。建议消息 `feat(skill): equip existing allies and document slots`；只纳入本功能可分离差异。在最终报告中列出通过/失败/未执行测试与必要的人工验证限制，不宣称本次槽位实现已完成爆发系统。

## 覆盖与交付检查

| 规格内容 | 负责任务 |
| --- | --- |
| 默认槽、读取、编辑器警告、失效引用与注册安全 | 1 |
| AI、同优先级、显式/终结入口、站位及底层合法性不变 | 2 |
| 角色迁移、用户参数保留、引用持久化与实例隔离 | 3 |
| 中文配置说明与策划操作文档 | 1、3 |
| 全量回归、TestScene 不变、用户改动保护 | 执行准备、3 |

计划自检：接口名称与规格一致；三个任务均有红灯/实现/绿灯步骤；五项 Review Focus 均有对应测试；无运行时换装、资源经济或爆发算法越界内容。以上是规划审查结果，不是测试通过记录。

## 实施记录（2026-09-29）

- 用户已授权开始实施。工作区原有大量未提交技能内容，且 Priest/GreaterHeal 依赖其中未跟踪文件。为保留实际基线，在当前检出上创建 `codex/character-skill-slots` 分支，没有复制、重置或提交用户改动。
- 基线抽查：`SingleSceneSkillHostTest`、`SkillConditionScopeTest`、`UnitBaseSkillHostAssemblyTest` 均通过。
- Task 1：新增 `SkillSlotContractTest`，先得到“默认槽/读取接口缺失”的预期失败，再实现槽位字段、读取、重复/跨 Host 校验。Godot 的节点类型数组必须以 `Array[SkillBase]` 赋值；未定型字面数组经 `Object.set()` 不会正确进入该字段。测试改用定型数组并验证通过。
- Task 2：新增 `SkillSlotRoutingTest`，先得到未装备技能可被请求、终结入口缺失等预期失败，再接入普通 AI、显式请求、终结入口与站位范围。迁移 `SingleSceneSkillHostTest`、`SkillConditionScopeTest`、`UnitDeathLifecycleTest` 的动态装配夹具。
- Task 3：新增 `CharacterSkillSlotAssemblyTest`，先验证旧场景的槽位缺失，再为 Guardian、Priest、Caster 增加节点引用。使用 Godot `PackedScene.pack` / `ResourceSaver.save` 在临时 `user://` 场景做序列化探针，确认节点引用编码为 `node_paths` 与 `NodePath`；正式场景仅添加对应 Host 覆盖。角色身份、重载与双实例冷却隔离测试通过。已更新技能系统用户指南。
- `--headless --editor --quit` 完成脚本导入，为三个新测试生成 `.gd.uid`。原有 `IronShieldData.tres` 对 ShieldAnimationLibrary 的失效 UID 产生警告，未改动该用户资源。
- 技能与单位目录的 80 个 SceneTree 测试中，71 个通过、9 个失败：`SingleSceneHolyLightTest`、`AICombatSystemTest`、`AllyMeleeCombatIntegrationTest`、`EnemyBehaviorStateMachineTest`、`PriestHolyLightActionAssemblyTest`、`PriestHolyLightAutomaticRuntimeTest`、`UnitDeathLifecycleTest`、`UnitRootConfigurationTest`、`WeaponAttackRangeTest`。前三个新技能槽测试均通过。HolyLight 旧测试断言固定治疗值，但当前用户配置有 `power_ratio = 1.2`，对应牧师数值断言亦未跟进；其他失败仍需与原有工作区基线对照，不能称为全部既有失败。
- 尚未完成：全绿回归、实际 Inspector 手动编辑验证、隔离提交及最终分支审查。后续任何完成声明必须说明这些限制。
- 独立只读审查发现重复 `skill_id` 时 Inspector 没指出失效槽位。新增失败断言后，Host 为重复 ID 的具体常规槽或终结技槽显示中文修复提示；`SkillSlotContractTest` 再次通过。审查中的数组元素以外结构变化告警刷新和部分额外测试组合仍是较小的后续覆盖事项。
- 当前打开的 Godot 编辑器仍缓存旧版 Host 脚本，且有未保存场景，故未强制重载。另一独立 Godot 编辑器进程实际读取到了 `regular_skills` 与 `finisher_skill` 两个导出字段，Priest 的两个技能节点引用正确。此验证不等于完成实时 Inspector 拖放操作。
