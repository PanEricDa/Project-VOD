# AI Combat Manual Mounting Implementation Plan

**Goal:** 将 AI 战斗系统从 `AIUnitBase` 父场景移除，改由每个具体单位场景手动选择并实例化。

**Architecture:** `AIUnitBase` 仅通过同级固定节点名 `CombatSystem` 查找可选的 `AICombatSystem`。近战单位使用 `AIMeleeCombatSystem.tscn`，远程单位使用 `AIRangedCombatSystem.tscn`；没有战斗部件的 AI 仍可正常移动和索敌。

## Completed tasks

- [x] 移除 `AIUnitBase.tscn` 预置的近战 CombatSystem。
- [x] 将 AIUnitBase 的组件查询改为可选查找，缺失时不报配置错误。
- [x] 为 Guardian、Saber 和 EnemyBase2 手动实例化 `AIMeleeCombatSystem.tscn`。
- [x] 为 Archer 手动实例化 `AIRangedCombatSystem.tscn`。
- [x] 更新基础迁移测试，验证 AIUnitBase 无战斗组件时安全工作。
