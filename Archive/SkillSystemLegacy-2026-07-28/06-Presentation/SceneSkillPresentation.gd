class_name IndependentSceneSkillPresentation
extends "res://SkillSystem/06-Presentation/SkillPresentationBase.gd"

@export_category("Effect Scene")
## 可同时包含粒子、灯光、动画和音频的独立表现场景。
@export var effect_scene: PackedScene
## 场景实例化后是否尝试调用公开播放方法。
@export var call_play_method: bool = true
## 默认遵循项目已有特效的 play() 接口。
@export var play_method_name: StringName = &"play"


## 实例化表现场景并放置到指定世界变换。表现失败不会修改技能结果。
func play(
	parent: Node,
	world_transform: Transform3D,
	_context: SkillContextType,
	_result: SkillDeliveryResultType = null
) -> Node:
	if not is_instance_valid(parent) or effect_scene == null:
		return null
	var effect: Node = effect_scene.instantiate()
	if not is_instance_valid(effect):
		return null
	parent.add_child(effect)
	if effect is Node3D:
		(effect as Node3D).global_transform = world_transform
	if call_play_method and not play_method_name.is_empty() and effect.has_method(play_method_name):
		effect.call(play_method_name)
	return effect
