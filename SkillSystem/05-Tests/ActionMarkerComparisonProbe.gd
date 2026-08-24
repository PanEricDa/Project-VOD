extends SceneTree

func _init() -> void:
	_print_markers("Shield basic_attack_1", "res://Item/Weapon/Shield/ShieldAnimationLibrary.res", &"basic_attack_1")
	_print_markers("Shield action_skill_1", "res://Item/Weapon/Shield/ShieldAnimationLibrary.res", &"action_skill_1")
	_print_markers("Staff basic_cast_1", "res://Item/Weapon/Staff/StaffAnimationLibrary.res", &"basic_cast_1")
	quit()

func _print_markers(label: String, resource_path: String, animation_name: StringName) -> void:
	print("--- ", label, " ---")
	var library := load(resource_path) as AnimationLibrary
	var animation := library.get_animation(animation_name)
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_METHOD:
			continue
		for key_index in animation.track_get_key_count(track_index):
			print(animation.track_get_key_time(track_index, key_index), " => ", animation.track_get_key_value(track_index, key_index))
