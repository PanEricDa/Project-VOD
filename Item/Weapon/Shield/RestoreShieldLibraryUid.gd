@tool
extends SceneTree

## 一次性盾牌资源迁移：正式保存现有动画库，并恢复盾牌数据及工作台共同引用的 UID。
const LIBRARY_PATH := "res://Item/Weapon/Shield/ShieldAnimationLibrary.res"
const SHARED_UID := "uid://njpdtps8x2gh"


func _initialize() -> void:
	var library := load(LIBRARY_PATH) as AnimationLibrary
	var intended_uid := ResourceUID.text_to_id(SHARED_UID)
	if library == null or intended_uid == ResourceUID.INVALID_ID:
		push_error("Shield animation library or intended UID is invalid")
		quit(1)
		return
	if ResourceSaver.save(library, LIBRARY_PATH) != OK:
		push_error("Could not save shield animation library")
		quit(1)
		return
	if ResourceSaver.set_uid(LIBRARY_PATH, intended_uid) != OK:
		push_error("Could not restore shield animation library UID")
		quit(1)
		return
	print("Shield animation library UID restored: ", SHARED_UID)
	quit(0)
