# 连携施放表现：指令反馈、临时镜头与释放停顿详细设计

> 日期：2026-10-14。
>
> 状态：用户已确认本详细设计，包含并发镜头、停顿内输入与暂停所有权补充；尚未实施。下一步见[实施计划](../Plans/2026-10-14-chain-skill-presentation-plan.md)，计划仍须审阅后才能执行。
>
> 本轮交付：本设计文档。下列脚本、场景、资源、接口和参数均为拟交付内容，不表示已经存在或已接入。
>
> 范围：在已完成的连携阶段二和成功释放表现接口上扩展表现，不实施连携阶段三、四，不改变技能合法性、费用、目标与伤害规则。

## 1. 已确认的体验与不可改变的边界

玩家需要清楚地知道“输入已收到、谁正在施法、何时真正出手、是否失败”，而不是获得一段使战斗排队的演出。

| 时点 | 卡片反馈 | 镜头与战场 |
| --- | --- | --- |
| 请求已受理，正在等待或接近 | 黄色边框，保留原状态文字 | 继续跟随玩家，不提前停顿 |
| 角色真正开始施法 | 绿色边框，显示施放中 | 立即开始快速移向该角色；施法与移动镜头同时进行 |
| 施法完成、交付成功接受 | 保持绿色 | 本次释放特效与音效启动；战场短暂停顿，首版 0.15 秒 |
| 停顿期间 | 成功反馈继续计时 | 角色、普通投射物及战斗计时暂停；本次释放特效与音效继续播放 |
| 释放强调结束 | 成功反馈仍可短暂保留 | 恢复战斗；镜头返回玩家当前构图，或衔接另一个仍在施法的伙伴 |
| 从成功释放起约 0.3 秒 | 清除本次绿色边框 | 不等待投射物命中或动作收尾结束 |
| 释放前失败或中断 | 短暂红色边框和原因 | 取消本次镜头接管，不播放成功释放停顿；按原规则清理请求 |

“马上移动”指同一开始通知中启动过渡，不是等待一个额外镜头阶段，也不是强制瞬间切镜。

成功释放是既有 delivery_started 接受事实，不是 release_started 意图通知，也不是命中。瞬发伤害/治疗正常结算；投射物只启动一次，暂停结束后继续原有运动，绝不再次发射。

所有表现都是临时内容。固定的是事实时点、请求身份、清理与播放契约；可替换的是镜头资源、视觉场景、声音资产、UI 样式和表现时长。表现缺失或失败不能取消技能、改变费用、伪造伤害或重置 AI。

## 2. 项目基线与真实缺口

### 2.1 已有可复用内容

- SkillBase 已有 Cast / Release / Cancel 视觉入口、释放音频、只读 CameraEffectProfile 资源槽与 camera_effect_requested 通知。
- SkillReleasePresentationPlayer 已挂在 SkillBase 的固定 RuntimeEffects 子节点上，统一负责成功接受后的视觉与音频；其实例独立于技能存活。
- SkillHostComponent 已有确认动作开始、成功释放、带身份的指令失败与动作锁。
- SquadChainCommandController 已管理四伙伴、根请求身份、世代、专注预留/提交/退款，不需要第二份指令执行器。
- SquadChainCommandDisplay 已显示 waiting / approaching / casting / released 和待执行文字；目前只有整体灰显，没有动态黄/绿/红边框。
- CameraFollowController 已管理玩家跟随、死亡回退、位置平滑、速度预留与分档缩放。
- SquadChainCommandPreview 已继承 TestCombatRoom、装配四伙伴指令和开发费用批次，适合作为新预览的父场景。

### 2.2 需要补齐的地方

1. 现有镜头出口只发生在成功释放后，无法提前展示施法；而 SkillBase.cast_started 发出时，Host 尚未完成连携 active/pending 迁移，不能直接当队伍级动作确认通知。
2. 现有镜头请求不包含本次表现/根请求/世界身份，无法可靠地处理旧通知、并发请求与延迟返回。
3. 尚无暂停所有权管理；不能由每个技能自行 paused=true，然后在定时器中无条件 paused=false。
4. 释放视觉和音频默认继承父节点处理模式，会和战场一起停下；仅改变技能节点的处理模式又会错误地放行技能计时与交付。
5. 指令控制器目前在 SceneTree.paused 时拒绝输入，可能漏掉 0.15 秒停顿内的下一次按键。
6. UnitStateComponent 的死亡看门狗、死亡移除延迟，以及 CombatRoomController 的失败延迟使用 create_timer 的默认 process_always=true，不能直接宣称它们会随战斗暂停。
7. HitFeedbackBridge 使用 PROCESS_MODE_ALWAYS，并直接叠加子相机位置；必须检查暂停及现有缩放的兼容，不能让新镜头另行争写相机。

本轮仅检查并设计上述衔接，不顺带重构 AI、导航、普通攻击或关卡流程。

## 3. 架构取舍

| 方案 | 结果 | 本设计取舍 |
| --- | --- | --- |
| 每个技能直接控制镜头、暂停和卡片 | 文件少但相互覆盖，取消/重载容易泄漏状态，临时效果难替换 | 不采用 |
| 建设完整时间轴、演出图和全队串行队列 | 能力丰富但超出本轮体量，并改变独立出手规则 | 不采用 |
| 既有技能报告事实，关卡表现组件协调镜头/停顿，UI 独立显示 | 保留执行体系；资产和策略可替换；装配入口有限 | 推荐 |

不把镜头或停顿写成 SkillEffectBase：该组件层承担战斗数值效果，而表现不能因删除或替换而改变技能成功性。

## 4. 装配与职责

```text
关卡 / 连携独立预览
  SquadChainCommandController       原指令与专注事务，不播放效果
  SquadChainCommandDisplay          原卡片界面，增加表现状态
  CameraRig                         原 CameraFollowController
    Camera3D                        保留视角、FOV 和分档缩放
  ChainSkillPresentationController  新的关卡级表现协调组件
    PauseCoordinator                可见的 GamePauseCoordinator 固定子节点

伙伴 / SkillHost / SkillSocket / 具体连携 SkillBase
  Presentation
    Cast：原蓄力场景
    Camera：镜头资源
    Release：原视觉、锚点、音频；新增释放强调资源
    Cancel：原取消场景
  RuntimeEffects                    原成功释放播放器，不再添加第二套播放层
```

### 4.1 SkillBase / RuntimeEffects

保留接受边界和普通行为。为每次根动作/直接触发准备独立表现身份与只读快照；播放释放视觉/音频，并报告实例准备和启动事实。它们不查找关卡节点、不控制 Camera3D、不切换 SceneTree.paused。

### 4.2 Host / 指令控制器

Host 在动作确认完成后报告确切请求；指令控制器核对根身份、槽位和世代后转发可观察事实。费用和退款仍只有原控制器执行。新增通知是事实接口，不要求订阅者响应，不等待镜头返回值。

### 4.3 ChainSkillPresentationController

关联一个指令源、一台 CameraRig 和一个暂停协调器；监听根连携事实，管理有限的活动表现、镜头候选和释放实例时钟注册。它不能调用 activate、release_action、cancel_command、Focus.commit 或修改目标。

首版仅编排所属四伙伴的根连携；不按 Combo_ / Trig_ 文件名识别用途。普通技能与子技能保留通用表现接口，但不会因为继承根伤害身份而自动获得连携镜头/停顿。未来接入其他用途时复用这些接口，不建立新技能管线。

### 4.4 CameraFollowController

相机的正常跟随与临时 Rig 构图仍由同一个控制器写入。不将正常 target 改成伙伴，不调用会立即 snap 的 _assign_target 来实现临时观察。

### 4.5 GamePauseCoordinator

独立管理暂停持有者、释放强调时钟和恢复；不认识技能、角色职业、费用或评分。同一 SceneTree 只允许一个有效暂停所有者实例；重复装配告警，不能两套管理器争写全局暂停。

首版为关卡组件的静态可见子节点，不新增 Autoload。以后菜单或终结模块使用同一协调器的公开接口；本轮只验证该接口，不制作菜单或终结流程。

## 5. 请求身份与只读表现快照

新增 SkillPresentationContext，继承 RefCounted，不是 Resource 资产，不在 Inspector 配置。

| 数据 | 约束 |
| --- | --- |
| presentation_id | 每次施放独立正身份；同次施法和释放保持一致，不用技能实例 ID 代替 |
| command_request_id | 根连携的既有请求 ID；普通技能为 0，不分配第二套连携身份 |
| scene_scope_id / world WeakRef | 拒绝跨世界/已退出通知；不保活场景 |
| purpose / execution_mode / is_chain_root | 从现有上下文生成，只读；子技能不冒充动作根 |
| source / target WeakRef | 角色删除后可安全失效；不长期保存 SkillContext、Host 或 Request |
| world_transform | 本阶段有限世界变换；施法和释放可以是不同的不可变阶段快照 |
| camera / accent 配置快照 | 同一次施放稳定；不在回调里重新读取当前 Inspector |
| 释放视觉、锚点与音频 | 资产引用只读；不复制 PackedScene 或音频内容 |

动作型在确认开始时分配身份，释放时生成同身份的阶段快照；直接触发没有施法阶段，在交付接受时创建一次。数值复制、镜头纯策略资源按单次 duplicate 隔离，PackedScene / AudioStream 等资产只保留只读引用，不深复制全部美术资产；不把播放进度、Timer、暂停 token 或相机引用写回共享 .tres。

SkillBase 增加 `get_current_presentation_context() -> SkillPresentationContext` 只读查询，供 Host 在确认后取得本次快照；无活动动作时返回 null。释放/取消后清除技能的活动引用，交付和表现实例仍可持有各自阶段快照。所有快照私有存储、公开只读属性，不允许消费者改写本次资源或身份。

单次取消、释放和旧交付最终失败按自己的身份核对。已释放请求不因后续打空、死亡或动作取消转为可退款失败。

表现去重仅保存仍活动、仍有释放实例或仍在短暂 UI 保留期的记录；随后按世代/原请求归属拒绝旧通知，不建立永久历史 ID 集合，也不能用一个“最大已见 ID”拒绝合法乱序释放。一次请求结束后清理信号、Callable、策略副本和 WeakRef 登记；不为每帧、每次命中或每枚碎片创建镜头管理节点。

## 6. 事实通知与调用顺序

以下是拟新增的公开契约，不是实现代码。全部需在声明附近补充简体中文说明。

### 6.1 动作真正开始

Host.confirm_active_action_started 完成 SkillBase 确认、request.mark_action_started、active/pending 迁移后，发出 `command_action_started(request, presentation)`。发通知前后都校验同一身份/世代；发生同步取消或解绑时不得继续发有效开始通知。

队伍控制器在本请求属于自己且未终结时转发 `command_started(slot_index, presentation)`。UI 据此立即变绿，表现组件据此申请临时焦点。既有 SkillBase.cast_started 及普通技能名称提示保持原语义和时序，不整体搬动旧信号。

0 施法时间也必须允许“开始与释放在同一次调用/同一帧内发生”；不得为了 UI 或镜头新增等待帧。

### 6.2 成功释放

```text
Runner 接受真实交付
→ SkillBase 标记接受并准备本次释放快照
→ 既有 delivery_started → Host.skill_released → 控制器提交专注
→ command_released：UI 建立成功后边框保留计时
→ RuntimeEffects 准备视觉/音频实例
→ release_instance_prepared：注册本次释放表现时钟
→ 设置初始位置并 add_child / 正常启动播放
→ release_presentation_started：申请 0.15 秒短暂停顿
→ 原同步 Effects 或原投射物会话按规则继续处理
```

`release_instance_prepared(presentation, instance)` 在实例进树、_ready、autoplay 和 Tween 创建前通知；只能设置该表现实例的播放时钟，不能操作技能或交付。视觉和音频分别通知，某一通道为空或无效不阻断另一通道。

`release_presentation_started(presentation)` 在本次通道启动步骤结束后恰好一次通知；没有可用视觉/音频但配置了强调资源，仍可请求纯停顿。它表示成功释放的表现阶段开始，不表示资产已渲染出像素，也不以某个特效必须成功为前提。

因此原 prepare_release 中“视觉/音频/镜头都空则返回空”的早退需要纳入强调资源判断；动作开始的轻量身份快照也不能因没有美术资产而省略，否则 UI 和纯停顿请求会失去事实关联。

上述通知由 RuntimeEffects → SkillBase → Host → 指令控制器作事实转发，队伍层只转发自己受理的根连携。Host 按快照身份与注册来源转发，不使用“当前技能仍 CASTING”作为已释放表现的前提；源技能已经 READY 或即将卸载不能误指向下一次施放。根节点之外不依赖 RuntimeEffects 的硬路径，也不让 UI 监听每个碎片。

现有 camera_effect_requested 四参数通知保留为兼容的一次性请求出口；本次完整施法镜头消费新带身份事实，不同时消费旧信号，避免重复播放。老信号不悄悄换签名或代表新阶段。

### 6.3 失败与清理

控制器增加 `command_failed(slot_index, request_id, reason)` 事实通知，只在释放前失败时产生一次。必须先捕获槽位、请求 ID 和原因，再执行可能触发 lifetime_finished、删除 Record 的逻辑；不能在记录删除后再猜槽位。费用仍按原事务路径退款，表现回调不得重复退款。

增加 `scope_changed(scope_root)` 只读绑定通知与 `get_bound_scope()` 查询，供表现/UI 解除旧世界；不再配置第二份玩家或世界引用。解绑时清理属于旧世代的表现，不闪一整排红框。

command_lifetime_finished 仍是动作和全部交付的资源清理通知，不能代替施法失败、成功释放或镜头返回事件。

## 7. 临时镜头的开放接口

### 7.1 资源与后端

保留 CameraEffectProfile 作为强类型资源基类，新增安全默认的策略方法：

- `get_phase_duration(phase) -> float`：阶段为基类定义的进入/返回枚举，单位秒；0 为不等待的即时过渡，负数或非有限值使该镜头请求降级跳过，不阻止技能。
- `sample_rig_transform(from_pose, destination_pose, progress, phase) -> Transform3D`：progress 为归一化 0—1；纯计算，不修改节点、不保存进度。返回须有限。

新增 SkillFocusCameraProfile 继承该基类，仅暴露进入时间和返回时间，首版默认 0.12 / 0.20 秒；内部采用平滑曲线，首版只平移并保留方向。基类空资源安全无效果，不能把“任意基类都必须是平移镜头”写死成类型分支。

CameraFollowController 增加 class_name 供强类型 Inspector 选择，并增加：

- `begin_presentation_focus(presentation_id, source, profile) -> bool`：正身份、同一有效世界、存活 source；只申请临时构图，不更换正常 target。
- `end_presentation_focus(presentation_id)`：仅结束匹配请求，启动返回；旧身份无操作。
- `clear_presentation_focus()`：场景解绑等强制撤销接口，不操作技能和暂停。
- `set_presentation_pause_source(source)`：装配层注入同世界暂停协调器，null 可卸载；不增加相机 Inspector 配置。绑定期间相机可在强调停顿中推进过渡，显式暂停停止过渡；卸载恢复原处理模式，停止接收暂停中的缩放输入。

Rig 后端负责安全应用策略结果；新镜头算法可以通过资源子类替换。新增旋转、FOV 或遮挡避让等超出本版契约的能力，仍需扩展后端，不能声称任何未来效果仅换资源就必然可用。

### 7.2 构图行为

- 进入从相机当前实际构图开始，目标每帧取伙伴当前世界位置加原 camera_offset。
- 保持现有 Camera3D 俯视角、FOV 和玩家缩放档位；不拉近特写，不自动重置缩放。
- 临时伙伴焦点不使用玩家速度 look-ahead；垂直处理沿用当前 lock_vertical_follow 约定。
- 正常目标解析和玩家死亡回退仍有效，但其 snap/maximum_follow_distance 不能抢写临时过渡。必须分开正常期望构图计算与最终 Rig 写入。
- 返回以当前正常目标的实时构图为终点，不用进入前保存的玩家旧位置；返回完成后沿同一正常跟随状态衔接，避免第二次平滑产生跳变。
- 技能过短或已释放时镜头尚未到位，允许提前进入释放保持/返回；不延长施法来满足镜头。
- 没有当前合法正常目标时，安全保持最后有效构图并清理临时占用；出现合法目标后按原规则恢复。
- 缩放仍遵守原 InputMap；相机因表现使用 ALWAYS 后，明确忽略暂停中的缩放事件，不无意放宽其他输入，也不新增缩放缓存。

### 7.3 兼容现有震动

新表现只写 Rig，不直接对 Camera3D.position 加偏移。缩放仍由原控制器处理；HitFeedbackBridge 的现有加/减偏移需要针对渲染顺序、暂停和返回做回归。

若测试证明缩放覆盖旧震动、旧偏移被重复减去，最小修正是由相机提供按来源登记的局部震动偏移，桥仅提交自身偏移，子相机最终位置统一为“基础位置 + 缩放 + 各来源震动”；无该接口的普通预览保留旧兼容路径。此兼容修正列为可验证要求，不把新的镜头抖动、美术震动参数或全面相机重写塞入本轮。

HitFeedbackBridge 在 SceneTree.paused 时停止局部卡刀与震动的计时/采样，避免普通命中反馈在冻结期间提前耗尽；恢复继续原进度，离树仍移除自身占用。

## 8. 释放强调与暂停所有权

### 8.1 独立资源，不绑定镜头

新增 ReleaseAccentProfile，继承 Resource，仅一个 export：`pause_duration_seconds`，默认 0.15 秒，Inspector 范围 0—0.3 秒，有限；0 关闭该次停顿。资源只描述释放强调，不引用 Camera3D、不承担伤害、不保存暂停 token。

技能的镜头与停顿可以独立留空：没有相机仍能播放视觉/音频；没有强调资源则不暂停；仅配置强调而不配置镜头也合法。不同技能共享同一个预设，不需要逐技能同步时长。

### 8.2 暂停协调器契约

- `bind_scope(scope_root)`：由关卡表现装配注入指令源当前绑定世界，null 解绑；先清理旧世界 token/实例登记再绑定新世界，世界仅以 WeakRef 保存，不增加 Inspector 世界参数。重复/跨 SceneTree 协调器装配必须拒绝。
- `request_release_accent(presentation_id, duration_seconds, owner) -> int`：正身份、有限非负秒数，owner 为有效本世界节点；返回自身持有 token，0 表示无停顿/拒绝/合并后无独立持有。重复身份不续时。
- `acquire_pause(owner, reason) -> int`：供未来菜单等持有显式暂停，必须显式释放；首版仅接受同绑定世界内的有效 owner，跨世界拒绝，只提供基础接口和测试，不创建菜单。
- `release_pause(token)`：仅解除该 token，幂等；不清除其他持有者。
- `is_release_accent_only() -> bool`：存在短停顿且不存在菜单等显式持有，也不存在进入前已暂停的外部基线。
- `has_release_accent() -> bool`：只读查询当前是否仍有合并后的释放强调区间，与是否另有显式暂停分开，供镜头正确结束释放保持阶段。
- `register_release_instance(presentation_id, instance)`：登记纯释放视觉/音频的 WeakRef 和原处理模式；不接受角色、技能、Runner 或战斗投射物。
- `pause_state_changed(battle_paused, presentation_allowed)`：只有状态改变时通知；不向 UI 泄露可编辑 token 列表。

协调器是本次装配世界内唯一的 SceneTree.paused 写入者；不改 Engine.time_scale，不改物理服务器开关。它以独立真实时间维护有限停顿，用内部短列表而不是不可控的跨场景 await 链。

进入管理前已经暂停的场景不自动解除：记录外部基线，本次强调不覆盖它。以后新增的暂停写入者必须经本接口，否则“已为 true 期间又有其他代码赋 true”的所有权无法从一个布尔值推断；本设计不虚假保证兼容任意绕过接口的写法。

owner 删除、绑定世界退出、组件离树、重复回调均释放自身 token。存在其他有效持有者时继续暂停；没有其他持有者且外部基线未暂停才恢复。整个世界退出时清理该世界全部 token；仅表现组件卸载但暂停协调器仍被其他模块使用时，只释放表现组件自己的 token。暂停协调器不能在其他持有者存活时单独卸载，此情况视为装配错误并告警，不能粗暴全部解锁；未来持久菜单必须先迁移到同一持久协调器后才跨世界持有。

### 8.3 重叠停顿

同一物理帧根释放的停顿合并取最大，不相加；第一笔通知即暂停，不为了收集同帧请求延迟整帧。同帧较长时长只可将该区间调整为“首笔开始时刻 + 本帧最大时长”，绝不能按每笔通知的到达时刻重新加时。后续物理帧的迟到通知不能刷新当前截止；恢复后至少经过一次正常物理推进，再允许建立新的强调停顿。所有成功释放仍播放各自资产与 UI 反馈，合并停顿不合并伤害或费用。

连射一次根技能只触发一次；后续箭、齐射多目标、命中、碎片和子技能不因共享 request_id 再次触发。该规则由根用途及表现身份消费实现，不为具体 RapidShot 写特例。

当前镜头所有者成功释放且请求了强调时，保持到实际合并强调区间结束后再返回/衔接，不以自己原来的 0.15 秒计时抢先返回；没有自身强调配置时直接进入返回/衔接。显式暂停只冻结表现进度，不会被误判成应立即返回的成功或失败。

### 8.4 两种时间

| 计时 | 使用的时间 | 行为 |
| --- | --- | --- |
| 施法、技能冷却、接近等待、连射间隔、状态时长、普通投射物寿命 | 战斗时间 | 强调停顿期间不推进 |
| 本次 0.15 秒强调、镜头过渡、0.3 秒边框保持 | 真实表现时间 | 强调期间推进，不读取已冻结的战斗 delta |
| 本次释放视觉/音频 | 表现时钟 | 强调期间推进；显式菜单等暂停期间停止 |
| 未来伤害间隔窗口 | 既定战斗时间 | 本轮不实现；以后自然随战斗暂停，不添加补偿秒数 |

显式菜单/未来终结暂停优先于临时表现：镜头与注册释放实例冻结，边框保留倒数挂起；强调的有限恢复计时仍可结束其 token，不得唤醒战场。关闭显式暂停后从原表现进度继续，不在菜单退出瞬间补跑一大段真实时间。

本轮不建设慢动作系统，当前工作基线为 Engine.time_scale=1；0.15/0.3 秒截止使用真实时钟。以后若加入 time_scale 缩放，原生 AnimationPlayer/粒子的独立实时推进还需额外适配，不能仅因节点为 ALWAYS 就声称它们不受慢动作影响。

### 8.5 既有计时器兼容

只调整与战斗冻结有关的现有调用：UnitStateComponent 的死亡看门狗和死亡移除延迟、CombatRoomController 的失败延迟显式使用 process_always=false。DefaultDeathEffect 的纯视觉销毁延迟同样随该普通视觉的战斗时钟处理，避免冻结时先回收。

原有取消/幂等逻辑保留，不借此修复与本功能无关的死亡规则。新增停顿的恢复计时则必须独立于暂停；不能统一把全部 Timer 改成同一模式。

## 9. 释放特效在停顿中继续播放

### 9.1 仅改变本次独立实例

RuntimeEffects 继续使用原 PackedScene、音频和锚点，且在 _ready / autoplay 前提供注册机会。协调器仅调整本次纯表现根节点的 process_mode：普通或强调阶段允许继续，显式暂停阶段停止。子节点默认 INHERIT；保存并在注销/拆卸时恢复原模式，不改共享源场景或资源。

不将 SkillBase、SkillHost、单位、DeliveryRunner、伤害区域或投射物设置为 ALWAYS。投射物的飞行视觉属于投射物会话，本轮仍随战斗冻结；只有 release_effect_scene 和 release_audio_stream 的独立实例获得表现时钟。

资产内部协议沿用已有 autoplay / play() / effect_finished / 自身安全回收。显式设置 ALWAYS 的子节点、未绑定节点的 Tween、内部 process_always=true 计时器不能靠根节点自动管理；通用资产校验需告警，首版临时样例必须满足 INHERIT 与绑定播放协议。不得递归改写任意资产中的脚本与游戏逻辑。

Tween 必须绑定表现实例并遵循其暂停模式；不能只设置 ignore_time_scale 就声称能正确响应暂停。Shader 的 TIME 不受 SceneTree 暂停控制，当前相关目录扫描未发现依赖项；未来若有需冻结的自定义 shader，必须使用资产显式提供的可控时间，不默认强制修改全部材质。

### 9.2 资产时长与停顿时长独立

首版提供约 0.15 秒的中性释放闪光样例，仅用于验证：小型光环/闪光扩散后消失，不带伤害、碰撞或投射物行为。

特效时间由自己的 AnimationPlayer / 粒子寿命编辑，停顿时间由 ReleaseAccentProfile 编辑。二者首版接近即可；不自动拉伸所有未来特效，不在特效结束时恢复战斗，不用暂停截止强行杀掉残留视觉。它们是两个可独立替换的表现职责，不属于必须始终相等的重复参数。

某些粒子首帧不可见，使用可在初始帧显示的 Mesh/闪光补充样例。只保证同一成功释放步骤启动，不为等待第一张粒子图像而延后交付或另冻结一次。

### 9.3 生命周期

已释放视觉/音频可继续独立存在，技能节点卸载不截断它们。协调器按 WeakRef 注册，仅保留播放所需的模式/身份；实例结束或 30 秒原安全回收后移除登记。移除协调器时先恢复登记模式，再清空监听与 token，不能让存活实例永久留在 ALWAYS。

## 10. 卡片边框状态与多请求

### 10.1 配置位置

继续修改 SquadChainCommandDisplay.tscn，不新建一套 HUD。每卡增加静态可见的 StateBorder 覆盖层，mouse_filter=IGNORE；样式以场景内 Theme / StyleBox 子资源维护，不为三种颜色增加 export，也不在脚本中硬编码颜色。

脚本只选择 waiting / casting / failed 对应样式；替换样式、卡片布局或整个显示场景不改变指令规则。四卡可共享只读样式，不能运行时修改同一 StyleBox 的颜色导致串色。

只增加两个时间参数：成功后保留 0.3 秒、失败提示 0.3 秒。默认约值可调，有限非负；失败文字沿用现有 reason 映射，不把旧请求的失败文案永久盖住新请求。

显示节点在运行时以 ALWAYS 更新纯 UI；它仍不接收施放按键、不推进任何技能。通过既有 command_source 的新增只读 `is_feedback_suspended() -> bool` 查询显式暂停状态，决定是否挂起显示计时，不再增加一项 UI 暂停节点配置。未装表现组件时该查询遵循原场景暂停，正常状态与旧 UI 一致。

### 10.2 状态不是 can_submit

绿色表示角色正在施法或刚成功释放，不表示此刻还能受理下一次请求。黄色表示已存在合法待执行请求，不表示正在支付。可用性灰显仅作用于内容/下一次输入提示，不能把整个卡片 modulate 灰掉后连绿色或红色边框也一并变暗。

command_released 发生时从真实表现时间起计 0.3 秒，包含其中 0.15 秒强调。旧动作仍在收尾不延长绿色，投射物仍在飞行也不延长绿色。

### 10.3 同角色有活动和缓存请求

排除下述短暂红色提示时，主边框规则为：活动施法的绿色优先；其后是尚未开始请求的黄色；再是旧成功的绿色保留态；最后为无边框。已有绿色时受理后一条，保留“已缓存”文字并给该文字一次轻量黄色确认，不用主边框抢走当前施法状态。

新请求/新施法出现后，旧 0.3 秒计时器不能清除新状态。每个显示记录带槽位、请求 ID、显示世代与自己的截止；不用单一 slot Timer 盲目清框。

释放前失败或新按键未受理时短暂红色，原因可见；若同槽仍有另一条有效活动/缓存请求，红色到期后重新从这些事实恢复正确状态，不取消另一条请求。拒绝不伪造 request_id，不抹去原请求。

scope 解绑、伙伴槽变更或 UI 重新绑定时立即清除旧显示世代；初始化时可读当前活动/缓存状态，但不补播已错过的红框或释放闪光。

## 11. 并发镜头与停顿内输入：本设计的补充建议

以下补充随本文获得用户确认：只调整表现协调与短暂停顿期间的输入接收，不改变伙伴独立执行、费用或动作锁规则。

### 11.1 镜头只有一个，不让技能排队

推荐“当前焦点完成优先”：A 已获得镜头时，B 开始施法仍立即变绿，但不抢走 A。A 释放强调结束或失败后，从仍在施法的候选中按开始顺序选择下一位，同序用请求 ID 稳定排序；若没有则返回玩家。

已释放完的 B 不补播过去镜头；所有伙伴照常并行，UI、释放特效、声音与费用不因未获得镜头而省略。镜头返回途中出现新可用候选，从当前构图接续，不先回到玩家再折返。

同角色后续请求有独立身份，旧结束通知不能取消新的焦点。候选只保留当前根动作，释放/失败/离树即移除；不存一条需要依次播放的历史演出队列。

角色死亡/无效立即撤销其焦点。施法看门狗以该请求有效施法时间加内部余量为边界，等待按战斗时间累计；只回收镜头并警告，不擅自宣布技能失败或退款。不能因另一技能的正常强调停顿而提前超时。

### 11.2 0.15 秒停顿不吞下一次连携按键

推荐在“只有释放强调暂停”时允许 1—4 请求受理：保持原合法性、专注预留和单伙伴一条缓存上限，恢复战斗后才由 Host/AI 推进。它不要求新的玩家操作，也不新增一个全队缓存。

指令控制器由表现装配显式注入暂停门禁，并在绑定期间使用 ALWAYS 接收输入；_process 仍只做装配/只读状态刷新，不推进 AI 或技能。新增 `set_presentation_pause_source(source)` 接口，source 为空时恢复原暂停拒绝行为；绑定/拆卸恢复原处理模式。Host 本身及行为层仍 PAUSABLE，不因接收按键而施法。

有菜单等显式暂停或外部暂停基线时不走该特许入口，也不把按键暂存到关闭菜单后；保留 InputMap、忽略 echo，按键只受理一次。Q/E、普通攻击、移动与其他输入不顺带建立新缓存，原输入合法性不放宽。

这部分必须测试真实输入、真实 Host 入队和预留，不能只把指令控制器设为 ALWAYS 却忘记 _input_reason 仍会拒绝。

## 12. Inspector 最终配置与迁移

### 12.1 技能根节点

```text
Presentation
  Cast
    Cast Effect Scene            原字段
  Camera
    Camera Effect Profile        原镜头槽重命名/归组，仍只有一个
  Release
    Release Effect Scene         原字段
    Release Effect Anchor        原字段
    Release Audio Stream         原字段
    Release Accent Profile       唯一新增资产槽，可空
  Cancel
    Cancel Effect Scene          原字段
```

原 release_camera_effect 的用途从“仅释放请求”扩展为完整施放镜头，因此新规范名为 camera_effect_profile。迁移必须保留旧序列化属性的读取兼容或通过 Godot 统一迁移所有引用，旧字段不再作为第二个 Inspector 槽展示。当前正式技能该槽为空，不等于可以忽略测试、预览和外部旧资源的兼容。旧信号继续原语义。

普通技能配置不增加新必填项；新镜头/强调都空时回到原有玩法和表现。四个连携内容可共用两个资源。用新镜头子类或不同视觉/音频替换临时内容时，不改 SkillBase、Delivery 或 AI。

### 12.2 参数数量

| 配置入口 | 新增/变化 | 默认 |
| --- | --- | --- |
| 每个 SkillBase | 新增 1 个可空 ReleaseAccentProfile 资源槽；原镜头槽重命名但不增槽 | 空，不暂停 |
| SkillFocusCameraProfile 预设 | 2 个秒数：进入、返回 | 0.12 / 0.20 |
| ReleaseAccentProfile 预设 | 1 个秒数：释放停顿 | 0.15 |
| 现有卡片 UI | 2 个秒数：成功保留、失败提示 | 0.30 / 0.30 |
| 关卡表现组件 | 3 个强类型节点引用：command_source、camera_source、pause_source | 前两项由策划连线；第三项场景预填固定子节点 |

不导出曲线算法、速度、内部时间水位、请求表、重入锁、token、并发权重、各职业开关或每技能 UI 色彩。资源字段/公开方法均须紧邻简体中文说明，editor warning 指出缺失/跨世界/重复暂停协调器等配置错误。

### 12.3 人类配置顺序

1. 打开连携技能根节点，为镜头与强调各选择一个共享预设。
2. 需要新释放视觉/音效时替换原两个资产槽；原 Cast 与命中/飞行资产不受影响。
3. 将 ChainSkillPresentationController.tscn 放到关卡根下，选择既有指令源与 CameraRig；pause_source 已预填自身可见子节点，不手写路径或生成伙伴。
4. 卡片样式在原 UI 场景中编辑，两项保持时间在 UI Inspector 中调整。
5. 先运行新的独立预览；正式关卡的接入另行确认，不自动修改单位摆放。

## 13. 拟交付文件：数量、位置与复用

本节为建议清单，需经书面审阅后再冻结到实施计划。不是本轮已经创建的文件。

### 13.1 新增运行脚本 5 个

| 路径 | 职责 |
| --- | --- |
| SkillSystem/01-Core/SkillPresentationContext.gd | 轻量只读本次表现身份与快照，不是技能或资产层 |
| Effects/Camera/SkillFocusCameraProfile.gd | 继承现有 CameraEffectProfile 的平移策略，策划共享参数 |
| Effects/Combat/ReleaseAccentProfile.gd | 独立可空的释放停顿配置 |
| GameFlow/Pause/GamePauseCoordinator.gd | 唯一暂停所有权、表现时钟与释放实例登记 |
| UnitSystem/Components/Combat/Squad/ChainSkillPresentationController.gd | 关卡级事实订阅、焦点协调与清理，不执行技能 |

不为四个职业各写表现脚本，不为一次投射物创建一个新管理器，不另建 SkillBase 子类。

### 13.2 新增场景 4 个

| 路径 | 创建方式 |
| --- | --- |
| UnitSystem/Components/Combat/Squad/ChainSkillPresentationController.tscn | 新组件场景；包含静态 PauseCoordinator 子节点，不另拆暂停场景 |
| Scenes/Previews/ChainSkillPresentationPreview.tscn | 继承既有 SquadChainCommandPreview，仅装配表现组件与预览资产覆盖；复用原场景脚本 |
| Effects/Skills/Shared/ReleaseAccentFlash.tscn | 新临时纯表现场景，以 Mesh/粒子/AnimationPlayer/Timer 原生节点完成约 0.15 秒闪光，不新增专用脚本 |
| Effects/Skills/Shared/ReleaseAccentFlashPreview.tscn | 复用/继承既有 SkillReleasePresentationPreview 的预览框架和脚本，预选新视觉 |

释放闪光的计时、动画、自回收均在场景内可见；不在 AnimationPlayer 方法轨道调用战斗/暂停/伤害代码。场景内动画与材质作为子资源，不拆出多份外部资源。

### 13.3 新增正式资源 2 个

- Effects/Camera/Presets/ChainSkillFocus.tres：SkillFocusCameraProfile。
- Effects/Combat/Presets/ChainReleaseAccent.tres：ReleaseAccentProfile。

必须由 Godot MCP/ResourceSaver 正式保存，验证有效 UID、脚本类型及强类型 Quick Load；文本可加载不是完成标准。本设计轮不创建这两份资源。

### 13.4 新增测试脚本 5 个

- SkillSystem/05-Tests/SkillPresentationLifecycleTest.gd。
- SkillSystem/05-Tests/ReleaseAccentClockTest.gd。
- UnitSystem/Tests/CameraSkillFocusTest.gd。
- UnitSystem/Tests/ChainSkillPresentationControllerTest.gd。
- GameFlow/Tests/GamePauseCoordinatorTest.gd。

UI、费用、旧释放播放器和已有相机回归在原测试中扩展，不重复建一个同职能测试框架。

**建议新增合计：10 个 .gd（运行 5 + 测试 5）、4 个 .tscn、2 个 .tres；.gd.uid 由 Godot 生成。** 文档与原文件修改不混入这个新增数量。

### 13.5 既有文件修改范围

- SkillBase.gd：镜头槽迁移、新强调槽、表现快照与通知；SkillBase.tscn 固定三节点不变，除必要保存/引用登记不新增节点。
- SkillReleasePresentationPlayer.gd：实例进入树前通知、释放启动通知；保留锚点、声音、watchdog、独立生命周期。
- SkillHostComponent.gd：确认后的动作通知和带身份表现转发；不改变动作许可或交付。
- SquadChainCommandController.gd：开始/失败/表现/绑定事实转发、强调停顿输入门禁，不新增费用规则。
- CameraEffectProfile.gd：纯策略接口；CameraFollowController.gd：强类型和临时构图接口。
- SquadChainCommandDisplay.gd / .tscn：边框样式、两项时间和请求级显示；保留原指令源入口。
- HitFeedbackBridge.gd：本暂停的兼容；若实测需要，按第 7.3 节最小接入统一偏移。
- UnitStateComponent.gd、CombatRoomController.gd、DefaultDeathEffect.gd：相关既有延迟的暂停语义。
- 四个 Combo_ 技能源场景：只填共享镜头/强调资产，不改伤害、治疗、费用、施法时间或目标。中性新闪光只在新预览中覆盖，不替换源技能已有的嘲讽/治疗释放视觉。
- 相关现有测试、配置指南与进度文档：在实施时同步更新；本轮只新增本文。

不改 project.godot 的按键或 Autoload；不改 TestCombatRoom 正式单位摆放，不向 TestScene 添加/修改单位，也不修改普通技能参数。新预览通过继承复用已有单位，不运行时生成替代阵容。

## 14. 验收与回归设计

| 测试入口 | 必须验证的可观察行为 |
| --- | --- |
| SkillPresentationLifecycleTest | 开始确认后才发事实；0 施法正常；失败不触发成功；接受/扣费/实例准备/释放强调顺序；连射一次；直接触发与子技能不冒充根；同技能多次身份隔离 |
| ReleaseAccentClockTest | 真实原生动画/粒子/音频在强调期间推进；角色/投射物/冷却冻结；显式暂停停止表现；实例模式在 _ready 前准备；autoplay、延迟 play、无脚本场景、自然结束与安全回收 |
| CameraSkillFocusTest | 正常玩家 target 不变；保持角度/FOV/缩放；短技能不等待镜头；动态返回；死亡回退；旧 ID 无害；策略替换/非法输出降级；原震动与缩放无漂移 |
| ChainSkillPresentationControllerTest | 多伙伴并发、焦点非抢占、候选过期不补播；请求/世界世代隔离；镜头 watchdog 不伪造失败；镜头缺失不影响暂停与特效；真实 1—4 停顿内入队但不执行 |
| GamePauseCoordinatorTest | token 幂等与 owner 删除；并发合并不续停；显式暂停不被强调解除；外部已暂停基线；重复装配拒绝；重载与退出恢复；0/非法时长；WeakRef 无长期保活 |
| 扩展 SquadChainInputDisplayTest | 黄色即时、实际开始绿色、成功后真实时间 0.3 秒；失败/拒绝红色；新请求不被旧计时清除；缓存确认不抢主边框；可用性灰显不遮边框；无按键/焦点穿透 |
| 原交易/生命周期/相机/关卡测试 | 费用与退款不变；释放后打空不转红退款；无表现组件时旧行为；死亡/关卡计时随暂停，正常非暂停结果不变 |
| 压力与回收 | 至少 100 次根连携及 10 次重载；结束后暂停 token、焦点候选、实例登记、请求显示记录回到基线，无重复声音、相机漂移或永久历史集合 |
| 正式资源契约 | 两个预设 UID 有效、脚本类型正确、Quick Load 可检索；四技能只有预期的新配置，无新增跨文件同值维护 |

真实效果验收不能只用假 Player/Host：新预览中运行四伙伴连携，录到开始、释放、停顿、返回和边框结束时点；以动画位置/粒子状态/音频播放进度证明释放资产确实推进，以物理位置/冷却证明战斗冻结。

自动化停顿时长按渲染/物理帧容差验收，不断言绝对精确到毫秒；60 FPS 下约 9 个渲染帧只是解释，不硬写成 9 帧实现。暂不把未听过的实际音量、舒适度或镜头节奏写成已通过。

使用当时工作区实际测试入口重新确定完整回归基线；上轮文档记录的 129 个通过不是本轮已重新执行。设计轮只做只读检查，不把未运行的测试记成通过。

## 15. 不做的内容与后续审阅

- 不实现连携伤害窗口、评分、终结选择、终结演出或新的专注恢复算法。
- 不打断已开始的普通动作、不改变等待/接近/动作锁，不为镜头建立全队技能顺序。
- 不做镜头旋转特写、FOV 推拉、电影黑边、镜头避障或每职业专属动画。
- 不重做完整 HUD，不添加新操作键，不扩大玩家动作或技能范围。
- 不要求正式美术/音效：开放接口、可运行临时样例和可替换共享资源足够验证。

用户已确认三个补充：①并发镜头当前焦点完成优先；②只有强调暂停时允许缓存下一次连携输入；③显式暂停优先于临时表现，且所有暂停调用方必须共用协调器。实施计划按这些决定展开，不重新引入强制演出队列或全局暂停期间自由操作。

书面设计通过后才编写实施计划，按小步可测试方式展开，不直接开始代码。用户未要求本轮 Git 提交/推送，因此只保留文档改动，不擅自记录版本或上传。

## 16. 引擎依据与设计自检

- Godot 的暂停停止物理，并依据节点 Process Mode 停止处理；信号仍能同步调用。依据：[Pausing games and process mode](https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html)。因此暂停不能替代交付的同步事务边界，也不能只给整名角色开 ALWAYS。
- SceneTree.create_timer 默认 process_always=true；ignore_time_scale 另行决定是否使用真实时间。依据：[SceneTree.create_timer](https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-method-create-timer)。因此战斗延迟和强调恢复需要明确不同参数。
- Tween 的暂停模式与忽略 time_scale 是两项职责，绑定节点与生命周期需明确。依据：[Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html)。
- Shader TIME 不受暂停影响。依据：[Spatial shader global built-ins](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html#global-built-ins)。本轮不建设全局 shader 时钟，只要求相关资产明确自身时钟。

自检结论：接受/动作/释放/命中/清理分离；技能不等待表现；停顿不冻结自身恢复；纯释放资产独立继续；旧回调按身份隔离；UI 不以可用性冒充状态；资源无运行状态；新文件按职责归类；新增数量已列明；并发与输入补充已获确认。上述为设计自检，不代替实现后的运行测试。
