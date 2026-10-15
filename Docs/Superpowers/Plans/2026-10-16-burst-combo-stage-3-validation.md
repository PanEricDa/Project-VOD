# 阶段三连携评价实施与验收记录

日期：2026-10-16。运行基线1942f0a；本阶段代码提交截至ffb9f86。状态：功能与首轮完整回归已完成，正式Focus审计及独立审查进行中；阶段四未实施。

## 实际交付

新增运行1gd/2tscn/0tres：SquadChainRoundController.gd/.tscn与Scenes/Previews/SquadChainRoundPreview.tscn。新增测试3gd；4个gd.uid由Godot登记。修改原指令脚本的两个窄接口，以及原伙伴UI脚本/场景；不改变SkillBase、Host、Delivery、技能参数、角色源场景、InputMap或正式房间。

组件Inspector只有command_source、damage_interval_seconds（2秒）、hit_score_scale（20）、damage_score_scale（500）；UI只新增round_source。UI未配置评价源时保留旧四卡，不显示新增区。终结资格只是一次结果通知，不提供终结菜单、暂停或库存。

## 分组证据

| 组 | 验证 |
| --- | --- |
| 轮次/时钟 | W先RED再GREEN；只在真实受理建立PENDING，空批次/受理回滚回收；精确截止接续，严格多1微秒过期；查询无副作用。10秒持续接续无总时限；真实菜单暂停与0.10秒释放强调冻结时钟；60/120/1000步累计时间误差不超过1微秒。 |
| 评分 | 同hit分10+15只H1/D25/S10；重复event不加分不续窗。20次1伤害S104、1次500伤害S105、10次25伤害S100、1次25伤害S10。过量伤害只计剩余5HP。配置下一轮捕获、非法配置拒绝，无退款副作用。 |
| 事务/交付 | 实际Host/Instant/Tracking/连射/爆裂碎片；旧轮A迟到弹和缓存不加入B，A缓存30/B首发20。并发预留40、重复失败不多退；瞬发清理不漏首击，已释放弹在来源死亡后仍计分。 |
| UI/预览 | 可空源、错误世界隐藏、只读查询、PENDING无虚倒数、分数显示夹紧、1秒结果、暂停挂起、首伤替换摘要。继承预览无开发批次脚本，关闭原debug_enabled避免重复Focus显示。 |
| 压力 | 100次真实根请求、50次自然闭窗、10世界重载；指令/账本请求、预留、动作锁、缓存、当前轮去重和来源表归零；观察者维持真实3单位。动态单位4→3，单独移除评价后旧投射物自然清理，新输入失败关闭。 |

三项新测试：UnitSystem/Tests/SquadChainRoundWindowTest.gd、SquadChainRoundIntegrationTest.gd、SquadChainRoundDisplayTest.gd。原重点事务/目标/表现/时钟测试同步回归通过。

重新从项目全域枚举（排除Archive/addons，包含GameFlow）137个SceneTree测试，逐文件Godot MCP运行：首轮137/137退出0、有PASS、无SCRIPT ERROR/ERROR/超时。原始结果位于本计划临时目录full-suite.json。另RangedAttackPipelineTest.collect_failures()返回[]；两个新场景UID有效。新增非法参数用例随后独立W再次通过。

## 实际运行与布局

新预览通过真实InputMap发送请求，非调用评价器伪造命中：法师一轮H1/D25.490196/S10.098039，弓手下一轮H3/D18.382353/S18.676471，均自然闭窗。诊断靶位置、血量和AI开关只改运行副本，未保存到正式场景。

逻辑视口1280×720时ACTIVE面板矩形(250,422,780,243)，1920×1080时(570,782,780,243)，均底部留55像素、居中向上扩展。Godot嵌入式截图帧缓冲仍为2560×1440，不能把截图尺寸当作逻辑视口尺寸。已检查截图内容；首伤后临时获取菜单暂停只为固定QA画面，随后释放，paused=false。

最后实际运行Debugger仅见既有SkillBase未赋初值、WorldHealthBar整数除法、Pyroblast参数遮蔽及MCP临时探针未用字段提示；无本轮新增运行SCRIPT ERROR/ERROR。不声称全部静态警告为0。

## 工具与实施说明

1. 按用户偏好留在当前Godot目录、当前codex分支；本地逐任务提交，不自动GitHub上传。
2. Windows无可用Bash技能助手；以Godot MCP原生文件API等价维护本计划ledger/brief与实际测试记录，不改生产流程。
3. 代码优先MCP脚本工具，场景用Godot原生编辑/API正式保存。继承保存复制local-to-scene交付资源，原生revert实测0项；仅新预览使用apply_patch清除冗余覆盖，保留引擎登记UID，再用真实加载/继承/运行测试验证。没有复制维护技能参数。
4. 集成夹具最初漏设敌方碰撞层4导致无碎片，补齐夹具而非改生产查询。UI1秒按现有真实表现时钟验证，不拿无头SceneTree加速timer比较墙钟。
5. 实跑探针最初同帧重用InputEvent被引擎警告，已改独立press/release事件重测；临时GDScript类型推断错误修正后重跑，不算生产故障。

用户仍需试玩整体可读性与舒适度；自动测试不能替代主观体验。正式关卡接入和终结系统留待后续授权。
