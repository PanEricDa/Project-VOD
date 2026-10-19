# 终结选择窗口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 连携结束并结算达分后显示限时十字终结选择，战斗降至5%，选择仅输出日志，随后安全恢复。

**Architecture:** 复用评价源的finisher_qualified、原四伙伴槽及InputMap；新增流程控制器和纯显示组件。GamePauseCoordinator扩展慢速所有权，原指令控制器扩展输入阻断所有权；不接技能执行。

**Tech Stack:** Godot 4.7、GDScript、Control/CanvasLayer、InputMap、SceneTree行为测试、Godot MCP Pro。

**Spec:** [已确认设计](../Specs/2026-10-18-finisher-selection-window-design.md)。

状态：2026-10-18用户确认计划与当前会话执行；本切片已完成，最终141/141回归及50次/10世界压力验证通过。完整记录见同目录2026-10-18-finisher-selection-window-validation.md。未提交/推送，保持当前目录。

## Global Constraints

- 触发为“连携结束，结算达分后才弹出”；沿用finisher_qualified(result)，不使用历史last_result重新发资格。
- 默认selection_duration_seconds=3.0真实秒、selection_time_scale=0.05；固定左1、上2、右3、下4。
- 不修改评分、2.5秒伤害间隔、专注收益、技能/单位数值或当前已有场景覆盖值；执行前记录实际值，不套用历史摘要。
- 选择只日志/发选择事实，不调用request_finisher，不扣费、不取消动作、不造成伤害。
- 不创建正式终结技能、美术演出、Q/E系统、手柄新键位、新Autoload或另一套伤害体系。
- 所有创建/修改/保存优先Godot MCP Pro；失败或不支持才说明原因并直接编辑，禁止覆盖未核对的编辑器未保存缓冲区。
- 不向res://Scenes/TestScene.tscn添加或修改单位，不迁移正式关卡；预览继承现有阶段三场景。
- 中文说明紧邻全部导出、公开方法和信号；UI场景节点可编辑，内部时长和状态不暴露。
- 无新外部.tres/.res；新场景由Godot保存并验证UID有效，脚本.uid由Godot生成。
- 文档与测试的“已通过”必须依据真实输出及exit_code=0，不能只看到PASS文本。

## Review Focus

1. 5%慢速下，3秒窗口仍按真实时间结束；显式暂停不偷走剩余时间。
2. 持键跨开窗、同帧多键、临界超时和关闭输入不能误选或穿透为连携。
3. 原时间倍率非1、多个时间/输入持有者及组件卸载不能误恢复或遗留全局状态。
4. 达分事件重复、旧世界、重绑和同步回调删除组件时不能重复开窗/结束或泄漏。
5. 未装备正式终结仍能验证界面；空槽/重复伙伴/死亡动态失效不能被选中，布局在小窗口不裁切。

## 1. 文件与配置入口

### 新建：运行/预览

| 文件 | 职责 |
| --- | --- |
| UnitSystem/Components/Combat/Squad/SquadFinisherSelectionController.gd | 资格、真实时钟、输入、状态、日志与持有清理 |
| UnitSystem/Components/Combat/Squad/SquadFinisherSelectionController.tscn | 可直接装配的控制组件 |
| UnitSystem/Components/UI/SquadFinisherSelectionDisplay.gd | 只读显示、内部动画时间及源切换清理 |
| UnitSystem/Components/UI/SquadFinisherSelectionDisplay.tscn | 可编辑的十字布局、文本、样式、倒计时 |
| Scenes/Previews/SquadFinisherSelectionPreview.tscn | 继承SquadChainRoundPreview，不复制或重建单位 |

### 新建：测试

- GameFlow/Tests/GameTimeScaleOwnershipTest.gd
- UnitSystem/Tests/SquadFinisherSelectionControllerTest.gd
- UnitSystem/Tests/SquadFinisherSelectionInputDisplayTest.gd

新建合计：5个.gd（运行2、测试3）、3个.tscn、0个.tres；Godot自动生成的5个.gd.uid单独计。

### 修改

- GameFlow/Pause/GamePauseCoordinator.gd：新增慢速token；同步修改“不使用time_scale”的旧类说明，旧暂停接口语义保持。
- UnitSystem/Components/Combat/Squad/SquadChainCommandController.gd：新增独立输入阻断token；不重写请求/费用管线。
- SkillSystem/04-Docs/SquadChainCommandConfigurationGuide.md：新增本切片装配、接口测试限制与验证方法。
- 设计稿和本计划：仅维护确认/执行状态；验收后新建Docs/Superpowers/Plans/2026-10-18-finisher-selection-window-validation.md。

不改SkillBase、现有普通/连携技能、伙伴源场景和原阶段三预览。若发现必要变更超出清单，先停下说明。

### Inspector

控制组件仅4项：round_source:SquadChainRoundController、pause_source:GamePauseCoordinator、selection_duration_seconds:float=3.0、selection_time_scale:float=0.05。
显示仅1项：selection_source:SquadFinisherSelectionController。四伙伴自动沿round_source.command_source取得，不重复配置。

## 2. 固定接口与状态

### GamePauseCoordinator

- acquire_time_scale(owner:Node, scale:float, reason:StringName)->int：同绑定世界；有限0<scale<=1；失败0。
- release_time_scale(token:int)->void：幂等，只释放本token，不能解除暂停token。
- 返回token沿用协调器递增分配器，慢速与暂停用不同记录表。
- 首个慢速token记录baseline=Engine.time_scale；有效值=min(baseline, 所有申请scale)。这是绝对速度上限，不累乘多个慢速。
- 最后持有者释放时恢复baseline，不写死1；无持有时不干预Engine.time_scale。删除持有者、解绑及世界退出同样恢复。
- 协调器为本世界时间写入唯一入口；不新增UI直接写Engine.time_scale的路径，不改物理tick频率。

### SquadChainCommandController

- acquire_input_block(owner:Node, reason:StringName)->int：同绑定世界弱所有权，失败0。
- release_input_block(token:int)->void：幂等，不改变现有_input_enabled。
- _input_reason额外考虑有效阻断；_clear_scope清理本世界阻断；无效owner回收。
- 仍保留set_input_enabled(bool)原语义。阻断不撤销已受理请求，不改费用提交/缓存推进。

### SquadFinisherSelectionController

- enum Phase { CLOSED, OPENING, SELECTING, CONFIRMED, CLOSING }。
- signal selection_state_changed(snapshot:Dictionary)。
- signal finisher_selected(selection:Dictionary)。
- signal selection_closed(result:Dictionary)。
- get_selection_status()->Dictionary：返回深复制纯值快照。
- try_select_slot(slot_index:int)->bool：0—3，复查时钟、阶段、显式暂停及伙伴；成功锁定一次、记录日志、发选择事实。
- cancel_selection(reason:StringName)->void：幂等立即清理；用于解绑/退出，不等待UI完成。

snapshot固定字段：phase、scene_scope_id、round_id、remaining_seconds、duration_seconds、progress_ratio、selected_slot、presentation_elapsed_seconds、interaction_allowed、slots。
slots固定四项，每项含slot_index、actor_instance_id、actor_name、available、reason；无Node/Resource/Request。
selection固定字段：scene_scope_id、round_id、slot_index、actor_instance_id、actor_name。
result固定字段：scene_scope_id、round_id、reason、selected_slot；reason为selected/timeout/no_available/cancelled，取消细节另加detail。

内部时间锁定：淡入/展开0.12秒，成功保持0.12秒，收起0.10秒；从OPENING起计算3秒选择时限，OPENING与SELECTING均可接受新按下。
CONFIRMED结束后进入CLOSING；超时直接CLOSING。只有完全关闭才释放本次慢速/输入持有。
显式暂停挂起上述所有真实计时；纯释放强调不挂起，沿用is_presentation_allowed()区分。输入处理前更新真实时钟，elapsed>=duration先超时。
用Time.get_ticks_usec采样真实时间，保存上一采样是否允许推进；暂停状态变化时先结算之前时段再更新标志，避免把暂停整段补算进去。
对同一round_source只允许一个有效控制器；重复装配失败关闭并告警一次。先建立状态/持有再发通知，通知后检查绑定代次，防止同步解绑后继续写旧状态。

### SquadFinisherSelectionDisplay

纯显示，无_input、无Button点击执行、无暂停/费用/技能调用；Control mouse_filter=IGNORE、focus_mode=NONE。
只用snapshot推进表现；绑定为空/无效/卸载时隐藏并断旧监听，不反向取消合法业务。
UI短动画用snapshot.presentation_elapsed_seconds，不能用受time_scale影响的Tween默认delta。

## 3. 验证入口

每个测试脚本extends SceneTree，沿用现有_expect/quit风格。以下T(path)表示Godot MCP Pro：
run_headless_script(script_path=path, timeout_sec=60)。
预期：对应测试打印“TestName: PASS”且exit_code=0；解析错误、超时、非0退出均为失败。

新增测试入口：
- T("res://GameFlow/Tests/GameTimeScaleOwnershipTest.gd")
- T("res://UnitSystem/Tests/SquadFinisherSelectionControllerTest.gd")
- T("res://UnitSystem/Tests/SquadFinisherSelectionInputDisplayTest.gd")

每项先写测试观察RED，再实现观察GREEN；不要一开始创建能假装通过的空组件。
运行前/结束后保留Engine.time_scale和SceneTree.paused现场；测试finally式收尾恢复自己的变更。

---

### Task 1：有所有权的慢速，保留现有暂停

**Files:** 修改GamePauseCoordinator.gd；新建GameTimeScaleOwnershipTest.gd。
**Interfaces:** consumes bind_scope/get_bound_scope/is_presentation_allowed；produces §2慢速接口。

- [x] 编写test_scale_ownership_and_baseline、test_invalid_owner_or_scale。断言：
```gdscript
Engine.time_scale = 0.7
var a: int = manager.acquire_time_scale(owner, 0.05, &"selection")
assert(a > 0 and is_equal_approx(Engine.time_scale, 0.05))
assert(not tree.paused)
var b: int = manager.acquire_time_scale(other, 0.02, &"other")
manager.release_time_scale(a)
assert(is_equal_approx(Engine.time_scale, 0.02))
manager.release_time_scale(b)
manager.release_time_scale(b)
assert(is_equal_approx(Engine.time_scale, 0.7))
```
补充baseline=0.02时申请0.05不加速；0、负数、NaN、INF、>1及跨世界owner均拒绝。
- [x] 运行新增时间测试，确认因接口缺失而RED，不把环境启动失败当RED。
- [x] 用MCP修改协调器，实现§2接口和弱引用回收，不改变已有暂停token处理。
- [x] 增加test_pause_accent_and_scale_independence、test_owner_free_unbind_scope_exit。真暂停期间释放慢速不解除暂停；强调按真实秒到期；删除owner/单独卸载manager/卸载world均恢复自己的速度，原显式暂停保护仍保持。
- [x] 运行新增时间测试及GamePauseCoordinatorTest.gd、SkillSystem/05-Tests/ReleaseAccentClockTest.gd到GREEN。
- [x] Review检查点A：没有第二时间写入者，没有把5%实现成tree.paused，没有更改普通物理频率。

### Task 2：连携输入阻断所有权，不改变已有请求

**Files:** 修改SquadChainCommandController.gd；新建SquadFinisherSelectionControllerTest.gd中的输入阻断用例。
**Interfaces:** consumes get_bound_scope/set_input_enabled；produces §2输入token。

- [x] 复用SquadChainRoundWindowTest.make_fixture(root)写test_input_block_preserves_other_owners、test_input_block_does_not_cancel_pending：
```gdscript
source.set_input_enabled(false)
var a: int = source.acquire_input_block(owner, &"selection")
var b: int = source.acquire_input_block(other, &"other")
source.release_input_block(a)
source.release_input_block(b)
assert(not source.submit_slot(0)) # 原false不能被误开启
source.set_input_enabled(true)
assert(source.submit_slot(0))
```
已受理请求在阻断前后ID、预留量保持不变；有效阻断期间submit_slot拒绝且不分配新轮。删除owner回收，跨世界owner拒绝，旧token不能影响新scope。
- [x] 运行控制器测试观察RED，再实现token接口与_input_reason最小增量；清理采用compare/identity，不强制set_input_enabled(true)。
- [x] 运行控制器测试、SquadChainInputDisplayTest.gd、SquadChainCommandTransactionsTest.gd到GREEN，保留原测试合法性预期。
- [x] Review：程序调用submit_slot同样被阻断；已受理请求的释放授权、缓存推进和旧轮退款路径不增加输入阻断检查。

### Task 3：资格到窗口的流程、真实时钟和安全关闭

**Files:** 新建SquadFinisherSelectionController.gd/.tscn；扩展SquadFinisherSelectionControllerTest.gd。
**Interfaces:** consumes Task1/2与finisher_qualified；produces §2控制器接口/快照，供Task4显示。

- [x] 写test_only_qualified_closed_round_opens、test_snapshot_is_read_only。使用真实W.make_fixture、W.start_released/W.deal/W.advance生成达分和结算，不靠手写UI数值伪造主正路径：
```gdscript
W.deal(f, request, 1000.0)
assert(f.round.get_round_status().finisher_ready)
assert(selection.get_selection_status().phase == 0) # 达分但未闭窗
W.advance(f, 2.000001) # fixture本身间隔2秒，不改正式默认2.5
assert(selection.get_selection_status().phase == 1)
assert(is_equal_approx(Engine.time_scale, 0.05))
```
正常低分闭窗不打开；重复发送同一个已结算result只开一次；晚绑定不从last_result补弹。
- [x] 运行控制器测试观察RED；用MCP创建控制脚本/组件场景并由Godot保存。
- [x] 实现绑定世界/代次与唯一所有者、资格去重、状态机、四项接口测试可用性、§2计时、日志与幂等清理。申请慢速和阻断任一步失败均回滚；busy时新资格不排队、不续时。
- [x] 加入test_real_three_seconds_at_five_percent、test_external_pause_freezes_remaining、test_timeout_boundary、test_live_availability。3秒真实等待容差0.15秒后必须进入关闭；显式暂停0.25秒不扣剩余，恢复不补扣；终结槽为空仍可选，空槽/两个重复槽均无效，死亡和跨世界对象不可选，全无效不持有慢速。
- [x] 加入test_choice_has_no_gameplay_side_effect、test_duplicate_stale_and_reentrant_cleanup。选择事件一次、关闭事件一次；选项对应角色、血量、专注、Host动作/预留不因“选择”改变。同步通知回调free/重绑组件，旧世界重放、主源删除、manager删除均安全关闭，无跨轮资格库存。
- [x] 运行控制器测试与Task1测试到GREEN。Review检查点B：资格事实不是技能请求；仅原轮正常结算达分触发，无原始角色强引用泄漏。

### Task 4：十字显示、真实输入与不可穿透

**Files:** 新建SquadFinisherSelectionDisplay.gd/.tscn、SquadFinisherSelectionInputDisplayTest.gd；补控制器_input实现。
**Interfaces:** consumes Task3公开快照/try_select_slot；输入归控制器，显示组件只读。

节点路径固定：
```text
SquadFinisherSelectionDisplay (CanvasLayer)
└─ Root (Control，全屏)
   └─ Cross (Control，中心约0.66/0.64)
      ├─ Title (Label)
      ├─ Slot1 (PanelContainer，左，Label子节点Key/Actor/Skill)
      ├─ Slot2 (PanelContainer，上，同上)
      ├─ Slot3 (PanelContainer，右，同上)
      ├─ Slot4 (PanelContainer，下，同上)
      └─ Countdown (ProgressBar，十字下方，0—1)
```

- [x] 写test_fixed_cross_slots_and_real_time_display、test_display_queries_have_no_side_effect：位置满足左1上2右3下4；四槽名对应原索引；源为空隐藏；快照改变后倒计时和灰显一致；修改返回快照不影响业务；显示不生成请求/扣费。
- [x] 写test_input_map_rebinding_and_held_key、test_repeat_multikey_and_close_no_leak。通过Input.parse_input_event送InputEventAction/按当前InputMap构造的键事件走真实viewport，不只直接调用_unhandled_input。每个1—4分别选对；改绑临时动作事件仍可用；持键跨开窗须释放重按；回声忽略；同帧多键只一次；关闭消费本次按下不增加command_accepted，下一次新按下可回常规连携。
- [x] 运行输入显示测试观察RED。
- [x] MCP建立场景节点/Theme/StyleBox并保存；默认深色半透明面板、银白标题、选中亮边、无效灰显，沿用项目字体。技能行固定“终结技（接口测试）”；无额外美术资源。Controller._input在活动期间消费四动作，显式暂停期间也消费但不选择。
- [x] 实现真实输入的新按下门控：开窗记录已持有动作，释放解除；关闭后保留必要的释放尾门控，不延长慢速、不可吞掉其他动作。try_select_slot本身亦拒绝过期/多次调用。
- [x] 用状态中的真实表现时长计算淡入/展开/高亮/收起；正常显示无Tween缩放依赖。实际像素布局初始按2560×1440制作，缩放以可用视口与安全边距夹紧，不增加布局脚本导出参数。
- [x] 测试2560×1440、1920×1080、1280×720及960×540的十字与倒计时矩形均在可见范围；所有Control忽略鼠标/焦点，不遮挡点击操作。
- [x] 三项新增测试及原SquadChainInputDisplayTest/ChainSkillPresentationControllerTest到GREEN。Review检查点C：UI没有业务调用，旧输入行为不受未装配组件的场景影响。

### Task 5：独立继承预览、装配说明与可见验证

**Files:** 新建Scenes/Previews/SquadFinisherSelectionPreview.tscn；补输入显示测试；修改配置指南。
**Interfaces:** consumes Task3/4组件场景；produces F6独立预览，无新增预览.gd。

- [x] 写test_preview_inherits_original_and_uses_single_pause_owner，验证源继承SquadChainRoundPreview、仅多1个控制器/1个显示、无新增单位/复制技能/第二PauseCoordinator，场景UID全部有效。
- [x] 运行测试观察RED，再用MCP创建真实继承场景，不展开复制原场景。
- [x] 装配selection.round_source=../SquadChainRoundController；selection.pause_source=../ChainSkillPresentationController/PauseCoordinator；display.selection_source=../SquadFinisherSelectionController。保留原连携UI、调试显示与当前源数值；不增加测试用自动弹窗或修改达分门槛。
- [x] 配置指南说明F6运行、积累专注/实时1—4连携/停手闭窗/达分弹窗/选择或超时的路径，说明当前只有日志、非正式终结技能合法性。
- [x] 编辑器检查5个导出项中文说明、节点/样式可编辑、无其他必填隐藏装配。保存后重载新场景，检查Inspector引用和UID。
- [x] 运行场景，截取弹出、按下反馈与关闭/倒计时状态；实测3秒及5%普通模拟差别。记录实际观测，不用截图代替时间/输入数据测试。

### Task 6：全循环、泄漏与回归验收

**Files:** 补三个新测试；新建validation.md；维护计划/设计状态，修正限既定文件范围。

- [x] 压力用例test_50_selection_cycles_and_10_world_reloads：每轮正常生成资格，交替选择/超时，定期重绑世界；慢速token和输入token最终清空，连接不累加，下一世界正常速度且可接收原连携输入。
- [x] 用MCP运行全部新增测试、GamePauseCoordinatorTest、ReleaseAccentClockTest、SquadChainRoundWindowTest、SquadChainRoundIntegrationTest、SquadChainRoundDisplayTest、SquadChainInputDisplayTest、SquadChainCommandTransactionsTest、ChainSkillPresentationControllerTest、CameraSkillFocusTest、CombatBalanceBaselineTest。所有脚本需exit=0；检查PASS后原生异常退出同样记失败。
- [x] 全量回归按实际可执行测试入口清单逐个运行，不把被preload的夹具/预览当入口。以前一轮归档verification.json已执行列表为基线，加入本次3项；执行时读取归档结构确认，不硬编码“全部141通过”。
- [x] 检查全量输出中的解析错误、无效实例、孤儿/资源泄漏与新增warning；可复现失败先定位，不能通过降低断言、改变游戏数值规避。
- [x] 独立审查本切片完整diff：时间恢复、输入穿透、身份/重入、安全清理、配置可读性；修复后重新运行受影响测试及最终全量。
- [x] 保存validation.md：实际文件数量、配置入口、运行路径、自动测试结果、可见验证截图/观察、未解决项。核对git diff未混入数值变化；不把全部阶段四标为完成。
- [x] Review检查点D与用户验收：用户能看到窗口、按键反馈、日志及恢复；明确终结演出尚未实现。仅用户另外授权才本地git/上传，不执行全目录暂存。

## 4. 自审覆盖与执行交接

| 设计要求 | 任务 |
| --- | --- |
| 结算达分触发、不重放历史 | 3 |
| 十字位置/四槽映射/显示时长 | 4、5 |
| 无正式终结仍可测/动态灰显 | 3、4 |
| 5%慢速与非1基线/多持有恢复 | 1、3、6 |
| 输入重绑/持键/超时/穿透 | 2、4 |
| 显式暂停/强调/真实时钟 | 1、3、4 |
| 删除/重入/切世界清理 | 1、2、3、6 |
| 人类可编辑、UID、预览、说明 | 4、5 |
| 日志而非技能执行/不改数值 | 3、5、6 |

自审结果：6项任务、4个review检查点；接口与字段统一；每个Review Focus均落到具体测试。新增5gd/3tscn/0tres，不提前创建终结技能或演出骨架。

执行方式建议：当前会话逐项实施（superpowers:executing-plans），维持同一个Godot编辑器现场，每个检查点先测试，再由独立审查者进行末尾整体审查。另一可选方式是逐任务子代理实施与审查，审查更密集但上下文成本较高。

请用户审阅计划并确认执行方式；本计划的生成不代表开始实现或自动备份提交。
