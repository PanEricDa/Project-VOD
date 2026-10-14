# 技能成功释放表现 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 成功施放时统一播放所选视觉和音效，并发出强类型镜头表现请求；根节点仅新增两个资产字段，不改变战斗结果。

**Architecture:** 在 SkillBase 已有 RuntimeEffects 节点挂通用播放器。播放器先生成本次资产/位置快照，再在交付接受通知和既有费用通知之后播放；释放实例独立于技能生命周期。镜头只做 Resource 类型与请求出口，不实现移动。

**Tech Stack:** Godot 4.7、GDScript、PackedScene、AudioStreamPlayer3D、Resource、现有 SkillBase/SkillDeliveryRunner、SceneTree headless 契约测试；编辑优先 Godot MCP Pro。

**Spec:** [已确认的正式设计](../Specs/2026-10-14-skill-release-presentation-design.md)。执行者先完整阅读设计与 AGENTS.md，再按本文逐项推进。

> 日期：2026-10-14。状态：用户确认后已在当前会话实施；自动化验收129/129通过，听感与两项测试覆盖补充待后续确认。见[验收记录](2026-10-14-skill-release-presentation-validation.md)。
> 代码基线：HEAD `0a2b21edbb1dc5de18b5692c0f9feffa985ca172` 加当前工作目录已有未提交内容，不从 HEAD 单独重建或覆盖当前目录。
> 本计划的任务一至四只指本次释放表现扩展，不是爆发连携的阶段一至四；连携阶段三、四仍暂停。

## Global Constraints

- “根节点实际新增两个 export。”字段固定为 release_audio_stream: AudioStream、release_camera_effect: CameraEffectProfile，默认均 null。
- “保留字段名称，避免现有场景资产引用丢失。”保留 cast_effect_scene、release_effect_scene、release_effect_anchor、cancel_effect_scene。
- “成功施放是‘交付已经被接受’，不是所有效果最终成功或最终命中。”沿用 delivery_started 边界，不改 release_started 含义。
- “根节点实际新增两个 export。每个通道独立可空，不增加总开关、播放器 NodePath、每技能音量/随机音调、表现延迟、镜头优先级或额外颜色参数。”
- “全部资源为空时不实例化视觉或声音，不创建计时器，不广播空镜头请求。”
- “本期不改 CameraFollowController、HitFeedbackBridge，不新增 CameraRig 节点或镜头仲裁。”
- 视觉异常驻留看门狗固定内部 30 秒；未知音频时长保护 30 秒，有限音频时长保护为 get_length() 加内部 1 秒；均不成为 Inspector 配置。
- RuntimeEffects 已有节点挂脚本，不增加基础技能节点；不新增 SkillEffectBase 效果、表现组合资源、全局 Autoload、技能专用脚本或正式内容资产。
- 所有 export、公开方法/信号及跨模块输入紧邻中文说明；技能根节点是唯一正式配置入口，预览参数只服务工具。
- 不自动改 TestScene/TestCombatRoom 的单位或配置、不改正式技能数值和资产选择、不改 project.godot/InputMap/总线布局。
- 优先 MCP 编辑/保存；回退直接编辑须说明原因。Godot 生成脚本 UID，场景经编辑器保存；若实际新增外部资源，正式保存并验证 UID、类型和 Quick Load。
- 保留已有未提交内容。开始执行前确认目标编辑器缓冲区和场景无冲突；不强制覆盖用户未保存编辑，不清空输出以隐藏错误。
- 本次仅编写计划，不执行任务、建工作树、提交或上传。后续每个任务完成后保留独立检查点；Git 提交仅在用户另行授权时执行，禁止 git add . 混入原有工作。

## Review Focus

1. 接受信号监听者同步改目标、换资产、清空上下文：本次表现应使用通知前准备的快照，不读取下一次请求。测试归任务三 `_test_acceptance_reentry_snapshot`。
2. 非单位变换的世界父节点/附着单位，以及特效在 ready 立即播放：特效第一次可观察位置就应正确，不在世界原点闪现；脚底朝向不继承武器俯仰。测试归任务一 `_test_ready_pose_and_anchor_space`。
3. 子技能或播放器立即销毁、延迟自动播放和完成：已释放的视觉/声音仍播完并回收，不调用失效宿主。测试归任务一/二 `_test_visual_outlives_player`、`_test_audio_outlives_player`，任务三 `_test_trigger_outlives_skill`。
4. 循环音频、无时长的流、多个技能共用同一音频资源：只影响音频通道，不改共享资源，不永久积累播放器。测试归任务二 `_test_audio_loop_and_watchdog`、`_test_audio_overlap_resource_isolation`。
5. 缺少 RuntimeEffects 脚本、错误视觉根类型、镜头无订阅者、请求后卸载世界：跳过/诊断表现，合法技能仍成功，且无孤儿节点或后续回调异常。测试归任务三 `_test_optional_channels_and_world_exit`。

## 文件与职责锁定

| 文件 | 操作 | 任务 | 职责 |
|---|---|---|---|
| SkillSystem/01-Core/SkillReleasePresentationPlayer.gd | 新建 | 一、二 | 临时快照、视觉/声音独立播放、镜头请求 |
| Effects/Camera/CameraEffectProfile.gd | 新建 | 一 | 无运行状态/具体参数的镜头 Resource 基类 |
| SkillSystem/05-Tests/SkillReleasePresentationTest.gd | 新建 | 一至四 | 一个独立 SceneTree 测试入口，逐步补充用例 |
| SkillSystem/01-Core/SkillBase.gd | 修改 | 三 | 两个资产字段、根信号、接受边界、清理分离 |
| SkillSystem/01-Core/SkillBase.tscn | 修改 | 三 | 在已有 RuntimeEffects 挂播放器脚本 |
| SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd | 修改 | 三 | 保留既有断言，补字段与基础装配契约 |
| SkillSystem/05-Tests/CasterFeetPresentationFacingTest.gd | 必要时修改 | 三 | 保留实际释放的脚底定位/朝向断言，不改为私有方法测试 |
| Scenes/Previews/SkillReleasePresentationPreview.gd | 新建 | 四 | 资产/锚点工具配置、UI 操作和请求观察 |
| Scenes/Previews/SkillReleasePresentationPreview.tscn | 新建 | 四 | 独立可运行预览，原生节点/简单几何体 |
| Docs/CurrentProgressReport.md、本文、对应设计 | 文档维护 | 四/本次 | 配置指南、实施状态及真实验证结果 |

目标新增合计 4 个 .gd、1 个 .tscn、0 个正式 .tres/.res。基础场景仅修改，不另建播放器场景；无须逐技能添加节点。预览/测试夹具在内存创建，不计入正式内容资产。额外必要变更先解释用途和交付数量，不默默扩展。

## 共用接口与测试入口

### 播放器接口

`class_name SkillReleasePresentationPlayer`，继承 Node，没有 export。固定公开接口：

```gdscript
prepare_release(context: SkillContext, action_transform: Transform3D,
    visual_scene: PackedScene, anchor: int, audio_stream: AudioStream,
    camera_profile: CameraEffectProfile) -> Dictionary
play_release(snapshot: Dictionary) -> void
signal camera_effect_requested(profile: CameraEffectProfile,
    source: Node3D, target: Node3D, world_transform: Transform3D)
```

anchor 使用唯一的 SkillBase.PresentationAnchor，不复制第二套可维护枚举。prepare 只读输入且不播放，所有空资源返回空快照；invalid context、非有限变换或无合法世界父节点也返回空。play 对空快照无操作。恰好一次由 SkillBase 接受边界负责，播放器允许预览主动重复播放。

快照是每次新 Dictionary，键固定为 visual_scene、audio_stream、camera_profile、world_transform、world_parent_ref、attach_parent_ref、source_ref、target_ref。资产是配置引用；world_transform 是值；节点使用 WeakRef/空值，不保存整个 SkillContext、command_request 或技能/播放器引用。附着意图为空表示世界播放；附着对象失效时使用世界快照回退，无合法世界父节点时不创建实例。

信号在播放器与 SkillBase 根节点上签名一致，同步转发一次；发送前把无效 source/target 转为 null。只传镜头配置与空间信息，不直接找相机，不新增全局信号总线。

### 内部回收接口

播放器内部 `_arm_watchdog(instance: Node, duration_seconds: float) -> void`：给实例添加名为 ReleaseWatchdog 的一次性 Timer。timer.timeout 直接绑定实例.queue_free，不捕获 SkillBase/播放组件；继承暂停处理模式。只在创建真实表现实例时调用，无资产不创建 Timer。

音频实例命名 ReleaseAudioVoice。finished 直接绑定自身.queue_free；保护 Timer 也在声音实例下。记录节点名称用于现场观察，不暴露配置，不增生产测试计数器。

### 测试夹具与分组

新测试继承 SceneTree，支持 `--group visual|audio|release|preview`，无参数运行已实现的全部用例；未知组明确失败，不能静默跳过。每任务结束执行该组及当前全套；最终全部四组均存在。

测试内定义 RecordingVisual/RecordingEffect 等夹具，不给生产类增加测试方法。`_make_fixture() -> Dictionary` 提供 world、source、target、context、action_transform、visual_scene、profile、trace；source/target 使用真实 UnitBase 基础场景，异队伍、位置固定，避免依赖自动 AI 行动。`_prepare_fixture(f: Dictionary, anchor: int) -> Dictionary` 调用上述唯一 prepare 接口；`_add_skill(f: Dictionary, direct: bool) -> SkillBase` 实例化真实基础技能，配置合法瞬发交付和记录效果，direct 决定真实激活路径。

断言片段中的 f/player/snapshot/trace 等均由这些夹具或当条测试设置；不是新生产 API。PackedScene 夹具在内存 pack，测试声音为有限短 AudioStreamWAV；声音内容仅供测试，不写正式资产。记录视觉在 ready/play 把位置和次数写到测试记录，不 mock 接受信号。

每次新测试先验证缺少行为而失败；新增类尚不存在时用受控加载和缺失接口断言，避免因 parser 未识别类而把语法错误当 RED。默认输出 `SkillReleasePresentationTest: PASS`，失败退出 1，成功退出 0。

### 执行与判断命令

优先 MCP：`run_headless_script({script_path: "res://SkillSystem/05-Tests/SkillReleasePresentationTest.gd", args: ["--group", "visual"], timeout_sec: 60})`；audio/release/preview 同理。全套省略 args。

工具不适用时的等价 PowerShell（不是要求现在执行）：

```powershell
& 'G:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe' --headless --path 'G:/Godot/ProjectVOD' --script res://SkillSystem/05-Tests/SkillReleasePresentationTest.gd -- --group visual
```

GREEN 必须退出 0、有 PASS、无未预期 ERROR/SCRIPT ERROR 和超时；不能只相信工具 success。预期配置诊断使用 warning，不故意制造引擎类型错误来充当测试。缺失类的 RED 与运行时错误区别记录。

---

## 任务一：位置快照、视觉播放及镜头配置基类

**Files:** 新建播放器、CameraEffectProfile 和测试；不改 SkillBase/模板/正式技能。

**Interfaces:** 消费现有 SkillContext、PresentationAnchor 和视觉资产协议；产出完整 prepare_release、视觉 play_release、镜头请求以及回收接口。音频分支在任务二补齐，此检查点不宣称完整功能。

- [x] **步骤1：写 visual 组失败测试。** 用例 `_test_prepare_is_read_only`、`_test_ready_pose_and_anchor_space`、`_test_visual_outlives_player`、`_test_profile_request_optional`、`_test_empty_and_invalid_visual`。关键断言：

```gdscript
var snapshot = _prepare_fixture(f, SkillBase.PresentationAnchor.ACTION_ORIGIN)
_expect(f.world.get_child_count() == before, "prepare does not spawn")
_expect(trace.is_empty(), "prepare does not emit requests")
player.play_release(snapshot)
_expect(trace == ["visual", "camera"], "one visual and one nonempty camera request")
player.free()
_expect(is_instance_valid(visual), "release visual outlives player")
```

分别设置 action=(2,1,3)、source=(2,0,3)、target=(7,0,3)、target_position=(9,0,4)，手工断言四锚点和脚底朝向 +X。RESOLVED_TARGET 附着视觉 local Basis 单位；CASTER_FEET 的世界 Basis 必须保持指向目标的水平朝向。世界父节点旋转/平移/缩放时 ready 记录的位置仍正确。重复 prepare 后改 context 不改旧快照，空资产无计时器；没有订阅者也能播放。

- [x] **步骤2：运行 visual 组，记录 RED 原因。** 应因播放器/快照行为缺失失败，不以 fixture 拼写或 parser 错误通过门槛。
- [x] **步骤3：创建两个生产脚本并实现接口。** CameraEffectProfile 为 class_name Resource，无 export/运行状态；播放器按现有四锚点语义准备快照，迁移朝向算法，不读取职业/AI。视觉正确定位后再进入 ready/播放；autoplay 资产不另调 play，非 autoplay 且提供 play 的资产调用一次；原生 one-shot 粒子允许自身启动。绑定 effect_finished 到自身回收，已有自释放资产同样兼容；30 秒 watchdog 独立存在。
- [ ] **步骤4：验证自然结束与异常回收。** 用自然结束资产观察消失；测试对 watchdog 发 timeout 验证回收回调，同时检查配置为 30 秒，不为单测真的等待 30 秒。暂停观察短时间无提前回收，恢复后继续；world.free 后无 orphan。错误根节点跳过视觉而仍发有效镜头请求。
- [x] **步骤5：运行 visual 组及当前新测试全套。** 再运行 CasterFeetPresentationFacingTest、SkillTemplateLayoutTest，确认尚未接入时已有功能不变。查所有新增 export/公开输入中文说明，不把快照变成 .tres。
- [x] **步骤6：review 检查点。** 重点检视 ready 定位、autoplay 不重复、弱引用、30 秒保护回调归属。记录文件差异和结果；授权提交时仅暂存本任务路径与其 .gd.uid。

## 任务二：音频通道、重叠与独立回收

**Files:** 修改播放器和同一测试脚本；无额外生产脚本、场景或声音资产。

**Interfaces:** 消费任务一快照与 `_arm_watchdog`。新增私有 `_play_audio(snapshot: Dictionary) -> void`、`_is_looping_audio(stream: AudioStream) -> bool`、`_get_audio_watchdog_seconds(stream: AudioStream) -> float`；唯一公开播放入口保持不变。

- [x] **步骤1：写 audio 组失败测试。** `_test_audio_outlives_player`、`_test_audio_overlap_resource_isolation`、`_test_audio_loop_and_watchdog`、`_test_audio_pause_and_world_exit`。使用 0.1 秒内存 WAV 和循环 WAV；核心断言：

```gdscript
player.play_release(snapshot)
_expect(voices.size() == 1 and voices[0].playing, "audio starts at release")
_expect(voices[0].global_position.is_equal_approx(Vector3(2, 1, 3)), "audio uses snapshot")
player.free()
_expect(is_instance_valid(voices[0]), "audio does not belong to skill player")
await create_timer(0.25).timeout
_expect(not is_instance_valid(voices[0]), "finite sound finishes and frees")
```

两个同时播放实例的数量应为 2，共用 AudioStream 的循环/音量配置不变。循环流无声音实例但视觉/镜头照常；有限时长保护为 0.1+1.0 秒，未知长度为 30 秒，非有限长度也用安全回退。

- [x] **步骤2：运行 audio 组，确认因尚无音频行为而 RED。** 保留 visual 组通过，不把 headless 无法听见当作声音失败的唯一证据。
- [x] **步骤3：实现 AudioStreamPlayer3D 通道。** 绑定 finished/watchdog 到声音自身；世界父节点、释放位置快照、默认全向与声音原速。存在 SFX 总线选 SFX，否则 Master；不创建/更改总线布局。
- [x] **步骤4：处理循环与复合资源。** 识别 WAV、OggVorbis、MP3 可用的循环配置；AudioStreamRandomizer 检查其候选流（防循环引用），循环候选导致本通道拒绝而非偷偷改共享资产。未知流靠时长与回收保护，不读取技能类型推断声音。
- [x] **步骤5：运行 audio、visual 和当前全套。** 测试中可临时增删 AudioServer 测试总线，不论断言成功/失败均在统一收尾中恢复，不写正式布局；退出 world/目标后没有遗留音频节点。声音不要求随 time_scale 改 pitch，暂停/恢复须符合播放器继承处理模式。
- [x] **步骤6：review 检查点。** 验证重叠、循环识别、复合资源、回调独立性、无 export 增长。记录差异和结果；授权提交时只含本任务文件。

## 任务三：接入真实 SkillBase 成功释放边界

**Files:** 修改 SkillBase.gd/.tscn、SingleSceneSkillBaseTest.gd 和新测试；必要时维护 CasterFeetPresentationFacingTest 的夹具清理，不弱化朝向断言。

**Interfaces:** RuntimeEffects 消费任务一/二完整播放器。根节点新增两项 export 和同签名 camera_effect_requested；新增私有 `_on_camera_effect_requested(profile: CameraEffectProfile, source: Node3D, target: Node3D, world_transform: Transform3D) -> void` 转发，不新增激活入口或成功信号。

- [x] **步骤1：写 release 组失败测试。** `_test_root_configuration_and_inheritance`、`_test_success_boundary_and_failure`、`_test_acceptance_reentry_snapshot`、`_test_trigger_outlives_skill`、`_test_volley_once_and_old_delivery`、`_test_optional_channels_and_world_exit`。以真实基础技能/Runner 激活和释放，不直接 emit delivery_started 替代。

```gdscript
_expect(skill.activate(context), "legal action request accepted")
_expect(trace.is_empty(), "queued request has no release presentation")
_expect(skill.confirm_action_started(action_transform), "action starts")
_expect(trace.is_empty(), "casting is not successful release")
_expect(skill.release_action(action_transform), "delivery accepted")
_expect(trace == ["accepted", "visual", "camera", "effect"], "acceptance before presentation before effect")
```

RecordingVisual 在 ready 记 visual，镜头根信号记 camera，RecordingEffect.apply 记 effect。包含合法直接触发、真实 CHAIN Host/费用夹具；CHAIN 测试在表现开始时费用已提交，失败前费用未提交。技能启动失败 trace 中无 visual/camera/audio；接受后 Effect 返回 false 仍只播放一次，费用不退。

- [x] **步骤2：运行 release 组取得 RED。** 缺字段/RuntimeEffects 装配、启动失败仍生成原有视觉、子实例清理截断等均须由行为断言复现；语法错误先修测试。
- [x] **步骤3：增加根字段、分组和装配。** 字段名/类型/默认按 Global Constraints；Presentation 下 Cast/Release/Cancel 分组。MCP 修改基础场景已有 RuntimeEffects 脚本并编辑器保存。ready 连接镜头转发，缺装配时 warning/跳过表现，不改变 gameplay；资源提示限定 CameraEffectProfile/AudioStream，保持根节点唯一配置入口。
- [x] **步骤4：移动释放调用并保存本次数据。** `_commit_release` 移除原成功视觉调用，保留停止蓄力、release_started 和费用/授权顺序。在真实 `_on_runner_delivery_started` 身份/接受去重后、delivery_started.emit 前调用 prepare_release；emit 后重新检查组件/世界，play 同一快照。不能调用等返回后才播放的路径。
- [x] **步骤5：分离清理并迁移旧私有视觉方法。** Release 的锚点/附着功能移入播放器，从 `_runtime_effect_instances` 的技能退出清理中移出；保留 Cast/Cancel 所需方法。正常下一轮激活不取消旧视觉/声音；清除临时释放数据时不能取消已创建实例，不长期保存最后一个 context。
- [ ] **步骤6：补重入与在途测试。** 接受监听者移动/删除 target、修改 context.target_position/技能资产，再验证本次位置、资产不变，下一次使用新配置；监听者 unload world 时不再创建实例。两次并发投射物各一次表现，旧 miss/failure 不重播；连射3箭、齐射3目标也仅1次根表现。fixture 借用现有弧线/追踪测试的内存项目物契约，不给生产代码加测试开关。
- [x] **步骤7：验证继承和实际退出。** 枚举当前 SkillSystem/00-Skills 的所有场景，确认每个 RuntimeEffects 都继承播放器，原视觉路径/锚点、冷却/伤害/治疗值与实施前快照一致；不硬编码总数14作为永久要求。成功 DIRECT_TRIGGER 后立即 free 技能，表现继续；真正 world.free 后全清。空资源不产生节点、镜头请求，缺播放器也不阻断合法交付。
- [x] **步骤8：运行 release 组、全套及重点回归。** 必跑 SingleSceneSkillBaseTest、SingleSceneDeliveryRunnerTest、CasterFeetPresentationFacingTest、TriggeredSkillActivationTest、TrackingProjectileConcurrencyTest、MultiShotArcDeliveryTest、MarkedTargetVolleyTest、SquadChainCommandLifecycleTest、SquadChainCommandTransactionsTest、UnitHealthFrameSkillNoticeTest、SkillTypeNoticeTest、ResourceUidAuditTest。逐项要求退出0/PASS，无未预期错误。
- [x] **步骤9：review 检查点。** 不改变接收/收费契约、不改 AI，不污染成功信号语义，快照在通知前准备、当前状态不被旧会话覆盖、旧视觉引用不遗留。授权提交时仅包括本任务路径及必要夹具修改。

## 任务四：独立 Preview、全量回归和交付说明

**Files:** 新建 Preview.gd/.tscn；在同一测试脚本补 preview 组；更新当前进度及本设计/计划状态。不创建具体技能表现资产。

**Interfaces:** Preview 直接使用 prepare_release/play_release，不伪称完整技能；公开 `play_preview() -> void`，PlayButton.pressed 连接它。TestChannelsButton 连接私有 `_play_test_channels() -> void`，只在本次调用使用内存音频/镜头配置，不修改已选资产字段。正式成功/失败仍由任务三的真实技能测试证明。

- [x] **步骤1：写 preview 组失败测试。** `_test_preview_load_and_configuration`、`_test_preview_repeat_and_cleanup`。验证场景可加载、资产工具配置强类型、单次测试按钮操作恰好1次声音/请求、重复不多重订阅、退出清理；普通播放在全部资源为空时请求计数为0。比较真实播放器 camera_effect_requested 收到的次数与 RequestCountLabel 显示的计数，二者不一致即失败。保存 Camera3D.global_transform，操作后仍相同；不新增全局输入动作。
- [x] **步骤2：运行 preview 组确认场景/行为缺失的 RED。** 不为任务四先改正式测试关卡来制造可见结果。
- [x] **步骤3：通过 MCP 创建并保存场景。** Node3D 根，固定子节点 SourceMarker/TargetMarker（Marker3D，分别在(-2,0,0)/(2,0,0)，附简单可视几何）、WorldPlayback（Node3D）、RuntimeEffects（播放器）、Camera3D（独立工具相机）、CanvasLayer/Panel/VBox（包含 PlayButton、TestChannelsButton、StatusLabel、RequestCountLabel）。预览根暴露 visual_scene: PackedScene、anchor: SkillBase.PresentationAnchor、audio_stream: AudioStream、camera_profile: CameraEffectProfile 四项工具配置，视觉/声音/镜头默认null，anchor默认ACTION_ORIGIN；不复制到正式技能，也不提交默认选择某个现有技能美术。发射变换固定为SourceMarker世界位置加向上1米；target_position取TargetMarker位置。工具上下文的delivery_parent为WorldPlayback。所有新增工具export/API同样有中文说明。
- [x] **步骤4：增加内存验证模式。** TestChannelsButton明确标为“测试音/镜头请求（非正式内容）”，以0.15秒、440Hz、22050Hz采样率的内存单声道16bit WAV/CameraEffectProfile 验证可听声音与请求；生成方法只在 Preview/Test，不出现在播放器生产类。RequestCountLabel显示“镜头请求：N（仅接口，无镜头移动）”，N只由真实请求回调递增。无需外部 .tres、音频文件或额外 export 开关。
- [ ] **步骤5：运行真实 UI 检查。** 通过 MCP 打开 Preview，必要时 Computer Use 操作按钮。临时选择已有 GuardianTaunt 视觉，确认四锚点、正确位置、重复播放和声音重叠；检查前后场景改动，临时验证参数不保存为正式默认。确认相机位置/变换未被请求改变；实际试听由可用音频能力或用户确认，截图和 headless playing 状态不能当试听证明。
- [x] **步骤6：运行新全套和完整活跃回归。** 枚举 `rg -l '^extends SceneTree' -g '*Test.gd' -g '!addons/**' -g '!Archive/**'`，每个脚本独立运行。记录每条路径、退出码、PASS/错误、超时，不用前次128项数量替代当次枚举。RangedAttackPipelineTest 为 RefCounted，单独执行 collect_failures 并确认 []，不可 free RefCounted。
- [x] **步骤7：编辑器与资源验收。** 检查新脚本类型登记、真实根 Inspector 的两个新槽、中文提示、Quick Load 类型过滤、现有资产引用有效；新 Preview 场景 UID 非 INVALID_ID。镜头基类注册不等于外部资源 UID；如果测试创建临时外部资源，ResourceSaver 正式保存、验证 UID/类型、检索后清理，禁止遗留正式样例。
- [x] **步骤8：压力/退出与差异检查。** 独立内存世界连续100次真实 DIRECT_TRIGGER，等待短表现实例结束后节点计数回到基线；10次世界创建/销毁，无旧镜头监听/孤儿/错误，普通费用与施放结果不变。跑 git diff --check，并检查 TestScene/TestCombatRoom、project.godot、CameraFollowController、HitFeedbackBridge 相对实施开始未变；已有未提交改动不算本次新增差异。
- [x] **步骤9：整体 review 与文档。** 核对 Spec 的13条验收；记录能播放/未订阅镜头/未提供正式内容的真实边界，说明具体配置入口与复用。Docs/CurrentProgressReport 新增日期段，不把本任务完成写成连携阶段三/四完成。本文逐项勾选，仅实际验证完成后更新状态；未实际试听则明确留下待用户确认。
- [x] **步骤10：交付检查点。** 汇报文件清单与4个新脚本/1个新场景/0正式资源的实际计数、测试结果和 Preview 操作。只有用户另外要求版本记录时才本地提交/上传，且先确认要记录的既有未提交范围。

## 自检覆盖与执行交接

| 正式设计验收 | 归属 |
|---|---|
| 根配置最少、资产类型与模板继承 | 任务三步骤1/3/7；任务四步骤7 |
| 不提前播放、失败不播放、接受后失败不回滚 | 任务三步骤1/2/4/8 |
| 单次/连射/并发/旧回调、普通/CHAIN/触发共通 | 任务三步骤1/6/7/8 |
| 四锚点、ready定位、重入快照 | 任务一步骤1/3；任务三步骤6 |
| 技能退出与独立回收、资源隔离、空值/异常 | 任务一/二；任务三步骤5/7；任务四步骤8 |
| 镜头类型与请求、不移动镜头 | 任务一；任务三步骤3；任务四步骤5/7 |
| 真实可见/可听预览、完整回归、资源和文件秩序 | 任务四步骤5至10 |

以上是实施准备，不表示任何代码/测试已完成。本计划推荐由当前会话按任务顺序执行，在四个检查点停下来验证，并在最终做独立代码审查；任务共享同一个播放器、测试入口和接受回调，串行推进能减少交叉接口变更。

用户确认本文后再选定执行方式：当前会话逐任务实施，或独立子代理逐任务实施/审查。开始执行时仍须读取对应执行技能；不能把“允许编写计划”当成已经允许代码、正式资产或版本发布。

## 2026-10-14 执行结论

当前会话完成四项功能实现，新增4个.gd/1个.tscn/0正式资源；修复独立审查发现的Top Level定位错误后，完整129项回归再次通过。以上勾选表示实际执行，不将未执行部分自动勾选。

未勾选的任务一步骤4、任务三步骤6表示视觉延迟autoplay/自然结束及完整重入组合矩阵仅部分覆盖，已作为审查Minor建议记录；任务四步骤5的可视检查已完成，但实际听感还需用户试听。详细结果、保留范围和执行工具差异见验收记录。本次未提交、上传、合并或进入连携阶段三/四。
