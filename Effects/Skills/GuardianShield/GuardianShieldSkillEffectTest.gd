extends SceneTree

## Guardian 盾击特效的场景契约：保证技能可安全实例化，并拥有可预览的两个核心视觉节点。

const EFFECT_PATH := "res://Effects/Skills/GuardianShield/GuardianShieldSkillEffect.tscn"
const PREVIEW_PATH := "res://Effects/Skills/GuardianShield/GuardianShieldSkillEffectPreview.tscn"

var _failures: PackedStringArray = []


func _init() -> void:
	var effect_scene := load(EFFECT_PATH) as PackedScene
	_expect(effect_scene != null, "Guardian shield effect scene loads")
	if effect_scene != null:
		var effect := effect_scene.instantiate()
		_expect(effect.has_node(^"ShieldArc"), "Effect owns a forward ShieldArc")
		_expect(effect.has_node(^"DefenseRing"), "Effect owns a ground DefenseRing")
		_expect(effect.has_node(^"AnimationPlayer"), "Effect owns AnimationPlayer")
		_expect(effect.has_method(&"play"), "Effect exposes play")
		_expect(effect.has_method(&"stop"), "Effect exposes stop")
		effect.free()
	var preview_scene := load(PREVIEW_PATH) as PackedScene
	_expect(preview_scene != null, "Guardian shield effect preview scene loads")
	_finish()


## 记录一项独立视觉资产的可加载性契约。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## 输出统一测试结果，便于 Godot headless 调用识别。
func _finish() -> void:
	if _failures.is_empty():
		print("GuardianShieldSkillEffectTest: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
