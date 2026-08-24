# Animation Marker Player Attack Motion Design

## Goal

为玩家三段武器攻击增加受 CharacterBody3D 碰撞约束的真实前进位移。动画库只标记位移开始时机，WeaponData 保存每段距离与武器共用速度，PlayerBase 保持唯一物理移动执行权。

## Data Flow

```text
AnimationLibrary method marker: request_attack_motion()
    -> CharacterAnimationEventPlayer.attack_motion_requested
    -> PlayerAttackController reads current combo index
    -> WeaponData.attack_forward_distances[index] + attack_motion_speed
    -> PlayerBase.request_attack_motion(direction, distance, speed)
    -> one move_and_slide() with regular movement + attack velocity
```

## Components

- `CharacterAnimationEventPlayer.gd`：挂在现有 CharacterAnimationPlayer 上，仅把无参数方法轨道调用转为信号。
- `WeaponData.gd`：新增 `attack_forward_distances: Array[float]` 与 `attack_motion_speed: float`。
- `PlayerAttackController.gd`：只在 ATTACKING 状态响应 marker，根据 1-based combo index 读取 0-based 距离数据，并转交 PlayerBase。
- `PlayerBase.gd`：提供真实攻击位移接口；锁定请求时的角色正面方向，将攻击速度与 WASD 水平速度相加，并继续使用唯一一次 `move_and_slide()`。

## Rules

- 冲刺优先：开始冲刺会取消攻击位移；冲刺期间拒绝新攻击位移请求。
- 普通 WASD 与攻击位移相加。
- 每段位移方向在 marker 触发时锁定，期间不转弯。
- 新 marker 替换尚未结束的旧攻击位移，不叠加。
- `cancel_combo()`、卸装和换装立即取消剩余攻击位移。
- 缺少 marker、距离数组项、非正距离或非正速度时安全无位移，攻击动画继续。
- CharacterRoot 动画仍只负责视觉重心，不作为真实位移。

## IronSword Defaults

```text
attack_forward_distances = [0.12, 0.16, 0.28]
attack_motion_speed = 2.0

basic_attack_1 marker = 0.15s
basic_attack_2 marker = 0.16s
basic_attack_3 marker = 0.20s
```

方法轨道目标固定为 `CharacterAnimationPlayer`，方法固定为 `request_attack_motion`，不携带参数。设计师以后只需在动画时间轴拖动 marker，并在 IronSwordData Inspector 中调整距离与速度。

## Exclusions

不加入 Root Motion、攻击碰撞、伤害、命中反馈、AI 接入或 TestScene 单位修改。
