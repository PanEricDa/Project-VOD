# Threat Debug Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为每个敌方单位添加只读、可开关的仇恨调试显示，不改变任何核心战斗行为。

**Architecture:** `ThreatDebugDisplay` 是 EnemyBase 的独立直接子节点。它仅监听既有威胁和锁定目标信号，将事件数据缓存为显示文本；它不读取或写入 ThreatComponent 的内部表，也不介入目标选择。

**Tech Stack:** Godot 4.7、GDScript、Label3D、现有 SceneTree 契约测试。

## Global Constraints

- 所有新增 `@export` 均紧邻简体中文用途说明。
- 不修改 `Scenes/TestScene.tscn` 中的任何单位实例。
- 不修改仇恨结算、索敌、行为状态机或伤害结算的核心脚本。
- 本项目不是 Git 仓库；以 Godot headless 测试和编辑器扫描作为验证。

---

### Task 1: 调试显示契约测试

**Files:**
- Create: `UnitSystem/Tests/ThreatDebugDisplayTest.gd`
- Test: `UnitSystem/Tests/ThreatDebugDisplayTest.gd`

**Interfaces:**
- Consumes: 同级节点 `ThreatComponent.threat_changed(source, previous_value, current_value)`。
- Consumes: 同级节点 `AITargetingComponent.locked_target_changed(previous_target, current_target)` 和 `get_locked_target()`。
- Produces: 对 `ThreatLabel.text` 与 `ThreatLabel.visible` 的可验证调试输出。

- [ ] **Step 1: 写入失败测试**

```gdscript
fake_threat.threat_changed.emit(hero, 0.0, 17.0)
fake_targeting.locked_target_changed.emit(null, hero)
_expect(label.visible, "positive threat makes display visible")
_expect(label.text.contains("Target: Hero 17.0"), "locked target is shown")
```

- [ ] **Step 2: 运行测试并确认因场景不存在而失败**

Run: `Godot --headless --path G:\Godot\SipSip --script res://UnitSystem/Tests/ThreatDebugDisplayTest.gd`

Expected: FAIL，原因是 `ThreatDebugDisplay.tscn` 尚未创建。

### Task 2: 实现只读调试场景

**Files:**
- Create: `UnitSystem/Debug/Threat/ThreatDebugDisplay.gd`
- Create: `UnitSystem/Debug/Threat/ThreatDebugDisplay.tscn`
- Modify: `UnitSystem/AI/Enemy/EnemyBase.tscn`
- Test: `UnitSystem/Tests/ThreatDebugDisplayTest.gd`

**Interfaces:**
- Produces: `ThreatDebugDisplay`，可通过 Inspector 的 `debug_display_enabled` 开关显示。
- Produces: `ThreatLabel`，显示当前锁定目标和按数值排序的最多四条缓存记录。

- [ ] **Step 1: 实现信号订阅与只读缓存**

```gdscript
func _on_threat_changed(source: UnitBase, _previous: float, current: float) -> void:
    _display_threat_by_source_id[source.get_instance_id()] = current
    _refresh_label()
```

- [ ] **Step 2: 实现 Label3D 文本与可见性刷新**

```gdscript
_label.visible = debug_display_enabled and not entries.is_empty()
_label.text = "Target: %s %.1f" % [target_name, target_value]
```

- [ ] **Step 3: 以直接子节点接入 EnemyBase 源场景**

```text
EnemyBase
├── ThreatComponent
├── AITargetingComponent
└── ThreatDebugDisplay (debug-only observer)
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `Godot --headless --path G:\Godot\SipSip --script res://UnitSystem/Tests/ThreatDebugDisplayTest.gd`

Expected: PASS。

### Task 3: 全量验证

**Files:**
- Test: `UnitSystem/Tests/ThreatDebugDisplayTest.gd`

- [ ] **Step 1: 运行既有仇恨契约测试**

Run: `Godot --headless --path G:\Godot\SipSip --script res://UnitSystem/Tests/EnemyThreatComponentTest.gd`

Expected: PASS，证明核心威胁组件未受影响。

- [ ] **Step 2: 编辑器扫描**

Run: `Godot --headless --editor --path G:\Godot\SipSip --quit`

Expected: 无新增解析错误。

## Self-Review

- 覆盖了只读边界、可开关显示、排序、锁定目标、隐藏规则和核心回归验证。
- 未留下 TBD/TODO 或未定义接口。
- 所有路径、信号名与当前 EnemyThreatComponent、AITargetingComponent 的现有公开接口一致。
