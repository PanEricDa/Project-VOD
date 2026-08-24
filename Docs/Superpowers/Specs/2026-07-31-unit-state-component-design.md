# UnitStateComponent 设计说明

## 目标

在不增加 `UnitBase` 职责的前提下，统一承载单位的生命周期状态，并为未来状态效果提供稳定入口。

## 职责边界

- `UnitBase`：生命值、阵营、目标可选性及既有公共信号。
- `UnitStateComponent`：死亡、复活、待删除状态，以及死亡后的生命周期策略。
- `WorldHealthBar`：只负责血条表现。
- `SkillHost`：只负责技能装载与释放。
- `CombatSystem`：只负责攻击行为。
- `Visual`：只负责角色模型和视觉节点。

## 当前节点路径

```text
UnitBase
├── UnitState
├── Visual
├── SkillHost
└── WorldUIRoot
    └── WorldHealthBar
```

## 死亡策略

`UnitStateComponent.death_mode` 提供三种模式：

- `KEEP_FOR_REVIVE`：保留视觉和单位根节点，等待 `revive()`。
- `REMOVE_AFTER_DELAY`：播放死亡动画，在 `remove_after_seconds` 到达后删除单位根节点。
- `REMOVE_IMMEDIATELY`：死亡后立即删除单位根节点。

死亡特效是可选的，组件没有特效场景时仍然可以正常处理状态。死亡期间模型保持可见，直到单位销毁或复活。死亡动画名称和动画库属于内部协议，不在 Inspector 中重复配置。

## 未来扩展

未来可以在 `UnitState` 下扩展数值状态、Buff/Debuff、控制限制等内容，但这些状态的具体表现仍应由独立 UI 或效果场景负责，避免形成一个包含所有逻辑的万能脚本。

本阶段没有迁移 `UnitBase` 的生命值代码，也没有修改 `TestScene` 中的单位实例。
