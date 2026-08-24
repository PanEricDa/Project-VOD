extends SceneTree

func _init() -> void:
	var library := load("res://Item/Weapon/Shield/ShieldAnimationLibrary.res") as AnimationLibrary
	var animation := library.get_animation(&"action_skill_1")
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_METHOD:
			continue
		for key_index in animation.track_get_key_count(track_index):
			print(animation.track_get_key_time(track_index, key_index), " => ", animation.track_get_key_value(track_index, key_index))
	quit()
