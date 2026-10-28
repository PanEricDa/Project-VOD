# 玩家技能阶段五验收记录

日期：2026-10-22。状态：用户批准后已完成三批实现与定向验证；全量复跑及一次独立review已完成，等待用户体验验收。未Git提交/推送。

## 1. 本次交付

- UnitBase内置被动位移请求、token、弱来源、碰撞例外及生命周期；Inspector仅新增Forced Movement / Forced Movement Enabled，默认true，关闭立即结束并回收，重新开启不恢复。
- PlayerBase与AIUnitBase在原物理循环消费同一delta，保持唯一move_and_slide。外力覆盖水平意图但不取消已开始技能、不退还冲刺次数；暂停/5%/受击锁保留原规则。
- PullTargetSkillEffect直接向UnitBase请求，不再按AI类型或子节点名找接收器。临时忽略单位身体、保留墙地/重力，完成后正常AI散开。
- Hero源显式挂已有Gather/ThreatMark，Regular Skills引用两个原节点；已有Input/Controller各1，无隐藏装配。正式源CD10/12秒。
- CombatRoom仅新增只读PlayerSkillBar并绑定本地Hero/PlayerSkillController，Panel偏移350,-420,574,-304；没有测试Harness/范围圈/靶子。
- PlayerSkillsTest继承源装配，清掉局部重复技能/输入/控制器，仅保留CD2秒；三模式、原位置/地形、Q示意圈保留，Unsupported根开关false。

## 2. 操作及配置入口

F5：Scenes/CombatRoom.tscn。Q聚拢、E限时仇恨；原WASD/F/鼠标中键和1—4连携/终结均不变。

F6：Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn。默认Training，Next依次Threat Combat、Squad Combat；Reset重建，测试CD2秒。Unsupported只免疫被动位移，E仍生效。

技能内容：SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn、Player_ThreatMark/ThreatMarkSkill.tscn。
范围唯一来自Delivery；Q落盘/时长在PullTargetSkillEffect，E仇恨/时长在ThreatChangeSkillEffect。单位外力许可在单位根，不要求挂组件。UI仅配置Skill Source，不复制业务数值。

## 3. 保护与原参数核对

原Q/E文件SHA256与本阶段开始一致：
- Q：113be90a53fe27bcec2f1d81902a2daa249f2b12b75d560dc997c3a0c2494699
- E：376ad22a2a34b8547b90956c8379accf87110eef1fc547951d0eabc261f14892

Q当前半径3.5m/圆心前移3m，落盘前移1.5m/半径0.6m，位移0.12秒，施法0.2秒；
E半径5m、2000临时仇恨、8战斗秒、施法0.15秒。正式CD10/12，测试局部2/2。
CombatRoom初始专注100、获取难度2、评分难度2、H0=15、D0=1000.01均保留。
Hero武器/生命/攻击/防御/原动作参数保留；未改伙伴、敌人、相机、动画、专注或评分数据。
Scenes/TestScene.tscn执行前即不存在，执行后仍不存在，未创建或修改其单位。
修改/新增场景原生保存，资源UID检查有效；未新增正式外部.tres/.res。

## 4. RED→GREEN与真实流程证据

A：UnitForcedMovementTest缺UnitBase接口的预定行为断言RED；迁移后该测试、Pull、PlayerSkillTestScene、PlayerSkillCombinedFlow、GatherPresentation、ThreatMarkPresentation共6项PASS/退出0。

保留原真实物理覆盖：3m/0.35秒、忽略Y、墙不穿、默认碰撞/忽略单位、动态增删/已有例外、5%/暂停/受击锁、替换与旧token、死亡/退树。新增根开关关闭重入拒绝及重开不续旧请求、Player真实技能期间外力不双重移动、禁输入仍可受外力。

B：AssemblyTest先因正式槽/适配器/HUD缺失RED；装配后Assembly、Control、ActionAnimation、Bar、TestScene、CombinedFlow、CombatRoomAssembly共7项PASS/退出0。不同Hero技能/CD独立，user临时场景原生保存重载槽引用有效，实际Q/E各一次输入只一次受理/释放。

C：扩展原CombatRoomFinisherFlowTest，不伪造伤害/专注/资格：
- 隔离运行夹具主动输出，实际E创建状态/贡献，实际Q至少2敌人进入释放快照圆盘，damage=0/focus=0/评分未开窗。
- 恢复敌人感知需物理服务器同步4帧，实际仇恨选择玩家；恢复四伙伴真实普通伤害获取专注。
- 自然等待真实10/12秒CD和共享CD结束后才测输入隔离；不是以CD拒绝冒充演出阻断。
- 实际3连携生成脚下银白闪光、真实伤害达分；选择及B各阶段Q/E真实输入与直接请求均拒绝、不消耗CD。
- 实际3终结：enter_closeup/windup/exit_closeup/release_pending/bombardment，5发5落地/主要特效0，最终速度1/非暂停/动作释放。
- 结束后两槽ready、输入恢复；新E确有状态后使玩家死亡，状态及临时贡献撤销；卸载重建无旧CD/输入令牌，HUD指向新Hero。
此为Task1/2完成后的集成验证，没有人为破坏生产代码制造RED。

完整回归首次出现UnitDeathLifecycleTest旧夹具前提不再成立：活跃普攻时要求技能同时启动，正式共享动作适配正确拒绝。已保留原普攻死亡断言并分开新增复活空闲后的真实技能死亡清理；该项RED→GREEN，不改变生产规则。

## 5. 原生F5/F6与界面

- F6 Training：Q受理/开始/释放/完成各1，affected2；E同样各1、affected5，标记及临时仇恨约2000；无接收器节点，Unsupported开关false。
- F6 Threat：1伙伴，E使5敌人按正常仇恨选择Hero；8秒后状态/贡献归零，可观察Guardian按普通仇恨接管部分目标。
- F6 Squad：4伙伴，E实际生效，Q affected2；实际连携达分。
- F5：正式源CD10/12；实际E给3敌人各2000贡献并选Hero，普通敌人仍正常移动/攻击。正式导航polygon0既有问题未改；本次近距离追击/战斗实际可运行，未宣称验证任意地图路径。
- F5真实B终结实机记录5发5落地/主要特效0、结束速度1/非暂停；另一次运行夹具仅提高耐久/减敌攻击以免观察时死亡，实际Q三目标arrived，终点约(3.067,-1.076)、(3.038,-1.332)、(2.964,-1.584)，均在中心(3.2,-1.5)半径0.6盘内。
- 截图核对2560×1440及1280×720逻辑视口，新增Q/E位于生命栏右上、不叠伙伴栏；低分辨率下原生命栏/原连携栏自身重叠不纳入本次修复。嵌入窗口像素截图仍2560×1440，逻辑viewport已确认1280×720。
- 新鲜原生运行Debugger errors=0，结束已停游戏；运行夹具修改未保存。

截图与原始测试输出在本阶段独立本地工作目录.godot/player_skills_stage5/，不作为正式美术/资源交付。

## 6. 实际文件范围

生产修改：
- UnitSystem/Base/00_UnitBase.gd、AIUnitBase.gd
- UnitSystem/Player/PlayerBase.gd、Hero/Hero.tscn
- SkillSystem/03-Extensions/PullTargetSkillEffect.gd
- Scenes/CombatRoom.tscn、Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn

测试新增/迁移：
- UnitSystem/Tests/UnitForcedMovementTest.gd及原生.gd.uid（迁移旧测试）
- UnitSystem/Tests/PlayerSkillsCombatRoomAssemblyTest.gd及原生.gd.uid（新增）
测试修改：PullTargetSkillEffectTest、PlayerSkillControlTest、PlayerSkillTestSceneTest、PlayerSkillCombinedFlowTest、CombatRoomFinisherFlowTest、UnitDeathLifecycleTest。

移除精确旧文件：ForcedMovementComponent.gd/.gd.uid/.tscn，ForcedMovementComponentTest.gd/.gd.uid。
活动文本与ResourceLoader依赖检查后才删除；迁移前原件保留本阶段baseline，可恢复。测试中旧节点名只用于断言其不存在，不构成运行依赖。历史阶段文档保留旧名。

同步当前使用指南、CombatRoom/PlayerSkills配置指南、总体设计最终入口、路线与本阶段设计/计划状态。

## 7. 执行裁决与边界

1. 既有dirty checkout已获批准且不允许自动Git：用Godot原生快照/ledger代替技能默认工作树/提交辅助器；成本是本地scratch需保留至获授权版本提交。
2. 迁名测试没有外部UID消费者，使用原生生成新测试UID；成本是历史测试UID不保留，活动引用使用新路径。
3. 全量发现旧死亡夹具的同步动作假设，改成忙碌拒绝与两类独立死亡清理；成本是多一个运行时生命周期子用例，不放宽生产动作互斥。

所有编辑优先Godot MCP Pro；脚本用专用编辑工具，场景用编辑器原生保存，文档/快照用MCP原生FileAccess，精确删除用原生DirAccess。没有回退直接文件编辑。测试日志由测试命令生成。
未碰插件、导航烘焙、旧Firebolt距离/用户技能平衡、阶段四P3施法灰显、旧HUD低分辨率布局；这些不因迁移自动修复。

## 8. 最终回归与独立review

全量SceneTree回归182项：180通过，2项与执行前相同的既有失败：
- UnitSystem/Tests/CameraFollowControllerTest.gd：room navigation mesh is baked，既有未烘焙。
- SkillSystem/05-Tests/SingleSceneFireboltTest.gd：旧断言cast range is 6m，用户源当前5m。

逐项检查退出码、SCRIPT ERROR/ERROR、ObjectDB/资源泄漏及invalid UID；除两项预期旧断言的ERROR外，无新增报错、泄漏或无效UID。
原始逐项结果：.godot/player_skills_stage5/full-suite-final.json。
全仓git diff --check仍报告既有插件runtime_commands.gd末尾空行；本阶段未修改插件，不将其计作本次干净结果。
本阶段差异格式检查无问题（STAGE5_WHITESPACE_MESSAGES=0）；新鲜编辑器错误0、未保存场景0。当前正式场景已打开，原生游戏已停止。

独立只读review：Critical0、Important0、Minor1，Approve with nits。按本阶段快照而非HEAD全部dirty内容审查，五项Review Focus未发现生产阻断项；审查本身未复跑引擎。

### 保留的轻微项

P3：UnitForcedMovementTest玩家用例未完整建立“活动攻击推进/活动冲刺”的前提。Q启动已清掉原推进，且未实际启动冲刺，故终态断言不能证明这两种活动状态被外力清理。生产清理分支存在且未发现对应错误；实际Player单一输出、持续输入、不取消技能、禁输入仍可受外力已通过。后续应补独立的活动推进/冲刺前提与次数不退还断言；本次按轻微项记录，不扩入修复。不能据本记录宣称这两个前提已动态覆盖。

### 审查未认证范围及执行裁决

- 审查按约定只读、不运行引擎；物理/原生保存/UID/二进制依赖采用主会话实测证据，不冒充审查者重验。本轮没有新正式.tres/.res，强类型Quick Load新资源验收不适用。代价：没有第二次独立运行审计。
- 任意地图导航、旧低分辨率布局与平衡维持排除范围。代价：这些既有限制仍在。
- “正式房间终结中途、同时活动外力时卸载”的完整组合未直接实测，只有各自退出清理证据，不将其等同组合覆盖。代价：此边界交互没有直接回归保护，后续可补测，不额外加玩法规则。

原始审查及裁决另保留.godot/player_skills_stage5/final-review.md；本阶段snapshot/ledger不清理，避免尚未Git提交时丢失迁移前副本。当前checkout保留，无提交/推送/合并/PR。
