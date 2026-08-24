# 治疗仇恨机制 — 设计方案

**日期**: 2026-08-07
**状态**: 待实现

---

## 目标

仇恨系统当前只有 DAMAGE 类型产生仇恨。`ThreatEvent.Kind.SKILL_BONUS` 枚举已定义但未激活。本方案为治疗技能补齐仇恨生成路径，使治疗者可以受到敌人的注意。

---

## 设计约束

| 约束 | 说明 |
|------|------|
| 不新增文件/脚本/组件 | 所有改动在现有三个文件中完成 |
| 仇恨分发范围 | 仅通知当前处于 ENGAGED 状态的 Pack 中的存活敌人 |
| 仇恨公式 | `治疗量 × threat_multiplier`（设计者在技能上自行设定 threat_multiplier，如 0.5） |
| 触发条件 | 技能有效治疗（`apply_healing()` 返回 > 0） |
| 归位中行为 | 与伤害仇恨一致，无特殊规则 |
| 非技能治疗 | 不产生仇恨（药水、Buff 等直接调用 apply_healing 的路径不经过 SkillEffect） |
| 无 EncounterController | 静默跳过，不影响治疗本身 |

---

## 架构

```
HealthChangeSkillEffect.apply(HEAL)
  → CombatValueResolver.apply_healing() → 返回 applied_amount
  → 若 applied_amount > 0 且 context.threat_multiplier > 0:
      → 通过 delivery_parent 找到 EncounterController
      → 调用其公开方法获取 ENGAGED Pack 中的存活敌人列表
      → 对每个敌人:
          创建 ThreatEvent (kind=SKILL_BONUS, base=applied_amount, multiplier=threat_multiplier)
          → enemy.get_threat_component().submit_threat(event)
  → 返回 true（仇恨提交失败不影响治疗结果）
```

---

## 各文件改动

### 1. `EnemyThreatComponent.gd` — 激活 SKILL_BONUS

**位置**: `submit_threat()` 方法

**改动**: 移除当前 `if kind != 0 return false` 的拒绝逻辑。SKILL_BONUS 与 DAMAGE 走完全相同的加法路径（累加、刷参考峰值、发信号）。

**已有安全网**: `_is_event_valid()` 已校验 source 存活、敌我关系、base_amount > 0，SKILL_BONUS 自动继承同等保护。

### 2. `EncounterController.gd` — 新增只读查询

**新增一个公开方法**，语义为「返回当前所有战斗中 Pack 的存活敌人列表」。

**内部逻辑**:
- `_is_configured == false` → 返回空数组
- 遍历 `_records_by_pack`，只取 `state == PackState.ENGAGED`
- 每个记录中过滤掉已被 `died` 确认击杀的和已释放的实例
- 返回 `Array[EnemyBase]`

**方法性质**: 纯只读，不发射信号、不改写状态、不触发副作用。

**边界场景**:

| 场景 | 行为 |
|------|------|
| 控制器未配置 | 空数组 |
| 无 Pack | 空数组 |
| 所有 Pack 为 DORMANT/RESETTING/CLEARED | 空数组 |
| ENGAGED Pack 中部分敌人已死 | 只返回存活者 |

### 3. `HealthChangeSkillEffect.gd` — HEAL 分支扩增

**位置**: `apply()` 方法，HEAL 分支末尾

**改动**: 在 `CombatValueResolver.apply_healing()` 调用后增加仇恨提交逻辑。

**流程**:
```
applied = CombatValueResolver.apply_healing(caster, target, base_amount, power_ratio)
↓ applied > 0 且 context.threat_multiplier > 0:
  ↓ 从 context.delivery_parent 定位 EncounterController
  ↓ 获取 ENGAGED 敌人列表
  ↓ 对每个存活敌人:
      创建 ThreatEvent:
        - kind = SKILL_BONUS
        - source = context.caster
        - base_amount = applied
        - threat_multiplier = context.threat_multiplier
      → enemy.get_threat_component().submit_threat(event)
→ return true
```

---

## 边界与失败设计

| 场景 | 行为 | 理由 |
|------|------|------|
| 治疗量 ≤ 0（目标已死/满血/零治疗） | 不触发仇恨 | 无效治疗不应引起注意 |
| `threat_multiplier` ≤ 0 | 跳过整个循环 | 允许设计者做零仇恨治疗 |
| EncounterController 不存在 | 静默跳过 | 测试/临时场景兼容 |
| ENGAGED 敌人列表为空 | 循环零次 | 正常非战斗场景 |
| 单个敌人 ThreatComponent 缺失 | `continue` 跳过，继续后续 | 防御性容错 |
| `submit_threat()` 内部拒绝 | 不关心返回值 | 已有 `_is_event_valid` 保护 |
| 敌方治疗敌方 | `_is_event_valid` 中 `is_hostile_to(source)` 拦截 | 无需 SkillEffect 额外判断 |
| 同帧多个治疗技能 | 各自独立提交 | 无共享状态，无竞争 |

---

## 全状态生命周期验证

### IDLE（非战斗，锁敌开启）
治疗仇恨只向 ENGAGED Pack 提交，DORMANT 敌人不会收到。治疗不唤醒未激活的敌人。✓ 符合预期。

### CHASE / ATTACK（战斗中）
SKILL_BONUS 累加到威胁表 → `threat_changed` 信号触发 `refresh_target()` → 正常参与目标优先级排序。目标切换受 `TARGET_SWITCH_THREAT_RATIO`（1.25×）保护。✓ 与 DAMAGE 行为一致。

### RETURN_HOME（归位中）
治疗仇恨写入 → `refresh_target()` 检测到 `detection_suspended == true` → 不选目标。抵达出生点后 `resume_detection()` → IDLE → 下一次 refresh 正常选出目标。✓ 与 DAMAGE 行为一致。

### DORMANT Pack
不收到通知。✓ 符合约束。

### RESETTING Pack
收到通知 → 敌人转入战斗 → EncounterController 重置倒计时 → 回到 ENGAGED。✓ 与 DAMAGE 行为一致。

### CLEARED / TRACKING_INVALID
查询方法自动排除。✓ 安全。

---

## 不改动的范围

- PlayerBase 的玩家操作不经过此路径（玩家通过 SkillBase 施法时仍然经过 HealthChangeSkillEffect）
- 非技能治疗（药水、Buff 光环、环境效果）不产生仇恨
- EncounterController 的职责不扩张（只新增一条只读查询，不管理友方单位）
- 半衰期衰减机制不变（SKILL_BONUS 的衰减与 DAMAGE 完全相同）

---

## 测试验证点

1. 治疗技能对友方目标生效 → ENGGAGED Pack 中敌人获得与治疗量 × threat_multiplier 相等的 SKILL_BONUS 威胁
2. `threat_multiplier = 0` 的治疗技能 → 无仇恨生成，治疗本身不受影响
3. 无 EncounterController 的场景 → 治疗正常生效，无报错
4. 归位中敌人被治疗仇恨命中 → 仇恨写入但索敌暂停，归位完成后正常拉怪
5. 治疗量溢出（目标满血溢出的部分不产生仇恨） → 只有实际有效治疗量计入
6. DORMANT Pack 中的敌人 → 不收到仇恨事件
7. 敌方单位治疗敌方单位 → submit_threat 内部拒绝，不产生对玩家的仇恨
