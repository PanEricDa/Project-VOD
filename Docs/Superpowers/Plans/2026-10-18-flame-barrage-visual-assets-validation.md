# 焰星连轰视觉资产验证（2026-10-18）

## 交付范围

四个全新独立视觉场景、四个分项 Preview、一个五连发 Preview。只复用既有角色模型与用户提供的终结动作，不复用旧技能视觉，不接伤害、AI、镜头、时停或正式终结技能管线。源文件和资源编辑均使用 Godot MCP Pro；场景均由 ResourceSaver 保存。

## 自动验证

新测试 `Effects/Skills/FlameBarrage/FlameBarrageVisualEffectTest.gd`：最新直接运行 **165 checks，0 failures，退出码0**，无孤儿节点、资源泄漏或退出错误。

验证九个有效 UID、旧技能视觉依赖隔离、播放/取消/重播、施法时长适配、跟随位置而不跟旋转、不同发射点下火星与亮核统一汇聚、0.35秒主爆炸通知与自动清理、全部五发完成、独立预览不显示错误五发计数、临时场景防覆盖，以及粗时间步长的真实时序。

重要时间断言：

- 推进0.4秒再推进0.1秒：第一颗年龄约0.166667秒，第二颗约0.046667秒，不能已命中。
- 总时间1.16秒：第一颗主爆炸尚未完成。
- 总时间1.19秒：仅第一颗主爆炸已完成。
- 总时间1.67秒：五颗主爆炸均完成。

## 原生画面检查

实际运行了 Cast、Release、Flight、Impact 四个独立场景及完整 Sequence。检查了破碎焰冠、短火尾、向前释放圆环、重叠冲击环和短火柱的画面；无新增投影黑影。独立组件可通过 AnimationPlayer 和网格/材质 Inspector 调整，不需修改运行脚本。

## 独立审查与修正

只读独立审查提出1项 Important 和3项 Minor。本轮按实际影响重评并在一个修正批次完成：

1. 大时间步导致新火球多消费出生前时间：Important，加入边界时间测试，RED→GREEN；改为按释放、发射、抵达及主视觉完成边界切分时间。
2. 汇聚点重复维护：对本项目“单一配置、人类可管理”要求重评为 Important；新增不同发射点测试，RED→GREEN。火星改为 Focus 的局部运动轨道，末端为局部零点，调整 Focus 不再维护16份终点。
3. 单项预览读数不实：重评为影响本轮验收可观察性的 Important；新增界面行为测试，RED→GREEN。分项只显示当前段状态，不再展示0/5。
4. 生成工具可能覆盖已有 Preview：按资源编辑安全要求重评为 Important；使用独立临时样例验证防覆盖，RED→GREEN。构建前检查全部九个输出，保存入口再次拒绝覆盖。

没有保留未修复的审查问题，没有再次派发审查。

审查中考虑后排除的事项：用户动画 stop 后姿态恢复遵循引擎；动作结束不会截断五发；取消不通知完成与循环飞行由持有方清理符合契约；Cast 分项只展示蓄力段；固定落点、无战斗与时停是已确认范围；未新增外部强类型资源，不产生本轮 Quick Load 检索任务。这些均保持现有设计，不引入额外规则。

## 文件未改动证明

动画库 SHA256（前后一致）：
`12600db9b2ac020213fa0b8767acc397a32344b01e5d2581bd15a1e74a63b613`

工作台 SHA256（前后一致）：
`b92f93e678d66056ed6cce81c52b57b92caf8e310e9880d8c7688a26d95ab06b`

## 全项目回归

首轮尝试143个 Test.gd：141个直接成功，一个原为 RefCounted 的 RangedAttackPipelineTest 需调用 collect_failures()（已原生执行，返回空失败列表），一个 CameraFollowControllerTest 失败。

已单独复测 CameraFollowControllerTest，失败仍为 `room navigation mesh is baked`。原生读取 Scenes/TestCombatRoom.tscn 的 NavigationRegion3D.navigation_mesh，polygon_count=0。不是本轮视觉改动造成；本次不改既有关卡，不自动烘焙。

首轮同时运行 MCP 和多个测试进程，MCP 请求被同项目测试 autoload 误接，产生工具诊断。已停止画面检查后单独重跑 ChainSkillPresentationControllerTest、SkillReleasePresentationTest、UnitHealthFrameSkillNoticeTest，全部 PASS，无该类注入错误或泄漏。最后一轮完整回归已完成：142个可直接运行的脚本中141个成功，仅 CameraFollowControllerTest 的原有导航网格断言失败；其余无脚本错误或退出泄漏。RefCounted 契约另行调用 collect_failures() 已通过。

原有防错用例会主动产生合法的配置警告，不能等同于测试失败。日志和结果表保存在 .godot/flame_barrage_validation/（不作为正式内容资产）。

## 最后运行复核

在真实运行的 Sequence 预览中连续重播30轮，每轮用1.9秒大步长推进，30/30轮均完成五次主爆炸，孤儿节点增量0。随后重新运行完整预览核对画面，并在 Godot 打开该场景供 F6 检查。未进行 Git 提交或推送。
