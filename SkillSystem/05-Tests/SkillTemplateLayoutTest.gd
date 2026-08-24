extends SceneTree

## 验证两份编辑器模板均继承唯一 SkillBase，且既有技能安全迁移到远程模板。

const MELEE_TEMPLATE_PATH := "res://SkillSystem/00-Templates/MeleeSkillTemplate.tscn"
const RANGED_TEMPLATE_PATH := "res://SkillSystem/00-Templates/RangedSkillTemplate.tscn"
const FIREBOLT_PATH := "res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn"
const HOLY_LIGHT_PATH := "res://SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn"

var _failures: PackedStringArray = []


func _init() -> void:
	_verify_template(MELEE_TEMPLATE_PATH, "MeleeSkillTemplate")
	_verify_template(RANGED_TEMPLATE_PATH, "RangedSkillTemplate")
	_verify_ranged_skill(FIREBOLT_PATH, "FireboltSkill")
	_verify_ranged_skill(HOLY_LIGHT_PATH, "HolyLightSkill")
	if _failures.is_empty():
		print("SkillTemplateLayoutTest: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


## 验证模板根节点保持 SkillBase 类型，确保不会产生第二套技能运行父类。
func _verify_template(scene_path: String, expected_name: String) -> void:
	var scene := load(scene_path) as PackedScene
	_expect(scene != null, "%s loads" % expected_name)
	if scene == null:
		return
	var instance := scene.instantiate()
	_expect(instance is SkillBase, "%s inherits SkillBase" % expected_name)
	instance.free()


## 验证现有远程技能继承模板后仍保留自身名称和单场景装配能力。
func _verify_ranged_skill(scene_path: String, expected_name: String) -> void:
	var scene := load(scene_path) as PackedScene
	_expect(scene != null, "%s scene loads" % expected_name)
	if scene == null:
		return
	var instance := scene.instantiate()
	_expect(instance is SkillBase, "%s remains SkillBase" % expected_name)
	_expect(instance.name == expected_name, "%s root name is preserved" % expected_name)
	instance.free()


## 记录一条模板场景契约断言。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
