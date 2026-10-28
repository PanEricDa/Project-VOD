# Guardian 终结技：震甲冲击

## 已落实效果

以 Guardian 自身为中心，在水平半径 4 米内向合法敌人结算一次伤害，然后降低命中敌人的防御 25%，持续 15 秒。原始伤害为 20 + 1.0 × 施法者有效攻击力，再经既有防御公式结算；本次伤害不享受自己随后施加的破甲。重复命中由同一效果来源刷新 15 秒，不叠加；死亡清理，到期恢复。不同来源仍遵循状态系统已有叠加语义。

## 配置入口

打开 `res://SkillSystem/00-Skills/Finisher_GuardianArmorBreak/GuardianArmorBreakFinisherSkill.tscn`：

- 根节点 Delivery → InstantTargetDeliveryConfig：Target Collection Mode = Caster Radius，Effect Radius = 4，Effect Relations = Hostile。
- 子节点 DamageEffect → 原 HealthChangeSkillEffect：Base Amount = 20、Power Ratio = 1。
- 子节点 ArmorBreakEffect → 原 StatModifierSkillEffect：Target Mode = Delivery Target、Modifier Stat = Defense、Modifier Mode = Percent、Amount = -25、Duration Seconds = 15、Stacking Rule = Refresh。
- 根节点 Cinematic Profile → 同目录 GuardianArmorBreakCinematic.tres；动作引用 GuardianArmorBreakAction.tres。
- 根节点 Camera Effect Profile → `res://Effects/Camera/Presets/GuardianArmorBreakCinematicCamera.tres`，保留进入特写、回到战斗视角、归回玩家三个过渡时间，当前均 0.2 秒。
- 根节点 Release Effect Scene → `res://Effects/Skills/GuardianArmorBreak/GuardianArmorBreakReleaseEffect.tscn`；锚点为 Caster Feet。

这是复用 SkillBase 的独立终结技实例，没有新建 Guardian 专用技能脚本。自身目标不依赖锁定敌人的存活和距离；敌人仍须满足范围交付的关系、可选取、存活规则。范围交付保留既有约 0.05 米浮点边界容差。

打开 `res://UnitSystem/AI/Ally/Units/Guardian.tscn`，SkillHost → Finisher Skill 指向 SkillSocket 下的 GuardianArmorBreakFinisherSkill。原有两个常规技能及独立连携技能不变。正式 CombatRoom 继承此源场景，无需另放单位。

## 属性规则与复用

StatModifierSkillEffect 只新增 Modifier Mode 选项，旧内容默认 Flat（固定点数），Amount 字段复用。Percent 时 -25 表示降低 25%，20 表示提高 20%。

有效属性 = max((基础属性 + 固定修正之和) × max(1 + 百分比点之和 / 100, 0), 0)。

攻击与防御 getter 共享此计算，不直接修改基础属性；后续基础值或固定 Buff 变化时百分比实时生效。Refresh 按来源、属性和模式识别同一修正；Stack / Replace 沿用已有状态容器的生命周期。旧 get_modifier_total 查询仍只返回固定点数。移动速度枚举仍是既有预留项，本次没有接入移动计算。

后续攻击强化、百分比降防等内容可复用同一 Effect，只改 Inspector 参数，不需复制状态计时或伤害代码。

## 动作、镜头和视觉

动作已使用用户预先创建的 ShieldAnimationLibrary.res/finish_attack_1；2026-10-20 在该空片段内完成四条姿态轨道和一条方法轨道，没有另建片段名。举盾准备约 0.2 秒，0.2—0.5 秒保持蓄力姿态，0.6 秒下砸并 release_action，约 0.766667 秒 finish_action，随后收势归位，片长约 1.333333 秒、非循环。Base Cast Time=0.6，默认原速播放。只驱动 CharacterRoot 和 WeaponSocket，原普通攻击／施法片段保持不变。正式 GuardianArmorBreakAction.tres 是该动作的独立快照，UID 保持不变；Workbench 已保留 IronShieldVisual 与 Shield 动画库装配，可继续编辑。今后修改库内动作后仍需同步正式 Action，不会自动联动。

沿用正式 B 导演：开始时暂停推进正面特写，镜头到位后以原有 5% 世界速度播放动作；释放帧暂停返回战斗视角，到位后结算范围伤害与破甲。由于是一次瞬发交付，结算完成即恢复世界速度并归还镜头，不等待不存在的投射物。镜头构图半径直接读取 Delivery，无需另填一份半径。

视觉为独立银蓝冲击环场景，暂时复用现有 GuardianTauntReleaseEffect 的纯表现脚本，原嘲讽特效不变。视觉半径为 4 米，仅负责表现，不承担实际命中。若之后改变技能半径，也应同步调整此视觉参数。没有新增投射物或音频资产。头顶浮动血条的左上状态栏以紫色圆点显示降防，与橙红色灼烧圆点并列，沿用12像素尺寸并向右排列。圆点直接读取StatusEffectComponent中的负向防御修正，支持固定值与百分比；同类多个来源只显示一个点，最后一个来源移除／到期时消失，死亡统一清理；不建立独立状态计时。

独立预览：`res://Effects/Skills/GuardianArmorBreak/GuardianArmorBreakReleaseEffectPreview.tscn`，F6 后点击播放，仅展示视觉，不修改属性。

## 验证

正式场景 F5，正常连携结算达标后，终结技选择窗口中按 1 使用 Guardian；Caster 仍为按 3。Guardian 周围应有敌人，才有实际命中与破甲对象。Remote Inspector 查看敌人的 StatusEffectComponent 可检查存活修正；UnitBase 的 defense 字段是基础值，不会因破甲被改写，实际结算使用 get_defense()。

自动测试：

- UnitSystem/Tests/PercentageStatModifierTest.gd：百分比与固定值混合、基础值变化、刷新、15 秒到期、死亡清理及旧接口兼容。
- SkillSystem/05-Tests/GuardianArmorBreakFinisherTest.gd：4 米边界、友敌过滤、先伤后破甲、重复刷新、资源 UID、真实动画与 B 导演、范围镜头构图和时间归还。

### 本次验证记录（2026-10-20）

全量 157 项测试，156 通过；唯一既有失败是 CameraFollowControllerTest 的基础房间导航网格未烘焙，未发现 ObjectDB 或资源泄漏日志。新增技能及百分比测试通过；额外覆盖首目标被伤害击杀后继续处理其余目标、刷新时更新数值。独立特效与正式场景装配已运行检查。三份外部资源 UID 有效，Cinematic 与 Camera 资源已在对应类型 Quick Load 中确认。CombatRoom 文件 SHA256 与实施前一致，用户已有修改未动。本次未提交 Git。

### finish_attack_1 制作与接入验证（2026-10-20）

在用户预备的盾牌工作台与已有空片段中完成动作。库内仅新增该片段的内容，原五个盾牌片段重新读取后的轨道／关键帧签名保持一致。同步正式 Action，保留库、Action、Profile 原 UID；Base Cast Time=0.6。工作台静态姿态保持基准，预览选择 ShieldAnimationLibrary/finish_attack_1。

全量仍为157项，156通过，唯一既有失败为 CameraFollowControllerTest 的导航网格未烘焙，无泄漏日志。实际正式场景通过导演执行新动画，释放后敌人防御2→1.5，流程 completed，世界速度恢复1.0、未残留暂停，动作占用正常结束。Caster 动画、CombatRoom文件和武器Visual前后哈希一致。本轮未提交Git。

### 用户微调后重新装载（2026-10-20）

已将编辑器中最新 ShieldAnimationLibrary/finish_attack_1 完整保存并同步至正式 GuardianArmorBreakAction.tres，再刷新 Cinematic Profile 引用。姿态以用户微调结果为准，不再用首版下砸高度限制释放姿态；未改用户关键帧。当前片长约1.333333秒，release仍为0.6秒、finish约0.766667秒，Base Cast Time=0.6无须改变。Guardian终结技真实执行与Shield动画库测试均通过，原资源UID保持不变。

### 降防圆点（2026-10-20）

WorldHealthBar订阅状态容器已有modifier_changed和modifier_removed信号，经has_negative_modifier(DEFENSE)只读查询显示紫色DefenseDownDot。正向防御Buff、负向攻击修正不会误显示；即使正向Buff抵消部分降防，负向防御效果仍在时仍显示。普通使用无须另配Named Status或增加Skill Effect组件，Guardian的现有ArmorBreakEffect自动接入。

WorldHealthBarDebuffTest覆盖双状态排列、颜色、刷新、多来源到期、显式移除、解绑／重新绑定及死亡；GuardianArmorBreakFinisherTest额外覆盖真实范围效果与动画释放后的圆点显示和到期消失。

降防来源对象提前销毁的边界同样已覆盖：modifier_removed在来源失效时发送null，避免向强类型UI监听传递已释放对象，状态与圆点依旧正常到期清理。

圆点最终验证：157项回归中156通过，唯一既有失败仍为CameraFollowControllerTest导航网格未烘焙，无泄漏日志。新增来源提前释放边界用例及状态组件测试复测通过；正式场景对敌人施加既有ArmorBreakEffect并叠加灼烧，实际SubViewport确认橙红、紫色圆点并列，防御2→1.5，未修改CombatRoom文件。
