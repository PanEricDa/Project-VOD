class_name PullTargetSkillEffect
extends SkillEffectBase

## 通用拉拽Effect：范围由Delivery唯一管理；本组件生成冻结目的地并提交请求，不直接移动；直属SkillEffectBase子节点仅在实际拉拽自然完成后执行。
enum CenterMode { CASTER_FRONT, TARGET_POSITION }
## 聚拢落点来源，默认CASTER_FRONT保留原身前聚拢；TARGET_POSITION使用技能已冻结的目标世界位置，不重新索敌。
@export var center_mode: CenterMode = CenterMode.CASTER_FRONT
## 仅CASTER_FRONT生效，从释放位置沿稳定朝向前推的距离，单位米，默认1.5；只影响本Effect聚集中心。
@export_range(0.0, 20.0, 0.1, "or_greater") var front_distance_m: float = 1.5
## 聚集期望圆盘半径，单位米，默认0.6；0表示中心点。拉拽期间允许单位重叠，墙体仍可截断，结束后恢复碰撞。
@export_range(0.0, 10.0, 0.1, "or_greater") var gather_radius_m: float = 0.6
## 外力持续的战斗秒数，默认0.35，必须大于0；由目标物理delta推进，暂停/慢放遵循世界时间。
@export_range(0.01, 10.0, 0.01, "or_greater") var duration_seconds: float = 0.35

## 待完成记录只存在于运行时；空子效果时不建立监听，离树时解除全部监听。
var _pending_completions: Dictionary[int, Dictionary] = {}

## 仅对树内存活且允许被动位移的UnitBase适用；关闭只跳过本Effect，不影响其他Effect。
func can_apply_to(_context: SkillContext, _result: SkillDeliveryResult, target: Node3D) -> bool:
	return _movable_target(target) != null

## context必须有本次释放快照；result不改写，target受理成功/已在圆盘内返回true，不代表物理抵达。
## 参数错误或单位拒绝返回false，让Delivery按原有真实执行失败规则处理。
func apply(context: SkillContext, result: SkillDeliveryResult, target: Node3D) -> bool:
	var receiver := _movable_target(target)
	if receiver == null or context == null or not context.caster is UnitBase:
		return false
	if not is_finite(gather_radius_m) or gather_radius_m < 0.0 or not is_finite(duration_seconds) or duration_seconds <= 0.0:
		return false
	var center: Vector3
	if center_mode == CenterMode.TARGET_POSITION:
		if not context.target_position.is_finite(): return false
		center = context.target_position
	elif center_mode == CenterMode.CASTER_FRONT:
		if not context.release_caster_position.is_finite() or not context.release_facing_direction.is_finite() or not is_finite(front_distance_m) or front_distance_m < 0.0: return false
		var forward := Vector3(context.release_facing_direction.x,0.0,context.release_facing_direction.z)
		if forward.length_squared() < 0.000001: return false
		center = context.release_caster_position + forward.normalized() * front_distance_m
	else:
		return false
	var offset := target.global_position - center
	offset.y = 0.0
	if offset.length_squared() <= gather_radius_m * gather_radius_m:
		return true
	# 正实例身份经整数混合产生稳定均匀圆盘点，不改变全局随机源，也无需策划配置seed。
	var seed_value: int = target.get_instance_id()
	var u: float = float(posmod(hash(seed_value), 1048576)) / 1048576.0
	var v: float = float(posmod(hash(seed_value ^ 0x5bd1e995), 1048576)) / 1048576.0
	var radius := gather_radius_m * sqrt(u)
	var angle := TAU * v
	var destination := center + Vector3(cos(angle),0.0,sin(angle)) * radius
	destination.y = target.global_position.y
	var start_position := receiver.global_position
	var token := receiver.request_forced_movement(context.caster as UnitBase, destination, duration_seconds, true)
	if token > 0 and receiver.get_forced_movement_token() == token and is_inside_tree() and not is_queued_for_deletion() and not _completion_effects().is_empty():
		_watch_completion(receiver, token, start_position, context, result)
	return token > 0

## 拉拽视觉直接读取本组件的唯一配置，不在特效资产重复维护落点/持续时间。
func get_presentation_data() -> Dictionary:
	return {&"pull": {"center_on_target":center_mode == CenterMode.TARGET_POSITION, "front_distance_m":front_distance_m, "gather_radius_m":gather_radius_m, "duration_seconds":duration_seconds}}

func _movable_target(target: Node3D) -> UnitBase:
	var unit := target as UnitBase
	return unit if is_instance_valid(unit) and unit.is_inside_tree() and not unit.is_queued_for_deletion() and not unit.is_dead() and unit.forced_movement_enabled else null


# 仅直属子效果属于完成后执行阶段；不递归收集，避免与技能根的即时Effects重复交付。
func _completion_effects() -> Array[SkillEffectBase]:
	var effects: Array[SkillEffectBase] = []
	for child: Node in get_children():
		if child is SkillEffectBase:
			effects.append(child as SkillEffectBase)
	return effects

# 绑定本次单位+token，不把后续替换请求的终态误当成本次完成；上下文独立复制。
func _watch_completion(receiver: UnitBase, token: int, start_position: Vector3, context: SkillContext, result: SkillDeliveryResult) -> void:
	var receiver_id := receiver.get_instance_id()
	_forget_completion(receiver_id)
	var callback := _on_movement_finished.bind(receiver_id, token)
	_pending_completions[receiver_id] = {
		"receiver": weakref(receiver), "token": token, "start": start_position,
		"context": context.duplicate_context(), "result": _capture_completion_result(result), "callback": callback,
	}
	receiver.forced_movement_finished.connect(callback)

func _on_movement_finished(finished_token: int, reason: StringName, receiver_id: int, expected_token: int) -> void:
	if finished_token != expected_token or not _pending_completions.has(receiver_id):
		return
	var pending: Dictionary = _pending_completions[receiver_id]
	if int(pending.token) != expected_token:
		return
	# 先移除本次监听，再执行子效果；子效果可安全发起新拉拽。
	_forget_completion(receiver_id)
	if reason not in [&"arrived", &"elapsed"] or not is_inside_tree() or is_queued_for_deletion():
		return
	var receiver := pending.receiver.get_ref() as UnitBase
	if _movable_target(receiver) == null:
		return
	var displacement: Vector3 = receiver.global_position - Vector3(pending.start)
	displacement.y = 0.0
	if displacement.length_squared() <= 0.000001:
		return
	var context := pending.context as SkillContext
	var result := pending.result as SkillDeliveryResult
	for effect: SkillEffectBase in _completion_effects():
		if not is_inside_tree() or is_queued_for_deletion() or _movable_target(receiver) == null:
			break
		if is_instance_valid(effect) and not effect.is_queued_for_deletion() and effect.get_parent() == self and effect.can_apply_to(context, result, receiver):
			if not effect.apply(context, result, receiver):
				push_warning("PullTargetSkillEffect: 完成后子效果执行失败：" + String(effect.name))

func _forget_completion(receiver_id: int) -> void:
	if not _pending_completions.has(receiver_id):
		return
	var pending: Dictionary = _pending_completions[receiver_id]
	_pending_completions.erase(receiver_id)
	var receiver := pending.receiver.get_ref() as UnitBase
	if is_instance_valid(receiver) and receiver.forced_movement_finished.is_connected(pending.callback):
		receiver.forced_movement_finished.disconnect(pending.callback)

func _exit_tree() -> void:
	for receiver_id: int in _pending_completions.keys():
		_forget_completion(receiver_id)


# Delivery会反复替换共享result.current_hit；独立包装冻结当前目标身份，但保留同一hit对象，
# 使同次命中后续即时/延迟效果仍累加到自己的命中账本，不错误引用最后一个范围目标。
func _capture_completion_result(result: SkillDeliveryResult) -> SkillDeliveryResult:
	if result == null:
		return null
	var captured := SkillDeliveryResult.new()
	captured.succeeded = result.succeeded
	captured.original_target = result.original_target
	captured.origin_position = result.origin_position
	captured.intended_position = result.intended_position
	captured.impact_position = result.impact_position
	captured.impact_direction = result.impact_direction
	captured.failure_reason = result.failure_reason
	captured.current_hit = result.current_hit
	captured.affected_targets.assign(result.affected_targets)
	captured.hit_outcomes.assign(result.hit_outcomes)
	return captured
