class_name SkillPresentationContext
extends RefCounted
## 单次施法/释放的只读表现快照；不持有单位、世界或原技能上下文。
enum Stage { CAST, RELEASE }
var _data: Dictionary = {}
var _source: WeakRef
var _target: WeakRef
var _world: WeakRef
var _camera: CameraEffectProfile

## 当前阶段CAST施法/RELEASE成功释放；不同阶段为独立快照。
var stage: int:
	get: return _data["stage"]

## 本次施放独立正身份；开始和成功释放相同，重复施放不同。
var presentation_id: int:
	get: return _data["presentation_id"]

## 原根连携请求正身份；普通技能为0，不重新分配指令身份。
var command_request_id: int:
	get: return _data["command_request_id"]

## 本次世界的实例身份；世界弱引用失效后不得跨世界消费。
var scene_scope_id: int:
	get: return _data["scene_scope_id"]

## 原技能实例身份；同场景多个实例不混用，不持有技能节点。
var skill_instance_id: int:
	get: return _data["skill_instance_id"]

## 原请求用途枚举；普通和根连携沿用SkillContext.Purpose。
var purpose: int:
	get: return _data["purpose"]

## 原执行入口枚举；角色动作和直接触发沿用SkillContext.ExecutionMode。
var execution_mode: int:
	get: return _data["execution_mode"]

## 仅角色动作根连携为真；衍生子交付不触发队伍镜头或强调。
var is_chain_root: bool:
	get: return _data["is_chain_root"]

## 本次开始时的有效施法秒数；仅供表现看门狗，不能改变技能时间。
var effective_cast_time: float:
	get: return _data["effective_cast_time"]

## 当前阶段有限世界变换；释放阶段使用已解析锚点，不保存跟随目标。
var world_transform: Transform3D:
	get: return _data["world_transform"]

## 开始时选定的释放视觉资产；可空，共享只读，不深复制美术内容。
var visual_scene: PackedScene:
	get: return _data["visual_scene"]

## 开始时选定的一次性音频资产；可空，共享只读，不影响费用。
var audio_stream: AudioStream:
	get: return _data["audio_stream"]

## 开始时选定的SkillBase.PresentationAnchor枚举；决定释放锚点。
var release_effect_anchor: int:
	get: return _data["release_effect_anchor"]

## 开始时复制的真实停顿秒数，0为无强调；消费者拒绝非有限或0—0.3外的值。
var pause_duration_seconds: float:
	get: return _data["pause_duration_seconds"]

## 捕获本次技能配置；world/变换须有效，presentation_id为0时分配新正身份，非法返回null。
@warning_ignore("shadowed_variable")
static func create(skill: SkillBase, context: SkillContext, action_transform: Transform3D, presentation_id: int = 0) -> SkillPresentationContext:
	if not is_instance_valid(skill) or context == null or not action_transform.is_finite() or not is_instance_valid(context.delivery_parent) or not context.delivery_parent.is_inside_tree() or context.delivery_parent.is_queued_for_deletion():
		return null
	var result := SkillPresentationContext.new()
	result._data = {"stage": Stage.CAST, "presentation_id": presentation_id if presentation_id > 0 else CombatDamageContext.allocate_id(),
		"command_request_id": context.command_request.request_id if context.command_request != null else 0,
		"scene_scope_id": context.delivery_parent.get_instance_id(), "skill_instance_id": skill.get_instance_id(),
		"purpose": context.purpose, "execution_mode": context.execution_mode,
		"is_chain_root": context.purpose == SkillContext.Purpose.CHAIN and context.execution_mode == SkillContext.ExecutionMode.CHARACTER_ACTION,
		"effective_cast_time": skill.get_effective_cast_time(), "world_transform": action_transform,
		"visual_scene": skill.release_effect_scene, "audio_stream": skill.release_audio_stream,
		"release_effect_anchor": int(skill.release_effect_anchor),
		"pause_duration_seconds": skill.release_accent_profile.pause_duration_seconds if skill.release_accent_profile != null else 0.0}
	result._source = weakref(context.caster) if is_instance_valid(context.caster) else null
	result._target = weakref(context.resolved_target) if is_instance_valid(context.resolved_target) else null
	result._world = weakref(context.delivery_parent)
	result._camera = skill.camera_effect_profile.duplicate() as CameraEffectProfile if skill.camera_effect_profile != null else null
	return result

## 创建同身份释放快照；context只读本次目标，anchor_transform为已解析有限世界锚点；不重读技能。
func for_release(context: SkillContext, anchor_transform: Transform3D) -> SkillPresentationContext:
	if context == null or get_world() == null or not anchor_transform.is_finite(): return null
	var result := SkillPresentationContext.new()
	result._data = _data.duplicate()
	result._data.stage = Stage.RELEASE
	result._data.world_transform = anchor_transform
	result._source = _source
	result._target = weakref(context.resolved_target) if is_instance_valid(context.resolved_target) else null
	result._world = _world
	result._camera = _camera
	return result

## 返回仍存活施法者，删除/离树后为空；不延长其生命周期。
func get_source() -> Node3D: return _node(_source) as Node3D
## 返回本阶段仍存活目标，删除/离树后为空。
func get_target() -> Node3D: return _node(_target) as Node3D
## 返回本次原世界，删除/离树后为空。
func get_world() -> Node: return _node(_world)
## 返回隔离副本，消费者不能改写快照内部策略；空表示无镜头配置。
func get_camera_profile() -> CameraEffectProfile: return _camera.duplicate() as CameraEffectProfile if _camera != null else null

func _node(weak_reference: WeakRef) -> Node:
	var value = weak_reference.get_ref() if weak_reference != null else null
	return value if is_instance_valid(value) and value.is_inside_tree() and not value.is_queued_for_deletion() else null