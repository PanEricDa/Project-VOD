class_name SkillExecutionClock
extends RefCounted
## 每次根请求独立的时间适配器；不持有世界强引用，不修改Engine或SceneTree，不是策划资源。
var _scope: WeakRef
var _independent: bool = true
var _action_held: bool = false
var _frame_modes: Dictionary = {}
var _frame_scales: Dictionary = {}

## world为本次原世界；独立模式只让本请求消费者按正常活动秒推进，不能解除真暂停。
func configure(world: Node) -> void:
	_scope = weakref(world) if is_instance_valid(world) else null
	_independent = true
	_action_held = false
	_frame_modes.clear()
	_frame_scales.clear()

## held只冻结本请求角色动画，不影响投射物或镜头；用于镜头等待到真实释放之间的门闩。
func hold_action(held: bool) -> void:
	_action_held = held

## world_delta为物理回调秒数；角色动画专用，镜头等待时返回0，仍服从世界真暂停。
func get_action_delta(world_delta: float) -> float:
	return 0.0 if _action_held else get_delta(world_delta)

## 本次退回普通世界时间；不清零任何交付/动画进度，同一帧已读快照不变，下帧生效。
func use_world_time() -> void:
	_independent = false

## world_delta为本回调的Godot秒数，physics区分物理/渲染帧；纯读取，同帧多个消费者不重复消费。
## 独立时解除time_scale影响，上限0.1活动秒防后台补发；真暂停/世界失效返回0。
func get_delta(world_delta: float, physics: bool = true) -> float:
	if not _allowed() or not is_finite(world_delta) or world_delta <= 0:
		return 0.0
	var key := _frame_key(physics)
	if not _frame_modes[key]:
		return world_delta
	return get_presentation_delta(world_delta, physics)

## 镜头等始终按真实活动时间的表现消费者使用；不受A切回世界模式影响，仍服从真暂停。
func get_presentation_delta(world_delta: float, physics: bool = false) -> float:
	if not _allowed() or not is_finite(world_delta) or world_delta <= 0:
		return 0.0
	var key := _frame_key(physics)
	if not _frame_scales.has(key):
		_frame_scales[key] = Engine.time_scale
	var scale: float = _frame_scales[key]
	return clampf(world_delta / scale, 0.0, 0.1) if is_finite(scale) and scale > 0.0 else 0.0

## 返回仍存活的原世界，供装配验证；只使用弱引用，不允许据此改绑请求。
func get_bound_scope() -> Node:
	var world: Node = _scope.get_ref() if _scope != null else null
	return world if is_instance_valid(world) and world.is_inside_tree() and not world.is_queued_for_deletion() else null

func _allowed() -> bool:
	var world: Node = _scope.get_ref() if _scope != null else null
	return is_instance_valid(world) and world.is_inside_tree() and not world.is_queued_for_deletion() and not world.get_tree().paused

func _frame_key(physics: bool) -> String:
	var prefix := "p" if physics else "r"
	var key := prefix + str(Engine.get_physics_frames() if physics else Engine.get_process_frames())
	for old: String in _frame_modes.keys():
		if old.begins_with(prefix) and old != key:
			_frame_modes.erase(old)
			_frame_scales.erase(old)
	if not _frame_modes.has(key):
		_frame_modes[key] = _independent
		_frame_scales[key] = Engine.time_scale
	return key
