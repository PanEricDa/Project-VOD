# 终结评分效果奖励配置

更新：2026-10-25。

本功能沿用现有 SkillEffectBase 继承体系，没有新增效果父类、资源类型或目录层级。

## Inspector 配置入口

打开具体技能场景，选择其伤害、治疗、属性修正或仇恨 Effect 子节点：
**Finisher Reward → Use Finisher Bonus**。

默认关闭，保持原效果；勾选后，该效果指定的数值接受本次终结评分倍率。此开关按Effect节点独立保存，不是“是否属于终结技能”的分类，也不向节点树子效果自动传播。原有自动技能、连携技能和直接预览的倍率默认1，勾选也不会凭空得到额外奖励。

| 效果 | 实际增强数值 | 保持原规则 |
|---|---|---|
| HealthChangeSkillEffect | 原结算器的完整基础值＋攻击力换算结果，伤害/治疗均适用 | 防御、输出增益、实际扣血/回血、命中身份与仇恨仍沿原管线 |
| StatModifierSkillEffect | amount，负数仍为负数 | 持续时间、叠加规则、视觉与目标 |
| ThreatChangeSkillEffect | threat_amount，含永久入池与临时可撤销贡献 | 时间、衰减与撤回规则 |
| 状态添加/移除、拉拽、触发子技能 | 当前不增强 | 范围、数量、时间等保持原值 |

非数值Effect仍继承该字段，但当前不消费它；开关不会自动推测“哪个参数要增强”。新增Effect需要增强时，在该脚本的明确数值结算处调用父类 scale_effect_value(value, context)。

## 评分曲线

只在本轮实际闭窗时捕获：
M = 1 + 0.5 × (1 − exp(−max(S−100,0)/50))。

100分为1倍，125分约1.197倍，150分约1.316倍，200分约1.432倍，极高分趋近1.5倍。低于资格线仍不能取得终结资格。公式为评价组件内部规则，不在每个技能重复配置阈值和曲线。

## 当前正式配置

- Finisher_FlameBarrage/FlameBarrageFinisherSkill.tscn → DamageEffect：开启。
- Finisher_ArcherPowerShot/ArcherPowerShotFinisherSkill.tscn → DamageEffect：开启。
- Finisher_GuardianArmorBreak/GuardianArmorBreakFinisherSkill.tscn → DamageEffect、ArmorBreakEffect：开启。
- Finisher_HolyBlessing/HolyBlessingFinisherSkill.tscn → DamageBlessingEffect：开启。

其他技能沿用关闭默认值。上述原有基础伤害、攻击力倍率、25%降防、30%增伤、15秒持续等静态数据均保留；评分只产生本次运行时有效值。150分时25%降防约变为32.9%，30%增伤约变为39.5%；时长不变。

## 数据链与复用

Round闭窗结果 → Selection原轮快照 → Execution → SkillContext.finisher_multiplier → Delivery → Effect。

选择窗口不读取后来的新轮评分。上下文复制和Trigger创建的子技能继承同一标量；子技能用途即使是REGULAR也不丢失原倍率。每个子Effect仍依据自己的开关，使用自己的配置计算，不能把父效果已经增强的结果再乘一遍。Trigger自身开关不代替子技能伤害Effect开关。

普通/脚本直接调用 begin_finisher(actor, scatter_seed, preview_mode) 保持1倍兼容；程序化特殊演出可用末尾可选 finisher_multiplier 参数传入有限且>=1的显式倍率。正式玩家流程只采用已验证选择窗口冻结的评分结果。技能配置和共享资源不会被运行时倍率改写。

## 验证入口

- SkillSystem/05-Tests/FinisherRewardEffectTest.gd：曲线样本、默认/异常倍率、上下文复制、伤害与治疗、正负属性、临时仇恨撤回、触发子技能继承与独立开关。
- UnitSystem/Tests/FinisherScoreRewardFlowTest.gd：真实150分闭窗、冻结选择、真实施法交付、五发五落地及下一次直接预览恢复1倍。

验收：完整191项回归中189通过；两项既有失败为CameraFollowControllerTest（导航未烘焙）和SingleSceneFireboltTest（旧6米断言）。独立审查无重要问题，新增两项测试独立复跑通过。主场景已检查五个主要Effect的开关，四个技能场景原生保存及UID校验通过。
