extends SceneTree

## 验证可选 Delivery 外部预设已由 Godot 正式登记 UID，且能被强类型字段安全加载。

const PRESET_PATHS := [
	"res://SkillSystem/02-Delivery/Presets/InstantTargetDelivery.tres",
	"res://SkillSystem/02-Delivery/Presets/TrackingProjectileDelivery.tres",
	"res://SkillSystem/02-Delivery/Presets/GroundAreaDelivery.tres",
]

var _failures: PackedStringArray = []


func _init() -> void:
	for preset_path in PRESET_PATHS:
		var resource_uid := ResourceLoader.get_resource_uid(preset_path)
		_expect(resource_uid != ResourceUID.INVALID_ID, "%s has a valid Godot UID" % preset_path)
		var preset := ResourceLoader.load(preset_path)
		_expect(preset is SkillDeliveryConfig, "%s loads as SkillDeliveryConfig" % preset_path)
	if _failures.is_empty():
		print("DeliveryResourceIndexTest: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


## 记录一个资源契约断言；失败信息直接指出不可被 Inspector 使用的资源路径。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
