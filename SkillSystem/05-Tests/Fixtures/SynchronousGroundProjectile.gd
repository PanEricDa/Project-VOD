extends Node3D
## 测试投射物：发射调用内同步抵达，用于验证物理阶段结算。
signal projectile_hit(target: UnitBase, position: Vector3, direction: Vector3)
## destination为预采样地面；start仅匹配通用投射物契约。
func launch_point(destination: Vector3, _start: Vector3) -> bool:
	projectile_hit.emit(null,destination,Vector3.DOWN)
	queue_free()
	return true
