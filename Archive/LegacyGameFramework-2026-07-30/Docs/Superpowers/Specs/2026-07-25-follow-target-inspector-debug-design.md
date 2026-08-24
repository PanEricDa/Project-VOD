# 跟随目标 Inspector 调试字段设计

## 目标

`AllyBehaviorStateMachine` 的默认跟随规则继续由算法固定解析唯一
`faction_id = "Player"` 的单位，不增加可配置的目标、阵营或节点路径。

## Inspector 表现

- 增加只读分类 `Debug`。
- 增加只读属性 `Current Follow Target`。
- 属性显示状态机当前实际使用的跟随单位。
- 属性不参与场景保存，不能在 Inspector 中被设计师改写。
- 默认玩家解析、显式调用 `set_follow_target()`、目标失效和恢复玩家跟随时刷新显示。

## 接口边界

`set_follow_target(target: CharacterBody3D)` 仍是唯一写入跟随对象的公开接口。
调试属性只读取内部运行状态，不参与目标选择和跟随算法。

## 验证

- Inspector 属性存在且带只读标记。
- 属性不带存储标记。
- 默认解析玩家、显式切换单位及恢复玩家时显示值均与实际跟随对象一致。
- 既有状态机、继承场景改名和索敌集成测试继续通过。

