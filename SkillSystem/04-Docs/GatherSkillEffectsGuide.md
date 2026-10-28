# 旧身前Gather说明（2026-10-23）

本文件仍描述保留的Player_Gather/GatherSkill.tscn及其身前聚拢预览。它已从玩家Q槽卸下，但内容没有删除或修改；当前Q使用独立的Player_TargetGather技能。收束表现脚本现可通过只读pull.center_on_target快照兼容目标聚拢，默认false保留旧行为。当前技能配置见[目标聚拢指南](TargetGatherSkillConfigurationGuide.md)。

# Gather 拉拽技能特效

## 使用与配置

- 技能：`SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn`。根节点 Inspector → Presentation → Cast / Release，分别选择蓄力与释放场景；沿用原开放 PackedScene 接口，可替换或留空。
- 蓄力：`Effects/Skills/Gather/GatherCastEffect.tscn`。银白偏青蓝的短风线聚向动作发射位置，使用共享 FlameBarrageEffectPlayer 的 configure_cast / 时钟 / 取消契约；AnimationPlayer 的 effect 动画控制风线。没有新建角色动画。
- 释放：`Effects/Skills/Gather/GatherReleaseEffect.tscn`。VisualRoot/Boundary 为选取范围断弧，Ribbons 为收束风带，Destination/CollapseRing 为落点收缩圈。颜色/材质在原生 MeshInstance3D 的 Material Override 编辑。
- 预览：`Effects/Skills/Gather/GatherEffectPreview.tscn`，F6 后自动循环，可按 Replay 重播；读取正式 Q 参数，不运行伤害、AI、外力位移。
- 实战：`Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn`，F6 后按 Q；仍保留2秒测试冷却。未向正式 Hero / TestScene / CombatRoom 添加单位或玩家技能系统。

## 唯一数据来源

范围半径3.5m、前移3m来自技能 Delivery；聚集前移1.5m、圆盘半径0.6m、持续0.12战斗秒来自子节点 PullTargetSkillEffect。均保持用户现有配置。特效不再暴露第二套相同参数。正式技能CD10秒、施法0.2秒保持不变。

释放时冻结脚下位置和稳定水平朝向；选取圆心与聚集目的地分别计算。释放特效挂世界层且 top_level，后续玩家移动、转身、移除或世界父级缩放不会改变已释放几何。风带随拉拽时长收束，之后保留0.15战斗秒收缩残影；无伤害、仇恨、镜头和时停。

## 框架增量与复用

1. SkillEffectBase.get_presentation_data() 默认空。需要自动同步视觉参数的 Effect 可按职责返回纯值字典；Pull 只返回自身落点、半径、时长，不持有额外配置。
2. SkillPresentationContext 在施法开始复制配置，释放阶段补充已有的实际释放位置/朝向；get_effect_data(key) 返回独立副本，不持有原技能或强单位引用。同职责键重复时按技能直接子节点顺序最后者覆盖；普通配置应每职责挂一个Effect。
3. SkillReleasePresentationPlayer 在视觉入树前可选调用 configure_release(presentation)，已有不实现此接口的特效维持原流程；不新增另一套技能执行机制。
4. GatherReleaseEffect 仅消费快照、生成风带并复用共享生命周期/请求级时钟；没有目标筛选或拉拽逻辑。取消施法仍由 SkillBase 原有蓄力清理处理。

配置在下一次施法时捕获；不支持施法中途编辑同一玩法资源来热改当次表现。预览中的参考原点只用于独立展示，不是正式技能参数。所有 .tscn 由 Godot API 原生保存并验证有效 UID；本次未新增外部 .tres/.res。

## 验证

新增 `SkillSystem/05-Tests/GatherPresentationTest.gd`：资产接入、冻结释放位置/朝向、选取/落点分离、非默认半径与时长、只读字典隔离、变换父级、取消蓄力、并发实例、施法者移除后完成与回收。已从缺失功能的失败运行转为通过，无脚本错误或泄漏输出。

Godot 原生运行独立预览，检查中段风带和蓄力线条；实际测试场景输入Q：受理/开始/释放/结束各1次、影响2目标、释放视觉1次，结束后0遗留 Gather 视觉节点，Debugger 0错误。

完整回归：178项 SceneTree 测试，176通过，2项已有失败；无本次新增失败。保留未改动的旧失败为 UnitSystem/Tests/CameraFollowControllerTest.gd（正式关卡 NavigationMesh 未烘焙）与 SkillSystem/05-Tests/SingleSceneFireboltTest.gd（旧6m断言与用户现有5m配置不符）。
