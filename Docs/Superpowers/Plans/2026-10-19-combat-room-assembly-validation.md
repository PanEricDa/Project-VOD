# 完整战斗房间组装验收

日期：2026-10-19。承接已确认的Caster终结技执行计划Task 4，将已有能力接入正式启动入口，不新增战斗机制。

## 交付

- 新增 `Scenes/CombatRoom.tscn`：继承TestCombatRoom，只装入七个已有系统组件，静态连接原四伙伴、专注、评分、暂停及相机。由Godot编辑器原生创建继承场景并保存，场景UID为`uid://co2m3r48287tf`。
- 项目启动场景改为CombatRoom；旧基础房间、阶段预览不重复装配系统。
- `UnitSystem/Components/UI/SquadChainCommandDisplay.tscn`仅把阶段二占位标题改为通用连携指令标题，布局和逻辑不变。
- 新增两个测试：CombatRoomAssemblyTest、CombatRoomFinisherFlowTest。
- 新增 `SkillSystem/04-Docs/CombatRoomAssemblyGuide.md`，更新原FlameBarrageFinisherConfigurationGuide运行入口。

没有新增运行脚本，没有改动伤害、专注公式、技能费用、动作动画或单位摆放，没有修改TestScene。当前正式流程B，历史A/B比较工具保留，不成为正式游戏入口。

## 装配决策

1. 使用继承式CombatRoom入口而不将系统添加到TestCombatRoom：旧阶段预览都继承后者，直接修改会产生重复所有者及破坏隔离验证。代价为一个明确的新入口场景；若不合适可切回启动场景并迁移七个已有实例，不损失原地图与单位。
2. 专注难度沿用基础房间10，初始0；评分沿用最新选择预览难度2、H0=15、D0=1500.01，间隔2.5秒。组装不承担新的平衡改动；若体验需变动，只调整原Inspector字段，不改接口代码。

## 测试方法与边界

先写入口装配契约，观察“complete playable CombatRoom exists”失败，再原生组装保存并通过。画面复查发现旧阶段二标题，新增断言先失败，随后只修改Label文本并通过。

端到端测试保持伙伴普通AI工作，实际伤害获得专注，发送InputMap事件3，真实连携伤害形成评分并结算达分，再发送3选择Caster。测试实例提高敌人耐久、安排近距离站位并降低专注/评分难度、缩短伤害间隔，以快速验证连接，不作正式数值平衡结论；不伪造伤害或资格信号，不保存夹具调整。

手工SceneTree测试在add_child后才赋current_scene，与引擎正式加载不同，故测试沿现有Host.configure_owner显式指定世界。真正F5启动单独核查：技能Host交付父节点、指令作用域、PauseCoordinator作用域均为CombatRoom，普通AI开启、初始专注0、获取难度10、演出模式B。

真实输出：enter_closeup → windup → exit_closeup → release_pending → bombardment → returning → idle；发射5、落地5、主要特效待办0、reason=completed。选择输入没有穿透成第二次连携，结束及卸载后time_scale=1且无树暂停。

首次完整回归：154项中153通过；唯一失败CameraFollowControllerTest / room navigation mesh is baked，是原有基础房间导航网格未烘焙。泄漏日志0。标题修正后另做最终完整回归，结果见下节。

## 内容保护与审查

全部写入通过Godot MCP Pro；场景使用编辑器原生装配与保存，项目设置通过专用工具修改。没有直接覆盖编辑器中未保存资源，没有提交或推送Git。

原动画库、Workbench和正式Action哈希与上一轮一致：

- MagicGlobeAnimationLibrary.res：7492EA621727A5F39B8E525CE6523F23B3DB92EE9214D093882B317CF1BEDBB6。
- HeroAnimationWorkbench.tscn：B92F93E678D66056ED6CCE81C52B57B92CAF8E310E9880D8C7688A26D95AB06B。
- FlameBarrageAction.tres：5CECCECF07087749EF1B8B50FC75C69D3343B55DF616C084AE4B949ED1E9D92C。

本轮为实现者自审，未进行独立代理审查；审查覆盖同域引用、重复所有者、预览脚本隔离、按键穿透、资源/时间清理、Inspector可见性与文件范围。没有额外待处理轻微审查项；旧导航问题单列，不在本轮修改地形。

## 最终回归

标题修正后最终完整回归：154项，153通过、1项既有失败；短时限终结选择压力测试单独运行通过。唯一失败仍为CameraFollowControllerTest的room navigation mesh is baked，未新增失败。ObjectDB/资源泄漏日志0，git diff --check通过。两个新增组装/端到端测试均通过。

Godot原生读取确认：新入口继承TestCombatRoom、保存8个节点条目（根节点+七个组件）、UID有效、当前打开CombatRoom且无未保存场景。运行测试已停止。
