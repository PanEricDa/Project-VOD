extends SceneTree

## 三段连锁全部由同一 SkillBase 模板、通用 Delivery 和 Trigger Effect 装配。

const A_PATH := "res://SkillSystem/00-Skills/ExplosiveArrow/ExplosiveArrowSkill.tscn"
const B_PATH := "res://SkillSystem/00-Skills/ExplosiveFragment/ExplosiveFragmentSkill.tscn"
const C_PATH := "res://SkillSystem/00-Skills/BurningSplash/BurningSplashSkill.tscn"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	for path: String in [A_PATH, B_PATH, C_PATH]:
		if not ResourceLoader.exists(path):
			_expect(false, "required skill scene exists: " + path)
		else:
			_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "skill scene has indexed UID: " + path)
	if not failures.is_empty():
		_finish()
		return
	var a := (load(A_PATH) as PackedScene).instantiate() as SkillBase
	var b := (load(B_PATH) as PackedScene).instantiate() as SkillBase
	var c := (load(C_PATH) as PackedScene).instantiate() as SkillBase
	root.add_child(a)
	root.add_child(b)
	root.add_child(c)
	_expect(a != null and b != null and c != null, "all three scenes inherit SkillBase")
	if a == null or b == null or c == null:
		_finish()
		return
	_expect(a.get_script() == b.get_script() and b.get_script() == c.get_script(), "all skills use the same root script")
	_expect(a.delivery is ArcProjectileDeliveryConfig and b.delivery is ArcProjectileDeliveryConfig, "main arrow and fragments share Arc delivery type")
	_expect(c.delivery is InstantTargetDeliveryConfig, "final splash uses existing instant target delivery")
	_expect(a.skill_cooldown == 7.0 and b.skill_cooldown == 0.0 and c.skill_cooldown == 0.0, "parent has seven-second cooldown and trigger-only children have zero")
	var a_trigger := _trigger(a)
	var b_trigger := _trigger(b)
	_expect(a_trigger != null and b_trigger != null and _trigger(c) == null, "only parent and fragment continue the chain")
	if a_trigger != null and b_trigger != null:
		_expect(a_trigger.get_script() == b_trigger.get_script(), "both fanout stages reuse identical TriggerSkillEffect")
		_expect(a_trigger.max_targets == 3 and b_trigger.max_targets == 3, "fanout count comes from each Inspector config")
		_expect(a_trigger.child_skill_scene.resource_path == B_PATH and b_trigger.child_skill_scene.resource_path == C_PATH, "trigger scene references form A to B to C")
		_expect(b_trigger.required_status_id == &"burning" and a_trigger.required_status_id.is_empty(), "only fragment checks pre-hit burning")
	_expect(_count_costs(b) == 0 and _count_costs(c) == 0, "trigger content has no resource costs")
	var archer := (load("res://UnitSystem/AI/Ally/Units/Archer.tscn") as PackedScene).instantiate()
	root.add_child(archer)
	var host := archer.get_node(^"SkillHost") as SkillHostComponent
	_expect(int(archer.combat_action_policy) == 1, "Archer prioritizes skills then uses basic attacks")
	_expect(host.get_node_or_null(^"SkillSocket/ExplosiveArrowSkill") != null, "Archer equips main arrow in SkillSocket")
	_expect(host.regular_skills.size() == 2 and host.regular_skills[0] is SkillBase and host.regular_skills[1] == null, "Archer has one equipped regular skill, leaving second slot open")
	var animation_player := archer.get_node_or_null(^"Visual/AllyVisual/CharacterAnimationPlayer") as CharacterAnimationEventPlayer
	_expect(animation_player != null and animation_player.has_animation(&"weapon/basic_cast_1"), "Archer visual receives Bow's actual cast animation")
	var firebolt := (load("res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn") as PackedScene).instantiate() as SkillBase
	root.add_child(firebolt)
	_expect(_has_burning_effect(firebolt), "Firebolt applies generic four-second burning status")
	var library := load("res://Item/Weapon/Bow/BowAnimationLibrary.res") as AnimationLibrary
	_expect(library != null and library.has_animation(&"basic_cast_1"), "Bow supports generic external cast animation")
	if library != null and library.has_animation(&"basic_cast_1"):
		_expect(_count_release_markers(library.get_animation(&"basic_cast_1")) == 1, "Bow cast animation releases skill exactly once")
	archer.free()
	firebolt.free()
	a.free()
	b.free()
	c.free()
	_finish()


func _trigger(skill: SkillBase) -> TriggerSkillEffect:
	for child: Node in skill.get_children():
		if child is TriggerSkillEffect:
			return child as TriggerSkillEffect
	return null


func _count_costs(skill: SkillBase) -> int:
	var count := 0
	for child: Node in skill.get_children():
		if child is SkillCostBase:
			count += 1
	return count


func _has_burning_effect(skill: SkillBase) -> bool:
	for child: Node in skill.get_children():
		if child is ApplyNamedStatusSkillEffect and child.status_id == &"burning" and child.duration_seconds == 4.0:
			return true
	return false


func _count_release_markers(animation: Animation) -> int:
	var count := 0
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_METHOD:
			continue
		for key_index in range(animation.track_get_key_count(track_index)):
			var value: Variant = animation.track_get_key_value(track_index, key_index)
			if value is Dictionary and value.get("method", &"") == &"release_action":
				count += 1
	return count


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("ExplosiveArrowAssemblyTest: PASS")
	quit(0 if failures.is_empty() else 1)
