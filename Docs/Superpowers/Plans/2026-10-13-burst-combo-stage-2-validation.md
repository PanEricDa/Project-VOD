# 爆发连携阶段二验收记录

日期：2026-10-13。状态：阶段二实现及后台验收完成；最终126/126通过，独立审查问题已修复验证。实际键盘与操作手感待用户人工验收；未进入阶段三。

基线/当前HEAD：`0a2b21edbb1dc5de18b5692c0f9feffa985ca172`；本阶段均为当前目录未提交差异。未自动提交或上传GitHub。

## 可见成果

运行`res://Scenes/Previews/SquadChainCommandPreview.tscn`（F6），1盾击、2强效治疗、3火球、4连射。四卡显示实际费用、等待/接近/施放/收尾/缓存以及拒绝原因；已有Focus显示总量、预留、可用。预览继承正式房间，复用17单位，仅自身初始专注100。

已实现独立连携槽、单伙伴一条等待缓存、原动作结束后衔接、连携动作锁、执行前当前锁定意图、原目标策略回退、专注预留/提交/退款、重复费用与根/子交付清理。正常AI两个普通槽继续工作，连携不受自身/公共CD和AI犹豫限制，不抹去已有普通计时。

没有实现阶段三伤害间隔窗口、评分或阶段四终结选择/暂停演出；预览是单个开发费用批次，不是最终连携流程。

配置指南：`SkillSystem/04-Docs/SquadChainCommandConfigurationGuide.md`。新增配置仅7种字段：Host1、费用2、控制器3、显示1。内部身份、用途、tokens、轮次和状态均不export。

## 验证与修正

- 每个任务先RED再GREEN；前六任务完整回归分别119、120、121、123、124、125个有效入口通过。最后活跃项目扫描126个SceneTree `*Test.gd`（118旧+8新），不计Archive下9个旧体系入口或会写资源的工具脚本。
- 第一轮最终回归125/126；Caster旧测试假定总登记数2。修正为总登记3、普通槽仍2且连携引用自己的独立节点，单项已PASS。最终整轮结果及审查结论待写入下节。
- RangedAttackPipeline独立RefCounted契约：`collect_failures()`返回`[]`。
- Guardian实际动作资源：释放0.20s、开近战窗口0.21s、动作结束0.60s；没有修改动画迁就收费。装配Probe输出完整MeleeAction payload。
- InputMap物理device0匹配新增测试先失败；MCP写入device16只绑定指定设备。通过MCP编辑器API正式保存为device=-1（所有设备），四动作真实匹配测试PASS。生产脚本只使用InputMap动作名。
- UI首次运行发现Godot不支持`%g`，改用支持的字符串格式；最终UI测试无ERROR，卡片显示20.0/30.0的真实费用。
- 两个旧测试迁移：HolyLight同步效果失败仍视为已接受并进入CD；压力测试血量缺口由delivery_started移到delivery_finished，避免接受通知早于治疗时被测试自身立即回满。未改数值。

## 实际预览数据

MCP运行真实预览，通过`Input.parse_input_event`注入device0物理数字键，经过Viewport/InputMap/控制器/真实角色动作/Delivery，不直接调用技能释放。运行时探针不保存正式场景。

| 批次 | 根请求 | 技能 | 实际收费 | 生命周期 |
| --- | --- | --- | --- | --- |
| 93 | 94 | combo_guardian_bash | 20 | 完成 |
| 93 | 96 | combo_greater_heal | 20 | 完成 |
| 93 | 98 | combo_firebolt | 20 | 完成 |
| 93 | 100 | combo_rapid_shot | 20 | 完成 |
| 877 | 878 | combo_greater_heal | 20 | 完成 |
| 877 | 883 | combo_greater_heal | 30 | 完成 |

第一轮总量100→20，预留0、请求记录0；第二次重开批次不同，连续治疗总量100→50，预留0、记录0。满血也能显式请求治疗，未误用仅自动AI的40%条件。

ComputerUse已检查真实窗口截图、布局与焦点；其数字键注入实际收到keycode50/physical4194313/device16，不能声称它成功模拟物理数字键。此为自动化输入限制，保留物理InputMap设计，不为工具额外添加游戏规则。需用户在编辑器实际按1—4进行手感验收。

## 正式场景后台审计

运行`Tools/CombatSimulation/RunSquadFocusSceneAudit.gd`默认3轮各20秒战斗、10次额外重载、2200笔事务，退出0、`SquadFocusSceneAudit: PASS`，failures空。

| 战斗轮 | 有效收益事件 | 有效伤害 | 最终Focus（与逐笔计算相同） | 最大账差/范围不一致 |
| --- | --- | --- | --- | --- |
| 1 | 80 | 1300.0 | 28.4556126287902 | 0 / 0 |
| 2 | 87 | 1432.75920706839 | 40.2640999512972 | 0 / 0 |
| 3 | 84 | 1350.69158770617 | 33.9614530121137 | 0 / 0 |

13次清理均回到46基准节点、0孤儿、0旧Focus监听；世界、专注池和旧单位WeakRef释放。收益来源只有原普攻/普通技能和其子技能，没有自动施放Combo技能。

另有生命周期测试：10次重载+1000次实际零费用请求，预留/请求归零；旧追踪弹/触发子技能失败不清新动作，子投射物保留根身份且不二次收费。测试关闭特效仅为隔离账务压力，不代表已完成GPU/特效性能评估，不宣称任意场景绝无内存增长。

## 文件与编辑检查

等效单项验证命令（用console版本可在PowerShell中正确等待退出）：

```powershell
& 'G:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe' --headless --path 'G:/Godot/ProjectVOD' --script 'res://UnitSystem/Tests/SquadChainInputDisplayTest.gd'
& 'G:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe' --headless --path 'G:/Godot/ProjectVOD' --script 'res://Tools/CombatSimulation/RunSquadFocusSceneAudit.gd'
```

全量入口扫描：`rg -l '^extends SceneTree' -g '*Test.gd' -g '!addons/**' -g '!Archive/**'`，每个文件分别运行。检查退出0、PASS，且无ERROR/SCRIPT ERROR；不是仅相信工具的success字段。

新增14个gd（运行/预览6、测试8），7个tscn，0个正式tres/res；新增gd.uid由Godot登记。修改15个既有生产文件（10脚本、4伙伴源场景、project.godot），另修改4个旧测试与更新文档（3个契约迁移、1个Focus重入回归）。

7个新场景由Godot正式保存并校验有效UID；预览有正式房间base SceneState，四角色combo_skill强类型引用自己的SkillSocket实例，显示引用本关卡控制器。`Scenes/TestScene.tscn`与`Scenes/TestCombatRoom.tscn`均未修改。未更改普通技能数值、普通优先级或动画/VFX。

场景主要使用Godot MCP Pro；其通用实例工具展开冗余覆盖，改用MCP调用GEN_EDIT_STATE_INSTANCE；继承预览无对应创建API，最小场景声明apply_patch后由Godot正式保存/验证；Markdown格式MCP不支持，用apply_patch。编辑器未保存内容未覆盖，验证涉及两个开放脚本缓冲区均与磁盘一致。

## 最终回归与独立审查

独立审查：gpt-6-astra high，fresh context，只读审查tracked diff与全部untracked新实现、完整设计/计划及裁定记录。没有Critical或Minor，发现3项Important；全部通过先失败后通过的回归验证修复，不以审查意见替代测试证据。

1. Guardian连携近战开窗后被施法封锁，原取消入口没有关闭检测，残留命中会因载荷清空变成普通伤害并恢复专注。`AllyChainCommandPriorityTest`复现取消后新目标入范围仍受伤/获得Focus；修复为在清载荷之前同步关闭命中窗口，测试通过。
2. Controller在reserve同步通知重置Focus、解绑再绑定同世界或acquire重绑后继续受理旧请求。`SquadChainCommandTransactionsTest`新增3种同步重入案例均先失败；修复为保留原generation/world/pool/ledger，回调后核对原会话与本笔实际预留，回滚原事务所有者，测试通过。
3. scope_changed(null)回调内bind_scope原本返回true，但随后的旧解绑擦除新绑定并残留退出监听。`SquadFocusComponentTest`复现错误成功与重复连接；解绑内部串行保护，回调内重入绑定返回false，外层清理后再调用可正常绑定并取得新伤害收益，测试通过。此为内部生命周期保护，不新增配置或游戏机制。

修复后的完整126回归通过了一轮；正式场景3×20秒/10重载/2200事务审计也再次PASS：三轮账差与scope_mismatches均0，13次清理节点46、孤儿0、旧监听0。原有审计表是第一轮数据；审查修复后最终Focus分别28.3623147566386、26.1915776357611、35.0339141579483，均与逐笔计算相同。

同一修复阶段追加第四种受理边界测试：Host已缓存请求后，监听者禁用后续输入。修复前控制器误报拒绝但请求仍存在；改为入队前检查输入许可、入队后只核对原会话归属，RED→GREEN。已受理请求不因输入禁用取消，符合原方案。最终再次全量回归126/126通过：每项退出0、有PASS、无ERROR/SCRIPT ERROR或超时。RangedAttackPipeline再次返回[]；git diff --check通过，正式两场景diff为空，编辑器未保存场景列表为空。

阶段三/四明确不属此次；ComputerUse实际输入与手感仍须人工验收；UID/类型/完整测试和文档状态由主执行者验证，审查者未启动Godot。未追加第二次审查。

## 实施裁定与代价

1. 文档/进度文件不受MCP支持，使用apply_patch；技能提供的脚本仅生成隔离的执行记录。 代价：额外记录文件；未绕过游戏资源编辑优先级。

2. 按用户确认留在当前目录、不自动提交，保留未提交的执行记录。 代价：暂留可恢复的忽略文件，后续版本记录需另授权。

3. HolyLight接受契约及压力夹具通知时序随设计迁移。 代价：旧断言改变；独立失败顺序测试防止掩盖实际收费错误。

4. 补Host内部动作占用接口与Base排队目标刷新，而不读取Ally内部状态。 代价：小型内部接口变化，已由真实动作/目标测试覆盖。

5. 新增Focus.can_commit纯查询本请求承诺，避免借用其他请求预留。 代价：事务契约扩展，已由重置/失效预留测试覆盖。

6. 场景实例改用MCP调用GEN_EDIT_STATE_INSTANCE，避免展开冗余配置。 代价：依赖Godot实例保存行为，已重载检查。

7. 继承预览缺少MCP创建接口，最小声明回退apply_patch，然后Godot保存、UID及base SceneState验证。 代价：继承/引用风险，已有场景契约测试。

8. 无授权提交且review-package拒绝空提交范围，审查工作区diff和全部untracked实现。 代价：新文件可能被漏看；审查明确包含全部新实现。

9. 解绑中的重入bind_scope明确返回false，待外层结束重试。 代价：调用者需延后绑定；不增加配置或排队系统。

10. 保留阶段三/四的边界，不提前实现窗口、评分或终结。 代价：当前预览不是完整爆发循环，已明确标识。

11. ComputerUse物理键注入不一致，保留InputMap并报告限制，由人工验收手感。 代价：自动化不能证明所有真实键盘环境；device0与实际Viewport已验证。

12. 最终回归、UID与Inspector由主执行者验证，不让只读审查代替运行结果。 代价：仍需用户实际编辑器体验确认索引和易用性。

13. 文档状态等修复后回归全绿再标完成。 代价：短暂验证中状态，最终文件同步检查。

没有延期Minor；独立审查发现的三项Important均修复，最终完整回归已通过。未自动提交、上传、合并或删除当前工作区。

## 已知测试警告（预期降级案例）

1. CombatHUDBindingIntegrationTest：两个Player时HUD拒绝绑定。
2. CameraFollowControllerTest：多个Player时镜头等待唯一目标。
3. EncounterControllerTest：忽略空Pack。
4. PlayerTargetingComponentTest：未配置正式锁定标识时仍保留锁定能力。
5. SquadFocusSceneBindingTest：缺少或多个Player时自动绑定拒绝（两次）。

这些来自主动构造的不合法配置测试；不忽略非预期ERROR或ObjectDB泄漏。

## 最终126项逐项结果

下列均来自最终同一代码状态；有上述预期配置警告的五项仍无ERROR。

| 入口 | 退出码 | 结果 |
| --- | --- | --- |
| res://Effects/Skills/GreaterHeal/GreaterHealEffectTest.gd | 0 | PASS |
| res://Effects/Skills/GuardianShield/GuardianShieldSkillEffectTest.gd | 0 | PASS |
| res://Effects/Skills/GuardianTaunt/GuardianTauntReleaseEffectTest.gd | 0 | PASS |
| res://Effects/Skills/Pyroblast/PyroblastVisualEffectTest.gd | 0 | PASS |
| res://GameFlow/Rooms/Tests/CombatRoomControllerTest.gd | 0 | PASS |
| res://GameFlow/Tests/CombatHUDBindingIntegrationTest.gd | 0 | PASS |
| res://GameFlow/Tests/CombatHUDTargetHealthTest.gd | 0 | PASS |
| res://GameFlow/Tests/CombatHUDTest.gd | 0 | PASS |
| res://GameFlow/Tests/GameRunResultFlowTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/ApplyNamedStatusSkillEffectTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/ArcProjectileDeliveryTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/CasterFeetPresentationFacingTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/ConsumeNamedStatusSkillEffectTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/DeliveryResourceIndexTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/ExplosiveArrowAssemblyTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/ExplosiveArrowChainIntegrationTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/ExplosiveArrowStressTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/GreaterHealSkillTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/GuardianTauntConditionTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/GuardianTauntSkillTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/ImmediateArcVolleyTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/MarkedHostileCountConditionTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/MarkedTargetVolleyEdgeTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/MarkedTargetVolleyTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/MultiShotArcDeliveryTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/MultiShotSkillAssemblyTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/NearbySkillTargetQueryTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/PyroblastAssemblyTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/PyroblastIntegrationTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/RapidShotIntegrationTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/ShieldSkillFacingContractTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SingleSceneCoreContractsTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SingleSceneFireboltTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SingleSceneHolyLightTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SingleSceneSkillHostTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SkillCommandActivationTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SkillCommandSlotContractTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SkillConditionScopeTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SkillDamageProvenanceTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SkillHitOutcomeTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SkillSlotContractTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SkillSlotRoutingTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SkillSystemFinalLayoutTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/SkillTemplateLayoutTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/StatModifierSkillEffectTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/TargetHealthConditionTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/TargetResolverTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/ThreatChangeSkillEffectTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/TrackingProjectileConcurrencyTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/TriggeredSkillActivationTest.gd | 0 | PASS |
| res://SkillSystem/05-Tests/TriggerSkillEffectTest.gd | 0 | PASS |
| res://Tools/CombatSimulation/CombatNumericalSimulatorTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AIAttackControllerTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AICombatInheritanceTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AICombatSystemTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AISkillActionAnimationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AITargetingComponentTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AIUnitSkillFacingTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AIVisualContractTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AllyBehaviorStateMachineTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AllyInheritedRootRenameTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AllyMeleeCombatIntegrationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AllySkillCombatPolicyTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AllyStatusConfigurationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/AllyTargetingIntegrationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/BasicAttackDamageIntegrationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/CameraFollowControllerTest.gd | 0 | PASS |
| res://UnitSystem/Tests/CasterFireboltRuntimeTest.gd | 0 | PASS |
| res://UnitSystem/Tests/CasterSkillActionAssemblyTest.gd | 0 | PASS |
| res://UnitSystem/Tests/ChainCommandTargetSelectionTest.gd | 0 | PASS |
| res://UnitSystem/Tests/CharacterSkillSlotAssemblyTest.gd | 0 | PASS |
| res://UnitSystem/Tests/CombatDamageContractTest.gd | 0 | PASS |
| res://UnitSystem/Tests/CombatValueResolverTest.gd | 0 | PASS |
| res://UnitSystem/Tests/ComboCostLedgerTest.gd | 0 | PASS |
| res://UnitSystem/Tests/DamageAttributionIntegrationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/EncounterControllerTest.gd | 0 | PASS |
| res://UnitSystem/Tests/EnemyAttackEntryDelayTest.gd | 0 | PASS |
| res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd | 0 | PASS |
| res://UnitSystem/Tests/EnemyThreatComponentTest.gd | 0 | PASS |
| res://UnitSystem/Tests/EnemyThreatIntegrationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/FormationPositionDataTest.gd | 0 | PASS |
| res://UnitSystem/Tests/FormationTargetReservationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/GuardianTauntIntegrationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/HealingThreatIntegrationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/LegacyFrameworkArchiveContractTest.gd | 0 | PASS |
| res://UnitSystem/Tests/MeleeHitboxComponentTest.gd | 0 | PASS |
| res://UnitSystem/Tests/MeleeSkillDamageProvenanceTest.gd | 0 | PASS |
| res://UnitSystem/Tests/PlayerDashComboContinuityTest.gd | 0 | PASS |
| res://UnitSystem/Tests/PlayerDashRechargeTest.gd | 0 | PASS |
| res://UnitSystem/Tests/PlayerDashStatusBarTest.gd | 0 | PASS |
| res://UnitSystem/Tests/PlayerTargetingComponentTest.gd | 0 | PASS |
| res://UnitSystem/Tests/PlayerThreatFocusControllerTest.gd | 0 | PASS |
| res://UnitSystem/Tests/PriestHolyLightActionAssemblyTest.gd | 0 | PASS |
| res://UnitSystem/Tests/PriestHolyLightAutomaticRuntimeTest.gd | 0 | PASS |
| res://UnitSystem/Tests/ProtectAlliesPolicyTest.gd | 0 | PASS |
| res://UnitSystem/Tests/RangedWeaponResourceMigrationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/RepeatedSkillCastingLifecycleTest.gd | 0 | PASS |
| res://UnitSystem/Tests/ResourceUidAuditTest.gd | 0 | PASS |
| res://UnitSystem/Tests/ShieldAnimationLibraryTest.gd | 0 | PASS |
| res://UnitSystem/Tests/SkillApproachRecoveryTest.gd | 0 | PASS |
| res://UnitSystem/Tests/SquadChainCommandLifecycleTest.gd | 0 | PASS |
| res://UnitSystem/Tests/SquadChainCommandTransactionsTest.gd | 0 | PASS |
| res://UnitSystem/Tests/SquadChainInputDisplayTest.gd | 0 | PASS |
| res://UnitSystem/Tests/SquadFocusComponentTest.gd | 0 | PASS |
| res://UnitSystem/Tests/SquadFocusDebugDisplayTest.gd | 0 | PASS |
| res://UnitSystem/Tests/SquadFocusSceneBindingTest.gd | 0 | PASS |
| res://UnitSystem/Tests/StatusEffectComponentTest.gd | 0 | PASS |
| res://UnitSystem/Tests/TargetLockIndicatorTest.gd | 0 | PASS |
| res://UnitSystem/Tests/TargetSelectionPolicyTest.gd | 0 | PASS |
| res://UnitSystem/Tests/ThreatDebugDisplayTest.gd | 0 | PASS |
| res://UnitSystem/Tests/UnitBaseSkillHostAssemblyTest.gd | 0 | PASS |
| res://UnitSystem/Tests/UnitDeathAnimationIntegrationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/UnitDeathDissolveTest.gd | 0 | PASS |
| res://UnitSystem/Tests/UnitDeathLifecycleTest.gd | 0 | PASS |
| res://UnitSystem/Tests/UnitDirectoryLayoutTest.gd | 0 | PASS |
| res://UnitSystem/Tests/UnitHealthFrameTest.gd | 0 | PASS |
| res://UnitSystem/Tests/UnitRootConfigurationTest.gd | 0 | PASS |
| res://UnitSystem/Tests/UnitStateComponentTest.gd | 0 | PASS |
| res://UnitSystem/Tests/WeaponAttackRangeTest.gd | 0 | PASS |
| res://UnitSystem/Tests/WeaponDataInheritanceTest.gd | 0 | PASS |
| res://UnitSystem/Tests/WorldHealthBarDebuffTest.gd | 0 | PASS |
| res://UnitSystem/Tests/WorldHealthBarTest.gd | 0 | PASS |
