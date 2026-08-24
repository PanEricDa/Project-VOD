extends SceneTree

## 最终编号目录、资源 UID 与强类型嵌入配置契约测试。

const SCENE_PATHS: Array[String] = [
	"res://SkillSystem/01-Core/SkillBase.tscn",
	"res://SkillSystem/01-Core/SkillHostComponent.tscn",
	"res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn",
	"res://SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn",
]
const CASTER_ANIMATION_PATH := \
	"res://UnitSystem/AI/Ally/Animations/CasterAnimationLibrary.res"

var _failures: Array[String] = []


func _initialize() -> void:
	for path: String in SCENE_PATHS:
		_expect(
			ResourceLoader.get_resource_uid(path)
				!= ResourceUID.INVALID_ID,
			"resource has valid UID: " + path
		)
		_expect(load(path) is PackedScene, "scene loads: " + path)

	_expect(
		ResourceLoader.get_resource_uid(CASTER_ANIMATION_PATH)
			!= ResourceUID.INVALID_ID,
		"Caster AnimationLibrary has a valid UID"
	)
	_expect(
		load(CASTER_ANIMATION_PATH) is AnimationLibrary,
		"Caster AnimationLibrary loads with the correct type"
	)

	var firebolt := (
		load(SCENE_PATHS[2]) as PackedScene
	).instantiate() as SkillBase
	var holy_light := (
		load(SCENE_PATHS[3]) as PackedScene
	).instantiate() as SkillBase
	_expect(
		firebolt.delivery is TrackingProjectileDeliveryConfig,
		"Firebolt retains typed tracking delivery"
	)
	_expect(
		holy_light.delivery is InstantTargetDeliveryConfig,
		"HolyLight retains typed instant delivery"
	)
	firebolt.free()
	holy_light.free()
	call_deferred(&"_finish")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SkillSystemFinalLayoutTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
