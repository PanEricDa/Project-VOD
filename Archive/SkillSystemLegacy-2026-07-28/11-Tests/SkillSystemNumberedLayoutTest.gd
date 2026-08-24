extends SceneTree

const EXPECTED_DIRECTORIES: Array[String] = [
	"res://SkillSystem/00-Skills",
	"res://SkillSystem/01-Core",
	"res://SkillSystem/02-Conditions",
	"res://SkillSystem/03-Targeting",
	"res://SkillSystem/04-Decisions",
	"res://SkillSystem/05-Costs",
	"res://SkillSystem/06-Presentation",
	"res://SkillSystem/07-Delivery",
	"res://SkillSystem/07-Delivery/00-Agents",
	"res://SkillSystem/07-Delivery/01-Trajectories",
	"res://SkillSystem/07-Delivery/02-Collisions",
	"res://SkillSystem/07-Delivery/03-Impacts",
	"res://SkillSystem/08-Payloads",
	"res://SkillSystem/09-Presets",
	"res://SkillSystem/10-Docs",
	"res://SkillSystem/11-Tests",
]

const EXPECTED_RESOURCES: Array[String] = [
	"res://SkillSystem/01-Core/SkillBase.tscn",
	"res://SkillSystem/01-Core/SkillHostComponent.tscn",
	"res://SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn",
	"res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn",
	"res://SkillSystem/07-Delivery/00-Agents/BasicDeliveryAgent.tscn",
	"res://SkillSystem/07-Delivery/00-Agents/TrackingProjectileDeliveryAgent.tscn",
	"res://SkillSystem/10-Docs/SkillSystemUserGuide.md",
]

## 使用拆分字符串保存旧目录名，避免迁移时的机械路径替换把本测试的反向检查一并改写。
const OLD_DIRECTORY_NAMES: Array[String] = [
	"Core",
	"Conditions",
	"Targeting",
	"Decisions",
	"Costs",
	"Presentation",
	"Delivery",
	"Payloads",
	"Presets",
	"Docs",
	"Tests",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for directory_path: String in EXPECTED_DIRECTORIES:
		_assert_true(
			DirAccess.dir_exists_absolute(directory_path),
			"missing numbered directory: " + directory_path
		)
	for resource_path: String in EXPECTED_RESOURCES:
		_assert_true(
			ResourceLoader.exists(resource_path) or FileAccess.file_exists(resource_path),
			"missing numbered resource: " + resource_path
		)
	for directory_name: String in OLD_DIRECTORY_NAMES:
		var old_path := "res://SkillSystem/" + directory_name
		_assert_true(
			not DirAccess.dir_exists_absolute(old_path),
			"legacy unnumbered directory still exists: " + old_path
		)

	if ResourceLoader.exists("res://SkillSystem/01-Core/SkillBase.tscn"):
		var skill := load("res://SkillSystem/01-Core/SkillBase.tscn") as PackedScene
		_assert_true(skill != null and skill.can_instantiate(), "numbered SkillBase loads")
	if ResourceLoader.exists("res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn"):
		var firebolt := load(
			"res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn"
		) as PackedScene
		_assert_true(firebolt != null and firebolt.can_instantiate(), "Firebolt loads after migration")
	if ResourceLoader.exists("res://SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn"):
		var holy_light := load(
			"res://SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn"
		) as PackedScene
		_assert_true(
			holy_light != null and holy_light.can_instantiate(),
			"HolyLight loads after migration"
		)
	_finish()


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("SkillSystemNumberedLayoutTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
