class_name IndependentDirectTrajectory
extends "res://SkillSystem/07-Delivery/01-Trajectories/SkillTrajectoryBase.gd"

@export_category("Direct Travel")
## 从起点到目标快照位置的总时长；0 表示同一流程内瞬间到达。
@export_range(0.0, 30.0, 0.01) var travel_duration: float = 0.0
## 启用时让交付对象的 -Z 方向朝向移动方向。
@export var face_travel_direction: bool = true


func get_travel_duration(
	_context: SkillContextType,
	_origin: Vector3,
	_destination: Vector3
) -> float:
	return maxf(travel_duration, 0.0)


## 使用线性插值生成当前世界变换，不追踪目标后续移动。
func sample_transform(
	_context: SkillContextType,
	origin: Transform3D,
	destination: Vector3,
	progress: float
) -> Transform3D:
	var sampled: Transform3D = origin
	sampled.origin = origin.origin.lerp(destination, clampf(progress, 0.0, 1.0))
	var direction: Vector3 = destination - origin.origin
	if face_travel_direction and direction.length_squared() > 0.000001:
		sampled.basis = Basis.looking_at(direction.normalized(), Vector3.UP)
	return sampled
