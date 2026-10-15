@tool
class_name CameraEffectProfile
extends Resource
## 可替换的只读镜头策略；基础资源安全无运动。
enum Phase { ENTER, RETURN }
## phase使用Phase枚举；负数表示未实现该运动，0表示即时，单位秒。
func get_phase_duration(_phase: int) -> float: return -1.0
## from_pose/destination_pose为本次过渡的起点和目标世界姿态，phase使用Phase枚举。
## 返回本次固定过渡秒数；默认沿用阶段时长，子类可按位移适配，不能保存运行进度。
func get_transition_duration(_from_pose: Transform3D, _destination_pose: Transform3D, phase: int) -> float:
	return get_phase_duration(phase)
## source_offset是伙伴相对玩家位置的世界偏移，view_width是玩家深度处的视野宽度（米）。
## 默认保留完整位移；子策略可返回受限偏移，但不得修改节点或共享资源。
func get_focus_offset(source_offset: Vector3, _view_width: float) -> Vector3:
	return source_offset
## from_pose/destination_pose为有限世界姿态，progress为0—1；不得修改节点/共享资源。
func sample_rig_transform(from_pose: Transform3D, _destination_pose: Transform3D, _progress: float, _phase: int) -> Transform3D:
	return from_pose
