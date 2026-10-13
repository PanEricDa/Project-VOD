# 队伍专注基础（爆发连携阶段一）

这是伤害来源、队伍资源和费用事务的基础，不是已完成的连携操作系统。本阶段不增加正式快捷键、连携窗口、评分、终结演出，也不改角色技能数值。

## 直接验证

打开并运行 `res://Scenes/Previews/SquadFocusFoundationPreview.tscn`。

- 点击三次“普通伤害 100”：专注总量增加到 30。
- 点击“连携伤害 100”或“终结伤害 100”：仍然扣敌人生命，但不增加专注。
- 点击“预留 20”：总量 30、预留 20、可用 10。
- 点击“提交 15”：总量 15、预留 0、可用 15；未使用的 5 点承诺解除。
- 再造成一次普通伤害后，预留并归还：总量保持 25，归还只解除预留，不额外加钱。

按钮只服务开发验证，不能据此判断正式连携玩法已经实现。预览目标生命不足时会先恢复生命，避免目标死亡影响反复测试。

## 人工装配

1. 将 `SquadFocusComponent.tscn` 实例放到战斗世界根节点下，不放到角色下。
2. 默认自动绑定其父节点范围内唯一的 `Player` 和同队 `Ally`；只观察这个范围内的单位，支持 dummy 及动态加入的单位。
3. 如需显示，将 `res://UnitSystem/Components/UI/SquadFocusDebugDisplay.tscn` 放到场景中，在根节点的 `Focus Source` 选择专注组件，并开启 `Debug Enabled`。
4. 多玩家或需要特别队伍的测试中，关闭自动绑定，由场景装配代码调用 `bind_scope(world, party)`；不能靠隐藏约定猜测主角。

`TestScene.tscn` 的装配由用户在编辑器中完成。本次实现没有改动正式关卡或现有单位实例。普通技能、敌人、箭矢和碎片都不需要新增专注配置。

## Inspector：仅六项

| 位置 | 配置 | 默认 | 含义 |
| --- | --- | --- | --- |
| 专注组件根节点 / Focus | Maximum Focus | 100 | 专注容量，有限正数；初始化或重置时生效 |
| 同上 | Initial Focus | 0 | 新会话初始专注，限制在容量内 |
| 同上 | Damage To Focus Ratio | 0.1 | 每点有效常规伤害的专注收益；0 关闭收益 |
| 专注组件根节点 / Assembly | Auto Bind Parent | 开启 | 自动发现唯一玩家和同队伙伴；关闭则由代码明确绑定 |
| 显示组件根节点 | Focus Source | 空 | 唯一资源来源的强类型节点引用，不复制计算参数 |
| 显示组件根节点 | Debug Enabled | 关闭 | 开发显示开关，不影响资源计算 |

100、0、0.1 和预览中的 20/15 都是开发验证数值，不是最终平衡。运行中的总量、预留、可用量、来源身份、轮次与账本均为内部状态，不作为可编辑参数。外观直接编辑显示场景的 Control 节点，不增加一套重复的外观脚本参数。

## 文件职责

| 位置 | 内容 | 使用者 |
| --- | --- | --- |
| `UnitSystem/Combat/CombatDamageContext.gd` | 伤害发生前的来源快照 | 技能与伤害入口自动传递 |
| `UnitSystem/Combat/CombatDamageEvent.gd` | 实际扣血后的事件、每消费者防重 | 专注及后续评分读取 |
| 本目录 `SquadFocusComponent.gd/.tscn` | 队伍资源、预留/提交/归还及场景监听 | 场景装配 |
| 本目录 `ComboCostLedger.gd` | 同轮次、同角色、同技能的重复费用 | 后续连携控制器调用，不挂节点 |
| `UnitSystem/Components/UI/SquadFocusDebugDisplay.gd/.tscn` | 只读数值与专注条 | 开发观察 |
| `Scenes/Previews/SquadFocusFoundationPreview.gd/.tscn` | 独立开发演示 | 直接运行 |

来源和事件为内存数据，不是需要策划维护的 `.tres`。不增加全局 Autoload，也不按每个技能另建伤害管理器。

## 内部接口约定

- 有效常规收益 = 实际扣血 × 来源收益倍率 × 换算比例。过量伤害只按实际扣血计算，治疗和友伤不增加资源。
- `NORMAL` 收益倍率为 1；`CHAIN`、`FINISHER`、`UNATTRIBUTED` 为 0。触发子技能继承根来源，不能自行恢复常规收益。
- 常规 Resolver 入口自动建立普通来源。直接调用 `UnitBase.apply_damage` 且没有来源上下文时仍可扣血，但视为未知来源，不猜测可回充。
- 每笔真实扣血有独立事件身份；同一次命中的多个伤害效果共享命中身份。消费者分别认领事件，互不干扰。
- 请求身份与轮次身份通过 `CombatDamageContext.allocate_id()` 生成进程内单调正整数，跨场景不复用。不是 Resource UID，也不是 Inspector 参数。
- 预留不扣总量；成功释放后提交最终费用；失败归还承诺。最终费用不能超过预留。终态保留到调用方结束回调生命周期后 `release_request`，避免重复扣费。
- 重复加价只计算实际成功的根请求。后续缓存请求预留前序可能成功的费用上界；前序失败时释放多余承诺。碎片不再次登记费用。
- 同伙伴按登记顺序串行确认释放。轮次关闭后不允许新登记，但已有请求仍可完成。轮次身份必须单调递增；关闭水位避免永久保留所有历史轮次。
- 解绑先断开全部监听，再清理资源会话；同世界同名单重复绑定不重置。新绑定拒绝在绑定前已经发布的旧事件，消费者身份不随重绑变化，不能通过重放旧伤害重复回充。角色离场仍保留已发出攻击的来源快照，专注池不依赖玩家存活。
- 显示读取资源会话的实际容量，不直接读取尚未重置的配置值；开发显示开关在运行中改变也即时生效。

## 无收益或没有显示时

先检查显示开关和 `Focus Source`，再看自动绑定是否发现唯一玩家、队伍是否非中立、来源是否同队、目标是否敌方、来源世界是否与绑定范围一致。自定义嵌套测试世界应显式传递世界来源；不能把其他场景的旧投射物算入当前资源池。重复绑定、单位重新进树和场景切换都不应重复订阅。

对应八项测试位于 `UnitSystem/Tests/` 和 `SkillSystem/05-Tests/SkillDamageProvenanceTest.gd`；详细验收见 `Docs/Superpowers/Plans/2026-10-12-burst-combo-stage-1-validation.md`。

用户在 TestCombatRoom 装配后，可通过 `Tools/CombatSimulation/RunSquadFocusSceneAudit.gd` 复跑正式场景后台验证。该工具只操作运行时副本，不保存正式场景；逐笔比较真实伤害与专注，并检查重载、旧事件隔离、监听解除、弱引用、孤儿节点及事务记录清理。默认3轮各20秒战斗与10轮额外重载；结果见 `Docs/Superpowers/Plans/2026-10-13-squad-focus-formal-scene-stability-validation.md`。
