# 玩家双槽技能与联测配置指南

更新：2026-10-23，目标聚拢独立技能。正式Hero/CombatRoom已接入Q/E；专用场景继续提供三种模式和2秒测试冷却。

## 一、直接体验

正式体验：直接F5启动 `res://Scenes/CombatRoom.tscn`。Q以锁定敌人释放位置为中心聚拢5米范围敌人（拉拽完成后减速90%、持续3秒），无锁定拒绝；E临时仇恨，正式冷却分别10/12秒。

隔离测试：打开 `res://Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn`，按F6。

- 默认Training：静止靶，先F/鼠标中键锁定再Q，验证目标聚拢、E临时仇恨和2秒测试冷却。
- 左上Next按钮依次切换Threat Combat、Squad Combat、Training；每次重建当前场景，状态不继承。
- Threat Combat：真实敌人AI+验证Guardian，观察E拉怪、8秒到期后普通仇恨竞争。
- Squad Combat：四伙伴、普通战斗、专注、1—4连携和终结演出均复用正式链路。
- Q/E后可以继续原WASD、目标锁定；1—4按现有规则请求伙伴连携，达分闭窗后同按键选择终结。
- Reset重建当前模式。模式本身仅测试脚本元数据，不是正式玩法状态。
- Squad模式收起长调试读数，保留观察器及模式按钮；切回Training可看完整Q/E计数。
- Unsupported根节点的Forced Movement / Forced Movement Enabled故意关闭，Q跳过它，E正常生效；不是随机拉拽失败。所有单位不再挂接收器。

## 二、Inspector装配入口

```text
PlayerSkillsTest
  Hero（继承正式源装配，仅覆盖技能CD=2）
    SkillHost
      regular_skills = [Gather, ThreatMark]
      SkillSocket
        Gather（Player_TargetGather/TargetGatherSkill.tscn，测试CD=2；原节点名保持槽引用）
        ThreatMark（Player_ThreatMark/ThreatMarkSkill.tscn，测试CD=2）
    PlayerSkillInputComponent（InputMap动作名）
    PlayerSkillController（请求/只读槽状态）
  PlayerSkillBar（skill_source只拖Hero/PlayerSkillController）
  ValidationActors（四个已有伙伴源场景）
  原SquadFocus / Command / Presentation / Round / Selection / Execution及三种HUD
```

PlayerSkillBar仅一个导出字段：`skill_source: PlayerSkillController`。
快捷键从PlayerSkillInputComponent的动作名和InputMap读取；名称、图标、自身冷却从Host当前槽的SkillBase读取。
图标为空使用名称首字占位；不用复制技能配置，不增加图标资源。
常用数据都沿已有Inspector：Q/E根技能、Delivery、Effect和InputMap；本HUD不提供另一套数值。

技能栏场景：`UnitSystem/Components/UI/PlayerSkillBar.tscn`；
布局编辑Panel原生Control偏移，颜色/字体/反馈边框编辑原生Theme；0.25真实秒反馈为内部常量。
正式CombatRoom与独立测试场景局部将Q/E放在五人血条右上；不修改共享HUD脚本或既有血条布局。
技能栏所有Control忽略鼠标，不提供点击施法；技能栏隐藏/解绑不会取消技能。

## 三、只读与执行边界

`PlayerSkillController.get_slot_status(0或1)`返回独立Dictionary：
configured/skill_name/icon/input_action、phase/can_request/reason、
cooldown_remaining/cooldown_duration及global_cooldown_remaining/global_blocked。
phase为empty、ready、casting、cooldown或blocked。
can_request仅表示当前可尝试输入；目标、Condition、费用仍由原技能管线最终判定。
共享冷却不是技能自身冷却，动作忙/死亡/禁用也不伪装成新CD。

UI只消费Controller及slot_accepted/slot_rejected；`bind_source`幂等，
`unbind_source`仅解除UI监听，`refresh_immediately`只读刷新。
按下预选绿框并轻微放大，松开确认；受理／施放显示绿底，拒绝短红边。剩余CD直接读取真实SkillBase，不另起倒计时。
交互组件、共用主题和装配说明见 Docs/SkillInputFeedbackGuide.md；目标在松开时读取，普攻仅在确认且合法时抢占。
UI暂停时仍刷新，CD仍由战斗时钟负责。

## 四、联测装配与模式隔离

四伙伴在ValidationActors中，Inspector可直接查看：
Guardian(-2,0,5.5)、Priest(0,0,7.5)、Caster(-3,0,6.5)、Archer(1,0,6.5)。
指令槽顺序Guardian/Priest/Caster/Archer；全部引用本地CameraRig与本测试世界。
当前联测参数复制自2026-10-22读取的CombatRoom：
initial_focus=100，focus_gain_difficulty=2，score_difficulty=2，
hit_score_scale=15，damage_score_scale=1000.01；没有反向修改正式关卡。
这只是一次显式测试场景配置，不要求跨场景同步修改。

Harness在_enter_tree移除非本模式的伙伴/队伍系统，避免内部ALWAYS组件在_ready抢输入。
Training没有伙伴/连携系统；Threat只有Guardian；Squad才保留完整链路。
HUD不从Harness读取技能数据；Harness不能模拟伤害、专注或评分。

## 五、输入与暂停

原终结输入持有现在沿SquadChainCommandController传到PlayerBase通用输入许可：
多个持有者互不释放；基础set_player_input_enabled(false)不被演出结束覆盖。
正常owner退树自动撤回自己的输入持有。
新Q/E、移动/攻击/锁定读取同一许可；已开始行动不因新输入锁被额外取消。
不靠5%速度推断能否输入，不在技能中硬编码“终结期间”的分支。

## 六、数值及效果位置（保持已验收数据）

- Q：`SkillSystem/00-Skills/Player_TargetGather/TargetGatherSkill.tscn`。技能目标为当前锁定敌人，默认施法距离5m；Delivery用TARGET_RADIUS/WORLD_SCOPE/5m，Pull用TARGET_POSITION/聚拢半径0/0.12秒；源CD10秒，测试局部2秒。原身前技能Player_Gather/GatherSkill.tscn只从玩家槽卸下，源参数和原预览保留。
- E：`SkillSystem/00-Skills/Player_ThreatMark/ThreatMarkSkill.tscn`。5m、2000临时仇恨、8战斗秒。源CD12秒，测试局部2秒。
- Q/E已有独立Effects/Skills/Gather和ThreatMark特效/Preview；本阶段不制作新美术。
- 所有单位根Inspector：Forced Movement / Forced Movement Enabled，默认true；关闭立即取消当前外力、恢复本请求新增的单位碰撞例外，重新开启不恢复旧请求。
- UnitBase保存请求/生命周期；PlayerBase和AIUnitBase仍在原物理循环消费，保持重力、墙碰撞和唯一move_and_slide。禁用玩家新输入不等于免疫外力。
- 通用代码接口：UnitBase.request_forced_movement(source,世界XZ目的地,战斗秒,ignore_unit_collisions=false)；正token仅代表受理，0拒绝。cancel_forced_movement(token)及started/finished信号均在同一单位上，不找子节点。
- 裸UnitBase只有协议，实际运动由Player/AI原执行者完成；本轮不新增移动循环。
- 正式装配唯一入口：UnitSystem/Player/Hero/Hero.tscn → SkillHost/SkillSocket/Gather、ThreatMark；Host的Regular Skills引用这两个节点，根下Input/Controller各一个。后续换技能沿槽/信号，不在UI重复配置技能资产。
- 正式HUD：Scenes/CombatRoom.tscn → PlayerSkillBar → Skill Source，指向本地Hero/PlayerSkillController。

## 七、自动验证与后续

PlayerSkillBarTest：真实槽状态、CD、InputMap重绑、空图标、忙碌/暂停/死亡、UI解绑不影响动作。
PlayerSkillCombinedFlowTest：三模式、真实E/Q无直接伤害专注、普通AI获取专注、真实连携达分/五火球B终结、
Q/E输入隔离、多所有者许可、来源死亡清理、一次正常重建。
夹具仅在运行实例提高敌人耐久/调整难度以减少随机性，不写回资源、不伪造伤害/资格。
阶段五已接入正式源并迁移UnitBase；UnitForcedMovementTest、PlayerSkillsCombatRoomAssemblyTest及扩展CombatRoomFinisherFlowTest覆盖物理/装配/真实完整战斗。验收证据见Docs/Superpowers/Plans/2026-10-22-player-skills-stage-5-validation.md；Git操作仍需另行授权。


## 八、目标聚拢与旧技能的独立性（2026-10-23）

两份技能均继承SkillBase.tscn，通过同一个InstantTargetDeliveryConfig、PullTargetSkillEffect、UnitBase和表现通道执行，不新增专有技能脚本或执行管线。输入适配根据技能目标配置供给Self或当前锁定，不识别具体技能ID；非Self技能无锁定返回target_missing，普通E仍无需锁定。

Q在按键时绑定原锁定目标，释放时取其当时位置；之后玩家换锁定、转身或目标继续走动，不改变本次已冻结落点。目标释放前死亡等仍按原合法性取消。范围为水平距离，保留原边界容差、单位外力开关及世界碰撞。

范围示意圈在无锁定时隐藏、有锁定时跟随目标。新独立预览为Effects/Skills/TargetGather/TargetGatherEffectPreview.tscn；旧GatherEffectPreview仍演示旧身前技能。详情见[目标聚拢配置](TargetGatherSkillConfigurationGuide.md)。

当前Q完成后减速配置：TargetGatherSkill/PullTargetSkillEffect/StatModifierSkillEffect，选择交付目标、移动速度、百分比-90、持续3秒、REFRESH。该子效果在拉拽自然完成且实际移动后执行；中心原目标/免疫/取消不附加。详见[目标聚拢配置指南](TargetGatherSkillConfigurationGuide.md)第7节。

## 玩家技能优先普攻与续段（2026-10-23）

有效Q/E输入不再被普攻占用拦截。PlayerSkillController允许请求进入既有Host；目标、距离、冷却、GCD、Condition/费用以及动作端点/资产仍正常验证。仅在动作验证成功后，PlayerAttackController关闭当前普攻Hitbox、攻击位移及局部卡刀，保存下一段逻辑序号，并立即切入技能动作。无目标、超距、冷却中、施法封锁或无效动画，不打断原普攻、不隐藏排队。

技能动作完成（finish_action）而非release_action或投射物命中后恢复：
- 同武器第二段被打断，下一段为第三段；末段被打断则回到第一段。不重播被打断段，不补发未发生命中，已发生伤害不回滚。
- 技能过程中保存段数不超时。技能结束时仍按住普攻，且AttackController / Hold To Auto Chain开启，立即接下一段。
- 已松键或关闭自动连段，则进入原Combo Reset Duration配置的等待窗口，只有新输入才继续；超时后从第一段开始。Hero当前续段窗口仍为0.3秒，本次不改数值。
- 死亡、取消技能、卸装/切换武器、离树均清除旧续段；输入被禁用时不补发攻击。切换武器后从新武器第一段开始，按新武器自身段数运作。
- 技能动作期间普攻不覆盖技能，另一个普通技能也不抢占当前技能；原冲刺互斥规则不变。
- 结束通知先交由Host清理旧技能，再恢复普攻；动作身份与续段版本防止同步取消、换装、新技能回调被旧栈覆盖。

装配/维护入口：
- UnitSystem/Components/Combat/PlayerSkillController.gd：输入与HUD只把外部技能视为不可抢占占用，普攻时仍可显示技能可用；不复制技能合法性算法。
- UnitSystem/Components/Combat/PlayerAttackController.gd：通用动作抢占与下一段保存/恢复；内部封装不新增Inspector参数，不读取技能ID或具体武器名。
- 武器仍仅提供已有WeaponData、AnimationLibrary和标准动作方法帧；没有修改任何武器库/动画、技能场景或单位装配。现有Sword/Shield等不同段数武器共用相同控制逻辑。
- 无RESET库时停止动画使用keep_state，避免卸装后再次停止时重采样已移除的weapon/RESET。

验证：PlayerSkillAttackPreemptionTest使用真实Hero/Host/攻击控制器/动画，覆盖两件武器、段数续接、松键/超时、末段循环、忙碌与无效请求保护、命中窗口/位移/卡刀清理、死亡/取消/换装/卸装/输入禁用、结束回调重入以及InputMap按住普攻时输入技能。旧PlayerSkillControlTest中“普攻中拒绝技能”断言同步更新为已确认的新规则。

补充回归：普攻attack_finished通知内同步插入技能时，旧普攻完成栈在通知后重新验证动作版本及状态，防止覆盖已受理技能；新增真实动画推进用例先RED后GREEN。UnitDeathLifecycleTest同步改为技能可抢占普攻，并在死亡前重新建立真实普攻与攻击位移，保留其原有死亡清理测试目的。

正式武器库兼容性：Shield/basic_cast_1的finish_action方法键时间为float32约0.6000000238秒，动画length为double 0.6秒；PlayerAttackController校验允许is_equal_approx意义下的末帧表示差异，仍拒绝真正超出长度的方法帧。新增用例直接使用原Shield库（无显式测试Action覆盖），验证技能成功finish并续接第二段；没有修改用户动画或额外复制动画资产。

最终验证：全量185项，183通过；仅原有CameraFollowControllerTest（导航未烘焙）与SingleSceneFireboltTest（旧6米断言、当前源5米）失败。无新增SCRIPT ERROR、资源泄漏或invalid UID。独立只读审查提出的普攻结束回调重入问题已先RED后修正，末帧浮点兼容性复核无新增重要问题。原生F6实际InputMap按住普攻输入E：剑attack1→accepted(external=true)→release→finish与attack2同一毫秒；运行时换盾后重复验证，盾finish与attack2同为19530ms，原生E受理/开始/释放/完成各1、取消0、affected5，Debugger errors0。运行时换盾和观察节点未保存。武器库/动作资产、Hero装配、Q/E场景均未编辑，protected TestScene不存在且未创建。所有编辑使用Godot MCP Pro，无Git提交或推送。测试日志：.godot/player_skill_preemption_2026_10_23/full-suite-final.json。
