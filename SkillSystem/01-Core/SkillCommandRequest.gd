class_name SkillCommandRequest
extends RefCounted
## 一次连携根请求的身份与生命周期；不计算费用、不控制动画、不保存场景强引用。
## 根终态、动作结束且全部根/子交付结束后只通知一次；身份为进程内单调正整数。
signal lifetime_finished(request_id: int, round_id: int)

## 请求身份由创建方分配，发布后只读；子交付共享根身份。
var request_id: int:
	get: return _request_id
## 连携轮次归属由外部轮次所有者分配，发布后只读。
var round_id: int:
	get: return _round_id
## 施法者实例身份快照；节点删除后仍可诊断。
var caster_instance_id: int:
	get: return _caster_instance_id
## 根技能标识快照；已受理请求不跟随Inspector修改。
var skill_id: StringName:
	get: return _skill_id
## Focus绑定世界的实例身份，仅作世代检查，不保活世界。
var scene_scope_id: int:
	get: return _scene_scope_id
var _request_id: int = 0
var _round_id: int = 0
var _caster_instance_id: int = 0
var _skill_id: StringName
var _scene_scope_id: int = 0
var _caster_ref: WeakRef
var _skill_ref: WeakRef
var _timeout: float = 8.0
var _wait_elapsed: float = 0.0
var _release_authorizer: Callable
var _released: bool = false
var _failed: bool = false
var _action_started: bool = false
var _action_finished: bool = false
var _terminal: bool = false
var _tokens: Dictionary = {}
var _last_token_id: int = 0

## 创建受理快照；身份须正数，owner/skill/scope有效且skill属于caster后代，等待为有限正秒数。
## release_authorizer只检查资源授权，不支付；只能绑定数字身份/世代，不绑定本Request避免引用环。
static func create(root_id: int, batch_id: int, caster: Node3D, skill: SkillBase, scene_scope: Node, wait_timeout_seconds: float, release_authorizer: Callable) -> SkillCommandRequest:
	if root_id <= 0 or batch_id <= 0 or not is_instance_valid(caster) or not is_instance_valid(skill) or not is_instance_valid(scene_scope):
		return null
	if not caster.is_inside_tree() or not scene_scope.is_inside_tree() or not scene_scope.is_ancestor_of(caster) or not caster.is_ancestor_of(skill):
		return null
	if skill.skill_id.is_empty() or not is_finite(wait_timeout_seconds) or wait_timeout_seconds <= 0.0:
		return null
	var request := SkillCommandRequest.new()
	request._request_id = root_id
	request._round_id = batch_id
	request._caster_instance_id = caster.get_instance_id()
	request._skill_id = skill.skill_id
	request._scene_scope_id = scene_scope.get_instance_id()
	request._caster_ref = weakref(caster)
	request._skill_ref = weakref(skill)
	request._timeout = wait_timeout_seconds
	request._release_authorizer = release_authorizer
	return request

## 返回仍有效且未排队删除的施法者；失效返回null，不保活节点。
func get_caster() -> Node3D:
	var node = _caster_ref.get_ref() if _caster_ref != null else null
	return node as Node3D if is_instance_valid(node) and not node.is_queued_for_deletion() else null

## 返回仍有效且未排队删除的根技能实例；失效返回null。
func get_skill() -> SkillBase:
	var node = _skill_ref.get_ref() if _skill_ref != null else null
	return node as SkillBase if is_instance_valid(node) and not node.is_queued_for_deletion() else null

## 释放前的只读授权；未释放、未失败、引用有效且所有者确认预留可提交才为true。
func authorize_release() -> bool:
	return not _terminal and not _failed and not _released and get_caster() != null and get_skill() != null and _release_authorizer.is_valid() and _release_authorizer.call() == true

## 是否已接受根交付；后续打空或动作中断不撤销。
func has_released() -> bool: return _released
## 是否在接受交付前失败；成功后失败不会改变此状态。
func has_failed() -> bool: return _failed
## 是否已经确认根动画开始；接近不属于动作开始。
func has_action_started() -> bool: return _action_started
## 是否根动作已结束或从未开始的失败已完成；与投射物结束不同。
func has_action_finished() -> bool: return _action_finished
## 是否尚未开始的请求累计等待已到截止；开始后不超时中断。
func has_wait_expired() -> bool: return not _action_started and _wait_elapsed >= _timeout

## Host每物理帧传入有限非负秒数；开始/失败后停止累计，换目标不能重置。
func tick_wait(delta: float) -> void:
	if not _action_started and not _terminal and not _failed and is_finite(delta) and delta >= 0.0:
		_wait_elapsed += delta

## Host确认实际动画成功开始；终态/失败不再开始，不支付。
func mark_action_started() -> void:
	if not _terminal and not _failed: _action_started = true

## Host报告动作结束；幂等，交付仍可继续飞行。
func mark_action_finished() -> void:
	_action_finished = true
	_collect_terminal()

## 队伍控制器在资源提交成功后标记根交付已接受；不计子交付，不改变失败终态。
func mark_released() -> void:
	if _terminal or _failed: return
	_released = true
	_collect_terminal()

## 队伍控制器报告释放前失败；reason仅用于调用方诊断，成功后不可变成可退款失败。
func mark_failed(_reason: StringName) -> void:
	if _terminal or _released: return
	_failed = true
	if not _action_started: _action_finished = true
	_collect_terminal()

## 交付执行前保留单调正token；旧/重复token或终态拒绝，子技能共享同一个对象。
func retain_delivery(token_id: int) -> bool:
	if _terminal or token_id <= _last_token_id or token_id <= 0: return false
	_last_token_id = token_id
	_tokens[token_id] = true
	return true

## 接受失败或交付最终完成/失败后结束token；重复/未知结束无副作用。
func finish_delivery(token_id: int) -> void:
	if not _tokens.has(token_id): return
	_tokens.erase(token_id)
	_collect_terminal()

func _collect_terminal() -> void:
	if _terminal or not (_released or _failed) or not _action_finished or not _tokens.is_empty(): return
	_terminal = true
	_release_authorizer = Callable()
	lifetime_finished.emit(_request_id, _round_id)
