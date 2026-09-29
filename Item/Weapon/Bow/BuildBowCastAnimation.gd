@tool
extends SceneTree

## 一次性编辑器资源迁移：复制弓普攻演出，仅把发射事件改成通用技能 release_action。
## 可重复运行；已有合法 basic_cast_1 时不改资源。正式 .res 由 ResourceSaver 保存并核对 UID。

const LIBRARY_PATH := "res://Item/Weapon/Bow/BowAnimationLibrary.res"
const LIBRARY_UID := "uid://c1weyjsk4rubw"


func _initialize() -> void:
	var uid_before: int = ResourceUID.text_to_id(LIBRARY_UID)
	var library := load(LIBRARY_PATH) as AnimationLibrary
	if library == null or uid_before == ResourceUID.INVALID_ID:
		push_error("Bow animation library missing or has invalid UID")
		quit(1)
		return
	if not library.has_animation(&"basic_attack_1"):
		push_error("Bow basic_attack_1 is missing")
		quit(1)
		return
	if not library.has_animation(&"basic_cast_1"):
		var cast := library.get_animation(&"basic_attack_1").duplicate(true) as Animation
		var replaced := 0
		for track in range(cast.get_track_count()):
			if cast.track_get_type(track) != Animation.TYPE_METHOD:
				continue
			for key in range(cast.track_get_key_count(track)):
				var value: Variant = cast.track_get_key_value(track, key)
				if not value is Dictionary or value.get("method", &"") != &"release_projectile":
					continue
				var marker: Dictionary = value.duplicate(true)
				marker["method"] = &"release_action"
				cast.track_set_key_value(track, key, marker)
				replaced += 1
		if replaced != 1:
			push_error("Bow attack must have exactly one projectile release marker, got %d" % replaced)
			quit(1)
			return
		library.add_animation(&"basic_cast_1", cast)
		var saved := ResourceSaver.save(library, LIBRARY_PATH)
		if saved != OK:
			push_error("ResourceSaver failed: %s" % saved)
			quit(1)
			return
	if ResourceSaver.set_uid(LIBRARY_PATH, uid_before) != OK:
		push_error("Bow library UID restoration failed")
		quit(1)
		return
	# ResourceLoader 在本进程内可能仍缓存保存前的 UID；新进程的编辑器扫描与契约测试验证正式索引。
	print("BuildBowCastAnimation: saved; expected UID ", ResourceUID.id_to_text(uid_before))
	quit(0)
