# 玩家技能阶段四验证记录

日期：2026-10-22。当前实现范围：两槽技能栏、专用测试场景三模式、完整队伍联合流程和输入/生命周期边界。
用户已确认实施；未进入阶段五，未提交Git或上传GitHub。独立review结果在本文末补记。

## 1. 交付

新增生产文件：
- UnitSystem/Components/UI/PlayerSkillBar.gd
- UnitSystem/Components/UI/PlayerSkillBar.tscn

新增测试：
- UnitSystem/Tests/PlayerSkillBarTest.gd
- UnitSystem/Tests/PlayerSkillCombinedFlowTest.gd

修改既有：
- PlayerSkillController：只读槽快照，不改既有request_slot合法性/拒绝分类。
- PlayerSkillsTest.tscn / Harness：显式四伙伴及既有Squad链路；子节点进树前模式隔离。
- PlayerSkillTestSceneTest：HUD唯一来源与默认训练模式隔离断言。
- PlayerBase / SquadChainCommandController：终结系统既有输入持有向通用玩家许可传递。
- 本阶段计划、路线、配置指南；Spec仅更新阶段状态。

未创建新技能、Delivery、效果类型、外部.tres/.res、动画或特效资产。
所有编辑使用Godot MCP Pro；场景通过原生PackedScene/ResourceSaver及编辑器保存。
原工作区大量未提交改动保留；没有重置、分支切换或覆盖用户未保存场景。

## 2. RED → GREEN证据

### Task1：只读槽状态与HUD

初次PlayerSkillBarTest退出1：
- Controller must expose readonly slot status
- two-slot HUD asset must exist

新增接口及HUD后退出0，真实测试包括：
- 查询/重复绑定不触发受理、不修改动作或冷却，返回字典独立。
- 名称/图标读取当前SkillBase；空图标占位，InputMap临时改R后显示R并恢复。
- 真实Q动作释放启动2秒CD；读数与SkillBase一致，遮罩使用同一剩余量。
- 同帧动作忙、暂停、基础输入禁止、Host禁用、空槽、死亡均不可误显可输入。
- 共享CD和外部CD锁不伪装成技能自身CD。
- UI解绑不取消已经开始的E，所有Control不拦鼠标。

同批PlayerSkillControlTest、PlayerSkillActionAnimationTest、PlayerSkillTestSceneTest均退出0/PASS。
新场景UID：uid://dhgiqgsr4lo5u；原生保存后get_resource_uid有效、ResourceUID.has_id为true且映射到正确路径。
首次资产索引前测试出现过临时UID回退提示；完成索引后最终全量无新增UID错误。

### Task2：真实联合模式

初次PlayerSkillCombinedFlowTest退出1：
- mode2缺少四伙伴
- 非Squad模式/完整Squad装配契约未满足

装配后退出0/PASS：
- 三模式实际伙伴数0/1/4，只有Squad保留队伍/暂停/终结组件。
- 真实E提供临时状态与大于1900的玩家仇恨。
- 真实Q使开放目标抵达释放快照的聚拢盘，保留不支持位移靶。
- 暂时隔离伙伴输出时Q/E没有伤害事件、没有专注。
- 恢复伙伴真实AI后普通伤害从0获取专注，真实InputMap 3触发一次连携受理/释放。
- 真实连携伤害达分后打开终结窗口；不伪造伤害或资格通知。

夹具只在运行时提高怪物耐久、降伤害/移动和降低获取/评分门槛，以可靠验证接线。
正式Q/E参数、怪物源配置和正式关卡评分参数均不改变。

### Task3：真实输入漏口与修正

补真实终结边界测试，观察RED：
- real finisher selection: input must not accept Q/E
- windup: input must not accept Q/E
- bombardment: input must not accept Q/E
- Command输入持有未传到PlayerBase，多来源输入许可断言失败。

原因：现有终结选择/执行持有只阻断Squad命令；Q/E读取PlayerBase通用许可，两者未连通。
修正：PlayerBase增加通用有所有者的输入持有；Command既有token同步持有/释放玩家许可，
不更改set_player_input_enabled基础值，不在技能里特判终结，不读time_scale猜测输入权限。

GREEN：
- 显式暂停、基础输入禁止、真实终结窗口、enter_closeup/windup/exit_closeup/bombardment均不受理Q/E、不新释放、不消耗CD。
- 多持有者互不解锁、基础false被保留、owner正常退树自动撤回。
- 真实B终结遍历全部镜头门；launched=5、landed=5、main_effects_pending=0、reason=completed。
- 演出恢复paused=false/time_scale=1，Q/E重新受理。
- 玩家正常死亡撤销E状态/临时仇恨；一次场景重建是新身份、计数0、冷却就绪。
- 原SquadFinisherSelectionControllerTest（含其既有压力用例）仍PASS；本阶段没有新增压力测试。

## 3. 完整自动回归

枚举所有非Archive/addons、extends SceneTree的*Test.gd，最多4个进程并行。
最终本轮：**181项，179通过，2项既有失败；没有新增失败。**

既有失败：
1. UnitSystem/Tests/CameraFollowControllerTest.gd：正式房间navigation mesh未烘焙。
2. SkillSystem/05-Tests/SingleSceneFireboltTest.gd：旧断言6m，与用户当前5m配置不符。

均未为测试绿灯调整正式Gameplay或MCP插件。
全量包含计划列出的玩家输入/动作、位移、Pull、临时仇恨、Q/E表现及CombatRoom真实终结流程；
通过项未检测到SCRIPT ERROR、ObjectDB泄漏、ERROR或无效UID。

## 4. 原生运行与画面

Godot编辑器运行PlayerSkillsTest，使用真实InputMap输入：
- E受理/开始/释放/完成各1次，影响4个目标；临时仇恨约1997，4个目标按原逻辑选Hero。
- 同次过早请求Q被共享CD正常拒绝；HUD显示灰/剩余冷却，没有隐藏队列。
- 重开后Q受理/开始/释放/完成各1次，影响2个目标，HUD显示真实剩余0.2秒。
- 实际输入3产生1次连击、47.0588实际伤害、14.5108分；2.5秒无新伤害正常闭窗，未达分不弹终结。
- 原生Debugger检查0错误；普通结算后paused=false、time_scale=1。

检查2560×1440及1280×720逻辑视口：
- 新Q/E与既有生命列表/中央技能栏分开，空图标、技能名、CD可辨识。
- 原有五人血条与中央伙伴栏在1280布局自身有重叠，非本阶段引入；没有借机重做正式HUD。
- 测试长调试面板改为左上紧凑布局，Squad收起长读数，避免额外遮挡生命列表。
- Q范围圈保留，E示意圈仍关闭，已验收特效未重做。
- 首次MCP原生检查因另一个headless编辑器导入移除会话autoload而超时；使用工具自带reload_plugin恢复连接，未修改插件代码；之后原生检查正常。

## 5. 实施判断及边界

- 当前目录不提交版本，因此review用本阶段修改前快照而非HEAD全量diff；快照保留在.git忽略的.godot/player_skills_stage4，避免误审既有改动。代价是review需逐文件比较；不自动删快照或提交。
- 终结输入持有传到PlayerBase通用许可，覆盖新技能/移动/攻击/锁定，不只新增Q/E特判；代价是调用Command.acquire_input_block的其他未来系统也须接受同样的新战斗输入阻断语义，目前生产调用方只有终结选择/执行。
- 本测试Q/E用局部原生Control偏移放到生命列表右上；默认可复用HUD仍左下。代价仅为布局调整，不增加导出配置。
- 低分辨率原有血条/伙伴栏的响应式布局、阶段五正式装配、UnitBase被动位移内置、热装卸、Git操作均不在本阶段继续实施。

## 6. 独立review

只读独立review（Boyle）完成：无Critical、无Important，Approve with nits。已有文件逐个对比阶段四修改前快照，新增文件完整检查；review者未运行测试/写入。

Minor / P3暂缓：已开始Q/E动作时，若暂停或禁用新输入，Controller先返回blocked，使HUD暂时失去casting/绿边（短确认结束后）；实际已开始动作与费用不受影响。按轻微显示问题记录，不在本轮追加修正。后续可将动作阶段与新输入许可独立显示，并补组合状态测试。

审查范围判断：
- can_request不承诺目标/Condition/费用最终成功：明确契约，保留；误解代价是UI调用者需读此说明。
- 1280原血条/伙伴栏重叠：原生已观察，保留原正式布局，本轮新增Q/E未叠入；代价是既有低分辨率可读性仍需后续处理。
- 阶段五与UnitBase迁移：遵用户分阶段验收，未实施；代价是正式主场景尚不能直接使用玩家Q/E。
- 热插拔/动态换槽/高频重建：明确范围外，当前只保留接口；代价是未来装卸系统需另做验证。
- 两项既有失败：保留并报告，不为绿灯改Gameplay；代价是全量仍有2红。
- 其他未提交改动：不以HEAD全量diff归责，保留原工作；代价是本次review不保证用户既有改动无缺陷。

阶段四实现与验证已交付，仍等待用户实际体验验收；不会据此自动执行阶段五或Git操作。
