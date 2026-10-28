# 连携施法提示输入节奏 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax.

**Goal:** 在正式战斗中试验“按下一条命令后，看到该单位施法闪光才接受下一条全队连携输入”的手感。
**Architecture:** SkillBase 沿用 cast_effect_start_ratio 和本次有效施法时间，只发布一次施法提示时点事实；SkillHost 转发原上下文；SquadChainCommandController 以请求身份关闭/开放输入，不改变 AI、伤害窗口、费用或执行锁。显示组件只读取状态，过早输入不覆盖已有命令反馈。
**Tech Stack:** Godot 4.7 / GDScript / Godot MCP Pro.
**Spec:** 本文“已确认设计”（用户已确认全队门禁，2026-10-24）。

## 已确认设计

- 所有角色共用“下一条连携命令”的输入门禁。第一条正常受理；等待/接近/施法提示前不再受理第二条。
- 原四个连携场景已配置 cast_effect_start_ratio=0.5；该时点开放输入，不另配秒数、不依赖命中、不是精准按键判定。
- 提示时点以后持续可输入；下一条受理立即重新关闭。过早按键不缓存、不预留专注、不显示施放失败；InputMap 与现有 echo 过滤不变。
- 同角色仍受原动作锁和一个等待槽约束。其他角色可在提示后开始，并非等待前一技能动作/投射物全部结束。
- 失败、死亡、中断、等待超时和世界解绑必须放行；旧请求后续释放/结束不能误解除新请求门禁。
- 无特效资产、实例创建失败、瞬发技能也有合法提示时点，不允许因缺失美术锁死输入。
- 加一个关卡级 Inspector 开关 wait_for_cast_cue，框架默认关闭以保留旧用例；正式 CombatRoom 开启，方便本轮比较回退。无新增时间参数。

## Global Constraints

- 保持 G:/Godot/ProjectVOD 当前目录，遵循用户既有选择，不创建工作树、不覆盖无关改动。
- 编辑优先 Godot MCP Pro；所有公开接口和 export 提供中文说明。
- 不改 Scenes/TestScene.tscn 单位实例，不改 MCP 插件，不提交 Git，不导出游戏。
- 本轮只调输入，不改专注/评分/连携伤害间隔/技能本身数值。

## Review Focus

- 同帧连续 1234 和重复按键只受理第一条，预留不能增加。
- 缺失资产、零施法、技能被取消都不能卡住输入。
- 上一条迟到回调不能放开下一条门禁；世界重绑不能保留旧阻断。
- 同步通知重入不能绕过门禁追加命令。
- UI 提示不能把“忽略过早输入”显示为已经接收命令的失败。

### Task 1: 提示时点与全队输入门禁

**Files:** 修改 SkillSystem/01-Core/SkillBase.gd、SkillHostComponent.gd，UnitSystem/Components/Combat/Squad/SquadChainCommandController.gd、UnitSystem/Components/UI/SquadChainCommandDisplay.gd。新建 UnitSystem/Tests/SquadChainCastCueInputTest.gd。
**Interfaces:** SkillBase / SkillHost 新增 cast_cue_reached(context: SkillContext) 信号；仅传递事实，不驱动下一技能。Controller 只接受属于当前绑定及门禁请求的信号。

- [x] 先写真实 Host、Focus、动画集成测试，运行并记录预期失败。
- [x] 新增信号转发和以请求 ID 维护的输入门禁；处理失败/释放兜底/生命周期及重入。
- [x] 使用既有 ratio 调度，即使无视觉资产也发时点信号；保持普通技能表现生命周期。
- [x] UI 将等待提示前状态显示为“等待施法提示”，忽略 gate 尚未开放的拒绝，不覆盖黄/绿边框。
- [x] 运行新增用例和受影响原有用例，确认未产生脚本错误或泄漏。

### Task 2: 正式场景装配及验证

**Files:** 修改 Scenes/CombatRoom.tscn、Docs/CurrentSystemUserGuide.md；测试沿用 Task1 和既有 CombatRoomAssemblyTest。
- [x] 在主场景 SquadChainCommandController 开启 wait_for_cast_cue；只修改此参数，不保存用户未保存内容。
- [x] 新增正式场景装配/行为断言，确认首次输入关闭、提示开放、取消恢复。
- [x] 运行全套既有测试并报告所有失败（既有 2 项失败不扩大修复范围）。
- [x] 独立审查本轮增量，记录操作说明、验证与回退入口。

## 执行记录

- 执行方式：本会话直接实施；先失败测试，后实现及回归。
- 不创建新工作树、不提交、不推送：遵循用户当前目录偏好和本轮授权范围。


## 验证与审查记录

- 新用例先出现预期失败：原系统可同时受理不同伙伴；加入门禁后通过。
- 新增重入回归先失败、后修正：只读状态查询中的同步重绑必须使旧受理失效，不能把旧按键移入新会话。原受理身份快照仍在查询前保存。
- 已验证：等待/开始施法/提示前输入拒绝；0.49尚未开放、0.5开放；下一条接收再锁；旧请求释放/取消/结束不误解锁；取消/超时/解绑重绑放行；同步专注通知不能重入；空资产与真实闪光；零施法SkillBase只发一次提示；真实Release marker补发提示；正式场景开启；黄/绿边框不被过早按键覆盖。
- 零施法采用真实SkillBase激活/动作确认测试。当前正式武器动作release marker非零，未伪造零帧动作，不声称覆盖零施法正式武器完整链。
- 初轮全量188项，186通过，仅既有CameraFollowControllerTest（导航未烘焙）及SingleSceneFireboltTest（旧6米断言）失败；最终重入修正后重新全量回归，结果保存在.godot/chain_cast_cue_2026_10_24/full-suite-final.json。
- 独立只读审查：未发现P1/P2，P3延后：门禁关闭输入期间，重复技能费用文字会暂时回到基础费用，开放后恢复正确报价；不影响实际专注预留/扣费。现有显示在禁止输入时已灰显，本轮不扩展报价UI。
- 配置开关只用于重新运行比较：运行时切换会清除当前门禁，不追溯已经受理的命令。
- 缺失视觉仍按逻辑提示开放；低帧率可在释放marker补发，不强制等待渲染器真的呈现一帧闪光。未增加截图扫描或显示帧屏障。
- 未新增损坏特效、死亡删除压力或低帧率/暂停实机专项；原生命周期、暂停、镜头和正式终结流程保留全套回归；具体手感留给玩家重新运行主场景对比。
- 所有本轮正式编辑均使用Godot MCP Pro。没有提交/推送Git、覆盖导出包、修改插件、添加受保护TestScene单位，也没有修改AI、伤害、评分或专注数值。

最终回归补充：188项中185项直接正常退出通过；两项既有断言失败不变。SingleSceneDeliveryRunnerTest 在打印PASS后发生一次原生退出异常（-1073741819）；随后用相同控制台程序串行复测3次、MCP原生运行复测1次，均PASS且exit=0。此异常原因尚未确定，不能把并发整轮称为全绿；未据此修改交付逻辑或MCP插件。新增门禁与重入用例最终PASS。
