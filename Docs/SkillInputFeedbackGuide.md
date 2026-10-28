# 技能按下／松开交互

更新：2026-10-25。

Q/E 和终结技现在采用同一种交互：按下显示绿色边框并放大 6%；按住不自动释放；松开确认，成功受理后显示绿色填充。普通连携 1—4 的施法提示阶段输入规则保持原样。

## 配置入口

- 键位：Hero 下 PlayerSkillInputComponent 的 Skill 1 Action／Skill 2 Action，仍引用 Project Settings → Input Map 的 player_skill_1／player_skill_2。不要在通用组件再配置一次键位。
- 交互模板：UnitSystem/Components/Input/PressReleaseInputComponent.tscn，脚本位于同目录。玩家输入组件与终结选择控制器各挂载一个实例，运行状态互不影响。
- 反馈主题：UnitSystem/Components/UI/Themes/SkillInputFeedbackTheme.tres。Q/E 的 Panel、终结窗口的 Root/Cross 均引用它；原测试场景的旧主题覆写已同步替换。
- 原生 Theme 中 PlayerSkillSelected／FinisherSelected 是绿框，PlayerSkillCasting／FinisherConfirmed 是绿底；PlayerSkillFailed 是红框。SelectionFeedback 的 selected_scale_percent 为 106。两种卡片保留各自的布局边距，不强制变成相同尺寸。
- 技能内容仍装配在 SkillHost 的既有槽位；技能本身不需要增加按键参数。

## 流程与边界

InputMap 事件 → 各自输入适配器 → PressReleaseInputComponent 预选／匹配松开 → 适配器向原控制器提交请求 → 原技能／动作管线。

组件只提供 begin_press(slot_index, identity)、end_press(slot_index, identity)、cancel_selection()、get_pressed_slot() 和 matches_selection(slot_index, identity)。end_press 返回 true 是确认意图，不能当作技能成功；它不支付资源，不推进冷却，不选目标。identity 为适配器提供的原内容数字身份，用来防止按住时更换槽内容后释放另一技能。selection_changed 信号只供预选反馈。

Q/E 在松开时才读取玩家当前锁定目标；普通攻击在这之前继续进行。合法技能确认后沿用已有抢占与段数续接；冷却、无目标、忙碌等仍由原管线拒绝并显示失败反馈。暂停、输入禁用、失焦会清空未确认预选，已经开始的技能不由本组件取消。

终结技保留原有时限、5%慢速、跨窗口持键隔离与角色合法性判断；松开后先显示约 0.12 秒绿底，再交接演出，确保反馈可见。Q/E 不增加这段等待，松开即提交。程序化 request_slot／try_select_slot 接口保持原行为。

UI 只读 Controller 的状态，卸载 UI 不影响按键。以后接入其他按下／松开操作时，在该操作的输入适配器下实例化模板并接线即可；其游戏规则仍由自己的控制器管理，不把技能系统塞进输入组件。

## 验证

PressReleaseSkillInputTest 使用真实 InputMap、Hero、Q/E 技能和动作管线，覆盖按住不释放、松开一次、错键不覆盖、普攻抢占时点、当前锁定、暂停／禁用／失焦、换装身份以及卸载 UI。现有玩家技能和终结技流程测试继续覆盖原技能合法性、资源、动画、实际投射物和镜头交接。

最终回归：189 项中 187 项通过，只有既有 CameraFollowControllerTest（导航网格未烘焙）和 SingleSceneFireboltTest（旧 6 米射程断言、当前 5 米）失败。独立审查发现的失焦持键残留、同帧短暂禁用均已增加失败复现并修正；新增测试同时覆盖丢失松开事件和终结技焦点恢复。原生 GPU 按下／松开截图已检查，主场景两个输入域的模板与主题引用已确认。
