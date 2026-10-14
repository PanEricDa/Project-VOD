extends Node3D
## 阶段二验证入口：只有一个开发费用批次，不代替阶段三的伤害间隔连携窗口。
var _development_round: int = 0
func _ready() -> void:
	var source := get_node("SquadChainCommandController") as SquadChainCommandController
	source.set_round_source(_peek_development_round, _acquire_development_round)
func _peek_development_round() -> int: return _development_round
func _acquire_development_round() -> int:
	if _development_round == 0: _development_round = CombatDamageContext.allocate_id()
	return _development_round
