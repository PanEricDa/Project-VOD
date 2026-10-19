@tool
class_name SkillCinematicCameraProfile
extends CameraEffectProfile
## 可替换的终结构图资源；阶段顺序封装，运行进度保存在CameraFollowController。
## 角色起始视觉局部坐标中的正面镜头位置，单位米；默认略高的前方特写，不跟随旋转动画。
@export var front_offset: Vector3 = Vector3(0.45, 1.15, -2.8)
## 特写观察高度，相对角色地面米数，默认0.55；只影响本次特写。
@export_range(0.0, 5.0, 0.05) var look_height_m: float = 0.55

@export_category("Transition Timing")
## 进入角色特写的真实活动秒数，默认0.2；过渡中暂停战斗，完成后继续终结动画，0表示即时到位。
@export_range(0.0, 3.0, 0.01) var closeup_transition_seconds: float = 0.2
## 从释放姿态退至目标区域战斗视角的真实活动秒数，默认0.2；到位前不提交技能释放，0表示即时到位。
@export_range(0.0, 3.0, 0.01) var battle_transition_seconds: float = 0.2
## 全部轰炸结束交回玩家的真实活动秒数，默认0.2；此段不额外暂停世界，0表示即时归位。
@export_range(0.0, 3.0, 0.01) var player_return_seconds: float = 0.2

## source_pose是动作起始视觉世界姿态，返回面向胸口的有限相机姿态；资源自身不保存角色。
func get_front_pose(source_pose: Transform3D) -> Transform3D:
	var point := source_pose.origin + Vector3.UP * look_height_m
	var position := source_pose * front_offset
	return Transform3D(source_pose.basis, position).looking_at(point, Vector3.UP)

## 返回进入特写的有效真实活动秒数；非法值安全回退0.2，不保存运行进度。
func get_closeup_transition_duration() -> float:
	return _safe_duration(closeup_transition_seconds)

## phase使用Phase枚举；ENTER返回退至战斗视角时长，RETURN返回交回玩家时长，单位真实活动秒。
func get_phase_duration(phase: int) -> float:
	return _safe_duration(battle_transition_seconds if phase == Phase.ENTER else player_return_seconds)

func _safe_duration(value: float) -> float:
	return clampf(value,0.0,3.0) if is_finite(value) else 0.2
