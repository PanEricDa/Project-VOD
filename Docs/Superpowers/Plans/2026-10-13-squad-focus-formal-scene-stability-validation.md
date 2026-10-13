# 正式战斗场景：专注数据与生命周期稳定性验证

日期：2026-10-13。用户已在 `Scenes/TestCombatRoom.tscn` 装配 Focus 与显示组件，要求验证真实场景的数据与后台稳定性。

## 结论

当前测试范围内未发现专注漏计、重复计入、跨场景数据污染、旧专注监听残留、场景节点或孤儿节点泄漏。没有修改任何游戏实现、正式场景或单位/技能参数；仅新增可重复运行的审计工具及本报告。

验证范围是3轮各20秒实际战斗、10轮额外重载和2200笔零额资源事务，不能据此保证任意长时间、GPU显存或全项目所有系统均无泄漏。

## 真实场景装配核对

Godot MCP 启动用户保存的场景，读取运行时：绑定范围 `/root/TestCombatRoom`，队伍5名（Hero、Guardian、Priest、Caster、Archer），观察单位17名，显示正确绑定。五名角色的技能交付范围均为这个场景，未混入全局根或其他世界。

正式场景 SHA256 在压测前后保持一致：`9CFFCDD54831BB4FAC50D2BEF90B5492188DCFE3D8E963DF0840AEA9B358804D`。未保存或改动用户场景；游戏已停止，编辑器仍保留 TestCombatRoom。

## 逐笔独立核算

通过已有 `IdealHeroCombatDriver` 驱动真实玩家攻击及现有 AI 战斗；驱动初始化后立即恢复原 `can_die`，没有无敌、加伤害、加血量或改技能。主动让现有敌群进入战斗，只改变测试副本运行状态，不添加敌人或伙伴。

审计器独立读取权威伤害事件，验证实际伤害等于扣血前后差值、事件身份不重复、来源队伍与敌方关系正确，按收益属性/换算比例/实际容量独立计算并与专注组件每笔比对。不使用组件私有账目计算“期望收益”，也不调用事件 claim 抢占消费。

| 轮次 | 实际事件 | 可收益事件 | 排除事件 | 可收益实际伤害 | 最终专注 | 独立期望 | 最大误差 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 115 | 83 | 32 | 1300.0000 | 28.47713526 | 28.47713526 | 0 |
| 2 | 127 | 87 | 40 | 1334.5919 | 31.69377348 | 31.69377348 | 0 |
| 3 | 106 | 81 | 25 | 1300.0000 | 29.12635200 | 29.12635200 | 0 |

合计348笔实际事件、251笔可收益事件、97笔排除事件，可收益实际伤害3934.5919。三轮均0范围错配，0数值误差，0重复事件，0负余额或非有限数值。覆盖普攻、盾击、Firebolt、Pyroblast、RapidShot、爆裂箭和触发碎片。

每笔收益按实际容量截断；满槽时仅在测试副本重置专注继续核对，避免满槽掩盖后续漏计。故“全部实际伤害×0.1”不等于最后余额，也不是游戏中的自动重置行为。

## 生命周期与事务检查

- 活动场景每单位只有一个专注伤害监听，专注池只有一个 node_added 全局连接。
- 每轮战斗结束及10轮额外加载后，共13次卸载检查：旧场景、旧专注池、旧单位 WeakRef 均失效；残留专注连接0。
- 在新场景向敌人重放旧场景事件：没有改变新专注值。
- 2200笔零额预留/提交/归还/终态清理：重复提交和退款拒绝，余额不漂移，资源事务记录归零；2200笔账本登记/成功或失败/关闭/清理后，记录与成功计数均归零。
- 非零费用与前序失败后释放多余预留，另外由既有 ComboCostLedgerTest 与 SquadFocusComponentTest 的真实事务断言重新验证。
- 预热后13次清理，场景树节点数始终46（常驻 HUD、MCP 服务及审计空世界）；新增路径0，孤儿节点0，资源对象数始终105。普通对象数1762—1768小幅波动，未随加载次数逐轮增长。

首次短探针发现节点数45→46，逐节点追踪确认是常驻 HUD 首次创建的 `DashSeparator1`。该视觉节点不是旧玩家或战斗场景残留，之后固定保留1个。因此正式压测先预热一次 UI，不把一次性初始化当作持续泄漏。

静态内存从98520999到98656467字节，约增加0.13 MiB。测试报告本身累计保存采样数据，且引擎有缓存/分配器波动；本次没有足够证据将这点增长归为泄漏，也不宣称静态内存完全不增长。节点、弱引用、资源数和专注连接是本次可直接验证的清理证据；没有进行长时间驻留或GPU显存检测。

卸载按照既有正式流程先调用 EncounterController.begin_scene_unload，再切换场景。最初直接切场景产生的“敌人未死亡就离树”警告来自测试未走预卸载接口；查明后修正审计流程，未修改或关闭游戏中的异常离树监测。最终完整压测退出码0，运行输出无 ERROR、无 WARNING。

## 复测与可重复入口

新增工具：`Tools/CombatSimulation/RunSquadFocusSceneAudit.gd`，不装配到游戏，不增加 Inspector 参数或 Autoload。默认3轮20秒战斗、10轮额外重载。Godot MCP 可运行：

```text
script_path: res://Tools/CombatSimulation/RunSquadFocusSceneAudit.gd
args: --cycles=3 --seconds=20 --reloads=10
timeout_sec: 120
```

最终完整压测耗时64.99秒，输出 `SquadFocusSceneAudit: PASS`。该入口使用原有场景与自动攻击驱动，每次结束退出独立测试进程。

复测10个入口全部退出码0：
- `UnitSystem/Tests/CombatDamageContractTest.gd`
- `UnitSystem/Tests/DamageAttributionIntegrationTest.gd`
- `SkillSystem/05-Tests/SkillDamageProvenanceTest.gd`
- `UnitSystem/Tests/MeleeSkillDamageProvenanceTest.gd`
- `UnitSystem/Tests/SquadFocusComponentTest.gd`
- `UnitSystem/Tests/ComboCostLedgerTest.gd`
- `UnitSystem/Tests/SquadFocusSceneBindingTest.gd`
- `UnitSystem/Tests/SquadFocusDebugDisplayTest.gd`
- `GameFlow/Tests/GameRunResultFlowTest.gd`
- `GameFlow/Tests/CombatHUDBindingIntegrationTest.gd`

场景绑定测试中的无/多玩家警告，以及 HUD 多玩家警告均为主动验证失败关闭的预期分支。编辑器日志还存在原有 WorldHealthBar 整数除法及 Pyroblast 特效参数同名警告，本次未修改这些不相关实现；MCP 临时检查节点也会产生未使用内部变量警告，不能与压测进程的新运行错误混为一谈。

本次验证没有进入阶段二、没有提交或推送。新工具保存为测试资产，后续可在技能或场景改动后复跑。
