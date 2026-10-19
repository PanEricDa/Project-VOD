@tool
class_name SkillCinematicProfile
extends Resource
## 只读演出配置，不保存进度、角色、token或落点；普通技能可留空，不决定伤害来源。
enum CinematicMode { RETURN_ON_RELEASE, HOLD_THROUGH_IMPACTS }
## A首颗成功发出恢复；B保持世界慢放到全部交付和主要爆炸结束。默认B便于体验轰炸。
@export var cinematic_mode: CinematicMode = CinematicMode.HOLD_THROUGH_IMPACTS
## 专属非循环动作；须有唯一release_action及合法finish_action方法标记。默认空为无效配置。
@export var action_animation: Animation
## 演出期间世界速度上限，默认0.05即5%；只控制世界，指定动作与交付由请求时钟正常推进。
@export_range(0.001, 1.0, 0.001) var world_time_scale: float = 0.05

## 返回配置错误；仅验证，不改变动画或资源。方法轨道以既有CharacterAnimationPlayer为接收者。
func validate_configuration() -> PackedStringArray:
	var errors := PackedStringArray()
	if cinematic_mode not in [0, 1]: errors.append("Invalid cinematic mode.")
	if not is_finite(world_time_scale) or world_time_scale <= 0 or world_time_scale > 1: errors.append("Invalid cinematic world speed.")
	if action_animation == null or action_animation.loop_mode != Animation.LOOP_NONE or not is_finite(action_animation.length) or action_animation.length <= 0:
		errors.append("Cinematic requires a finite, non-looping Animation.")
		return errors
	var release := marker_times(&"release_action")
	var finish := marker_times(&"finish_action")
	if release.size() != 1 or finish.size() != 1:
		errors.append("Cinematic requires exactly one release_action and finish_action.")
	elif release[0] < 0 or finish[0] <= release[0] or finish[0] > action_animation.length:
		errors.append("Invalid cinematic action marker order.")
	return errors

## 读取指定无参数动作marker的秒数，只用于既有动作契约预检及速度换算，不重新定义施法时长。
func marker_times(method_name: StringName) -> Array[float]:
	var result: Array[float] = []
	if action_animation == null: return result
	for track: int in range(action_animation.get_track_count()):
		if action_animation.track_get_type(track) != Animation.TYPE_METHOD or not action_animation.track_is_enabled(track): continue
		if str(action_animation.track_get_path(track)) != "CharacterAnimationPlayer": continue
		for key: int in range(action_animation.track_get_key_count(track)):
			if action_animation.method_track_get_name(track, key) == method_name and action_animation.method_track_get_params(track, key).is_empty():
				result.append(action_animation.track_get_key_time(track, key))
	return result
