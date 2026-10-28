# 战斗通关计时

## 使用与装配

独立组件：`res://GameFlow/Components/CombatRunTimer.tscn`。
已装在 `Scenes/CombatRoom.tscn → CombatRunTimer`，Inspector 只有 Assembly / Player，一个引用指向同场景 Hero。不需要给角色、武器或技能增加组件。

计时面板在左上角，格式为 `分钟:秒:百分秒`，例如 `01:23:45` 表示1分23秒450毫秒。外观直接编辑组件场景的 Panel 与 Time：位置、尺寸、字体、颜色均使用原生 Inspector，不另造脚本参数。

## 计时与结算

- 载入与重玩均显示零，等待玩家第一次主动移动并发生水平位移；出生定位、仅按键但没有位移、无输入的外力移动不触发。
- 起步后累加普通 `_process(delta)`，不单独适配慢放、镜头演出、时停或其他游戏流程。
- GameRunController 收到现有 room_completed / room_failed 时调用组件 stop，同步冻结时间；组件不判断胜负。
- 重玩界面显示本轮时间和最佳通关时间；战败附“未通关”，不更新最佳。未起步的零秒胜利不登记纪录。
- 最佳纪录由现有 GameRunController 按场景路径保存在内存字典中；同一次游戏运行内重玩保留，退出清空，不创建任何用户存档。
- 六位显示上限99:59:99，内部实际累计仍保留，纪录比较不截断。
- 没装计时组件的旧场景仍正常结算，隐藏时间栏，不遗留其他场景读数。

## 模块边界

CombatRunTimer：跟踪起步、累计游戏秒、显示时钟；公开 stop / get_elapsed_seconds / has_started / format_time。
GameRunController：沿原房间信号停止计时、比较本次进程纪录，向结果界面传入数值。
RunResultOverlay：set_run_times 只显示数据，不自行计时、查找玩家或保存纪录。

## 验证

运行 `GameFlow/Tests/CombatRunTimerTest.gd`：真实主场景装配、未移动等待、无意图位移、阻挡、主动起步、真实物理循环下的首帧结束冲刺与外力结束判定、六位格式、同步胜利冻结、真实重玩路径、多次重载最佳纪录、失败和较慢成绩不覆盖，以及旧场景隐藏时间栏。

主场景直接运行：观察零值 → 移动 → 时钟增长 → 胜利冻结 → 结果时间 → 点击重新开始，验证本轮归零；关闭后重新运行，最佳从暂无纪录开始。

本功能只更新项目源内容，不自动覆盖 Export 中已生成的测试游戏；向朋友分发前需要重新导出。

## 本次交付验证（2026-10-23）

- 专项测试先因缺少组件失败，再验证起步/结算/重玩转绿；真实物理补测先复现首帧结束冲刺漏起表及外力结束误起表，再修正为移动前捕获来源、物理后验证实际位移。无需修改玩家或技能实现。
- 原生D3D12主场景截图已检查，起步前0、真实移动后增长、胜利同步冻结、结果显示本轮与最佳；截图位于 `.godot/combat_run_timer_2026_10_23/clock.png` 与 `result.png`。
- 最终全量186项，184通过；仅此前已有的 CameraFollowControllerTest（房间导航未烘焙）和 SingleSceneFireboltTest（旧6米断言与当前配置不一致）失败。本次无新增脚本错误、资源泄漏或无效UID。完整记录：`.godot/combat_run_timer_2026_10_23/full-suite-final.json`。
- 独立只读审查后复核无新增重要问题。所有项目编辑使用Godot MCP Pro，未修改插件、动画、其他单位配置或受保护TestScene；未Git提交或重新导出游戏。
