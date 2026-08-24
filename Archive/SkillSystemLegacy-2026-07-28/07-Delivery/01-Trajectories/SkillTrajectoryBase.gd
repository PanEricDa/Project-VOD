class_name IndependentSkillTrajectoryBase
extends Resource

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")

## 弹道策略抽象基类。策略必须保持无状态，所有计时由 DeliveryAgent 实例持有。
func get_travel_duration(
	_context: SkillContextType,
	_origin: Vector3,
	_destination: Vector3
) -> float:
	return 0.0


## 父类保持起点变换，用于安全暴露接口但不提供实际弹道。
func sample_transform(
	_context: SkillContextType,
	origin: Transform3D,
	_destination: Vector3,
	_progress: float
) -> Transform3D:
	return origin
