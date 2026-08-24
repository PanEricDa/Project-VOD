class_name IdealHeroCombatDriver
extends Node

## 仅供无画面压测使用的 Hero 驱动；不写入正式 Hero 场景，也不替代 PlayerAttackController 的攻击流程。

var _hero: PlayerBase
var _attack_controller: PlayerAttackController

## 注入本轮临时 Hero；hero 会被设为不可击杀，并仍通过其既有攻击控制器发动攻击。
func configure(hero: PlayerBase) -> void:
	_hero = hero
	if is_instance_valid(_hero):
		_hero.can_die = false
		_attack_controller = _hero.get_node_or_null(^"AttackController") as PlayerAttackController


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_hero) or not is_instance_valid(_attack_controller):
		return
	var target := _find_nearest_enemy()
	if target == null:
		return
	var offset := target.global_position - _hero.global_position
	offset.y = 0.0
	if offset.length() > 0.9:
		_hero.global_position += offset.normalized() * minf(offset.length() - 0.9, 7.0 * delta)
	_hero.get_node_or_null(^"TargetingSystem").request_lock(target)
	_attack_controller.request_attack()


func _find_nearest_enemy() -> EnemyBase:
	var selected: EnemyBase
	var best: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"enemy_targets"):
		var enemy := node as EnemyBase
		if enemy == null or enemy.is_dead():
			continue
		var distance := enemy.global_position.distance_squared_to(_hero.global_position)
		if distance < best:
			best = distance
			selected = enemy
	return selected
