# 按下／松开技能交互复用实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 按下面任务逐项实施并验证。

**Goal:** Q/E 与终结技复用同一预选／松开确认组件及视觉主题，普通连携保持现状。
**Architecture:** 输入适配器解析各自 InputMap 和输入归属，共用节点只持有单次预选槽及不透明身份。技能控制器沿用现有合法性与动作管线；UI 只读显示。
**Tech Stack:** Godot 4.7 / GDScript / PackedScene / 原生 Theme。
**Spec:** 本文“确认设计”及本轮用户批准。

## 确认设计与约束
- 按下绿框并放大 6%，持续按住不施法；松开请求，受理后绿底。
- Q/E 在松开时读取当前锁定，并且仅此时允许抢占普攻；request_slot 程序化接口不变。
- 终结技保留既有 0.12 秒确认反馈、倒计时、暂停归属和跨窗口持键隔离。
- 一个运行时组件实例服务一个输入域；UI 可以独立拆卸。
- InputMap 仍为键位来源，不在新组件重配键位；冷却、目标、费用不进入通用组件。
- 优先 Godot MCP Pro 编辑；正式资源原生保存并校验 UID。保留当前工作目录及所有既有修改，不提交或上传。

## 文件与接口
- 新建 UnitSystem/Components/Input/PressReleaseInputComponent.gd 与同名 .tscn：begin_press(slot_index, identity=0)、end_press(slot_index, identity=0)、cancel_selection()、get_pressed_slot()；身份不一致视为取消，不能确认另一实例。
- 新建 UnitSystem/Components/UI/Themes/SkillInputFeedbackTheme.tres：统一绿框、绿底、错误红框与选中缩放；分别保留 Panel 和 PanelContainer 的布局样式。
- 修改 PlayerSkillInputComponent.gd/.tscn：Q/E 事件适配，禁用／暂停／失焦清空预选，松开才发 slot_requested。
- 修改 PlayerSkillController.gd：只读状态增加预选标记和技能实例数字身份。
- 修改 PlayerBase.gd：既有输入许可同步时通知技能输入组件，避免同帧短暂禁用留下旧预选。
- 修改 Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn：仅移除旧HUD主题覆写，沿用共用主题，不改变单位。
- 修改 PlayerSkillAttackPreemptionTest.gd：真实输入断言更新为松开确认时抢占。
- 修改 PlayerSkillBar.gd/.tscn：只读预选与确认反馈，共用主题，填充位于文字下层。
- 修改 SquadFinisherSelectionController.gd/.tscn：将预选状态改由共享组件维护，保留角色合法性与输入归属。
- 修改 SquadFinisherSelectionDisplay.gd/.tscn：使用共用主题缩放。
- 新建 UnitSystem/Tests/PressReleaseSkillInputTest.gd；沿用现有 Q/E 与终结技集成测试。
- 新建 Docs/SkillInputFeedbackGuide.md：配置入口、装配关系、复用方法。

## Review Focus
- 错键松开、重复按下不得确认；同时按键不覆盖首个选择。
- 暂停、输入禁用、失焦、移除后的松开不得迟到施法。
- 按住时更换槽内容不得确认新的技能／角色。
- Q/E 在松开前不能打断普攻；UI 卸载不影响输入。
- 终结技确认反馈期间暂停、关闭或角色失效不得意外执行。

## Task 1：共享交互与 Q/E
- [x] 编写真实 InputMap 测试：按下无请求／按住无请求／松开一次请求，绿框到绿底、普攻抢占时点、暂停／禁用／身份更换取消、无 UI 可用。
- [x] 运行并确认行为失败，记录 RED。
- [x] 实现共用组件及 Q/E 接线；原生创建场景和主题并验证 UID。
- [x] 运行新增与现有玩家技能测试，确认 GREEN。

## Task 2：终结技复用与交付
- [x] 用同一组件接入终结技，保留既有输入优先级与交接时序。
- [x] 运行终结技输入／暂停／生命周期与实际演出测试。
- [x] 原生渲染检查 Q/E 与终结技按住、松开样式。
- [x] 修正审查发现后再次完整回归，写入最终结果。

## 实施记录

- 旧行为 RED：按下即施法、持键时已抢占普攻，新增行为测试失败；接入后 GREEN。
- 原生截图已检查 Q/E 和终结技的绿框、6%放大与绿底，文字位于填充上层。
- 原测试场景保留了旧嵌入主题覆写，移除该覆写后复用外部 Theme；布局与单位均保留。
- 独立审查确认两个P2：失焦后的持键标记残留；同帧短暂禁用未同步取消。先新增测试复现 RED，再清理持键并在 PlayerBase 既有许可同步入口通知技能输入，测试 GREEN。同时覆盖上层吞掉release后安全取消与终结技焦点恢复。
- 修正后最终全量189项：187通过，仍只有2项已知基线失败：CameraFollowControllerTest（导航网格未烘焙）、SingleSceneFireboltTest（旧6米断言，当前5米）。相关输入、实际技能、主场景终结技及原生GPU画面验证均通过。无提交、上传或重打包。
- Ruling: 保持用户指定的当前目录与未提交修改，不建立工作树；技能UI共用原生主题，按Panel/PanelContainer保留合适边距。
- 所有写入均由 Godot MCP Pro 完成；新 Theme 原生 ResourceSaver 保存并校验UID和Theme类型。主场景装配已重新加载验证，两个输入域均可在节点树查看同一模板的独立实例。
