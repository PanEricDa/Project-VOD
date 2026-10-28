# 终结评分效果加成实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 按任务执行并验证。

**Goal:** 保留现有继承与效果管线，通过每个Effect的开关实现终结评分威力奖励。
**Architecture:** Round结算生成一次倍率，Selection冻结原轮结果，Execution注入SkillContext。Context复制、投射物和触发子技能继承倍率；EffectBase只提供开关和共用计算，三个现有数值效果明确调用。
**Tech Stack:** Godot4.7 / GDScript / Godot MCP Pro。
**Spec:** 本轮用户确认的EffectBase开关+共用方法方案，以及100分起额外奖励渐近50%的曲线。

## Global Constraints
- 不新增中间父类，不重排目录，不改近战动作或普通攻击管线。
- 普通/直接预览Context默认倍率1。不开启的效果不变化；非数值效果不增强。
- 公式 M=1+0.5*(1-exp(-max(S-100,0)/50))，固定内部常量，不新增策划需同步的参数。
- 只增强伤害/治疗完整数值、属性amount、仇恨threat_amount，保留持续时间/范围/数量/费用/归属。
- 开关默认false；四终结技的DamageEffect、Guardian ArmorBreakEffect、Priest DamageBlessingEffect开启。
- 所有写入优先MCP；场景原生保存并验证UID。留在用户当前目录，不提交或上传。

## Review Focus
- Context复制及Trigger新建Context不能丢失倍率，也不能因purpose=REGULAR漏掉衍生效果。
- 伤害基础值与攻击力部分只增强一次，防御、输出增益、实际扣血、仇恨仍由原结算器负责。
- 开关按节点独立；父触发器的开关不决定子技能效果。
- 终结窗口取原轮冻结结果，不能读取后来新轮或被外部修改的payload。
- 取消/重绑/超时/预览默认必须恢复1倍，不修改共享技能静态数值。

## 文件与接口
修改：SkillEffectBase.gd（use_finisher_bonus、scale_effect_value(value,context)）；三个数值Effect；SkillContext.gd（finisher_multiplier及复制）；TriggerSkillEffect.gd（子context传递）；SquadChainRoundController.gd（calculate_finisher_multiplier(score)、结算快照）；Selection（倍率冻结/发布/清理）；Execution（begin_finisher末尾可选倍率参数默认1，真实选择读取当前冻结状态注入）。四个Finisher场景只开启相关效果开关，不改原数值。

## Task 1：共用规则与数值效果
- [x] 新建FinisherRewardEffectTest，先RED：开关、默认、曲线样本、上下文复制、伤害/治疗、正负属性、永久/临时仇恨、触发子技能独立开关且不复利。
- [x] 实现父类、Context、数值效果与触发上下文传递，测试GREEN。

## Task 2：正式轮次到终结技能接线
- [x] 新建FinisherScoreRewardFlowTest，先RED：真实闭窗结果→选择→执行Context；默认预览1倍，取消后不遗留。
- [x] 实现Round/Selection/Execution快照链；原生开启四终结相关效果并验证UID。
- [x] 运行定向与完整回归，独立只读审查，记录基线失败。
- [x] 更新配置说明及验收；未请求Git操作，不提交/推送。

## 验收记录

- 两项新增测试均先在缺少接口/快照/正式开关的旧实现上失败，再在实现后通过。
- 最终全量191项：189通过；仅原有CameraFollowControllerTest（导航未烘焙）与SingleSceneFireboltTest（旧6米断言，当前5米）失败，无新增脚本错误/泄漏/无效UID报告。
- 独立只读审查对照13个本轮基线快照，未发现重要正确性问题；审查者独立重跑两项新增测试均PASS。
- 四个正式终结场景原生保存、UID有效；主场景刷新后五个主要Effect的开关均已核实开启，基础数值与15秒时长未改。
- 编辑器两份打开的效果脚本先核对CodeEdit与磁盘完全一致，再使用MCP专用脚本编辑工具安全更新并同步缓冲；未覆盖未保存内容。所有写入均通过Godot MCP Pro。
- 不增加中间父类、不调整近战动作/普通攻击路径；没有Git提交、推送或重新导出。
- 配置指南：SkillSystem/04-Docs/FinisherScoreRewardConfigurationGuide.md。
