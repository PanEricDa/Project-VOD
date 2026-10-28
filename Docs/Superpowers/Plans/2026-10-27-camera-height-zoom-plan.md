# 相机地形高度与变焦俯角实施计划

需求：镜头随玩家跨层移动高度；拉近时镜头高度和俯角连续降低，最近默认30°，Inspector可调。

方案：复用CameraFollowController、现有滚轮InputMap和距离档位；默认关闭垂直锁定。围绕原镜头观察点旋转相机，俯角由平滑视距插值，不改变FOV。提供变俯角开关、近/远俯角和观察高度；旧固定角度模式可显式启用。反馈与技能特写沿用现有合成入口。

- [x] 新增CameraTerrainZoomTest，先验证旧代码不能满足高度与角度要求。
- [x] 仅扩展相机控制器，参数按职责分组、相邻中文说明；保留目标解析、暂停和特写接口。
- [x] 旧固定角度专项测试显式关闭变俯角；回归新测试、原跟随测试、反馈与遮挡测试。
- [x] 真机运行TestLevel01检查上/下层与近/远构图；补充配置文档。

执行裁定：本任务必须通过当前Godot编辑器/MCP验证，沿用已有工作目录；不切换工作树，不改Hero或地形，不提交已有用户修改。

验证限制：现有CameraFollowControllerTest已记录TestCombatRoom导航未烘焙断言失败；对比基线并如实保留该结果，不扩大到导航修改。

最终验证：新增地形/变焦测试、CameraSkillFocusTest、FinisherCinematicOcclusionTest、FinisherCinematicExecutionTest、FinisherCinematicPauseGateTest通过。CameraFollowControllerTest仅保留既有导航未烘焙失败。只读复核无重要问题。
实际关卡：上层Hero Y约13.84、盆地约-5.09，CameraRig相对高度均9米；最近30°/相对高度6.22米，最远50°/相对高度15.89米；真实移动后仍正确跟随。
补充：用常量数组初始化Zoom Distances，修正编辑器默认Nil而运行时才有值的问题，已加入Inspector默认值契约测试。


## 最近两档俯角范围细化（2026-10-27）

用户确认：只有最接近角色的两个档位进行俯角扁平变化，其余远景保持原角度。核对原场景和控制器后，基准是50°，并非55°。

实现：继续使用已有近／远俯角参数，以第三近档的距离作为恢复常规角度的边界；超过边界保持常规角度。默认四档由近到远为30°、45°、50°、50°。按平滑视距计算，因此边界过渡连续；只有一或两档时保持既有端点与安全处理。没有新增Inspector参数、InputMap动作或场景覆盖值。

验证：CameraTerrainZoomTest新增真实相机角度、远档过渡和五个非等距档位断言，修改前6项断言失败，修改后通过。CameraSkillFocusTest、FinisherCinematicOcclusionTest、FinisherCinematicExecutionTest、FinisherCinematicPauseGateTest通过；CameraFollowControllerTest仍仅有原TestCombatRoom导航未烘焙断言失败。备份与回归结果位于.godot/camera_near_pitch_2026_10_27/。本轮不修改地形、导航、其他数值或Git记录。

最终档位调整：按用户要求，将第二近档改为45°。内部在最近与常规俯角之间取75%作为第二近档，再按相邻距离平滑插值，默认四档30°、45°、50°、50°，不新增Inspector参数。更新后的第二档角度断言在修改前失败、修改后通过；CameraTerrainZoomTest、CameraSkillFocusTest、FinisherCinematicExecutionTest共3项通过。
