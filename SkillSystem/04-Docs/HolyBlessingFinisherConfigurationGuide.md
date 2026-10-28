# Priest 终结技：圣辉祝福

## 效果与配置

终结窗口按2使用Priest。技能自身为合法目标，不要求敌方锁定；释放瞬间收集8米内存活友方（包括自己和玩家），造成伤害提高30%，持续15秒。离开范围不移除；同一技能重复施加仅刷新，不叠加。治疗不增强，不造成直接伤害。

配置入口 `SkillSystem/00-Skills/Finisher_HolyBlessing/HolyBlessingFinisherSkill.tscn`：

- 根节点 Delivery：InstantTargetDeliveryConfig / Caster Radius，Effect Radius=8、Affected Relations=Self+Friendly、Candidate Source=World Scope。后者在释放瞬间从本次技能世界收集单位，不受牧师6米感知或旧候选快照限制；其他范围技能默认仍用Request Snapshot。该静态资源不保存进度，不在Priest源场景重复覆盖半径。
- DamageBlessingEffect：通用StatModifierSkillEffect，Delivery Target、Outgoing Damage、Percent、Amount=30、Duration Seconds=15、Refresh。伤害倍率以1为基础，统一CombatValueResolver只乘一次；不改Attack Power、技能基础值和治疗。
- 同组件 Presentation → Status Visual Scene：HolyBlessingBuffEffect.tscn。可替换或留空，不影响数值。视觉由状态记录托管，刷新复用；到期、移除、死亡或状态组件卸载清理。0.15秒淡出只是视觉收尾，不延长增益。
- Cast Effect Scene：HolyBlessingCastEffect.tscn，开始比例0；Release Effect Scene：HolyBlessingReleaseEffect.tscn，Caster Feet。
- Cinematic Profile：同目录HolyBlessingCinematic.tres，引用HolyBlessingAction.tres。Camera Effect Profile：Effects/Camera/Presets/HolyBlessingCinematicCamera.tres。三个镜头过渡时间沿用0.2秒，可独立调校。

Priest源场景SkillHost的Finisher Skill指向SkillSocket/HolyBlessingFinisherSkill；普通HolyLight、GreaterHeal与连携GreaterHeal不变。无需向测试关卡添加单位，也不修改CombatRoom。

## 动作与镜头

遵循Docs/AnimationWorkbenchWorkflow.md，工作台装配StaffVisual与已有StaffAnimationLibrary.res，保留unit和本地库。新增非循环finish_cast_1，总长1.5秒，仅CharacterRoot/WeaponSocket姿态及既有方法轨道。

0～0.2举杖；0.2～0.65头顶水平转两圈；0.65～0.9定格；0.9～1.15竖杖下杵；1.15 release_action；1.48 finish_action；1.5结束。连续小角度Quaternion关键帧完成两整圈，尾部为等价初始朝向，不反转两圈归位。原Staff库RESET、basic_attack_1、basic_cast_1内容不变，UID保留。正式Action是独立快照，后续修改库内片段仍需同步Action和Profile。

B导演：动作开始暂停推进特写，到位后世界5%而终结动作正常推进；完整看到举杖、两圈、定格和杵地。杵地marker暂停切回战斗视角，到位后交付祝福、播放地面特效并恢复正常世界时间；后摇正常归位，不等待15秒增益。没有新的镜头方法帧或专属终结执行器。

## 特效与复用

独立目录 `Effects/Skills/HolyBlessing/`：

- Cast：头顶金紫旋环及随杖端移动的圣徽；通用Effects/Combat/WeaponSocketCastEffect.gd复用既有表现播放器和请求时钟。局部偏移在VisualRoot/Focus/StaffTip编辑。
- Release：金紫地面扩散波与短圣徽闪光。主金环扩散至技能实际作用半径（目前8米）后淡出；通过通用Effects/Combat/RadiusReleaseEffectPlayer.gd接收本次SkillPresentationContext的范围快照，复用原播放器生命周期。半径唯一入口仍为技能根节点Delivery → Effect Radius，特效和预览不重复配置；VisualRoot/RangeRoot内按1米最大半径制作动画，仅此节点水平缩放，外部圣徽/光柱保持原尺寸。单体/无半径快照或不支持接口的旧特效不变。
- Buff：三道短金光及低亮菱形印记；AnimationPlayer的gain/idle/out可直接编辑。通用Effects/Combat/StatusModifierVisualPlayer.gd只控制动画收尾，不维护状态时长。全部特效不投射阴影。
- Cast、Release、Buff、Sequence各有独立*EffectPreview.tscn，F6播放，提供重播按钮及Auto Repeat开关。Sequence只演示动画和特效，不运行技能/AI/数值。

未来增伤/减伤输出类状态复用Outgoing Damage和StatModifierSkillEffect，无需专属技能脚本；其他状态可配置自己的Status Visual Scene。未配置视觉的旧技能行为保持不变。当前没有新增音频资产。

## 验证入口

- UnitSystem/Tests/OutgoingDamageModifierTest.gd：基础与攻击力伤害一起增强、实际扣血只乘一次、防御关系、治疗不增强、刷新、到期、死亡。
- SkillSystem/05-Tests/PriestHolyBlessingFinisherTest.gd：8米边界、自身/敌友/死亡过滤、离开范围保留、刷新视觉不重复、到期回收、真实Priest终结导演/动画/时间归还和资源UID。
- SkillSystem/05-Tests/HolyBlessingPresentationTest.gd：两圈连续旋转、定格、杵地、归位、原生资产UID、无阴影及淡出回收。

- SkillSystem/05-Tests/ReleaseEffectRadiusTest.gd：真实释放播放器的8米/变更半径快照、可见边界、中心不缩放、实例隔离、非法半径保护及预览同步/取景。
