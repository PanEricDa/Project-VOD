# Threat Mark 临时仇恨技能特效

## 配置入口

技能：`SkillSystem/00-Skills/Player_ThreatMark/ThreatMarkSkill.tscn`。

- 根节点 Presentation → Release → Release Effect Scene：`Effects/Skills/ThreatMark/ThreatMarkReleaseEffect.tscn`。
- 子节点 ThreatChangeSkillEffect → Presentation → Status Visual Scene：`Effects/Skills/ThreatMark/ThreatMarkStatusEffect.tscn`。可换用其他 Node3D 状态视觉或留空；duration_seconds=0 的普通仇恨分支忽略此项。
- 状态资产根节点的 Height Above Bar M 默认0.4米：标记中心高于现有血条锚点的位置。不需要逐个敌人增加组件或修改敌人源场景。无血条时沿用资产根节点预设高度。
- 配色、符号尺寸在状态场景 VisualRoot 下的网格和 Material Override 中编辑；gain / idle / out 在同场景 AnimationPlayer 中编辑。

正式技能保持半径5米、2000临时仇恨、持续8战斗秒、施法0.15秒、冷却12秒。测试场景原有E冷却2秒保持不变。没有修改目标选择、仇恨衰减或常规Guardian嘲讽。

## 表现

释放：淡红色圆环在0.18秒内向实际效果半径扩散，0.34秒结束回收。使用冻结的释放位置/朝向，释放后不跟随玩家；半径读取SkillPresentationContext，特效中不配置第二份5米。

状态：猩红感叹号与两侧短折角，约0.15秒出现，持续轻微呼吸，无持续旋转或剧烈跳动。整组标记朝向当前相机，并随头顶血条移动。状态结束后播放0.15秒out淡出。

标记只表示临时仇恨状态仍有效，不承诺怪物此刻一定攻击玩家。它不拥有仇恨，不检测攻击目标，也没有额外的八秒倒计时。

## 生命周期与复用

- `Effects/Combat/StatusModifierVisualPlayer.gd`：沿用Priest终结技的gain → idle → out生命周期。
- `Effects/Combat/HeadStatusMarkPlayer.gd`：继承上述播放器，仅负责整组标记面向相机及位于血条上方；其他头顶Buff/Debuff可复用，不依赖嘲讽类别。
- StatusEffectComponent的属性修正和命名绑定状态共用纯视觉记录及创建/收尾逻辑。commit_bound_status新增末尾可选visual_scene参数，默认空，既有调用保持有效。
- 视觉在成功提交后同步；失败刷新保留旧有效状态及视觉，未提交状态不生成标记。真实状态刷新复用同一实例，不重播gain。
- 同一目标、同一命名状态多来源只显示一份视觉，最后成功提交且提供非空视觉的有效记录决定资产（纯视觉版本号，不依赖字典插入顺序）；移除一个来源后仍存在其他提供视觉的来源时保留显示。
- 最后一个提供视觉的状态移除、外部清空仇恨、来源离树/死亡、目标死亡或清表时按真实记录收尾。目标节点离树/销毁时视觉随父节点销毁。
- 视觉资产可拆卸或留空，不改变状态提交、仇恨、伤害、AI或单位装配。

## 文件

`Effects/Skills/ThreatMark/` 内提供：

- ThreatMarkReleaseEffect.tscn / .gd：纯表现范围脉冲，复用RadiusReleaseEffectPlayer。
- ThreatMarkStatusEffect.tscn：独立头顶标记，挂通用HeadStatusMarkPlayer。
- ThreatMarkEffectPreview.tscn / .gd：独立组合预览，F6运行，Replay重播，End status按钮查看消失。读取正式E半径和状态时长，纯视觉，不施加仇恨或运行AI。
- 没有新增正式外部.tres/.res；场景均由Godot API原生保存并登记UID。

在`Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn`按E验证真实效果。不向`Scenes/TestScene.tscn`自动添加或修改单位，也没有将玩家技能组装到正式Hero或主关卡。

## 验证记录

新增`SkillSystem/05-Tests/ThreatMarkPresentationTest.gd`，从“资产/视觉接口缺失”的失败运行开始，验证实际Effect生成标记、重复刷新复用、刷新后持续、到期只移除临时仇恨、技能Effect销毁后状态独立、多来源聚合、来源移除、外部清空、失败提交/刷新回滚、目标死亡、范围圈真实半径/世界固定/回收与预览加载。

相关既有测试TemporaryThreatSkillEffectTest、TemporaryThreatLifecycleTest、HolyBlessingPresentationTest、PriestHolyBlessingFinisherTest、WorldHealthBarDebuffTest已通过。

实机测试场景E受理/开始/释放/结束各1次、影响4个目标、4份对应标记、范围外0份标记；截图验证标记位于状态小点与血条上方，Debugger 0错误。

本次复用共享StatusModifierVisualPlayer时修正其私有回调参数与Node.name同名的警告，仅参数重命名，不改变播放行为。

原生运行继续等待状态自然到期后：5个测试敌人的temporary_threat均为false，残留ThreatMarkStatusEffect节点0个，Debugger仍为0错误。新增测试另覆盖整组标记朝向相机、单位移动/旋转时跟随头顶血条，以及3个场景有效UID。

审查回归：不同来源使用不同视觉时，失败刷新不再改变成功视觉及其实例；仅成功提交更新内部纯视觉版本。10Hz物理/120Hz渲染下验证血条存在实际插值位置差异，并断言标记读取同一插值位置，防止跟随抖动；两项均先观察失败，再修正为通过。

修正后的最终全量回归：179项SceneTree测试，177通过，2项原有失败，无新增失败、脚本报错、实例泄漏或UID失效。原有失败：UnitSystem/Tests/CameraFollowControllerTest.gd（正式关卡NavigationMesh未烘焙）；SkillSystem/05-Tests/SingleSceneFireboltTest.gd（旧6米断言与用户现有5米配置不符）。未在本次表现任务中修改这两项。
