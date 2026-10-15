@tool
class_name SkillFocusCameraProfile
extends CameraEffectProfile
## 玩家锚定的距离加权构图；幅度、距离曲线及额外缓动时间内部封装，共享资源不存播放进度。
## 最终位移倍率；当前2.0使相同距离下的目标偏移为原版两倍，不改变距离曲线形状。
const MOVEMENT_DISTANCE_MULTIPLIER: float = 2.0
const FULL_ATTENTION_DISTANCE_METERS: float = 10.0
const MAX_OFFSET_WIDTH_RATIO: float = 0.12
const MAX_SOURCE_DISTANCE_RATIO: float = 0.45
const EXTRA_TRANSITION_SECONDS: float = 0.20
## 仅进入阶段的速度倍率；1.5将包含距离缓动的整段时长除以1.5，返回不受影响。
const ENTER_SPEED_MULTIPLIER: float = 1.5
## 进入偏移构图的基础秒数，默认0.30；加入最多0.20秒距离缓动后，整体除以内部速度倍率1.5。
## 默认实际进入约0.20—0.333秒，0始终即时，不延迟施法；不影响返回时长。
@export_range(0.0, 2.0, 0.01) var enter_duration_seconds: float = 0.30
## 偏移归零的基础秒数，默认0.55；大位移内部最多延长0.20秒，0始终即时，继续正常跟随玩家。
@export_range(0.0, 2.0, 0.01) var return_duration_seconds: float = 0.55
## phase为ENTER/RETURN；返回基础秒数，不修改资源。
func get_phase_duration(phase: int) -> float:
	return enter_duration_seconds if phase == Phase.ENTER else return_duration_seconds
## from_pose/destination_pose为本次起终点世界姿态；phase为ENTER/RETURN。
## 位移0.25米以内用基础时长，之后平滑增加，2.25米及以上最多加0.20秒。
## 进入阶段再将整体时长除以1.5，返回不变；基础0保持即时。
func get_transition_duration(from_pose: Transform3D, destination_pose: Transform3D, phase: int) -> float:
	var base := get_phase_duration(phase)
	if base <= 0.0: return base
	var extra := clampf((from_pose.origin.distance_to(destination_pose.origin) - 0.25) / 2.0, 0.0, 1.0)
	var duration := base + extra * EXTRA_TRANSITION_SECONDS
	return duration / ENTER_SPEED_MULTIPLIER if phase == Phase.ENTER else duration
## source_offset为伙伴相对玩家位置的世界偏移；view_width为玩家深度处视野宽度（米）。
## 水平距离从0到10米用平滑曲线增强；基础上限12%视野宽/45%伙伴距离，再乘最终倍率。
## 当前倍率2.0对应上限24%视野宽/90%伙伴距离，不增加垂直位移；时停与缓动规则不变。
func get_focus_offset(source_offset: Vector3, view_width: float) -> Vector3:
	if not source_offset.is_finite() or not is_finite(view_width) or view_width <= 0.0:
		return Vector3.ZERO
	var horizontal := Vector3(source_offset.x, 0.0, source_offset.z)
	var distance := horizontal.length()
	if distance <= 0.0: return Vector3.ZERO
	var t := clampf(distance / FULL_ATTENTION_DISTANCE_METERS, 0.0, 1.0)
	var strength := t * t * (3.0 - 2.0 * t)
	var amplitude := minf(view_width * MAX_OFFSET_WIDTH_RATIO * strength, distance * MAX_SOURCE_DISTANCE_RATIO)
	return horizontal / distance * amplitude * MOVEMENT_DISTANCE_MULTIPLIER
## 输入有限起点/实时终点与0—1进度；只平移，保留起点方向。
func sample_rig_transform(from_pose: Transform3D, destination_pose: Transform3D, progress: float, _phase: int) -> Transform3D:
	var t := clampf(progress, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return Transform3D(from_pose.basis, from_pose.origin.lerp(destination_pose.origin, t))
