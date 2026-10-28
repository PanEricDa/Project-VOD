extends SceneTree

## 玩家外部技能动作的行为契约；去掉动作入口、事件验证或倍率恢复会使本测试失败。
const ACTION_PATH := "res://Scenes/Tests/PlayerSkills/PlayerSkillProbeAction.tres"
const HERO_PATH := "res://UnitSystem/Player/Hero/Hero.tscn"
var _failures: Array[String] = []
var _events: Array[StringName] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_plain_action_payload_preserves_existing_metadata()
	_test_action_marker_contract()
	var hero := load(HERO_PATH).instantiate() as PlayerBase
	root.add_child(hero)
	await process_frame
	await process_frame
	hero.set_physics_process(false)
	var driver := hero.get_node("AttackController") as PlayerAttackController
	var animator := hero.get_node("Visual/HeroVisual/CharacterAnimationPlayer") as CharacterAnimationEventPlayer
	_expect(driver.has_method("request_external_action"), "player action entry must exist")
	if driver.has_method("request_external_action") and FileAccess.file_exists(ACTION_PATH):
		driver.set_process(false)
		animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		driver.connect("external_action_lifecycle", _on_lifecycle)
		_test_launch_origin_validation(hero, driver)
		_test_effective_cast_time_controls_release(driver, animator)
		_test_attack_cannot_steal_external_animation(driver, animator)
		_test_invalid_actions_rejected(driver)
		_test_zero_cast_handshake(driver, animator)
		_test_duplicate_release_and_natural_end(driver, animator)
	root.remove_child(hero)
	hero.free()
	await process_frame
	if _failures.is_empty():
		print("PlayerSkillActionAnimationTest: PASS")
		quit(0)
	else:
		for failure: String in _failures: print("FAIL: " + failure)
		quit(1)

func _test_plain_action_payload_preserves_existing_metadata() -> void:
	var skill := SkillBase.new()
	var found := false
	for property: Dictionary in skill.get_property_list():
		if property.name == &"action_animation": found = true
	_expect(found, "ordinary skill must expose a typed Animation asset")
	if found:
		var animation := Animation.new()
		skill.set("action_animation", animation)
		var action := MeleeSkillAction.new()
		action.base_damage = 17.0
		action.power_ratio = 0.4
		skill.add_child(action)
		var payload := skill.get_action_payload()
		_expect(payload.get("action_animation") == animation, "ordinary animation must reach action payload without cinematic profile")
		_expect(is_equal_approx(float(payload.get("base_damage", 0.0)), 17.0), "ordinary animation must preserve melee damage metadata")
		_expect(is_equal_approx(float(payload.get("power_ratio", 0.0)), 0.4), "ordinary animation must preserve melee power ratio")
		skill.set("action_animation", null)
		_expect(not skill.get_action_payload().has("action_animation"), "null action asset keeps legacy payload")
	skill.free()

func _test_action_marker_contract() -> void:
	_expect(FileAccess.file_exists(ACTION_PATH), "probe action must be a real saved asset")
	if not FileAccess.file_exists(ACTION_PATH): return
	var animation := load(ACTION_PATH) as Animation
	_expect(animation != null, "probe action is Animation")
	_expect(ResourceLoader.get_resource_uid(ACTION_PATH) != ResourceUID.INVALID_ID, "probe Animation has valid Godot UID")
	_expect(ResourceLoader.get_resource_uid("res://Item/Weapon/Sword/SwordAnimationLibrary.res") != ResourceUID.INVALID_ID, "weapon AnimationLibrary keeps valid UID")
	if animation == null: return
	_expect(animation.loop_mode == Animation.LOOP_NONE, "skill animation does not loop")
	var releases := _method_times(animation, &"release_action")
	var finishes := _method_times(animation, &"finish_action")
	_expect(releases.size() == 1 and is_equal_approx(releases[0], 0.20), "action releases once at the planned frame")
	_expect(finishes.size() == 1 and is_equal_approx(finishes[0], 0.38), "action finishes once after release")
	_expect(is_equal_approx(animation.length, 0.40), "probe action includes recovery")
	for index: int in animation.get_track_count():
		if animation.track_get_type(index) != Animation.TYPE_METHOD:
			var path := str(animation.track_get_path(index))
			_expect(path.begins_with("CharacterRoot:" ) or path.begins_with("CharacterRoot/WeaponSocket:"), "pose tracks only edit CharacterRoot and WeaponSocket")
	var library := load("res://Item/Weapon/Sword/SwordAnimationLibrary.res") as AnimationLibrary
	_expect(library.has_animation(&"basic_cast_1"), "Workbench action exists in Sword library")

func _test_launch_origin_validation(hero: PlayerBase, driver: Node) -> void:
	var origin := hero.get_node("Visual/HeroVisual/CharacterRoot/WeaponSocket/ProjectileOrigin") as Node3D
	var original := origin.transform
	origin.global_transform = Transform3D.IDENTITY
	_expect(driver.call("request_external_action", 0.2, null, {"action_animation": load(ACTION_PATH)}, 0), "valid launch origin at world identity must not be treated as missing")
	driver.call("cancel_external_action")
	origin.name = "UnconfiguredOrigin"
	_expect(not driver.call("request_external_action", 0.2, null, {"action_animation": load(ACTION_PATH)}, 0), "missing launch origin rejects action without starting it")
	origin.name = "ProjectileOrigin"
	origin.transform = original

func _test_effective_cast_time_controls_release(driver: Node, animator: AnimationPlayer) -> void:
	for duration: float in [0.20, 0.15]:
		_events.clear()
		_expect(driver.call("request_external_action", duration, null, {"action_animation": load(ACTION_PATH)}, 0), "valid action accepted")
		_expect(_events.is_empty(), "request must not advance zero-frame markers before Host confirmation")
		var elapsed := 0.0
		while elapsed < duration - 0.011:
			animator.advance(0.01)
			elapsed += 0.01
		_expect(_events.is_empty(), "no release before effective cast time")
		animator.advance(0.02)
		_expect(_events.count(&"release") == 1, "one real release at effective cast time")
		animator.advance(0.30)
		_expect(_events.count(&"finish") == 1, "one completion after release")
		_expect(not driver.call("is_action_in_progress"), "finish clears action occupancy")
		_expect(is_equal_approx(animator.speed_scale, 1.0), "action speed does not leak into next attack")

func _test_attack_cannot_steal_external_animation(driver: Node, animator: AnimationPlayer) -> void:
	_expect(driver.call("request_external_action", 0.20, null, {"action_animation": load(ACTION_PATH)}, 0), "test skill starts")
	var name_before := animator.current_animation
	driver.call("request_attack")
	driver.call("_process", 0.01)
	_expect(animator.current_animation == name_before, "ordinary attack cannot cover skill animation")
	_expect(not driver.call("request_external_action", 0.15, null, {"action_animation": load(ACTION_PATH)}, 0), "second action rejected while skill busy")
	driver.call("cancel_external_action")
	driver.call("request_attack")
	_expect(driver.call("is_attacking"), "ordinary attack works again after cancellation")
	driver.call("cancel_combo")

func _test_invalid_actions_rejected(driver: Node) -> void:
	var original := load(ACTION_PATH) as Animation
	var looped := original.duplicate() as Animation
	looped.loop_mode = Animation.LOOP_LINEAR
	_expect(not driver.call("request_external_action", 0.2, null, {"action_animation": looped}, 0), "looping action rejected")
	_expect(not driver.call("request_external_action", 0.0, null, {"action_animation": original}, 0), "positive release frame incompatible with zero cast")
	_expect(not driver.call("request_external_action", -1.0, null, {"action_animation": original}, 0), "negative cast time rejected")
	_expect(not driver.call("request_external_action", NAN, null, {"action_animation": original}, 0), "nonfinite cast time rejected")
	var no_finish := original.duplicate() as Animation
	for track: int in range(no_finish.get_track_count() - 1, -1, -1):
		if no_finish.track_get_type(track) == Animation.TYPE_METHOD:
			for key: int in range(no_finish.track_get_key_count(track) - 1, -1, -1):
				if no_finish.track_get_key_value(track, key).get("method") == &"finish_action": no_finish.track_remove_key(track, key)
	_expect(not driver.call("request_external_action", 0.2, null, {"action_animation": no_finish}, 0), "missing finish marker rejected")
	var disabled := original.duplicate() as Animation
	for track: int in disabled.get_track_count():
		if disabled.track_get_type(track) == Animation.TYPE_METHOD: disabled.track_set_enabled(track, false)
	_expect(not driver.call("request_external_action", 0.2, null, {"action_animation": disabled}, 0), "disabled method tracks cannot satisfy the release/finish contract")
	driver.call("cancel_external_action")
	var repeated := original.duplicate() as Animation
	for track: int in repeated.get_track_count():
		if repeated.track_get_type(track) == Animation.TYPE_METHOD:
			repeated.track_insert_key(track, 0.25, {"method": &"release_action", "args": []})
			break
	_expect(not driver.call("request_external_action", 0.2, null, {"action_animation": repeated}, 0), "duplicate release marker rejected")
	_expect(not driver.call("is_action_in_progress"), "all rejected actions leave no busy state")

func _test_zero_cast_handshake(driver: Node, animator: AnimationPlayer) -> void:
	var instant := (load(ACTION_PATH) as Animation).duplicate() as Animation
	for track: int in instant.get_track_count():
		if instant.track_get_type(track) == Animation.TYPE_METHOD:
			for key: int in instant.track_get_key_count(track):
				if instant.track_get_key_value(track, key).get("method") == &"release_action": instant.track_set_key_time(track, key, 0.0)
	_events.clear()
	_expect(driver.call("request_external_action", 0.0, null, {"action_animation": instant}, 0), "zero cast accepts zero-frame action")
	_expect(_events.is_empty(), "zero-frame release waits until action is advanced")
	animator.advance(0.001)
	_expect(_events.count(&"release") == 1, "zero-frame action releases once on first advance")
	driver.call("cancel_external_action")

func _test_duplicate_release_and_natural_end(driver: Node, animator: CharacterAnimationEventPlayer) -> void:
	_events.clear()
	driver.call("request_external_action", 0.2, null, {"action_animation": load(ACTION_PATH)}, 0)
	animator.advance(0.21)
	animator.release_action()
	_expect(_events.count(&"release") == 1, "duplicate animation release cannot double emit")
	var serial: int = driver.call("get_external_action_serial")
	driver.call("cancel_external_action")
	driver.call("request_external_action", 0.2, null, {"action_animation": load(ACTION_PATH)}, 0)
	_expect(int(driver.call("get_external_action_serial")) > serial, "ordinary request_id zero is not used as action identity")
	animator.advance(0.10)
	driver.call("_on_animation_finished", animator.current_animation)
	_expect(_events.count(&"release") == 1, "unexpected natural end never synthesizes damage")
	_expect(not driver.call("is_action_in_progress"), "unexpected natural end cancels occupancy")

func _method_times(animation: Animation, method: StringName) -> Array[float]:
	var times: Array[float] = []
	for track: int in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_METHOD: continue
		for key: int in animation.track_get_key_count(track):
			if animation.track_get_key_value(track, key).get("method") == method:
				times.append(animation.track_get_key_time(track, key))
	return times

func _on_lifecycle(_request_id: int, _serial: int, event: StringName) -> void:
	_events.append(event)

func _expect(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)
