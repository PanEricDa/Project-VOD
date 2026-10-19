# Debugger警告清理验证（2026-10-16）

## 原因及修复

- SkillBase.get_combo_focus_cost：局部found在首次读取前没有显式赋值。明确初始化为null，保持缺失/重复/非法费用组件的原判定。
- WorldHealthBar：状态圆点半径使用整数除法。改为显式浮点乘0.5后floori，仍为6像素，不关闭警告。
- PyroblastCastChargeEffect：回调参数name遮蔽Node.name。改为animation_name，回调行为不变。
- 炎爆蓄力火星在_process渲染帧更新MultiMesh，资产却继承物理插值。仅在独立PyroblastCastChargeEffect.tscn根节点把physics_interpolation_mode设置为Off；子视觉继承，不修改项目全局插值、角色或投射物。依据Godot官方规则：https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html 。
- EncounterController在房间free、detach或祖先queue_free时，敌人先离树，而父房间在回调瞬间仍显示在树中，旧保护不足。离树时立即标记TRACKING_INVALID防止错误清场，使用弱引用在帧末确认房间与Pack仍有效才发出异常事件和警告；正常整体卸载丢弃通知，重新登记的旧记录也不再通知。真正单独删怪/移走存活敌人仍报警，不会算作击杀。

## 公开信号约束

pack_tracking_invalid仍保留原两个参数，但现在于帧末确认。removed_enemy若已被释放则为null，仍存活但被移出树时则保留对象；调用方不得直接假定其有效。该约束已写在信号声明附近，不新增Inspector配置。

## 验证

先通过新增真实用例复现三种整房退出误报及炎爆插值配置失败，再实现修复。EncounterControllerTest覆盖整房free/detach/祖先queue_free无误报、真实单独删除/移出敌人仍有一次异常事件且不清场、已释放参数安全为null。PyroblastVisualEffectTest确认视觉根Off且火星有效插值关闭；既有技能费用与状态圆点测试通过。

完整回归137/137退出0、有PASS，无SCRIPT ERROR、ERROR或超时。空Pack、真实异常删怪及其他负向测试仍保留预期警告，不把测试故意触发的诊断视作正式场景问题。

真实渲染验证：正式SquadChainRoundPreview在全量回归期间运行，35/70/105/137项检查点的Debugger均为0，停止后也为0；独立炎爆蓄力预览另循环至少10秒，运行与停止后均为0。检查工具的临时诊断脚本曾生成unused私有变量警告，重启正常预览后不再存在；未为该工具临时代码修改项目检查配置。

所有编辑均使用Godot MCP Pro；EncounterController被编辑器打开时，先确认CodeEdit缓冲区与磁盘完全一致，再用MCP force编辑，并复核缓冲区已同步。炎爆场景通过编辑器属性工具保存，差异仅一条插值属性。未改玩法数值、技能内容或新增单位。

原始结果摘要：.superpowers/archives/2026-10-16-debugger-warning-cleanup/verification.json。
