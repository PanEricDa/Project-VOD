# Caster终结技组装与A/B演出：实施验证
日期：2026-10-19。实施计划：2026-10-18-caster-finisher-execution-plan.md。

## 已交付
- Caster正式Finisher槽装配焰星连轰；同一SkillBase与Effects，不建立独立伤害系统。
- 5颗弧线火球、0.12秒发射间隔、0.5秒飞行、5米散布、3米爆炸。
- 复用用户已验收动作与本轮前已验收的独立Cast/Release/Flight/Impact资产。
- A首发恢复；B首发切战斗区域、保持5%世界至交付及主要爆炸完成，再恢复并返程。
- 真实连携结算达分→终结窗口→选择Caster→执行，不是只输出log。
- ComparisonPreview用于A/B重复试放和真暂停，普通AI被冻结以隔离比较；SelectionPreview保留完整AI战斗入口。

配置与复用详见 SkillSystem/04-Docs/FlameBarrageFinisherConfigurationGuide.md。

## 最终运行证据
151个extends SceneTree测试全部重新运行，150通过；唯一失败为既有CameraFollowControllerTest：Scenes/TestCombatRoom.tscn导航网格未烘焙（polygon_count=0）。此项在实施前即已失败，本轮不擅自烘焙或改变地形。
151份最终日志无ObjectDB泄漏、无resources still in use。额外RefCounted测试RangedAttackPipelineTest.collect_failures()返回空数组。git diff --check通过。

重要专项：
- SkillExecutionClockTest、GroundArcDeliveryTest、FinisherSkillLifecycleTest。
- FinisherCinematicExecutionTest、FlameBarrageAssemblyTest、FlameBarrageRuntimeTest。
- FinisherExecutionReentrancyTest、FinisherExecutionEdgeTest、FinisherSourceConfigurationTest。
- 普通连射、炎爆、触发箭、普通/连携施法、镜头、时间持有和既有选择窗口回归通过。

Godot MCP真实可视运行：
- Comparison A首发后free_combat，Engine.time_scale=1，镜头不再占用；可以看到火球继续飞行。
- Comparison B轰炸时Engine.time_scale=0.05，五颗已发，落地/主爆炸待办继续更新；截图确认普通战斗角度转向目标区域，飞行和爆炸存在。
- 用既有PauseCoordinator在前摇/轰炸中真暂停取景，恢复后可继续；非零待办未提前释放B。
- 完整战斗SelectionPreview直接走实际执行入口：5发、5落地、主视觉待办0、completed、倍率恢复1。
- 真实资格窗口由RuntimeTest用实际连携伤害产生，3号Caster执行完整5发；未装备的其余角色不可选择。
- 调试器剩余临时gdscript://下_mcp_error未使用警告为MCP运行脚本辅助器自身；本次生产脚本枚举警告已消除。

## 独立审查与修复
只进行一次独立只读审查，不由审查者修改代码。9项重要问题全部用定向测试复现并修复：
1. 输入持有申请中的同步取消：局部接收token，核对generation后交接，过期归还。
2. 旧执行取消回调启动新执行：每个可重入调用后校验原generation。
3. 首发事实先于会话登记：Runner先登记、启动失败回滚，首发同步硬中断能停未发。
4. 多发动作deadline：由动画/前摇/发射数量与间隔推导预算，不额外暴露策划参数。
5. 最后发出后source删除：落地点再次验证并显式终止，不访问已释放对象。
6. 同步地面命中：物理队列结算；SkillBase将非物理来源释放排入下一物理帧，直接Runner入口拒绝非物理地形采样。
7. 动作驱动删除：恢复存活AnimationPlayer的处理模式，同步移除本驱动动画库。
8. 入树前视觉销毁：无效弱引用直接结清；不必等待watchdog。覆盖free/stop路径。
9. 长主视觉：入树时按其get_remaining_seconds一次性扩充预算，保留停滞故障超时。

另补Host取消回调开始新动作的身份保护（RED→GREEN）。
审查原标Minor的重复配置提升为重要：违反本项目人类可管理原则。清除Caster及预览中的终结技能静态覆盖，新增源配置契约测试。正式Delivery静态共享、会话复制；不需在多个文件同步发射参数。无需延期的小项。

## 实施裁决与代价
- 采用用户已验收的0.333333释放、0.433333完成标记、0.95片长，替代设计早期0.65/1.35参考；不修改原库。若需改变节奏，编辑正式独立Action资源。
- 原计划仅覆盖选择窗口，因此另写本次执行计划承接已确认设计，不增加新玩法；代价为多一份有明确职责的实施记录。
- TestCombatRoom本身尚无整条连携链路；沿既有完整SelectionPreview装配，不复制整条链路进基础房间。若以后改变正式关卡入口，只需迁移装配引用。
- 比较场景嵌套Battle，沿原Host.configure_owner显式统一作用域；仅限比较预览，不扩展正式技能身份规则。
- 未审查的既有专注/评分/选择基线和其他脏改动保持原状；代价为原有缺陷不在本次修复范围。
- 用户动画库/工作台通过开始与结束SHA256对照确认未变；没有用累计Git脏差异归责。
- 镜头观感由父任务实际可视运行验证；仍需用户最终主观体验A/B。
- 正式外部资源UID有效；真实Inspector Quick Load的SkillCinematicProfile与CameraEffectProfile过滤均能显示新资源；没有只依据文本头推断。
- 其他伙伴终结技、向基础TestCombatRoom补整套系统不在本次范围；当前只有Caster可选，符合首个技能验证目标。

## 原用户文件保护
MagicGlobeAnimationLibrary.res SHA256：
12600DB9B2AC020213FA0B8767ACC397A32344B01E5D2581BD15A1E74A63B613
HeroAnimationWorkbench.tscn SHA256：
B92F93E678D66056ED6CCE81C52B57B92CAF8E310E9880D8C7688A26D95AB06B
均与本轮开始一致。未修改TestScene单位；未自动提交或推送Git。
