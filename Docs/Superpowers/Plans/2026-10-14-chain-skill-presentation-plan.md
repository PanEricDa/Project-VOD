# 连携施放表现 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变连携执行规则的前提下，实现黄/绿/红卡片反馈、施法临时镜头、成功释放时 0.15 秒战场停顿与独立播放的释放特效。

**Architecture:** SkillBase/Host 提供带身份的只读表现事实，关卡表现组件协调既有相机与独立暂停所有权，原 UI 消费相同请求状态。视觉、音频、镜头与停顿分别配置，空资源安全退化；不建立第二套技能管线或全队施放队列。

**Tech Stack:** Godot 4.7、GDScript、Resource/PackedScene、AnimationPlayer、AudioStreamPlayer3D、原生粒子、SceneTree 契约测试；优先 Godot MCP Pro 编辑和验证。

**Spec:** [已确认的详细设计](../Specs/2026-10-14-chain-skill-presentation-design.md)。执行者须完整阅读该设计与项目 AGENTS.md；上轮释放接口计划的“不做镜头/暂停”仅限定上轮，本计划按新的已确认范围扩展。

> 日期：2026-10-14；实施完成：2026-10-15。备份版本 `3bc5f9f` 已提交并上传；六项任务完成，修复独立审查3项Important问题后，134/134全量回归再次通过。实际音量/听感与镜头舒适度仍待用户试玩；连携三、四阶段仍暂停。详见[验收记录](2026-10-14-chain-skill-presentation-validation.md)。下文原始基线保留为制定时记录，实际实现以当前代码和验收证据为准。
>
> 基线：当前目录 G:\Godot\ProjectVOD，HEAD `0a2b21edbb1dc5de18b5692c0f9feffa985ca172` 加现有未提交内容。不能只从 HEAD 重建并丢弃阶段二、UI 和释放接口。
>
> 推荐沿用当前会话逐任务实施、每组验证、最终一次独立审查。用户批准本设计不等于已批准本实施计划或代码执行；本轮不创建产品脚本/场景/资源，不提交或上传 Git。

## Global Constraints

- “固定的是事实时点、请求身份、清理与播放契约；可替换的是镜头资源、视觉场景、声音资产、UI 样式和表现时长。”
- “成功释放是既有 delivery_started 接受事实，不是 release_started 意图通知，也不是命中。”
- “首版 0.15 秒”战场停顿；“从成功释放起约 0.3 秒”清除本次绿色边框，包含停顿；释放前失败/拒绝红框默认 0.3 秒。
- SkillFocusCameraProfile 进入/返回默认“0.12 / 0.20 秒”；ReleaseAccentProfile 停顿默认“0.15 秒”，有限、范围“0—0.3 秒”；0 关闭停顿。
- “不将正常 target 改成伙伴”；保持俯视角、FOV 和缩放档位，镜头不延长施法，不等命中或动作收尾。
- “本次释放特效与音效继续播放”；只注册纯释放实例，不能给 SkillBase、Host、单位、Runner、伤害区域或战斗投射物放行暂停。
- “同一物理帧根释放的停顿合并取最大，不相加”；不按迟到通知重新加时，至少一次正常物理推进后再开放新强调。
- “当前焦点完成优先”；未获得镜头的伙伴照常并行，已结束的施放不补播。
- “只有释放强调暂停”时允许 1—4 受理/预留/缓存，恢复后执行；显式/外部暂停不允许，不增加全队缓存，不扩展 Q/E 等输入。
- 根节点只新增一个 release_accent_profile 资产槽；原镜头槽迁移为 camera_effect_profile，旧 release_camera_effect 兼容但不再作为第二个 Inspector 配置。
- UI 只新增成功保留、失败提示两个时间；三色在场景 Theme/StyleBox 维护。关卡组件三个引用，pause_source 在自身场景预填。
- 所有 export、信号、公开方法及跨模块输入紧邻简体中文说明；资源只保存配置，不保存运行状态；未知/失效资产不影响费用与战斗结果。
- “不改 project.godot 的按键或 Autoload”；不自动添加/修改 TestScene 单位，不改 TestCombatRoom 的单位摆放、原普通技能或连携数值。
- 仅给四个 Combo_ 技能填共享镜头/强调；新中性闪光只在新预览覆盖，原嘲讽/治疗视觉不替换。连携阶段三、四仍暂停。
- MCP 优先创建/编辑/保存；不支持或实际失败才说明并回退。正式 .tres/.res 经 Godot 保存，验证 UID、脚本类型与 Quick Load，不能只文本写入。
- 保留现有未提交改动与编辑器未保存缓冲区；无授权不建新工作树、不强制覆盖、不提交/上传，不执行 git add .。

## Review Focus

1. 在接受通知、表现实例 _ready 或失败退款回调中同步卸载/重绑：旧请求必须安全停止，不能在新世界注册实例或漏掉失败。任务一的 `_test_reentrant_release_and_failure`、任务四的 `_test_scope_change_during_instance_prepare`。
2. 时长为 0、负数、NaN/INF，或无视觉音频但配置强调：零值即时退化，非法值跳过该表现，纯停顿仍有效，不锁死世界。任务一的 `_test_optional_and_legacy_configuration`、任务二的 `_test_duration_boundaries`、任务三的 `_test_zero_and_invalid_profile`。
3. A 较早受理但比 B 晚释放，同角色新请求覆盖显示，而旧成功/失败计时尚未结束：不得用最大 ID 拒绝 A，不得清除新框或错误抢镜。任务四的 `_test_out_of_order_roots`、任务五的 `_test_old_deadline_cannot_clear_new_state`。
4. 停顿中按连携键、打开显式暂停、销毁技能或重载：按键不丢也不执行；显式暂停不被自动恢复；纯释放实例独立回收。任务二的 `_test_pause_ownership_and_exit`、任务四的 `_test_input_during_accent`、任务六压力验证。
5. 原镜头字段的旧场景、空基础镜头资源、多个实例共享预设，以及未装新组件的正式场景：兼容加载且普通行为不变；Inspector 仍只有一个镜头槽，预设 UID/类型正确。任务一的 `_test_optional_and_legacy_configuration`、任务三的 `_test_shared_profile_is_stateless`、任务六资源与配置审计。

---

## 1. 文件结构与交付数量锁定

### 新增产品内容

| 文件 | 任务 | 职责/创建方式 |
| --- | --- | --- |
| SkillSystem/01-Core/SkillPresentationContext.gd | 一 | RefCounted 本次表现身份与只读快照 |
| Effects/Camera/SkillFocusCameraProfile.gd | 一 | 继承已有 CameraEffectProfile 的平移策略 |
| Effects/Combat/ReleaseAccentProfile.gd | 一 | 单项释放停顿配置 |
| GameFlow/Pause/GamePauseCoordinator.gd | 二 | 暂停所有权与释放实例时钟 |
| UnitSystem/Components/Combat/Squad/ChainSkillPresentationController.gd | 四 | 根连携事实的关卡表现协调 |
| UnitSystem/Components/Combat/Squad/ChainSkillPresentationController.tscn | 四 | 新组件；固定可见 PauseCoordinator 子节点 |
| Effects/Camera/Presets/ChainSkillFocus.tres | 六 | 共享镜头预设，0.12 / 0.20 秒 |
| Effects/Combat/Presets/ChainReleaseAccent.tres | 六 | 共享停顿预设，0.15 秒 |
| Effects/Skills/Shared/ReleaseAccentFlash.tscn | 六 | 原生节点组成的临时纯视觉，无专用 .gd |
| Effects/Skills/Shared/ReleaseAccentFlashPreview.tscn | 六 | 继承 SkillReleasePresentationPreview，复用其脚本 |
| Scenes/Previews/ChainSkillPresentationPreview.tscn | 六 | 继承 SquadChainCommandPreview，复用其脚本与既有阵容 |

### 新增测试入口

1. SkillSystem/05-Tests/SkillPresentationLifecycleTest.gd：任务一及六。
2. SkillSystem/05-Tests/ReleaseAccentClockTest.gd：任务二及六。
3. GameFlow/Tests/GamePauseCoordinatorTest.gd：任务二。
4. UnitSystem/Tests/CameraSkillFocusTest.gd：任务三。
5. UnitSystem/Tests/ChainSkillPresentationControllerTest.gd：任务四及六。

新增合计 **10 个 .gd（运行 5 + 测试 5）、4 个 .tscn、2 个 .tres**；Godot 自动生成 .gd.uid。其余是既有文件修改，不另外拆第二套 HUD、暂停场景、特效专用脚本或演出资源组合。

### 既有文件及修改锚点

| 文件 | 精确修改位置/职责 | 任务 |
| --- | --- | --- |
| SkillSystem/01-Core/SkillBase.gd | Presentation export；confirm_action_started、_on_runner_delivery_started、取消/退出、RuntimeEffects 转发 | 一 |
| SkillSystem/01-Core/SkillReleasePresentationPlayer.gd | prepare_release、play_release、_play_visual、_play_audio；兼容旧调用 | 一 |
| SkillSystem/01-Core/SkillHostComponent.gd | confirm_active_action_started；_connect_skill/_disconnect_skill；新事实转发 | 一 |
| UnitSystem/Components/Combat/Squad/SquadChainCommandController.gd | 绑定、_fail_record、事实转发；之后添加暂停门禁 | 一、四 |
| Effects/Camera/CameraEffectProfile.gd | 无副作用策略接口，不保存播放进度 | 一 |
| UnitSystem/Components/Camera/CameraFollowController.gd | class_name；_process、正常构图、临时焦点、缩放/震动最终写入 | 三 |
| Effects/Combat/HitFeedbackBridge.gd | 暂停下计时；必要的统一相机偏移兼容 | 三 |
| UnitSystem/Components/State/UnitStateComponent.gd | _start_death_watchdog、_schedule_dissolve_start 的 Timer 暂停语义 | 二 |
| GameFlow/Rooms/CombatRoomController.gd | _schedule_failure 的 Timer 暂停语义 | 二 |
| Effects/Death/DefaultDeathEffect.gd | _ready 销毁延迟随普通战斗暂停，补邻近中文说明 | 二 |
| UnitSystem/Components/UI/SquadChainCommandDisplay.gd / .tscn | 原界面的请求级边框与时间，不拥有技能/暂停 | 五 |
| SkillSystem/00-Skills/Combo_GuardianBash/ComboGuardianBashSkill.tscn | 只选择两个共享预设 | 六 |
| SkillSystem/00-Skills/Combo_GreaterHeal/ComboGreaterHealSkill.tscn | 同上 | 六 |
| SkillSystem/00-Skills/Combo_Firebolt/ComboFireboltSkill.tscn | 同上 | 六 |
| SkillSystem/00-Skills/Combo_RapidShot/ComboRapidShotSkill.tscn | 同上 | 六 |
| SkillSystem/05-Tests/SkillReleasePresentationTest.gd、SingleSceneSkillBaseTest.gd | 保留旧接口/锚点/播放测试，补兼容断言 | 一、六 |
| UnitSystem/Tests/SquadChainInputDisplayTest.gd | 扩展真实卡片、输入、重绑验证 | 五 |
| UnitSystem/Tests/UnitStateComponentTest.gd、GameFlow/Rooms/Tests/CombatRoomControllerTest.gd | 新暂停语义回归，原非暂停规则不变 | 二 |
| SkillSystem/04-Docs/SkillSystemUserGuide.md、SkillTemplateAndDeliveryWorkflow.md、SquadChainCommandConfigurationGuide.md | 最终配置、兼容与预览使用说明 | 六 |
| Docs/CurrentProgressReport.md、本设计/计划及验收记录 | 只记录实际通过项目，不将其写成连携三/四阶段完成 | 六 |

SkillBase.tscn 仍是原三个固定节点；仅在 Godot 要求登记/保存时保存，不增加表现子层。其他必要夹具变更须列明原因，不能为通过测试偷偷改游戏数值。

## 2. 验证入口与执行准备

- 生产文件/资源编辑优先 MCP，计划中的编辑动作均指 MCP 适用操作；Markdown 无适用工具时才使用 apply_patch 并说明。
- 每项先写行为测试，确认 RED，再做最小实现并确认 GREEN。新增 class_name 尚未导入、语法错误或超时都不算有效 RED；如需声明壳以供解析，真实失败必须仍由行为断言证明。
- 新测试均 extends SceneTree，无参数运行该文件全部用例，打印 `<文件基名>: PASS` 并 quit(0)；任一断言失败输出原因并 quit(1)。不用 --quit-after 提前退出伪造通过。
- MCP 命令统一为 `run_headless_script({script_path: "res://...Test.gd", timeout_sec: 180})`；要求退出码 0、明确 PASS、无 SCRIPT ERROR/未预期 ERROR/超时。后续步骤使用这个命令模板逐文件运行。
- 测试夹具复用 `UnitSystem/Tests/AllyChainCommandPriorityTest.gd.make_fixture(parent, actor_path, manage_requests)` 的真实 Host/动画/单位；涉及费用用 manage_requests=false 加真实 Focus/指令控制器，不再同时挂测试自动 mark_released。
- 夹具与临时音频/策略资源仅在内存，不改 TestScene 或正式房间。临时外部序列化夹具用独立测试路径并正式保存后清理，不能残留正式样例。
- 暂停计时测试用实际帧和单调时间观察，不手工调用整套暂停更新来代替运行；需要观测的测试入口/观察节点可以 ALWAYS，夹具中的战斗探针必须 PAUSABLE。
- 每个任务末尾保存原始 RED/GREEN 输出与差异检查；仅实际验证完成才勾选。版本提交不是本计划默认步骤，用户另行授权后仅提交明确范围。

## 3. 四个验收组

| 验收组 | 任务 | 可审阅结果 |
| --- | --- | --- |
| A：事实与身份 | 一 | 开始/成功/失败通知与快照正确，未装新表现仍保持原玩法 |
| B：时间与镜头 | 二、三 | 战斗停而释放表现继续；镜头不改玩家绑定，安全返回 |
| C：连携与界面 | 四、五 | 根连携并发、停顿内缓存，以及黄/绿/红边框完整接通 |
| D：可见内容与交付 | 六 | 独立预览、共享预设、资源 UID、真实运行、全量回归和整体审查 |

这四组仅指本功能的实施检查点，不对应游戏连携阶段一至四。A/B/C 先交付数据层通过证据；D 才宣称用户可在独立预览完整试玩。每组不通过则留在该组修正，不带已知失败进入下一组。

## 任务一：表现身份、资源契约与真实开始/释放事实

**Files:** 新建 SkillPresentationContext.gd、SkillFocusCameraProfile.gd、ReleaseAccentProfile.gd、SkillPresentationLifecycleTest.gd；修改文件表中 SkillBase、播放器、Host、指令控制器、CameraEffectProfile 和既有释放测试。

**Interfaces — produces:**

- `static SkillPresentationContext.create(skill: SkillBase, context: SkillContext, action_transform: Transform3D, presentation_id: int = 0) -> SkillPresentationContext`：0 从现有 CombatDamageContext.allocate_id 取得表现身份；非法 world/变换返回 null，不影响游戏激活。
- `SkillPresentationContext.for_release(context: SkillContext, anchor_transform: Transform3D) -> SkillPresentationContext`：同一身份的不可变 RELEASE 快照；保留开始时资产/数值，不重新读取技能字段。
- `SkillPresentationContext.Stage { CAST, RELEASE }`；只读字段：stage、presentation_id、command_request_id、scene_scope_id、skill_instance_id、purpose、execution_mode、is_chain_root、effective_cast_time、world_transform、visual_scene、audio_stream、release_effect_anchor、pause_duration_seconds；`get_source() -> Node3D`、`get_target() -> Node3D`、`get_world() -> Node`、`get_camera_profile() -> CameraEffectProfile`。节点仅 WeakRef；策略按次 duplicate，资产不深复制；消费者不能写回策略副本。
- `SkillBase.get_current_presentation_context() -> SkillPresentationContext`；export `camera_effect_profile: CameraEffectProfile = null`、`release_accent_profile: ReleaseAccentProfile = null`；release_camera_effect 保留非 export 的兼容 getter/setter，只代理新字段，不保存第二份值。
- `CameraEffectProfile.Phase { ENTER, RETURN }`；`get_phase_duration(phase: int) -> float`、`sample_rig_transform(from_pose: Transform3D, destination_pose: Transform3D, progress: float, phase: int) -> Transform3D`。基类阶段时长返回 -1 表示无具体运动，安全跳过；子类 export `enter_duration_seconds=0.12`、`return_duration_seconds=0.20`，零值即时。
- `ReleaseAccentProfile.pause_duration_seconds: float = 0.15`，唯一 export，范围 0—0.3；非法运行时值由消费者安全拒绝，不改共享值。
- 播放器保留原 6 个参数，追加可空第7项：`prepare_release(context: SkillContext, action_transform: Transform3D, visual_scene: PackedScene, anchor: int, audio_stream: AudioStream, camera_profile: CameraEffectProfile, presentation_context: SkillPresentationContext = null) -> Dictionary`；返回原 Dictionary 加可选 presentation 键，`play_release(snapshot: Dictionary) -> void` 不变。
- 播放器/SkillBase/Host 对应转发 `release_instance_prepared(presentation: SkillPresentationContext, instance: Node)`、`release_presentation_started(presentation: SkillPresentationContext)`；空旧工具上下文不伪造根身份。
- Host 新增 `command_action_started(request: SkillCommandRequest, presentation: SkillPresentationContext)`。
- 指令源新增 `command_started(slot_index: int, presentation: SkillPresentationContext)`、`command_failed(slot_index: int, request_id: int, reason: StringName)`、`command_release_instance_prepared(slot_index: int, presentation: SkillPresentationContext, instance: Node)`、`command_release_presentation_started(slot_index: int, presentation: SkillPresentationContext)`、`scope_changed(scope_root: Node)`、`get_bound_scope() -> Node`。

- [x] **步骤1：记录执行基线与编辑器状态。** MCP 核对项目路径/版本，检查目标脚本缓冲区及打开场景未保存冲突；记录 git 状态、原文件 hash、四连携资产/参数、TestCombatRoom/TestScene/project.godot 状态。枚举并逐项运行当前活跃 SceneTree 测试；当前计划编写时枚举为 129，但执行以当时清单为准。任何已有失败先诊断，不覆盖工作区或降断言。
- [x] **步骤2：写身份/顺序/兼容失败测试。** 在 SkillPresentationLifecycleTest 写 `_test_identity_and_snapshot`、`_test_start_after_host_confirmation`、`_test_fee_instances_and_accent_order`、`_test_reentrant_release_and_failure`、`_test_optional_and_legacy_configuration`。验证同一次开始/释放 ID 相同、下次不同、开始快照不跟随后改资产、子技能不是根、节点删除不保活；费用夹具明确设20基础费且初始100。核心断言如下，fixture 只连接一种费用所有者：

```gdscript
host.command_action_started.connect(func(request, presentation):
    _expect(request.has_action_started(), "actual action already confirmed")
    _expect(host.get_active_command_id() == request.request_id, "Host identity committed")
    _expect(host.get_pending_command_id() == 0, "pending migration completed")
    _expect(presentation.command_request_id == request.request_id, "same root")
)
# 单视觉、无音频夹具：fee 在 command_released 记；prepared 在进树前记。
_expect(trace == ["fee", "prepared", "visual_ready", "accent", "effect"], "accepted presentation order")
_expect(focus.get_current_focus() == 80.0, "presentation does not pay twice")
```

Focus.get_current_focus() 已核对为既有接口，不新增查询方法。还须测试：失败退款时 lifetime_finished 同步移除 Record 仍报告正确槽位；0 施法开始/释放可同帧；全空无资产节点，只有强调时仍有表现启动事实。

- [x] **步骤3：运行新测试取得 RED。** MCP 运行该文件，保留“缺少已确认开始通知/身份不稳定/释放纯强调早退”等行为失败；语法/类型未登记先修测试，不当成果。
- [x] **步骤4：实现快照与资源契约。** 按 Interfaces 新建3个运行脚本并扩展 CameraEffectProfile；所有参数中文说明。确认动作开始前捕获本次配置，释放前产生独立阶段快照；保留 source/target/world 弱引用。迁移镜头字段为单一 export，非导出别名兼容旧脚本赋值及旧场景属性；经 Godot 保存后只写新字段。禁止在共享资源中存运行进度。
- [x] **步骤5：实现播放/确认事实。** 在原接受通知之前准备释放快照，原 Host/Focus 提交后播放；实例初始变换、watchdog 和 prepared 通知均在 add_child/_ready 前准备，通知后重验实例/世界。visual/audio 启动步骤后发一次 typed started，保留旧四参数镜头信号。Host 完成原 active/pending 提交后发开始；注册/注销对称，转发不能依赖技能当前仍 CASTING。
- [x] **步骤6：实现根身份转发与失败快照。** 指令源只转发自己受理且匹配来源、世界世代的根，不按目录前缀。_fail_record 在可能删记录的回调前捕获 id/slot/reason，退款仍走原逻辑；解绑先通知旧 scope 失效，再清理，避免红框串新世界。完成通知不代替释放事实。去重存活期有界，不用最大已见 ID 拦乱序。
- [x] **步骤7：完成兼容与重入 GREEN。** 在测试专用 user:// 临时路径构造含旧字段的最小场景文本夹具（不是正式资产），实际 ResourceLoader.load 验证兼容；再经 Godot 保存确认仅存新字段，清理本次明确创建的单个临时文件。不能先用新 ResourceSaver 生成夹具而误以为测到了旧字段。prepared 监听中 free 实例/卸载世界、accepted 监听换目标/清 context/换资产，当前快照不串下一次。单次连射/多目标只一个根开始和强调事实，已接受后最终失败不改成退款。运行新文件及 SkillReleasePresentationTest、SingleSceneSkillBaseTest、SkillCommandActivationTest、SquadChainCommandTransactionsTest、SquadChainCommandLifecycleTest、UnitHealthFrameSkillNoticeTest、SkillTypeNoticeTest。
- [x] **步骤8：验收组 A。** 核对只新增一个技能资产槽、旧场景可加载、原三节点结构和普通行为不变；记录红→绿、公开接口与变更文件。未装新协调器时相机/暂停均不改变，不能在此步把基础事实完成称为完整镜头已接入。

## 任务二：暂停所有权、真实时间恢复与释放实例时钟

**Files:** 新建 GamePauseCoordinator.gd、GamePauseCoordinatorTest.gd、ReleaseAccentClockTest.gd；修改 UnitStateComponent.gd、CombatRoomController.gd、DefaultDeathEffect.gd 及文件表对应原测试。此任务测试夹具显式连接任务一通知，暂不建立关卡协调组件。

**Interfaces — consumes:** 任务一的 prepared/started、只读表现身份与 pause_duration_seconds。

**Interfaces — produces:** GamePauseCoordinator extends Node，运行时 ALWAYS；没有 export。

- `bind_scope(scope_root: Node) -> bool`、`get_bound_scope() -> Node`。
- `request_release_accent(presentation_id: int, duration_seconds: float, owner: Node) -> int`。
- `acquire_pause(owner: Node, reason: StringName) -> int`、`release_pause(token: int) -> void`。
- `is_release_accent_only() -> bool`、`has_release_accent() -> bool`、`is_presentation_allowed() -> bool`；最后一项在正常战斗或仅强调暂停时为 true，显式/外部暂停为 false。
- `register_release_instance(presentation_id: int, instance: Node) -> bool`：允许尚未进树的纯表现实例，WeakRef 登记原模式；调用者在同世界且实例将挂该世界。实例退树或无效后注销。
- 实施审查补充 `unregister_release_instance(instance: Node) -> void`：仅撤回调用方自己登记的实例并恢复原模式，不回收实例、不解除任何暂停。指令/伙伴重绑不是世界销毁，表现组件只撤回自身token与登记；独立暂停协调器仍监听真实世界退出。
- `pause_state_changed(battle_paused: bool, presentation_allowed: bool)`。

- [x] **步骤1：写暂停边界失败测试。** GamePauseCoordinatorTest 写 `_test_duration_boundaries`、`_test_same_frame_merge`、`_test_pause_ownership_and_exit`、`_test_scope_and_duplicate_manager`。真实等待断言0/负/NaN/INF/大于0.3拒绝且战斗仍运行；0.15可恢复；同帧0.1+0.2只到首笔开始+0.2，重复身份不续时，后一帧迟到不延长；恢复前不能创建无限延续。显式暂停在强调到期后仍有效，释放显式 token 才恢复；进入前已 paused 的基线不擅自解除。owner 删除、整个世界 free/queue_free/重载、同树第二管理器、跨世界 owner 均有确定结果。
- [x] **步骤2：写真实实例时钟失败测试。** ReleaseAccentClockTest 写 `_test_release_runs_battle_stops`、`_test_explicit_pause_suspends_release`、`_test_native_autoplay_and_cleanup`。用真实 Root/Runner 释放，prepared 时登记一个含 AnimationPlayer 的纯场景和内存短 WAV。另放正在运动的 PAUSABLE CharacterBody3D 测试探针、正常飞行的原投射物，以及已进入6秒冷却的普通技能 cooldown_probe；先观察正常物理帧确实移动/减CD，不能使用 make_fixture 中已禁物理更新的actor或0CD连携作为冻结证据。在0.05秒真实等待后检查：

```gdscript
_expect(tree.paused, "battle paused during accent")
_expect(mover.global_position.is_equal_approx(mover_before), "moving battle actor stays frozen")
_expect(projectile.global_position.is_equal_approx(projectile_before), "ordinary projectile stays frozen")
_expect(visual_player.current_animation_position > visual_before, "release animation advances")
_expect(is_equal_approx(cooldown_probe.get_cooldown_remaining(), cooldown_before), "regular cooldown frozen")
```

SkillBase.get_cooldown_remaining() 已核对为既有接口，不加生产测试开关。恢复后再次验证运动/冷却推进，防止探针从未运行的伪通过。追加无脚本原生场景、autoplay=true/false、延迟 play、自然完成、技能/播放器 free 后视觉和声音仍独立；显式暂停时动画/声音/回收时间停止。自动测试播放状态与实际听感分开登记，GPU 粒子真实可见推进留任务六运行检查。

- [x] **步骤3：运行两个文件取得 RED。** 缺少所有权、不恢复、根模式设置太晚、动画跟着战斗停等须由运行断言暴露；测试超时使用独立 ALWAYS 看门狗恢复自身测试树并失败退出，不能留下 Godot 测试进程无限等待。
- [x] **步骤4：实现暂停所有权与合并。** 以 SceneTree 级唯一登记拒绝重复管理器，scope/owner 仅弱引用；使用单调真实时间和有限记录，恢复仅解除自身 token。记录首笔物理帧/首时刻，同帧取最大，迟到不从现在加时；至少一次正常物理推进再重新开放。显式暂停与进入前基线保持独立，不改 time_scale/物理服务器。持有中整世界退出恢复自己的暂停；协调器单独卸载但存在其他有效持有者按设计报告装配错误，禁止伪装正常恢复。
- [x] **步骤5：实现表现实例时钟。** prepared 回调在进树前注册原模式；正常/强调允许本次根继续，显式/外部暂停改为遵从暂停；不改变共享场景、单位或投射物。校验原生碰撞/物理节点及非 INHERIT 子模式，对不符合纯表现协议的资产给明确 warning、不递归修改业务脚本。解绑恢复原模式并清空弱登记，普通 Node 绑定 Tween 与实例 Timer 遵循同一模式。
- [x] **步骤6：修正既有相关 Timer 的暂停语义。** 指定的两处 UnitState、房间失败与 DefaultDeathEffect 延迟显式 process_always=false，其正常时长/取消路径保持不变；为 DefaultDeathEffect.lifetime 补中文说明。GamePauseCoordinator 自身截止独立运行，不把它改成战斗 Timer。扩展 UnitStateComponentTest、CombatRoomControllerTest 在实际暂停窗口中的断言。
- [x] **步骤7：运行 GREEN 与旧回归。** MCP 跑上述新2文件、UnitStateComponentTest、UnitDeathLifecycleTest、UnitDeathDissolveTest、UnitDeathAnimationIntegrationTest、GameFlow/Rooms/Tests/CombatRoomControllerTest、SkillReleasePresentationTest、MultiShotArcDeliveryTest、TrackingProjectileConcurrencyTest。恢复时声音只续播、不重放，投射物只续飞、不重发；token/模式和节点回到基线。
- [x] **步骤8：记录时间证据。** 记录暂停开始/结束的真实时间、动画位置/战斗位置与测得帧容差；不以手调更新函数、纯截图或 playing=true 替代所有时钟证明。此任务结束不对正式关卡装配管理器。

## 任务三：同一相机内的可替换临时构图

**Files:** 新建 CameraSkillFocusTest.gd；修改 CameraFollowController.gd、HitFeedbackBridge.gd，复用原 CameraFollowControllerTest.gd。只添加资源策略和临时构图，不新增 CameraRig 或相机实例。

**Interfaces — consumes:** 任务一 CameraEffectProfile.Phase、get_phase_duration/sample_rig_transform；任务二暂停状态。

**Interfaces — produces:** CameraFollowController 增加 class_name；`begin_presentation_focus(presentation_id: int, source: Node3D, profile: CameraEffectProfile) -> bool`、`end_presentation_focus(presentation_id: int) -> void`、`clear_presentation_focus() -> void`、`set_presentation_pause_source(source: GamePauseCoordinator) -> void`。

若下述真实回归证明缩放与旧震动争写，实施已确认的最小兼容接口 `set_feedback_offset(owner: Node, offset: Vector3) -> void`、`clear_feedback_offset(owner: Node) -> void`；偏移按来源 WeakRef 登记并在子相机最终位置中合成，无新 export。此接口仅解决复现的问题，不追加新震动设计。

- [x] **步骤1：写焦点与策略失败测试。** `_test_normal_target_is_not_rebound`、`_test_dynamic_return_and_short_cast`、`_test_zero_and_invalid_profile`、`_test_shared_profile_is_stateless`、`_test_pause_death_and_old_identity`。先记录玩家 resolved_target、Camera3D basis/FOV/档位，进入伙伴焦点后它们不变；移动玩家后返回其新构图；0进入/返回无需等待；空基础 profile/-1/非有限输出安全跳过；两台内存相机共用预设不互改进度；旧 ID 不能结束新焦点。
- [x] **步骤2：写缩放/震动共存失败测试并运行 RED。** `_test_zoom_shake_composition` 用真实桥与原 HitFeedbackProfile、最小合约攻击源，在两种处理顺序中反复缩放/抖动/返回，偏移结束后 Camera3D.position 精确回到基础+所选档位；暂停期间震动时间不耗尽。先保留能复现争写的断言；如果没有复现，不为统一接口擅自重构。运行新相机文件确认临时焦点接口/行为缺失的有效失败。
- [x] **步骤3：实现临时构图与暂停注入。** 拆分“正常期望构图计算”和“最终 Rig 写入”，target/FocusMode 不改为伙伴。进入从当前姿态出发，目标取伙伴实时位置+camera_offset，无伙伴速度预留；返回取正常目标实时构图。ENTER/RETURN 调用纯策略，时长0直接完成；非法结果回退正常跟随。保持原缩放与角度，snap/maximum_follow_distance 不抢临时写入；移除临时焦点后正常跟随不二次跳变。
- [x] **步骤4：实现已验证的反馈兼容。** HitFeedbackBridge 在 tree.paused 时不推进局部卡刀/震动；退出仍清理。若步骤2已 RED，桥对支持 set_feedback_offset 的相机 Rig 提交自身偏移，Rig统一合成；普通预览相机无接口时保留旧加减方式，切相机/删除 owner 不能残留上一台偏移。相机因暂停注入使用 ALWAYS 后仍拒绝暂停中的滚轮输入，卸载恢复原处理模式。
- [x] **步骤5：运行相机与旧系统 GREEN。** MCP 跑 UnitSystem/Tests/CameraSkillFocusTest.gd、CameraFollowControllerTest.gd、PlayerThreatFocusControllerTest.gd、PlayerTargetingComponentTest.gd，以及 SkillSystem/05-Tests/SkillReleasePresentationTest.gd；这些旧入口均已核对存在。场景静态 CameraRig/Camera3D 无变更；复制策略仅运行时存在，无新资源文件。
- [x] **步骤6：验收组 B。** 汇报真实暂停/特效推进与临时镜头返回证据、相机争写是否实际复现及所作最小修正。确认普通跟随/死亡回退/缩放测试通过，再进入协调与 UI；不在此时调整角色数值。

## 任务四：关卡表现协调、并发焦点与停顿内输入

**Files:** 新建 ChainSkillPresentationController.gd/.tscn、ChainSkillPresentationControllerTest.gd；修改 SquadChainCommandController.gd；消费任务一既有通知，不改技能动作优先级或费用。

**Interfaces — consumes:** 任务一 command_started/failed/released、prepared/started 与 scope 事实；任务二 GamePauseCoordinator；任务三临时镜头 API。

**Interfaces — produces:**

- 协调组件 export 只有 `command_source: SquadChainCommandController`、`camera_source: CameraFollowController`、`pause_source: GamePauseCoordinator`；场景第三项预填 `./PauseCoordinator`。
- SquadChainCommandController 新增 `set_presentation_pause_source(source: GamePauseCoordinator) -> void`、`is_feedback_suspended() -> bool`。有效同世界注入期间开启原指令节点的 ALWAYS 输入，不增加 Inspector 参数；null 恢复旧处理模式/暂停门禁。
- 协调组件无需新增玩家操作 API；内部表仅保留当前施法候选、已释放保持与未清理实例的身份。camera_source 或 pause_source 单通道失效分别跳过/告警，不阻断另外的可用通道。

- [x] **步骤1：写并发/身份失败测试。** `_test_nonpreemptive_camera_candidates`、`_test_out_of_order_roots`、`_test_scope_change_during_instance_prepare`、`_test_missing_channels_and_cast_watchdog`。实际受理 A再B、让B先释放，均扣本次费用一次；A合法释放不因ID较小被拒。A有镜头时B只候选，A结束后只选择仍在施法的B；B已释放则不补播，返回途中新候选直接接续。source删除/世界重绑拒绝旧回调；镜头watchdog只撤销镜头，不取消请求/退款。
- [x] **步骤2：写停顿内真实输入失败测试。** `_test_input_during_accent` 构造至少两个真实伙伴/Host与一个Focus，由实际 InputEventAction 投入既有 squad_chain_1—4；强调期间受理一次、预留增加，但 Host动作未开始且动画/投射物不推进；恢复后一次执行。缓存满不覆盖、echo/释放忽略；显式暂停或进入前外部暂停不缓存，关闭后不补发。断言费用不因这段输入重复提交。
- [x] **步骤3：运行 RED。** MCP 运行新文件，记录“无协调装配/不会选候选/暂停输入拒绝”等运行失败；不要为通过测试先把四伙伴动作串行化或把 Host 设为 ALWAYS。
- [x] **步骤4：创建协调组件与场景。** MCP 建根节点并挂脚本，固定子节点 PauseCoordinator挂任务二脚本，保存并验证场景UID；运行时只订阅 command_source，scope_changed 时先撤销旧焦点/登记/注入再绑定新世界。场景内只需策划选择原指令源和CameraRig；引用跨世界或同暂停源已被另一组件接管时告警并拒绝重复控制。
- [x] **步骤5：实现有限并发策略。** command_started 按开始顺序/同序request ID进入候选；当前镜头不被另一开始抢占，失败/离树撤销。prepared只给根连携的纯释放实例登记时钟；started只按本次身份申请强调，保留当前镜头直到合并强调真正结束。无强调配置直接返回/衔接，不等待特效 effect_finished；忽略子交付、命中与旧世界。施法看门狗使用effective_cast_time+内部1秒余量并按战斗时间累计，不导出，不因别人的停顿提前失效。
- [x] **步骤6：实现仅强调暂停的输入门禁。** _unhandled_input 在显式/外部暂停时直接忽略，不给暂停菜单制造红色游戏反馈；只有 is_release_accent_only 时允许原 submit_slot 走原预检/入队/预留。保留 _input_enabled、玩家资格和单伙伴缓存限制；_process 只刷新，不调用行为物理推进。is_feedback_suspended 在显式/外部暂停true，正常/仅强调false；null来源遵从原tree暂停。
- [x] **步骤7：运行 GREEN 与生命周期复查。** 新协调测试及 SquadChainCommandTransactionsTest、SquadChainCommandLifecycleTest、AllyChainCommandPriorityTest、ChainCommandTargetSelectionTest、SquadChainInputDisplayTest。prepared回调换世界、组件 free、技能 free、actor死亡、旧请求终结都不残留token/焦点/订阅；无法证明其他暂停持有者安全的卸载必须告警，不无条件resume。
- [x] **步骤8：记录协调检查点。** 明确四伙伴仍独立，没获得镜头不影响技能；示例证明暂停期间按下的指令已预留而未执行。场景创建仅为系统组件，不向 TestScene/TestCombatRoom 添加组件或单位。

## 任务五：原卡片的黄/绿/红状态与请求级保持

**Files:** 修改 SquadChainCommandDisplay.gd/.tscn、UnitSystem/Tests/SquadChainInputDisplayTest.gd；不新增 UI 脚本或外部 Theme 资源。

**Interfaces — consumes:** 任务一/四 command_accepted、command_started、command_released、command_failed、command_rejected、scope_changed、get_slot_status、is_feedback_suspended。

**Interfaces — produces:** 显示脚本仅新增 export `success_hold_seconds: float = 0.3`、`failure_hold_seconds: float = 0.3`，有限非负；原 command_source 不变。每卡增加 `StateBorder` Control/Panel覆盖层；Theme 变体命名 `ChainWaiting`、`ChainCasting`、`ChainFailed`，仅供显示替换。

- [x] **步骤1：写卡片实际行为失败测试。** 在原测试追加 `_test_card_state_transitions`、`_test_old_deadline_cannot_clear_new_state`、`_test_pending_confirmation_and_rejection`、`_test_feedback_pause_and_rebind`。用真实请求观察边框样式而非源码搜索：受理黄、确认开始绿、释放后0.3秒清；失败/拒绝红0.3秒后恢复有效请求。释放强调0.15秒算入0.3秒，不额外延到0.45；显式暂停挂起保持倒数。

```gdscript
_expect(border.theme_type_variation == &"ChainWaiting", "accepted feedback immediate")
# 实际确认动作后：
_expect(border.theme_type_variation == &"ChainCasting", "confirmed action is green")
# 实际释放后，等待累计 >=0.3 秒表现时间、加测得的渲染帧容差：
_expect(not border.visible, "success tail expires independently of projectile flight")
```

不依赖固定9帧或在已暂停的节点中等待其自己的 _process；断言保持时间0与非法值安全降级。旧已释放投射物最终失败不产生红框/退款；新请求先开始后旧截止到达仍保留新状态。

- [x] **步骤2：运行原文件取得新断言 RED。** 原输入映射/四槽/纯显示断言继续保留，不能以删除旧测试替换为颜色存在检查。
- [x] **步骤3：通过 MCP 编辑卡片场景。** 四卡各静态 StateBorder，全矩形透明背景，仅有约2像素圆角边框；Theme内三色默认黄/绿/红（临时样式，可在资源编辑器替换），不在脚本写死颜色。保持所有 Control 的mouse_filter=IGNORE与focus_mode=NONE；不让新覆盖层改变原布局或抢输入。可用性灰显移到卡片内容，不调暗边框。
- [x] **步骤4：实现请求级显示。** 受理时由request.caster_instance_id与当前固定四伙伴映射记录ID/槽，不长期保留Request；开始通知直接带槽/表现身份。主状态按“活动施法绿 > 未开始请求黄 > 成功保留绿 > 无”，短暂红提示优先，到期重新取当前事实；施放中再受理只给“已缓存”文字一次黄色确认，不抢绿色主框。保留真实 can_submit 灰显，不把等待当CD。
- [x] **步骤5：实现时间与重绑清理。** UI自身ALWAYS但不收输入；用任务四is_feedback_suspended挂起显式暂停的倒数，忽略长暂停期间真实时间差。每条计时带request ID/世代，旧任务不得清新框；scope解绑/command_source替换清旧记录。初始化只恢复当前活动/缓存，不补播过期结果；成功0.3秒到期后即使角色仍released收尾也不重新亮绿。
- [x] **步骤6：运行 GREEN。** MCP跑完整SquadChainInputDisplayTest和协调测试，核对四卡共享只读StyleBox无串色、灰显边框仍明确、红提示不取消另一缓存、失败记录生命周期后不永久增长。原未装表现预览仍拒绝全局暂停输入，保留其原断言。
- [x] **步骤7：验收组 C。** 展示/记录受理、施法、成功保留、失败和缓存五种状态的实际UI数据；相同事实同时驱动镜头与UI，但二者可独立删除/替换。此处仍不称完整内容已经配置，进入任务六补可见预览。

## 任务六：正式预设、临时闪光、独立预览与完整交付

**Files:** 创建清单中的2个.tres、临时闪光与两个预览共3个.tscn；修改四个Combo_技能源场景的两项资产引用，补既有UID/释放/装配测试与配置文档。

**Interfaces — consumes:** 任务一至五已通过的全部契约；复用现有 SkillReleasePresentationPreview.gd 和 SquadChainCommandPreview.gd，不新增预览脚本。

- [x] **步骤1：写内容/装配/UID失败测试。** 在 SkillPresentationLifecycleTest 追加 `_test_formal_assets_and_alias_migration`，ReleaseAccentClockTest 追加 `_test_accent_flash_scene`，ChainSkillPresentationControllerTest 追加 `_test_preview_assembly_and_stress`。两个预设 UID 不为INVALID、类型对应、数值正确；所有技能保留原RuntimeEffects/两个普通槽与参数；四个Combo只新增共享引用。临时闪光无碰撞/伤害/技能脚本；两个预览根继承/复用指定脚本和静态阵容，新闪光只覆盖新预览，不改源治疗/盾击视觉。
- [x] **步骤2：运行相关测试取得内容缺失 RED。** 不用提前手写资源文件代替 Godot 资源保存，也不为了给现有预览加特效而修改TestCombatRoom。
- [x] **步骤3：正式创建两个共享资源并配置四技能。** MCP/ResourceSaver 保存到文件表路径，注册类型/UID，使用 Godot 编辑并保存四个Combo_根 `camera_effect_profile` 与 `release_accent_profile`。前后比较伤害/治疗、费用、施法、CD、目标、Delivery、飞行/命中特效及原释放视觉完全不变；两个普通技能不动。
- [x] **步骤4：创建无专用脚本的临时释放场景。** MCP建Node3D根、VisualRoot（小球/圆环Mesh与可选单次粒子）、AnimationPlayer、CleanupTimer；初始帧已有可见闪光，时间轴约0.15秒扩散/淡出，Timer约0.18秒一次性自回收并通过原生连接queue_free。子节点INHERIT，无方法轨道伤害/暂停调用。颜色、尺寸、材质、动画在场景内编辑，不导出新技能参数；其时长不反过来控制停顿。
- [x] **步骤5：创建并保存两个独立预览。** ReleaseAccentFlashPreview继承原工具预览，预选visual_scene为新闪光、锚点ACTION_ORIGIN，音频/镜头工具字段仍空，复用原按钮和内存测试音。ChainSkillPresentationPreview继承原阶段二预览，只加已保存的关卡表现组件，command_source指原指令源、camera_source指原CameraRig，pause_source已预填子节点；四技能在此新预览实例中覆盖中性闪光和ACTION_ORIGIN。通过编辑器可见的继承属性完成，不运行时生成单位或偷改原源视觉。
- [x] **步骤6：实际运行与Inspector验证。** MCP运行新整合预览，按既有1—4测试四伙伴、同角色重复、忙碌等待、失败、停顿中下一次按键、多伙伴并发与滚轮档位。以日志身份/费用/真实时点对应可见镜头/边框；以原生动画位置、粒子画面与声音状态证明特效在0.15秒内推进；确认恢复后投射物只飞一次。检查0.3秒清框、动态返回与暂停正确解除。无真实收音能力时明确实际音量/听感待用户，不以截图代替试听。
- [x] **步骤7：资源与类型审计。** 每个新场景/正式资源 Godot保存后验证UID；两个.tres脚本类型和属性hint正确，实际Inspector的Quick Load按对应类型可找到预设。若工具无法直接操作该界面，明确留下人工检索项，不把类名登记等同于已通过Quick Load；临时外部兼容测试资源按规则清理。运行ResourceUidAuditTest并扩展新正式资源契约。
- [x] **步骤8：压力、重载和完整回归。** 新整合测试至少100次根连携及10次世界重载：正常动作/交付推进，暂停恢复，等待原生表现自然回收后token、候选、弱登记、UI记录回到基线；无永久历史集合或重复监听。枚举所有当时活跃SceneTree脚本逐文件MCP运行，记录exit/PASS/error；不能只跑5个新增测试。RangedAttackPipelineTest是RefCounted，单独collect_failures应为[]，不free它。新文件无参数跑全部用例；若为定位加分组，最终必须再跑完整入口。
- [x] **步骤9：独立审查与验收组 D。** 推荐当前会话逐项实施完后由一名独立只读审查者检查本功能差异及设计/计划覆盖；修复实证问题并重新运行相关及完整回归，不自动提交。git diff --check通过；按开始hash检查project.godot、TestScene/TestCombatRoom、普通技能源场景无本次意外改动。交付实际新增数量、Editor错误、未通过/未验证项与预览操作，文档更新严格对应证据。

## 4. 文档、覆盖自检与实施交接

任务六更新既有三份技能配置指南、CurrentProgressReport、设计/计划状态，并新增 `Docs/Superpowers/Plans/2026-10-14-chain-skill-presentation-validation.md` 汇总逐项结果。设计/计划/验收为Markdown，不计入10个.gd/4场景/2资源，也不额外创建同内容教程。

| 设计范围 | 归属任务与验收 |
| --- | --- |
| 开放资产、单槽迁移、身份与事实边界（设计1—6、12） | 一；六资源/Inspector审计 |
| 临时镜头、缩放/震动、短技能/动态返回（设计7） | 三；四并发；六运行 |
| 暂停所有权、时间、旧计时器（设计8） | 二；四输入/合并释放；六重载 |
| 纯释放资产独立播放/回收（设计9） | 一通知；二时钟；六临时资产与运行 |
| 三色、缓存、拒绝、0.3秒与旧计时（设计10） | 五，保留原输入及纯显示断言 |
| 并发非抢占与停顿内输入（设计11） | 四，真实事件与费用夹具 |
| 文件数量、强类型/UID、预览及人类配置（设计13） | 六，数量与场景树审核 |
| 压力、回归、清理与范围（设计14—16） | 全任务各自测试，六全量与独立审查 |

计划自检已完成：接口名字/参数在消费任务中一致，原 prepare_release 确认为6参数并追加可空第7项；任务一不提前引用任务二尚未创建的暂停类；两个测试查询方法和所列旧回归入口已核对存在；每个Review Focus均有指定测试；暂停测试包含暂停前后的运行正对照，不使用0CD/已禁处理的探针证明冻结；没有把0.15停顿等同整个演出时间轴，没有把无资源或镜头竞争改成技能失败。上述仅为文档自检，不是代码或测试通过记录；实施发现设计无法满足时先报告，不以临时特殊规则隐藏。

**执行建议：Native，即由当前会话按任务一至六顺序实施，A/B/C/D四组验证后推进，最后一次独立审查。** 原因是这些任务紧密共享SkillBase、Host和同一接受回调，连续维护可减少接口分叉；如用户选择子代理方式，先按对应技能读取本计划和已确认设计，再逐任务独立实施/审查，不把共享文件任务并行写入同一目录。

执行已完成，按用户授权先备份提交/上传再实施；实施后的改动保留本地待验收，未自动再次提交或上传。正式关卡未自动装配新组件，先在独立预览试玩。
