# 终结选择窗口：实施与验收（阶段四第一切片）

日期：2026-10-18。范围完成：选择接口、慢速、倒计时、UI与日志；并非完整阶段四完成。
设计：[选择窗口设计](../Specs/2026-10-18-finisher-selection-window-design.md)。
计划：[实施计划](2026-10-18-finisher-selection-window-plan.md)。

## 可以看到什么

F6运行 `res://Scenes/Previews/SquadFinisherSelectionPreview.tscn`。
沿用原战斗：积累专注、锁定目标、1—4施放连携，停止续接后等待伤害间隔结束。
只有连携结算达分才弹出；累计分数先达到门槛不提前弹出。
十字位于画面中央偏右下方，左1 Guardian、上2 Priest、右3 Caster、下4 Archer；名字/角色均来自原固定伙伴槽。
战斗降至5%；默认3真实秒倒计时。新按下选项出现亮边，输出[FinisherSelection]选择日志，短暂保持后收起。
不选则超时放弃。关闭恢复申请前速度，且不解除其他暂停或输入禁用。
目前只有接口测试选项：未装备正式终结仍能测试；不执行终结技能、不扣专注、不取消原动作或缓存。

## Inspector与文件

控制器：`UnitSystem/Components/Combat/Squad/SquadFinisherSelectionController.tscn`。
仅Round Source、Pause Source、Selection Duration Seconds、Selection Time Scale四项。
预览引用原SquadChainRoundController，以及原ChainSkillPresentationController/PauseCoordinator；不重复配置角色、专注或评价。

显示：`UnitSystem/Components/UI/SquadFinisherSelectionDisplay.tscn`，Selection Source指向控制器。
Root/Cross下可直接编辑Slot1—4、Title、Countdown、Theme/StyleBox；编辑器手动显示Root不会被工具脚本自动隐藏。
运行时弹出/高亮/收起时长内部封装，不导出新的策划参数。

正式新增：运行2gd、测试3gd、3tscn、0tres（不含Godot生成的5个脚本.uid）。
修改原暂停协调器、伙伴指令控制器及配置指南。原有数值测试仅同步两条过期预期：预览专注难度3、评分难度2；这两个值在开工前即如此。

## 自动验收

- 最终全量：141/141测试入口通过，全部exit_code=0，且无SCRIPT ERROR或ERROR输出。
- 全量后补强死亡与跨世界选择分支，完整SquadFinisherSelectionControllerTest再次exit=0。
- 压力：50次真实资格轮次、选择/超时交替、10个世界重载；时间token、输入阻断无累积，恢复为原速度。
- 真实Host释放、实际扣血与评价闭窗验证资格，未用UI假分数替代主正路径。
- 输入走InputMap和真实viewport：四槽、改绑、持键跨开窗、回声、同帧多键、关闭边界、解绑期间释放及恢复后新按下。
- 真实时钟在5%倍率下正常推进；显式暂停冻结剩余时间，释放强调不偷改其他持有。
- 慢速多持有取最慢上限，不累乘；非1基线恢复、删除owner/manager/world/解绑、幂等清理通过。
- 伙伴空槽、重复、死亡、跨世界无效；未装备终结技能仍可验证接口。
- 视口2560×1440、1920×1080、1280×720、960×540布局不裁切。
- 继承场景base state及三个新场景有效UID已验证；预览只有一个原暂停协调器。
- UI只读、深复制快照、晚绑定不补弹历史、重绑不能重放已消费轮次。
- 原连携执行、费用、技能、动画、镜头、伤害、治疗及资源回归包含于141项。

首轮140/141：唯一失败为旧CombatBalanceBaselineTest预览难度断言过期，已核对开工前快照并仅同步断言；没有改动游戏配置让测试过关。

完整归档：`.superpowers/archives/2026-10-18-finisher-selection-window/verification.json`。
工作日志与开工前文件快照保留在`.superpowers/sdd/2026-10-18-finisher-selection-window-plan/`，因未授权提交而不删除唯一恢复资料。

## 可见验证与工具限制

实际运行独立预览，检查弹出、Caster选中亮边和关闭后的截图：
- `.superpowers/sdd/2026-10-18-finisher-selection-window-plan/preview-open.png`
- `.superpowers/sdd/2026-10-18-finisher-selection-window-plan/preview-confirmed.png`
- `.superpowers/sdd/2026-10-18-finisher-selection-window-plan/preview-closed.png`

截图使用仅运行时注入的已结算资格及忽略目录中的frame-local探针，不保存进正式场景、不降低正式评分门槛；自动验收另走真实伤害与结算。
选择高亮约0.12秒，普通截图工具第一次未抓到该短帧，未将那张截图冒充成功证据。
一次带await的临时MCP运行脚本触发插件“异步函数未await”错误；插件不支持该调用方式，未修改插件，以同步装配的临时探针抓帧成功。
MCP生成的临时脚本本身有_mcp_error未使用警告；正式新增脚本测试无此警告。不得把工具历史日志宣称为游戏代码错误或伪称清空历史Debugger。

## 独立审查与处理

独立只读审查者Sagan给出5项Important与1项Minor，执行者按实际影响处理：
1. 申请输入阻断的同步回调取消会遗漏刚返回的token：新增失败回滚测试RED→GREEN，使用局部token/绑定代次检查。
2. 输入事件推进关闭后可能穿透：保存事件进入时的所有权，旧方法变异复现RED、恢复新方法GREEN。
3. 信号回调直接free发信号对象：Godot对象锁禁止，真实复现为引擎locked-object错误；不能承诺支持。改用合法queue_free并补解绑、计时和输入路径的清理验证，调用链检查排队删除/树状态。
4. 同源重绑清零已消费水位：保持全局单调轮次水位，阻止历史重放；RED→GREEN。
5. 解绑期间keyup未清持键尾状态：先处理释放状态，再查指令绑定；RED→GREEN。
6. 编辑器持续隐藏Root：按“人类可编辑”要求升级为必须处理，运行时渲染增加编辑器保护，MCP验证手动显示false→true。

无延后Minor。未再次派遣审查者；按已选执行方式，修正通过回归验收。

## 实施裁定与影响

- 按用户选择在当前目录实施，不自动提交/推送、不开新工作树。影响：没有逐任务Git恢复点，以本轮快照和日志保留回退依据。
- 重复或跨世界伙伴不连接Host信号，避免原有重复connect报错。影响：无效配置需修正后才重新参与，不静默选择其中一个。
- 卸载回调采用queue_free；直接free发信号对象仍由Godot禁止。影响：后续模块须遵循引擎生命周期，不承诺绕过对象锁。
- 编辑器允许静态手动显示，运行时才驱动弹窗动画。影响：编辑器不自动播放战斗驱动动画，但节点和样式可直接维护。
- 旧数值断言对齐当前预览3/2，配置未改。影响：不再约束历史10/1.5参数，现有伤害、专注算法和评分算法不变。

## 尚未实现

实际终结技能及合法性、角色行动接管、暂停演出与释放点结算、正式关卡装配均未进入本切片。
玩家仍可按已有规则在慢速中移动；窗口只占用原四个伙伴输入。
