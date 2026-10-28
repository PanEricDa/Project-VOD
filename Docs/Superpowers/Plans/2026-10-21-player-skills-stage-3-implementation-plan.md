# 玩家技能阶段三：临时仇恨与E Debuff实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this approved plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking. 本文仅细化阶段三，不授权连做阶段四、五。

**Goal:** 将独立测试场景的E探针替换为真正的限时仇恨技能，让敌人依既有仇恨规则转向玩家，并在状态结束时只撤销对应临时贡献。

**Architecture:** 复用SkillBase、InstantTargetDelivery、ThreatChangeSkillEffect、EnemyThreatComponent和StatusEffectComponent。状态容器唯一管理持续时间；仇恨容器区分普通池和临时贡献并统一查询。效果组件只协调绑定，不持有持续计时，也不建立玩家专属仇恨、目标锁定或技能执行管线。

**Tech Stack:** Godot 4.7、GDScript、SceneTree测试、Godot MCP Pro原生场景保存。

**Spec:** [玩家聚拢与临时仇恨技能设计](../Specs/2026-10-21-player-gather-threat-skills-design.md)，尤其第6节；[五阶段路线](2026-10-21-player-skills-staged-roadmap.md)阶段三。

状态：2026-10-21用户已确认并实施阶段三；核心功能和177项回归已完成，独立review发现的3项边界问题已测试复现并修复；最终177项回归175通过、仅两项既有失败；等待用户体验验收。阶段四、五不实施。

## Global Constraints

- 用户已验收Q；以当前保存属性为准，禁止回写旧默认值。Q作用半径3.5米、圆心前移3米、拉动时长0.12秒、落点身前1.5米、散布半径0.6米、施法0.2秒；技能源冷却10秒，测试场景局部冷却2秒。
- 仅显示Q青蓝示意圈；E范围圈维持关闭。示意圈读取实际Delivery，不创建重复范围参数。
- 编辑优先Godot MCP Pro；不覆盖编辑器未保存修改，不修改插件，不自动提交Git或上传。
- 延续用户选择，在当前G:/Godot/ProjectVOD目录工作，不新建工作树。
- 不更改Scenes/TestScene.tscn单位；前四阶段不把玩家技能装到正式Hero/EnemyBase/CombatRoom。
- 不实现UnitBase被动位移迁移；该项仍属最后统一优化。
- 不增加强制目标、仇恨权级、特殊聚怪状态、远程射程调整或玩家技能专注消耗。
- 不制作阶段四的完整技能栏及释放特效，不扩展驱散玩法或运行时装卸系统。
- 正式外部Resource若新增，必须Godot保存并验证UID；本阶段计划不新建.tres/.res。
- export和公开接口就近提供中文说明，内部token/账本/事务参数不暴露到Inspector。
- 基线既有失败单独记录：CameraFollowControllerTest正式房间导航未烘焙；SingleSceneFireboltTest旧断言6米与当前5米配置不一致。

## Review Focus

1. 刷新状态时，旧撤销回调不能删掉新贡献；Task 2以刷新/重入断言覆盖。
2. 普通伤害、治疗仇恨、查询比例、目标选择与调试使用同一合计值；Task 1和Task 3覆盖。
3. 自然衰减后到期，不得从总池硬减初始量；Task 1/2覆盖。
4. 状态创建失败、来源失效或回调重入，不得破坏旧记录或复活新一代已结束记录；Task 2/3覆盖。
5. 归位清仇恨不能留下状态点；状态移除也不能留下贡献；Task 2/4覆盖。

## 1. 当前代码核对

- EnemyThreatComponent已有统一submit_threat、get_threat_for、snapshot、比例和resolve_target；目前只有按来源存储的普通池，_process按原S形曲线衰减。
- EnemyBase._on_threat_changed会刷新既有索敌；死亡和RETURN_HOME均调用clear_threat。无需额外写玩家目标或新建AI状态。
- StatusEffectComponent已有命名状态和属性修正，但命名状态目前只有status_id→剩余时间，缺少来源、效果身份与清理回调。
- ThreatChangeSkillEffect只提交固定SKILL_BONUS；Guardian继续使用这条普通分支。
- WorldHealthBar已订阅named_status_changed，可沿用已有状态小点行。
- 专用测试场景E仍是ProbeE；训练敌人关闭感知且原地待机，单纯替换技能不能直接宣称已经验证真实追击。

## 2. 对外配置与内容

新增正式技能：
`SkillSystem/00-Skills/Player_ThreatMark/ThreatMarkSkill.tscn`

根节点继承SkillBase：
- skill_id=player_threat_mark，display_name=Threat Mark，类型Debuff。
- 自身启动，不要求锁定；自动施法关闭；允许移动/转向；施法0.15秒。
- 源场景冷却12秒；测试实例覆盖2秒，沿用用户方便测试的约定。
- Delivery沿用InstantTarget / CASTER_RADIUS / WORLD_SCOPE / HOSTILE，半径5米、圆心偏移0。
- 子节点ThreatChangeSkillEffect：threat_amount=2000，新增duration_seconds=8。
- action_animation为空，沿用已有Sword/basic_cast_1；不新增占位动画和特效。

策划只需要配置：
1. 技能根节点的已有基础属性和Delivery。
2. Effect的仇恨量与持续时间。

duration_seconds默认0，含义为普通永久入池后依原规则衰减，不创建状态；正值才创建绑定的临时贡献。duration_seconds为负数、NaN或Inf应拒绝，不能静默改成普通仇恨。

temporary_threat为该限时Effect内部稳定状态标识，不额外提供一个容易填错的Inspector字段。效果身份优先读取现有context.damage_context.skill_id（先判空）；不新增SkillContext.skill_id字段；同来源同技能同Effect类别刷新。未提供skill_id的直接调用使用稳定通用Effect标识，不使用Effect节点实例ID作为持续效果身份。

## 3. 账本、状态与生命周期

### 3.1 仇恨合计

`来源有效总仇恨 = 普通池当前值 + 此来源所有有效临时贡献当前值`

普通池既有新增/衰减参考值保持原样；每笔临时贡献保存自己的当前值和参考峰值，共用原衰减算法，不能让普通伤害反复刷新临时贡献的衰减起点。

同一目标、同一来源、同一effect_key刷新而不叠加，重新设为本次amount；其他来源/技能独立。临时账本不保存剩余秒数。

公开运行时接口：
- `upsert_temporary_threat(source:UnitBase,effect_key:StringName,amount:float)->int`：返回本次有效贡献token，0拒绝；有限正amount、有效树内敌对存活来源才接受。
- `remove_temporary_threat(token:int)->bool`：只撤销对应身份，重复安全；旧token不能影响新一代。
- `temporary_threat_removed(token:int)`：贡献因状态以外的原因被撤销时供生命周期解绑；不承载倒计时。
- get_threat_for/get_threat_snapshot/比例/resolve_target全部使用合计值，不暴露可写内部字典。

每笔记录使用弱来源引用；账本退出、来源死亡/离树、无敌对关系、敌人死亡/归位清表都清理对应记录。状态仍有效而贡献自然衰减至极小值时，数值按原阈值归零，但保留其绑定身份到状态结束，避免把“仇恨数值耗尽”误作提前驱散。

### 3.2 状态绑定

在现有StatusEffectComponent内部增加带来源的BoundStatusRecord，不新建组件或Resource资产。记录保存status_id、来源弱引用、effect_key、唯一代际token、剩余战斗秒数和清理Callable。

公开运行时接口：
- `apply_bound_status(status_id:StringName,source:UnitBase,effect_key:StringName,duration_seconds:float,on_removed:Callable)->bool`：同来源同效果刷新；成功绑定才返回true。
- `has_named_status`、`get_active_status_ids`聚合原命名状态和绑定记录；同名多来源只有全部结束后才发送active=false。
- `remove_named_status`和`clear_all_named_statuses`同时覆盖绑定记录，先脱离容器再调用清理，防止回调重入误删。
- 在内部保存外部贡献终止的连接，用token过滤旧通知；连接由状态容器持有，不依赖技能Effect节点是否还活着。
- 唯一身份由prepare接口返回；remove_bound_status(token:int)->bool只移除指定代。旧五参数apply_bound_status保留为prepare+commit的便捷入口，避免改动现有调用假设。

普通命名状态与绑定状态的任一清理都不能误发同名聚合active=false。仍由advance_effects使用战斗delta统一推进；暂停不计时、5%慢放按世界流速计时。不得同时在Threat或Timer再记一份8秒。

### 3.3 原子刷新与失败处理

必须先验证所有输入和两个容器，再准备新一代记录；旧状态和贡献保留到本次绑定能够提交。仅验证参数合法，不能替代状态创建失败测试。

采用固定的准备/提交顺序，不让实现者另选跨模块的私有字典写入方式：

- Threat新增运行时接口prepare_temporary_threat(source:UnitBase,effect_key:StringName,amount:float)->int、commit_temporary_threat(token:int)->bool、discard_temporary_threat(token:int)->void。prepare只暂存、不计入查询或发送变化；commit替换同键旧贡献并发布合计变化；discard只丢弃尚未提交的一代。upsert是前两步的便捷包装。
- Status新增prepare_bound_status(status_id:StringName,source:UnitBase,effect_key:StringName,duration_seconds:float,on_removed:Callable)->int、commit_bound_status(token:int,on_commit:Callable=Callable())->bool、discard_bound_status(token:int)->void、remove_bound_status(token:int)->bool。prepare不改变旧状态和倒计时；commit先安装待提交状态，在通知前调用可选on_commit；返回false时撤销自身新代，旧有效记录保持不变。
- Status提供bind_external_status_removal(bound_token:int,external_end_signal:Signal,external_token:int)->bool；信号须只有一个int身份参数，容器内部连接并核对token；只保存发出者弱引用与信号名，解除记录先断连。此接口不识别Threat类或具体技能。
- Effect顺序：准备临时贡献→准备绑定状态（清理回调绑定remove_temporary_threat和新token）→登记外部终止信号→commit_bound_status，其on_commit为commit_temporary_threat。失败只discard本代；成功后两个准备表均不得残留。
- commit_temporary_threat发出threat_changed时，新状态已安装；named_status_changed发出时，新贡献已可查询。旧状态与旧贡献的撤销只能携带旧token。发生通知回调重入后必须复查代际，旧commit不能覆盖新请求。
- 这些接口只服务跨容器的一次Gameplay绑定，无export参数、无新Resource、无装备事务系统；日常策划仍只看到仇恨量和持续时间。

若创建失败，仅丢弃本次待提交记录，旧状态/旧贡献及剩余时间不变；若提交后因死亡/离树被正常终止，则按生命周期撤销，不复活旧记录。任何旧回调都要校验代际，不能覆盖回调中新产生的请求。

Effect只在单次apply中做协调；存续期间的撤销Callable绑定仇恨容器和token，不绑定Effect自身，不能捕获整份SkillContext或以技能存活为前提。

## 4. 文件交付与任务

正式新增1个.tscn，测试新增2个.gd；不计划新增正式.gd/.tres/.res。Godot生成的.gd.uid保留。文档另计。

### Task 1：普通池与临时贡献统一查询

**Files**
- Modify: UnitSystem/Components/Threat/EnemyThreatComponent.gd
- Create/Test: UnitSystem/Tests/TemporaryThreatLifecycleTest.gd

**Interfaces**
- Consumes: UnitBase存活/阵营/离树事实、ThreatEvent与原S形衰减参数。
- Produces: 第3.1节临时贡献接口与合计查询；普通submit_threat默认契约不变。

- [x] 编写test_expiry_preserves_ordinary_pool：关闭衰减时assert(total==2100)，追加普通50后assert(total==2150)，撤销临时token后assert(total==150)。
- [x] 编写失败测试：开启衰减时，单独普通150的对照池与撤销临时贡献后的普通池一致，而非总池减2000。
- [x] 编写失败测试：两来源、同来源两效果、重复刷新不叠加、相对最高竞争者比例和snapshot一致；默认Guardian普通加仇恨不变。
- [x] 运行TemporaryThreatLifecycleTest确认RED来自缺少接口/行为，不是解析错误。
- [x] 实现账本与共享衰减计算，所有最终查询统一合计；原目标切换倍率不变。
- [x] 运行TemporaryThreatLifecycleTest、EnemyThreatComponentTest、EnemyThreatIntegrationTest、HealingThreatIntegrationTest、PlayerThreatFocusControllerTest和ThreatDebugDisplayTest，预期全部PASS且无引擎错误。

### Task 2：单一时钟与绑定生命周期

**Files**
- Modify: UnitSystem/Components/Status/StatusEffectComponent.gd
- Modify: UnitSystem/Components/Threat/EnemyThreatComponent.gd
- Test: UnitSystem/Tests/TemporaryThreatLifecycleTest.gd

**Interfaces**
- Consumes: Task 1 token/撤销接口与信号。
- Produces: apply_bound_status、聚合状态查询、原子刷新与两侧解除。

- [x] 补RED：test_bound_status_expiry_and_refresh / test_partial_source_expiry。8秒到期assert(not has_named_status)，4秒刷新后再走4.1秒assert(has_named_status)；两来源只到期一笔时assert(has_named_status)。
- [x] 补RED：remove_named_status、clear_all_named_statuses、来源死亡/离树、敌人死亡、clear_threat/归位、退出；状态和贡献均清理。
- [x] 补RED：创建失败旧贡献不变，旧回调迟到、新回调重入不能删除新代；撤销不持有已销毁Effect。
- [x] 实现内部BoundStatusRecord、状态聚合、单一战斗时钟、代际隔离与提交顺序。
- [x] 跑TemporaryThreatLifecycleTest、StatusEffectComponentTest、ConsumeNamedStatusSkillEffectTest、ApplyNamedStatusSkillEffectTest、WorldHealthBarDebuffTest；预期PASS，不改变灼烧、降防和属性修正行为。

### Task 3：复用ThreatChangeEffect和正式E技能

**Files**
- Modify: SkillSystem/03-Extensions/ThreatChangeSkillEffect.gd
- Create: SkillSystem/00-Skills/Player_ThreatMark/ThreatMarkSkill.tscn
- Create/Test: SkillSystem/05-Tests/TemporaryThreatSkillEffectTest.gd

**Interfaces**
- Consumes: Task 1/2统一账本与状态绑定、现有context.damage_context.skill_id、SkillEffectBase/Delivery。
- Produces: duration_seconds默认0兼容分支和正式Threat Mark场景。

- [x] 补RED：test_default_permanent_and_timed_branch。duration=0重复两次assert(threat==400)；duration=8重复两次assert(temporary_total==2000)，到期assert(temporary_total==0)；非法duration不新增普通仇恨。
- [x] 补RED：不适用单位混合批次只跳过当前Effect；状态拒绝时无临时残留、旧有效记录不变。
- [x] 实现duration_seconds与can_apply_to适用性查询；不能把参数错误吞成“无目标”。
- [x] 用Godot原生继承/保存技能，不另建Delivery脚本、玩家专用Effect或状态Timer。
- [x] 跑TemporaryThreatSkillEffectTest、ThreatChangeSkillEffectTest、SkillSystem/05-Tests/GuardianTauntSkillTest.gd、UnitSystem/Tests/GuardianTauntIntegrationTest.gd、PullTargetSkillEffectTest瞬发范围兼容契约；预期PASS，正式场景有有效UID。

### Task 4：同场景真实E输入、状态点与接续验证

**Files**
- Modify: Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn
- Modify: Scenes/Tests/PlayerSkills/PlayerSkillsTestHarness.gd
- Modify: UnitSystem/Components/UI/WorldHealthBar.gd
- Modify: UnitSystem/Tests/PlayerSkillTestSceneTest.gd
- Modify: UnitSystem/Tests/WorldHealthBarDebuffTest.gd
- Create: Docs/Superpowers/Plans/2026-10-21-player-skills-stage-3-validation.md

**Interfaces**
- Consumes: Task 3正式E、既有InputMap/槽位和WorldHealthBar状态订阅。
- Produces: F6实际可验证的E及只读反馈；保留Q已验收参数/示意圈。

- [x] 补RED：E槽为正式SkillBase、一次真实输入只施放一次、无伤害/专注/连携事件；独立冷却2秒。
- [x] 补RED：temporary_threat产生独立玫红色状态点；与灼烧和降防共存，到期去掉自身小点，不提前隐藏其他状态。
- [x] 在专用测试场景替换ProbeE实例并更新Regular Skills引用；增加测试专用的Training / Threat Combat切换按钮；默认Training保持现有Q靶子，切换通过重载专用测试世界并在_ready中读取一次测试模式标记。Threat Combat开启敌人原有感知、行为与战斗；不是生产AI新状态。
- [x] 在专用测试场景ValidationActors下挂Guardian源场景实例，命名ValidationGuardian，初始(-2,0,5.5)。Training模式在开始训练前移除该验证实例；Threat Combat保留且启用原有AI和普通技能。只修改这个专用场景，不动受保护TestScene或Guardian源数值，不在生产类加测试reset。
- [x] Harness只读展示目标/玩家合计仇恨/状态有无；不给HUD独立状态倒计时，不增加E范围圈或复杂技能栏。
- [x] 自动集成验证：Guardian先有普通400、E后敌人依既有规则选择玩家、8秒后临时贡献归零、Guardian依真实仇恨再次竞争；不保证违反当前倍率/感知规则的强制接管。
- [x] 原生F6按E并移动，检查近战追击和远程维持原射程；到期状态点消失，Q拉拽仍按当前配置有效。手动/自动结果一致才交付。
- [x] 全量回归并逐项分类，独立review只读检查生命周期与Q配置保护；记录PASS/既有失败/新增失败以及Debugger/泄漏。之后停止，等阶段三体验验收，不进入阶段四。

## 5. 验证命令

PowerShell模板（每个Task替换对应脚本）：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/TemporaryThreatLifecycleTest.gd'
```

通过标准：对应PASS、退出码0，且没有SCRIPT ERROR、ERROR、ObjectDB泄漏或残留资源警告。若测试只打印PASS但有引擎错误，仍按失败处理。

人工入口：Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn，F6。正式主场景本阶段不接入。

## 6. 当前推进记录

- [x] 用户确认Q调试通过，原生读取当前保存配置并将其作为新基准。
- [x] 更新旧范围圈测试，消除2米/0.8米硬编码断言；保留独立控制值测试，确保不是删断言来掩盖问题。
- [x] 当前PlayerSkillTestSceneTest与PullTargetSkillEffectTest均PASS。
- [x] 完成阶段三详细设计及计划自审：四个任务覆盖账本、状态、Effect、正式内容、AI接续和状态点。
- [x] 用户已确认细化计划，按原有方式当前会话本人执行；最终独立review与修正已完成。
- [x] Task 1—4实施与数据验收。

不自动Git提交或上传。E技能与新接口已实现；结果见2026-10-21-player-skills-stage-3-validation.md。
