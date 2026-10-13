extends Node3D

## 测试用同步命中投射物；target 是本次预选目标，position 与 direction 描述命中。
signal projectile_hit(target: UnitBase, position: Vector3, direction: Vector3)


## 从 start_position 立即命中有效目标；仅用于检验交付会话在同步回调期间的生命周期。
func launch(target: UnitBase, start_position: Vector3) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	global_position = start_position
	projectile_hit.emit(target, target.global_position, Vector3.FORWARD)
	queue_free()
	return true
