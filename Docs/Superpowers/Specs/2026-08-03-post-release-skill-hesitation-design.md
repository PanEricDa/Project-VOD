# 技能释放后犹豫设计

## 目标

将 AI 技能的随机犹豫从施法前移动至技能成功释放后。技能第一次进入合法施法距离时应立即请求动作；成功交付后才进入随机等待，等待结束后再开始独立技能冷却。

## 运行流程

```text
READY → QUEUED → CASTING → RELEASED → POST_RELEASE_HESITATION → COOLDOWN → READY
```

- `READY`：可被自动或明确请求。
- `QUEUED`：目标尚未进入施法距离；一旦进入范围，立即请求角色动作。
- `RELEASED`：动画的 `release_action()` 已成功启动 Delivery。
- `POST_RELEASE_HESITATION`：按技能配置生成一次随机等待；技能不可再次请求，但不持有 Host 的 active skill，也不占用公共冷却。
- `COOLDOWN`：犹豫结束后才开始计时的独立技能冷却。

## 职责边界

- `SkillHostComponent` 只负责技能装配、候选选择、动作路由与公共冷却；不再计算 AI 随机犹豫，也不在请求前保留 pending skill。
- `SkillBase` 唯一维护释放后的犹豫计时和技能冷却状态。
- 行为状态机在技能释放后可继续让普通攻击填充；既有公共冷却仍从成功动作请求开始计时。

## 配置语义

- 保留现有字段名以避免现有技能场景失效：`decision_delay_min/max` 改为“释放后常规等待”的最小/最大秒数。
- `extra_hesitation_chance/min/max` 改为“释放后额外等待”的概率与秒数。
- 配置值的默认数值不变；只有生效时点从施法前移动到成功释放后。

## 失败与取消

- 任何未成功交付的请求都不产生犹豫或技能冷却。
- Delivery 启动失败仅沿用 `cooldown_on_failed_release` 的既有冷却规则，不进入释放后犹豫。
- 重置、死亡、卸载或场景离树应清空犹豫与冷却计时。

## 验证标准

- 自动技能的首发不再等待随机时间。
- 成功释放后先处于等待状态，等待结束后才触发 `cooldown_started`。
- 释放后等待期间 `is_ready()` 为 false，自动技能不会重复请求。
- 显式请求仍不使用随机等待。
- 原有技能范围、动作、Delivery、公共冷却和普通攻击行为不变。
