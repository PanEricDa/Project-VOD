# 玩家攻击输入缓存与按住连击设计

## 目标

为 `PlayerAttackController` 增加明确的输入提前量和按住自动连击，同时保持连击段数由当前武器的
`basic_attack_1...N` 动画决定。

## Inspector 参数

```gdscript
@export var attack_action: StringName = &"player_attack"
@export var input_buffer_duration: float = 0.15
@export var combo_reset_duration: float = 0.7
@export var hold_to_chain_enabled: bool = true
@export var hold_combo_restart_delay: float = 0.3
```

## 行为

- 攻击播放期间的下一次按键只缓存 `input_buffer_duration` 秒。
- 当前段在缓存过期前结束时，立即进入下一段；过早输入会自然失效。
- 当前段结束后没有有效缓存时，仍可在 `combo_reset_duration` 内手动接续。
- 开启按住连击后，只要攻击键仍被按住，每段结束时都会自动续接。
- 整套连击结束且攻击键仍被按住时，等待 `hold_combo_restart_delay` 后从第一段开始新一轮。
- 自动重启等待期间松开按键会取消重启；重新按下属于新的主动输入，可立即开始。
- 最多缓存一次输入，不允许跳段。
- 取消攻击、换武器或重新配置组件时清空所有缓存和等待状态。

## 范围

不修改武器动画、装备系统、角色移动、Hitbox、伤害或 InputMap 绑定。

