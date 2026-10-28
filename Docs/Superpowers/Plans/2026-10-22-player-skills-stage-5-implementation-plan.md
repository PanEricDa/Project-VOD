# 玩家技能阶段五：被动位移迁移与正式装配 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking. 沿用当前目录、当前会话本人实施、阶段末一次只读独立review；共享Godot只有一个写入方。本计划已获用户批准执行；实施证据和最终状态见同目录2026-10-22-player-skills-stage-5-validation.md。

**Goal:** 让正式F5入口拥有可实际拉动敌人的Q、限时仇恨E及只读技能栏，同时把被动位移收口到UnitBase，不再要求挂接收器。

**Architecture:** UnitBase内置唯一外力请求、碰撞例外和生命周期；PlayerBase/AIUnitBase在原物理循环消费。Pull只调单位接口；Hero源场景显式装技能与输入，CombatRoom只加HUD。独立测试场景去重并保留2秒CD、三模式和观察器。

**Tech Stack:** Godot4.7、GDScript、CharacterBody3D、InputMap、原生继承场景、SceneTree行为测试、Godot MCP Pro。

**Spec:** [已确认阶段五设计](../Specs/2026-10-22-player-skills-production-integration-design.md)；[总体设计](../Specs/2026-10-21-player-gather-threat-skills-design.md)第5.1节；[阶段四证据](2026-10-22-player-skills-stage-4-validation.md)。

## Global Constraints

- 优先Godot MCP Pro创建、修改、保存；不支持/失败时说明后再回退。检查编辑器未保存资源，不覆盖用户缓冲区。
- 在G:/Godot/ProjectVOD当前checkout操作，不建新工作树，不自动Git提交、推送或清理既有未提交文件。
- 不向res://Scenes/TestScene.tscn添加或修改任何单位实例；执行前后比较其文件哈希/差异。明确允许修改Hero源场景，不把源继承的自然更新误当成允许改旧场景实例。
- 不重调技能、怪物、友方、专注/评分、仇恨、受击锁、相机或动画数值。执行前重读用户当前参数并记录，以当时值为准。
- 当前Q：半径3.5m、圆心前移3m、落盘前移1.5m/半径0.6m、位移0.12战斗秒、施法0.2秒、源CD10秒；E：半径5m、2000临时仇恨、8战斗秒、施法0.15秒、源CD12秒。独立测试均覆盖CD2秒。
- UnitBase只新增一个常用export：Forced Movement / forced_movement_enabled=true。中文说明覆盖用途、默认、关闭时立即取消及范围；内部状态不导出。
- 不新增组件节点、隐式运行时装配、第二个移动循环/时钟、仇恨权级、聚怪状态、技能打断规则或专注费用。
- 只迁移已确认被动位移与正式接入，不新增位移类型、技能、美术、动画、装备/热换槽或专项压力测试。
- 不顺带修复阶段四P3施法灰显、旧HUD低分辨率布局、房间导航烘焙或Firebolt旧6m断言。
- 正式场景不得带入测试Harness、模式按钮、范围圈、Probe技能、Unsupported靶或强制AI开关。
- 场景必须原生保存并检查继承/UID；本计划不新建正式.tres/.res。如果实施确需新增外部Resource，先说明必要性，原生保存、UID有效、强类型Quick Load。
- 原生运行与headless测试错开；最多4个headless进程。不在活跃编辑器旁另起headless编辑器导入，以免改写会话MCP autoload。
- 完成三批后停止交付；不执行后续新功能或Git操作。

## Review Focus

1. 关闭外力开关或退出单位时，终态回调重新请求：必须拒绝，碰撞先恢复且不能复活旧请求。Task1的disabled/exit重入测试覆盖。
2. 替换/到达/取消中同步再次发起：捕获的旧token不能清理新速度/新例外，旧取消不能覆盖新运动。Task1保留原重入契约。
3. 玩家/AI同时有受击锁、主动推进和外力：只有一条水平输出，暂停/5%只消费同一delta，结束不追补被覆盖推进。Task1实际物理验证。
4. Hero上移时继承场景与测试手工装配重复：Q/E一次输入只能一次执行，不共享不同Hero的运行技能/CD。Task2检验源、测试、正式入口及保存重载。
5. 正式Q/E与终结/退出共存：输入隔离不等于外力免疫；结束后恢复输入和时间，临时仇恨/例外不留到新世界。Task3真实普通伤害→连携→终结流程覆盖。

---

## 0. 执行准备与共享接口

- [x] 记录branch/HEAD、当前dirty清单、编辑器未保存场景/脚本、Q/E源及测试覆盖、CombatRoom核心配置；保留用户全部既有差异。
- [x] 用Godot MCP建立本阶段独立的`.godot/player_skills_stage5/`，保存下面全部拟改/拟移除文件的修改前副本，以及protected TestScene、Hero、CombatRoom、Q/E/伙伴技能的哈希/数值记录。不得复用或覆盖stage4目录。
- [x] progress.md首行标明本计划完整路径，记录三批状态、实际命令/输出与所有必要裁决；从首个未完成Task继续，不重复实施已完成任务。
- [x] 重跑关键基线：旧ForcedMovementComponentTest、PullTargetSkillEffectTest、PlayerSkillControlTest、PlayerSkillTestSceneTest、PlayerSkillCombinedFlowTest、CombatRoomFinisherFlowTest。Expected：六项原有行为PASS；不是要求当前尚无的新接口先通过。
- [x] 基线异常先查明来源，不靠迁移掩盖；确认无未保存冲突后再改代码。已知全量基线为181项179通过、2项既有失败。

### 精确接口契约（Task1产生，后续共同消费）

UnitBase新增公开字段/信号/方法：

```gdscript
# 默认true；关闭时立即终结活动外力，reason=disabled，开启不恢复旧请求。
@export var forced_movement_enabled: bool = true

signal forced_movement_started(token: int)
signal forced_movement_finished(token: int, reason: StringName)

func request_forced_movement(source: UnitBase, destination: Vector3,
		duration_seconds: float, ignore_unit_collisions: bool = false) -> int
func is_forced_movement_active() -> bool
func get_forced_movement_token() -> int
func cancel_forced_movement(token: int) -> void
```

继承层内部接口固定为：

```gdscript
func _validate_forced_movement() -> void
func _consume_forced_movement_step(delta: float) -> Vector3
func _report_forced_movement_result(token: int, actual_displacement: Vector3, blocked: bool) -> void
func _finish_forced_movement(token: int, reason: StringName) -> void
```

公开与内部入口均旁置中文职责/单位/约束。请求校验、世界XZ插值、终态清理沿现接收器算法迁移；
查询不推进、不改写，拒绝0不覆盖旧请求，正token只表示受理。
消费只增加本帧有效物理delta；点位公式保持start.lerp(destination,elapsed/duration)，step=point-current_position并令Y=0。
终态精度沿现有remaining.length_squared<=0.0001，撞墙提前结束、不补瞬移。
已有arrived/elapsed/blocked/replaced/cancelled/source_invalid/owner_invalid原因保持，开关关闭新增disabled。

碰撞记录、弱来源、token、进入树受理许可、步进时间全归UnitBase私有字段。
不开第二个计时器，不把旧组件藏在运行时自动add_child里。

## Task1 / A：内置被动位移与Pull迁移

**Files — Modify:**
- UnitSystem/Base/00_UnitBase.gd：上文全部状态、接口、碰撞与生命周期；修改旧类注释，明确内置被动位移协议但不负责主动移动/AI。
- UnitSystem/Base/AIUnitBase.gd：原物理外力分支和死亡处理改用继承接口，删除按节点名找接收器。
- UnitSystem/Player/PlayerBase.gd：同一已有物理循环增加外力分支，保留Input/Host及原主动行动。
- SkillSystem/03-Extensions/PullTargetSkillEffect.gd：适用性与提交改为UnitBase，无AI子类型/子节点装配检查。
- Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn：仅移除接收器、Unsupported根开关关闭，保留其余位置/数值/装配。
- SkillSystem/05-Tests/PullTargetSkillEffectTest.gd：迁移夹具及适用性契约。
- UnitSystem/Tests/PlayerSkillTestSceneTest.gd、PlayerSkillCombinedFlowTest.gd：单位信号/开关取代组件；保留真实输入与落盘断言。

**Files — Migrate:** UnitSystem/Tests/ForcedMovementComponentTest.gd及其.gd.uid → UnitSystem/Tests/UnitForcedMovementTest.gd及其.gd.uid；以新测试名输出结果，原实际行为覆盖保留。

**Files — Remove after reference migration:**
- UnitSystem/Components/Movement/ForcedMovementComponent.gd
- UnitSystem/Components/Movement/ForcedMovementComponent.gd.uid
- UnitSystem/Components/Movement/ForcedMovementComponent.tscn

**Interfaces:** Consumes既有接收器算法与Player/AI唯一物理循环；Produces第0节UnitBase接口，供Pull、Task2正式敌人和Task3使用。不新增EnemyBase组件/脚本分支。

- [x] **Step1 — 先写RED。** 迁移旧测试到UnitForcedMovementTest，首段用has_method安全断言新接口存在；缺失时退出1并给具体FAIL，不允许用“调用不存在/解析错误”当RED。增加真实无组件AI/Player夹具、开关和重入断言；暂保留旧组件文件供迁移前对照。
- [x] **Step2 — 实跑RED。** 用第4节命令执行UnitForcedMovementTest；Expected：缺少UnitBase内置请求能力。记录输出后再实施。
- [x] **Step3 — 实现UnitBase状态。** 从接收器迁入私有状态/算法，owner改为self；_enter_tree开启受理、_exit_tree先关闭受理再恢复例外/结束。在基类死亡生命周期清理本单位请求，不能只依赖AI死亡回调；物理验证来源仍在受击锁前执行。setter先写false再终结，回调重入不能绕过关闭。旧token只处理自己的终态；清理速度/例外在发信号前完成，不在回调后再覆盖新状态。
- [x] **Step4 — 接两条原物理循环。** AI保持原“死亡→受击锁→更新AI→外力优先水平输出→重力/转向→move_and_slide→回报”；去掉forced节点引用。Player在死亡/受击锁后、读取新移动/冲刺前捕获token，有外力时不启动本帧新主动推进。私有_discard_forced_movement_intents()仅清理_regular_horizontal_velocity、cancel_attack_motion及已有冲刺剩余/方向/免伤阈值；不退还已消费冲刺次数、不改冷却规则、不取消AttackController/Host动作。重力/转向照原流程，末尾只调用一次move_and_slide；外力帧不调用主动Dash距离扣账。
- [x] **Step5 — 迁移Pull和独立场景。** Pull.can_apply_to要求树内存活、非queued的UnitBase且开关允许；关闭时即便已在圆盘内也不误报。apply保留释放快照/稳定点位算法，只调用request_forced_movement。native移除四个临时接收器，Unsupported.forced_movement_enabled=false；将两项场景测试的move_finished监听改为forced_movement_finished，活动查询改单位方法。
- [x] **Step6 — 迁移旧能力测试。** 保留3m/0.35秒抵达、Y=99不改重力、墙后不补位、默认身体碰撞、ignore=true可重叠、原例外不被删、动态单位增删、5%/暂停/受击锁、替换重入、来源/目标死亡离树。将重复/缺组件适用性用例替换为开关false/存活/非UnitBase；极简UnitBase作为协议夹具明确不自动运行物理，不再把它作为“天然不支持Pull”的目标。
- [x] **Step7 — 精确删除旧内容。** 全活动.gd/.tscn/.tres/.res的路径/类名引用必须已迁移，二进制.res依赖用ResourceLoader.get_dependencies核对，不只依赖文本搜索；验证精确3个旧生产文件及旧测试路径才移除。优先Godot资源工具；不支持时说明后用原生DirAccess精确删除，不用目录递归删除。文件与UID迁移后扫描编辑器文件系统并等待索引，再重读场景；历史Docs阶段记录可保留旧名并标明历史。
- [x] **Step8 — GREEN及同场景检查。** 执行UnitForcedMovementTest、PullTargetSkillEffectTest、PlayerSkillTestSceneTest、PlayerSkillCombinedFlowTest、GatherPresentationTest、ThreatMarkPresentationTest。Expected：6项退出0/PASS，无SCRIPT ERROR、泄漏、无效UID。F6训练模式Q仍到相同盘、Unsupported不动、E正常；在根Inspector看见一个开关，不再看到接收器节点。
- [x] **Step9 — 记录A交付。** 本批仅完成底层收口与测试迁移；Hero源和CombatRoom尚未正式装Q/E。写阶段五validation，不自动Git。

### A批关键新增断言

下列片段放测试夹具中；source/body由原真实CharacterBody夹具创建，不能伪造物理结果：

```gdscript
_check(body.has_method("request_forced_movement"), "UnitBase provides built-in forced movement")
# 缺方法时安全_finish退出；实际调用随后通过call避免RED阶段静态解析不存在方法。
var token: int = body.call("request_forced_movement", source, Vector3(3,0,0), 0.35, true)
_check(token > 0, "plain AI receives without a child receiver")
body.set("forced_movement_enabled", false)
_check(not body.call("is_forced_movement_active") and body.get_collision_exceptions().is_empty(),
	"disable ends own motion and restores its temporary collisions")
_check(body.call("request_forced_movement", source, Vector3.ZERO, 0.35) == 0, "disabled rejects")
```

另写test_disabled_and_exit_reentry、test_player_physics_and_no_double_move、test_old_token_reentry_collision、
test_player_input_block_still_accepts_external_motion、test_hit_lock_and_five_percent_clock。
Player实际移动到3m/0.35秒的误差<0.08；持续原方向输入不能把终点加倍，结束不复活旧攻击推进/冲刺；
外力不应取消已经开始的真实技能Host动作。来源失效、接收者死亡与离树后均无活动请求/新增碰撞例外。
关闭→重开不恢复旧请求；无效新请求不破坏当前请求；已有碰撞例外保留用单独非空夹具断言，不能套用上面空例外断言。

## Task2 / B：Hero正式装配、HUD与测试去重

**Files — Create:** UnitSystem/Tests/PlayerSkillsCombatRoomAssemblyTest.gd及编辑器生成的.gd.uid。
**Files — Modify:**
- UnitSystem/Player/Hero/Hero.tscn
- Scenes/CombatRoom.tscn
- Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn
- UnitSystem/Tests/PlayerSkillControlTest.gd
- UnitSystem/Tests/PlayerSkillTestSceneTest.gd

**Interfaces:** Consumes Task1默认UnitBase能力、已有Controller.request_slot/get_slot_status、Input组件和PlayerSkillBar.skill_source；Produces正式Hero固定路径SkillHost/SkillSocket/Gather、ThreatMark及两个常规槽，Input/Controller各1；CombatRoom/PlayerSkillBar只绑定Hero/PlayerSkillController。不改Controller请求逻辑或HUD脚本。

- [x] **Step1 — 写源/正式装配RED。** 新AssemblyTest加载Hero、PlayerSkillsTest、CombatRoom，确认正式源有两个真实技能/输入/控制器、合法槽引用、HUD唯一来源；此时源尚未装配，应安全FAIL，不读不存在节点崩溃。
- [x] **Step2 — 实跑RED。** 执行PlayerSkillsCombatRoomAssemblyTest；Expected：正式Hero槽/组件、正式HUD缺失，非解析错误。
- [x] **Step3 — 开始原生场景迁移事务。** 确认源/测试都无用户未保存内容，记录所有局部覆盖。先从独立测试场景撤下其自有的Gather/ThreatMark/Input/Controller及regular_skills局部装配，保留两项CD=2的记录和HUD引用目标路径；保存中间态但不启动测试。不删除来自父源的节点。然后打开Hero源继续下一步，避免源上移后同名节点自动改名/重复。
- [x] **Step4 — 装正式Hero。** 在已有Host/SkillSocket实例化两个已有正式技能，节点名Gather/ThreatMark，regular_skills=[Gather,ThreatMark]；根挂已有InputComponent/Controller。源技能默认CD10/12，不加测试覆盖。native保存，重新实例化验证技能来自各自.tscn、Host只有1、Input/Controller各1、不创建临时资源。
- [x] **Step5 — 恢复测试必要覆盖。** 重新打开PlayerSkillsTest，确认继承Hero后路径与Host引用已解析；用Inspector原生Revert移除多余regular_skills/源装配覆盖，仅保留继承Gather/ThreatMark的CD=2。若MCP不能可靠删除单项继承覆盖，使用Computer Use原生Revert；仍无法操作才说明原因回退最小文本调整并原生重读保存。三模式/单位位置/Unsupported开关/本地HUD布局不变。
- [x] **Step6 — 装正式HUD。** 打开CombatRoom，在根实例化既有PlayerSkillBar，唯一skill_source指Hero/PlayerSkillController。原继承关系和其他组件/数值不变；本地Panel原生偏移参照独立场景放在既有生命列表右上，不改共享HUD脚本或已有伙伴栏。native保存并重新读取，检查有效UID及无悬空NodePath。源场景变化会自然传播到TestCombatRoom等Hero消费者，不改其单位实例。
- [x] **Step7 — 修复旧测试夹具而非降低行为标准。** PlayerSkillControlTest复用继承Input/Controller，不再手工.new/add_child同类节点；原probe两个技能仅覆盖运行夹具的regular_skills，保留全部受理/取消/旧回调/死亡断言。其“无新组件旧移动”夹具在进树前仅运行时移除继承Input/Controller，仍验证无适配组件时原移动正常。PlayerSkillTestSceneTest把“正式Hero未装配”过时断言改为正式源有2槽、源CD10/12且测试CD2独立；不把测试改成恒真/删除原单次计数。
- [x] **Step8 — 验证GREEN。** 执行AssemblyTest、PlayerSkillControlTest、PlayerSkillActionAnimationTest、PlayerSkillBarTest、PlayerSkillTestSceneTest、PlayerSkillCombinedFlowTest、CombatRoomAssemblyTest。Expected：7项退出0/PASS，无重复signal/节点、无解析错误、无泄漏；比较变更前源武器/角色数值和CombatRoom核心设置完全保留。
- [x] **Step9 — 记录B交付。** F5有正式技能/HUD、F6保留2秒可测配置；不能把这一步源装配通过当作全部正式战斗已验收。

### B批必须覆盖的具体行为

```gdscript
# 使用实际源实例及独立场景，不根据源码字符串猜测装配。
_expect(hero.get_node_or_null("PlayerSkillController") != null, "formal Hero has controller")
_expect(formal_host.get_regular_skill(0) == hero.get_node("SkillHost/SkillSocket/Gather"), "slot0 is own Gather")
_expect(is_equal_approx(formal_host.get_regular_skill(0).skill_cooldown,10.0), "formal Q keeps source cooldown")
_expect(is_equal_approx(test_host.get_regular_skill(0).skill_cooldown,2.0), "test keeps local fast cooldown")
_expect(room.get_node("PlayerSkillBar").skill_source == room.get_node("Hero/PlayerSkillController"), "one local HUD source")
```

同文件再覆盖：E源12秒、2个Hero实例技能对象不同、一个实例实际释放后另一实例仍ready、
打包到user临时.tscn并ResourceSaver保存/重载后仍是原槽内节点、正式敌人默认能力且无组件。
按真实InputMap Q/E各一次，accepted/start/release各1；拒绝不重复支付/CD；没有测试Probe/Harness/范围圈进入正式入口。
结构递归只按脚本类型统计，不用节点名starts_with替代实际唯一性检查。

## Task3 / C：正式战斗联合验证与交付

**Files — Modify:** UnitSystem/Tests/CombatRoomFinisherFlowTest.gd（在原真实流程前增加Q/E环节）、必要时仅扩充PlayerSkillsCombatRoomAssemblyTest的退出/重建断言。
**Docs — Modify:**
- Docs/CurrentSystemUserGuide.md（本轮玩家技能/被动位移段落及更新日期，不重写无关旧内容）
- SkillSystem/04-Docs/CombatRoomAssemblyGuide.md（Q/E正式入口/源配置/新HUD及本轮真实参数记录）
- SkillSystem/04-Docs/PlayerSkillsConfigurationGuide.md（最终源装配、UnitBase开关、Unsupported含义）
- Docs/Superpowers/Plans/2026-10-21-player-skills-staged-roadmap.md及本阶段设计/计划状态
- Docs/Superpowers/Specs/2026-10-21-player-gather-threat-skills-design.md只更新当前状态/最终入口，旧阶段事实保留为历史
**Docs — Create:** Docs/Superpowers/Plans/2026-10-22-player-skills-stage-5-validation.md。

**Interfaces:** Consumes Task2正式装配及Task1UnitBase能力；原普通damage_resolved→SquadFocus→实际指令→Round→Selection→B演出链不变。不增加生产reset、测试开关或测试专用公共接口。

- [x] **Step1 — 先扩展正式流程断言。** 仍加载真实CombatRoom，运行夹具将初始focus设0，提高敌人耐久、设置可测站位，不保存资源。先暂时关闭夹具伙伴/敌人的主动输出，在真实Q/E输入前记录生命、专注和伤害事件。敌人Q落盘以释放时快照判断，不使用结束时已移动玩家位置。
- [x] **Step2 — 正式Q/E事实验证。** 实际E一次提供temporary_threat与临时贡献，等原共享CD后Q一次至少将两个合法目标拉入同一聚拢盘；伙伴无需外挂接收器，普通敌人默认可拉。Q/E阶段damage事件=0、focus=0、评分未开窗；恢复敌人原AI确认会按仇恨选玩家，不写locked_target、不手工补仇恨。
- [x] **Step3 — 恢复真实队伍链。** 开启原伙伴AI后真实普通伤害增加focus；在发连携前先等待玩家Q/E真实CD及共享CD全部自然结束，断言两槽确实可尝试请求，不用仍在CD的拒绝证明输入隔离，也不手工reset冷却。等待上限取当前真实remaining最大值+3真实秒（普通速度下），沿原测试较低运行门槛/较短间隔发实际3，验证实际连携、银白闪光、达分窗口；确认时暂停/选择/enter/windup/exit/bombardment阶段Q/E无新受理/Effect/CD消耗。再实际3选Caster终结，5发5落地、主要特效归零、镜头/时间恢复；后续Q/E在输入许可恢复且各自真实CD就绪后重新可受理，不将尚在10/12秒正常CD误判为演出残留。
- [x] **Step4 — 生命周期与保护范围。** 终结结束及真实冷却就绪后再次输入E，先断言状态/贡献确实存在，再让玩家死亡，应撤销其临时状态/仇恨，活动外力回收碰撞例外；一次卸载/重建，新对象无旧CD/绑定/暂停令牌。若常规怪物死亡删除，观察使用弱引用/有效性判断，测试不读已销毁实例。比较TestScene哈希和源参数快照；不为测试方便保存单位重摆/耐久/临时低门槛。
- [x] **Step5 — 针对新增行为实跑。** 修改测试先跑：若Task1/2已使新断言直接PASS，记录为集成验证，不虚构RED、不改生产代码制造失败；若发现真实问题，按诊断→最小复现RED→修正→GREEN。Expected：CombatRoomFinisherFlowTest、AssemblyTest及原PlayerSkillCombinedFlowTest退出0，无新增报错/泄漏。
- [x] **Step6 — 原生双入口。** headless停完后F6训练/Threat/Squad三模式检查Q/E、Unsupported、特效与冷却；F5正式入口检查源CD10/12、真实E引怪/Q聚拢、Guardian按原仇恨竞争、伙伴输出、1—4连携/终结、退出时间恢复。实际截图检查原2560×1440和1280×720逻辑视口下新增Q/E不叠既有生命/伙伴栏；既有低分辨率布局问题仍单独记录。若导航基线阻断真实追击，明确报告不能验收的步骤并讨论，不临时改导航/移动逻辑冒充通过。
- [x] **Step7 — 完整回归。** 沿第4节全量枚举，每项核对退出码及SCRIPT ERROR/ERROR/ObjectDB泄漏/invalid UID，不只搜PASS。Expected：无新增失败；原CameraFollowControllerTest导航未烘焙和SingleSceneFireboltTest旧6m断言单独列出。测试数量由实际枚举决定，不硬凑181；预计旧测试迁名+新增Assembly后约182。
- [x] **Step8 — 文档同步与一次只读独立review。** reviewer只比较stage5快照/新增文件，不归责HEAD全部dirty差异；检查上文5个Review Focus、Inspector/文件结构、临时组件完全移除与场景去重。重要问题一次RED→GREEN修正再全量；轻微发现记录交付，不顺手扩建系统。
- [x] **Step9 — 交付并停止。** 更新validation、路线状态、实际文件清单与F5/F6操作；用户能直接Inspector配置单位开关与Hero槽。未获授权不Git提交/上传，不继续其他玩法。

## 4. 可复制验证命令

以下函数只在测试终端会话中声明，不创建生产工具；调用前停原生游戏：

```powershell
$stageGodot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
$stageProject = 'G:\Godot\ProjectVOD'
function Test-StageScript([string]$ScriptPath) {
    $stageOutput = & $stageGodot --headless --path $stageProject --script $ScriptPath 2>&1
    $stageExit = $LASTEXITCODE
    $stageOutput
    if ($stageExit -ne 0 -or [bool]($stageOutput -match 'SCRIPT ERROR|ERROR:|ObjectDB instances leaked|invalid UID')) {
        throw ('Test failed: ' + $ScriptPath + ' exit=' + $stageExit)
    }
}
Test-StageScript 'res://UnitSystem/Tests/UnitForcedMovementTest.gd'
Test-StageScript 'res://SkillSystem/05-Tests/PullTargetSkillEffectTest.gd'
Test-StageScript 'res://UnitSystem/Tests/PlayerSkillsCombatRoomAssemblyTest.gd'
Test-StageScript 'res://UnitSystem/Tests/CombatRoomFinisherFlowTest.gd'
```

其余确切测试路径：
- res://UnitSystem/Tests/PlayerSkillControlTest.gd
- res://UnitSystem/Tests/PlayerSkillActionAnimationTest.gd
- res://UnitSystem/Tests/PlayerSkillBarTest.gd
- res://UnitSystem/Tests/PlayerSkillTestSceneTest.gd
- res://UnitSystem/Tests/PlayerSkillCombinedFlowTest.gd
- res://UnitSystem/Tests/CombatRoomAssemblyTest.gd
- res://SkillSystem/05-Tests/GatherPresentationTest.gd
- res://SkillSystem/05-Tests/ThreatMarkPresentationTest.gd

Task0基线命令使用迁名前res://UnitSystem/Tests/ForcedMovementComponentTest.gd。RED阶段预期抛出失败，必须读到预定行为断言后再开始实现。
全量沿现有rg枚举所有非Archive/addons的*Test.gd、过滤首行extends SceneTree，最多4并行；记录每项结果与汇总，不把已知失败吞掉。

## 5. 计划自查与批准门槛

- A→B：UnitBase请求/开关/信号的名称、类型完全一致，B不再挂接收器。
- B→C：Hero固定节点名Gather/ThreatMark与测试/HUD路径一致；正式/测试CD10/12与2秒隔离。
- 当前全部旧接收器活动引用已定位在本计划Task1文件清单；正式Hero上移会影响的旧夹具已明确列入Task2。
- 删除临时组件前必须迁移引用并实际验证；没有“先删文件让解析报错”式RED。
- 设计第3—4节由Task1覆盖，第5节由Task2覆盖，第6—7节由Task3覆盖。
- 测试夹具改变旧事实而非降低行为要求；旧物理/重入/回收断言保留，新增玩家实际运动断言。
- 不把文档写完或场景可加载等同于玩法验证；F5/F6与完整回归、review都有独立证据。
- 正式输入隔离测试在玩家技能真实冷却已自然结束后进行，避免用冷却拒绝掩盖输入穿透；死亡清理先建立新有效E，避免对已到期空状态做恒真断言。
- 三批顺序固定、每批可测；执行方式沿用此前已选择的当前会话本人实施、阶段末一次独立review。
- 用户2026-10-22已确认书面设计及“先内置位移再正式装配”顺序；本计划已获用户批准并实施；实际证据以阶段五validation为准。

最终状态：三批实施、定向/原生/全量验证及一次独立review已完成，用户体验验收待确认；182项180通过、2项既有失败，P3玩家活动推进/冲刺前提覆盖缺口保留，不宣称已动态验证。详见阶段五validation。
