# 阶段三连携评价实施与验收记录

日期：2026-10-16。运行基线1942f0a；本阶段代码提交截至ffb9f86。状态：功能、完整回归、正式Focus审计与独立审查均已完成；两项非阻断改进延后，详见下文。阶段四未实施。

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

重新从项目全域枚举（排除Archive/addons，包含GameFlow）137个SceneTree测试，逐文件Godot MCP运行：首轮137/137退出0、有PASS、无SCRIPT ERROR/ERROR/超时。原始结果归档在 .superpowers/archives/2026-10-16-burst-combo-stage-3-evaluation-plan/full-suite.json；最终复验为同目录final-suite.json，正式审计formal-audit.json、独立审查final-review.md与ledger一并保留。另RangedAttackPipelineTest.collect_failures()返回[]；两个新场景UID有效。新增非法参数用例随后独立W再次通过。

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

## 最终审计与独立审查

正式Focus审计默认3轮各20秒、10次世界重载、2200笔事务PASS。三轮最大账目误差均0，世界归属错配0；清理后节点回基线52、orphan0、旧Focus监听0。

独立审查Sagan（gpt-6-astra/high）只读检查完整3f77e9b..599c854差异，并独立重跑W/I/U均PASS。无Critical/Important，结论可合入。以下Minor已核对为非阻断，本轮不扩大修复：

1. 错误重复装配第二个评价组件时，每帧会重试并告警；有效单组件装配不受影响。后续可按源/所有者身份去重告警。
2. 尚无close_round→slot_status_changed早期同步回调，以及UI更换Focus源后旧监听断开的专门用例；已有round_finished重入、世界解绑、提供者替换与通用重载检查通过。属于测试覆盖补强，不据此声称发现运行故障。

实施范围取舍：保持当前目录和分支（需继续注意并发人工编辑）；Windows技能助手以等价MCP记录替代（仅影响流程记录）；原生继承保存的冗余配置清理（若继承有误由加载与实跑测试发现）；阶段四/正式房间未接入（后续另授权）；主观舒适度由用户试玩确认（可能需要继续调表现）。

Git仅本地记录，未推送、未合并、未创建PR。最终版本号见Git最新本地提交。

最终收尾复验：重新独立运行全部137项，137/137退出0、有PASS，无SCRIPT ERROR/ERROR/超时。没有因审查意见再修改运行逻辑；两项Minor明确延后。临时执行目录已清理为可恢复归档，其他计划目录未触碰。

## 2026-10-16：调试UI补充数值评分

复用原Evaluation/ChainSummary标签，在连击后增加“评分105.00 / 100”。实时连携与1秒结算摘要均显示实际未封顶分数，保留两位小数；进度条仍最多100%。新一轮立即替换旧分数，PENDING与摘要结束后继续按原规则隐藏，不新增Inspector项、节点、场景或评分规则。

新增真实UI断言先RED（实时105、摘要105、新轮5.20均未显示），再仅修改原显示格式GREEN。SquadChainRoundDisplayTest与SquadChainInputDisplayTest通过；完整回归137/137退出0、有PASS，无SCRIPT ERROR、ERROR或超时。原始结果归档于.superpowers/archives/2026-10-16-score-display/full-suite.json。


## 2026-10-16：保留上一轮评分供调试查看

移除UI内部1秒摘要计时，结算后的连击数、数值评分、评分条和结果保留到新轮第一次有效连携伤害；新指令受理/释放尚未命中时仍显示旧结果。闭窗后伤害间隔倒数立即隐藏，解绑/更换评价源时清空旧摘要，不延长业务窗口，不保存终结资格。未更改评分、专注收益或自然回复。

真实UI测试先复现4项失败，再通过；新增暂停、未命中新轮、低分结果保留和解绑重绑检查。完整回归137/137通过，退出码0、有PASS，无SCRIPT ERROR、ERROR或超时；错误来源测试仍会主动触发既有预期警告。结果记录：.superpowers/archives/2026-10-16-score-display/retained-result-suite.json。


## 2026-10-16：评分与专注获取难度系数

在原SquadChainRoundController增加Evaluation / Score Difficulty，在原SquadFocusComponent增加Focus / Focus Gain Difficulty，各1个export float。均默认5、Inspector最低0.1、可超过10，并提供中文用途/约束/生效时机说明。无新增场景、脚本或资源，不改变原H0=20、D0=500及damage_to_focus_ratio=0.1。两处均采用原结果×5/各自难度，评分每轮受理时捕获，专注从下一笔有效常规伤害生效；100分资格线、连击/实际扣血、窗口、资源余额/容量/费用与零收益来源规则不变，不增加自然恢复。

新增真实伤害行为测试先RED再GREEN：覆盖5/2.5/10/1/0.1、评分资格及跨轮快照、专注容量封顶/动态修改不重算余额/预留扣费不缩放/连携终结不回充/基础收益0仍关闭，以及0/负数/NaN/Inf拒绝无效输入。Godot编辑器API实测两个源场景的新增属性均对Inspector可见，默认值5.0，范围0.1,10.0,0.1,or_greater。

定向测试启动时曾出现多种全局类型未识别；检查编辑器类索引注册后，无源码改动复跑通过。最终完整回归137/137通过，退出0、有PASS，无SCRIPT ERROR、ERROR或超时；非法配置/重复评价源等测试仍会主动发出预期警告。结果记录：.superpowers/archives/2026-10-16-score-display/difficulty-coefficients-suite.json。


## 2026-10-16：对数连击与1.1次幂伤害评分

已在原SquadChainRoundController实现S=[40×log₂(1+H/H0)+60×(D/D0)^1.1]×(5/难度)，按本轮累计H/D重算。无新增脚本、场景、资源或export参数，专注收益与技能规则未改。默认基准试调为H0=10、D0=100，原难度默认5作为当前曲线标准倍率，不承诺复刻旧线性分数。Godot编辑器API实例化确认当前SquadChainRoundPreview继承10/100，用户难度覆盖3保持不变；未编辑预览或哥布林场景。

TDD先按批准的算例、边际收益与累计伤害规则观察RED，再实现GREEN；新增同一命中100伤害一次/拆十笔得分相同、十次独立命中100伤害只增加连击贡献、等总伤害下后十击收益小于前十击、同次命中伤害的边际贡献温和增加等检查。难度系数/快照与真实UI数值断言更新到曲线模型，保留原资格/闭窗/退款/晚到弹道规则。真实UI显示357.89（1击500伤害）、5.88（1击1伤害）且保持上次结果，100进度上限不截断实际评分。

SquadChainRoundWindowTest、SquadChainRoundDisplayTest与SquadChainRoundIntegrationTest定向通过，完整回归137/137退出0、有PASS，无SCRIPT ERROR、ERROR或超时；既有负向测试保留预期警告。结果记录：.superpowers/archives/2026-10-16-score-display/curve-score-suite.json。


## 2026-10-16：衔接窗口增加30%

原评分节点damage_interval_seconds默认由2.0改为2.6秒，并同步中文参数说明与配置指南；未改评分、专注、技能速度、输入或续窗规则。当前预览无窗口覆盖值，直接继承新默认；未编辑用户预览或单位场景。

按TDD新增正式源场景默认值驱动的真实伤害测试：旧2秒配置先出现3项预期失败，改为2.6后通过。验证首击开启2.6秒、2.1秒仍可衔接、恰在2.6秒命中可续窗并刷新完整2.6秒、超过2.6秒正常闭窗。既有时钟算法用例显式配置2秒夹具，避免试玩调参耦合核心契约；新增UI预览装配断言单独验证正式预览为2.6秒。

窗口、UI及交付集成定向测试通过；完整回归137/137退出0、有PASS，无SCRIPT ERROR、ERROR或超时，负向测试保留预期警告。结果记录：.superpowers/archives/2026-10-16-score-display/window-extension-suite.json。
