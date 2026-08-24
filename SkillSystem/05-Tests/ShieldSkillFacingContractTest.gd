extends SceneTree

## 契约：角色技能动作可使用 CharacterRoot 的局部 Y 轴旋转进行演出；世界基础朝向由外层 Visual 负责。
func _init() -> void:
	var resource_uid := ResourceLoader.get_resource_uid("res://Item/Weapon/Shield/ShieldAnimationLibrary.res")
	if resource_uid == ResourceUID.INVALID_ID:
		_fail("ShieldAnimationLibrary.res must have a valid Godot resource UID")
		return
	print("ShieldAnimationLibrary UID: ", ResourceUID.id_to_text(resource_uid))
	var library := load("res://Item/Weapon/Shield/ShieldAnimationLibrary.res") as AnimationLibrary
	var animation := library.get_animation(&"action_skill_1")
	if animation == null:
		_fail("action_skill_1 is missing")
		return
	var has_local_yaw_pose := false
	for track_index: int in range(animation.get_track_count()):
		if animation.track_get_path(track_index) != NodePath("CharacterRoot:rotation"):
			continue
		for key_index: int in range(animation.track_get_key_count(track_index)):
			var rotation: Vector3 = animation.track_get_key_value(track_index, key_index)
			if not is_zero_approx(rotation.y):
				has_local_yaw_pose = true
	if not has_local_yaw_pose:
		_fail("action_skill_1 must retain its CharacterRoot local yaw pose keys")
		return
	print("PASS: Shield skill retains CharacterRoot local yaw action poses")
	quit()


func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	quit(1)
