class_name AIRangedCombatSystem
extends AICombatSystem

## 远程战斗组件：消费统一动画发射事件，在通用 ProjectileOrigin 创建投射物。
## 投射物本身负责飞行和命中规则，本组件不保存弹道、碰撞或伤害算法。

const PROJECTILE_ORIGIN_PATH: NodePath = ^"ProjectileOrigin"


func _configure_attack_delivery() -> bool:
	var controller := get_attack_controller()
	if not is_instance_valid(controller):
		return false
	var callback := Callable(self, "_on_projectile_release_requested")
	if not controller.projectile_release_requested.is_connected(callback):
		controller.projectile_release_requested.connect(callback)
	return true


func _on_projectile_release_requested(
	weapon_data: WeaponData,
	target: UnitBase,
	attack_index: int,
	_attack_direction: Vector3
) -> void:
	var ranged_weapon := weapon_data as RangedWeaponData
	if ranged_weapon == null or ranged_weapon.projectile_scene == null:
		return
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	var controller := get_attack_controller()
	var weapon_socket := controller.get_weapon_socket() if controller != null else null
	var origin := weapon_socket.get_node_or_null(PROJECTILE_ORIGIN_PATH) as Node3D if weapon_socket != null else null
	if origin == null:
		push_warning("AIRangedCombatSystem: ProjectileOrigin is missing.")
		return
	var projectile := ranged_weapon.projectile_scene.instantiate() as Node3D
	if projectile == null or not projectile.has_method(&"launch"):
		if projectile != null:
			projectile.queue_free()
		push_warning("AIRangedCombatSystem: projectile_scene must expose launch(target, origin).")
		return
	var projectile_parent: Node = get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = get_tree().root
	projectile_parent.add_child(projectile)
	if projectile.has_signal(&"projectile_hit"):
		projectile.projectile_hit.connect(_on_projectile_hit.bind(attack_index))
	if projectile.call(&"launch", target, origin.global_position) != true:
		projectile.queue_free()


func _on_projectile_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	attack_index: int
) -> void:
	var controller := get_attack_controller()
	if is_instance_valid(controller):
		controller.report_attack_hit(target, hit_position, hit_direction, attack_index)
