# Weapon Data Inheritance Implementation Plan

**Goal:** 将武器共性、近战交付数据和远程交付数据拆分为扁平、可在 Inspector 直接维护的继承型 Resource。

**Architecture:** `WeaponData` 保存所有武器共有的视觉、动画和攻击距离。`MeleeWeaponData` 保存近战前移与 Hitbox 配置；`RangedWeaponData` 保存投射物预制场景与弹道参数。技能系统不在本次变更范围。

## Completed implementation steps

- [x] 新增继承契约测试，定义剑、盾、法杖、法球为近战兜底数据，弓为远程数据。
- [x] 创建两个派生 Resource 脚本并迁移字段。
- [x] 通过 Godot ResourceSaver 重存五份数据资源并验证 UID 与 Inspector 类型。
- [x] 收紧近战 Hitbox 与攻击位移接口的参数类型。
