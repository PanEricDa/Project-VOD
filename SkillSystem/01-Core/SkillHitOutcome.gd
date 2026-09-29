class_name SkillHitOutcome
extends RefCounted

## 单个目标的一次命中结果；由 Delivery 在任何 Effect 执行前创建，不作为共享资源保存。

## 本次实际结算的目标；后续 Effect 不得将其他目标的结果写入这里。
var target: Node3D
## 命中前已经存在的命名状态快照；同次命中施加的新状态不会出现在这里。
var statuses_before_hit: Array[StringName] = []
## 本目标由本次效果序列造成的实际生命损失，单位为生命值，默认 0。
var actual_damage: float = 0.0
## 本目标由本次效果序列恢复的实际生命值，默认 0；不计入伤害。
var actual_healing: float = 0.0
## 本次命中的世界位置；附近触发以此为中心，默认世界原点。
var impact_position: Vector3 = Vector3.ZERO
