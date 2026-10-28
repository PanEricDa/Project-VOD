class_name PlayerSkillController
extends Node

## 玩家输入与统一SkillHost/动作执行者的轻量适配；不维护技能冷却或Gameplay效果。
## slot_index是静态常规槽0/1；skill仅供反馈，不能由订阅者直接执行Effect。
signal slot_accepted(slot_index: int, skill: SkillBase)
## reason为稳定拒绝分类；拒绝不排队、不支付、不开始冷却。
signal slot_rejected(slot_index: int, reason: StringName)

var _owner: PlayerBase
var _host: SkillHostComponent
var _driver: PlayerAttackController
var _input: Node
var _skill: SkillBase
var _context: SkillContext
var _serial: int = 0
var _requesting: bool = false
var _request_failure: StringName = &""

func _ready() -> void:
	_owner = get_parent() as PlayerBase
	_driver = _owner.get_node_or_null(^"AttackController") as PlayerAttackController if is_instance_valid(_owner) else null
	call_deferred("_bind_defaults")

func _bind_defaults() -> void:
	if not is_instance_valid(_owner) or not is_inside_tree():
		return
	bind_host(_owner.get_node_or_null(^"SkillHost") as SkillHostComponent)
	_input = _owner.get_node_or_null(^"PlayerSkillInputComponent")
	if is_instance_valid(_input) and _input.has_signal("slot_requested") and not _input.is_connected("slot_requested", _on_slot_requested):
		_input.connect("slot_requested", _on_slot_requested)

## 绑定同一玩家已有Host；重复绑定不重复连接。null等同unbind_host，不创建/注册技能。
func bind_host(host: SkillHostComponent) -> void:
	if _host == host:
		return
	unbind_host()
	if not is_instance_valid(host) or not is_instance_valid(_owner) or host.get_parent() != _owner or not is_instance_valid(_driver):
		return
	_host = host
	_host.action_requested.connect(_on_action_requested)
	_host.approach_requested.connect(_on_approach_requested)
	_host.active_skill_changed.connect(_on_active_skill_changed)
	_host.set_action_state_provider(_driver)
	if not _driver.external_action_lifecycle.is_connected(_on_action_lifecycle):
		_driver.external_action_lifecycle.connect(_on_action_lifecycle)

## 解除自身连接并取消自己仍拥有的动作；不改变Host槽位、装备或独立冷却。
func unbind_host() -> void:
	if is_instance_valid(_host):
		if is_instance_valid(_skill) and _host.get_active_skill() == _skill:
			_host.cancel_active_skill(&"player_controller_unbound")
		if _host.action_requested.is_connected(_on_action_requested):
			_host.action_requested.disconnect(_on_action_requested)
		if _host.approach_requested.is_connected(_on_approach_requested):
			_host.approach_requested.disconnect(_on_approach_requested)
		if _host.active_skill_changed.is_connected(_on_active_skill_changed):
			_host.active_skill_changed.disconnect(_on_active_skill_changed)
		_host.set_action_state_provider(null)
	_clear_action()
	if is_instance_valid(_driver) and _driver.external_action_lifecycle.is_connected(_on_action_lifecycle):
		_driver.external_action_lifecycle.disconnect(_on_action_lifecycle)
	_host = null

## 请求0/1常规槽；true仅代表受理且同步启动未失败，不等于实际释放。
## 仅Self目标的技能明确传自身；其他目标式技能只传玩家当前锁定，无锁定拒绝，不自动找敌或隐藏排队。
## 普攻不阻挡有效技能请求；Driver在动作资产验证后才原子抢占普攻并负责段数续接，其他技能/冲刺仍互斥。
func request_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index > 1:
		return _reject(slot_index, &"invalid_slot")
	if not is_instance_valid(_owner) or _owner.is_dead():
		return _reject(slot_index, &"owner_dead")
	if not _owner.is_player_input_enabled() or get_tree().paused:
		return _reject(slot_index, &"input_disabled")
	if not is_instance_valid(_host) or not is_instance_valid(_driver):
		return _reject(slot_index, &"skill_unavailable")
	var skill := _host.get_regular_skill(slot_index)
	if skill == null:
		return _reject(slot_index, &"empty_slot")
	if _requesting or _driver.is_external_action_in_progress() or _host.get_active_skill() != null or _owner.is_player_dashing():
		return _reject(slot_index, &"action_busy")
	var target := _get_input_target(skill)
	if target == null:
		return _reject(slot_index, &"target_missing")
	_requesting = true
	_request_failure = &""
	var accepted := _host.request_skill(skill.skill_id, target)
	_requesting = false
	if not accepted or not _request_failure.is_empty():
		return _reject(slot_index, _request_failure if not _request_failure.is_empty() else &"skill_unavailable")
	slot_accepted.emit(slot_index, skill)
	return true

## 只读查询0/1槽；返回独立显示快照，仅检查输入目标是否存在，不受理/支付或执行目标资格、距离、Condition预检。
## can_request只表示当前可尝试输入；目标、费用及软条件仍由Host最终判定。
## pressed仅表示尚未确认的输入；skill_instance_id为防止按住时换装的数字身份，0表示空槽。
func get_slot_status(slot_index: int) -> Dictionary:
	var skill := _host.get_regular_skill(slot_index) if is_instance_valid(_host) and slot_index >= 0 and slot_index < 2 else null
	var action: StringName = &""
	if is_instance_valid(_input) and slot_index >= 0 and slot_index < 2:
		action = _input.get("skill_1_action" if slot_index == 0 else "skill_2_action")
	var status := {
		"slot_index":slot_index, "configured":skill != null,
		"skill_instance_id":skill.get_instance_id() if skill != null else 0,
		"pressed":slot_index >= 0 and slot_index < 2 and is_instance_valid(_input) and _input.get_pressed_slot() == slot_index,
		"skill_name":skill.display_name if skill != null else "",
		"icon":skill.icon if skill != null else null, "input_action":action,
		"phase":&"empty", "can_request":false, "reason":&"empty_slot",
		"cooldown_remaining":skill.get_cooldown_remaining() if skill != null else 0.0,
		"cooldown_duration":maxf(skill.skill_cooldown,0.0) if skill != null else 0.0,
		"global_cooldown_remaining":_host.get_global_cooldown_remaining() if is_instance_valid(_host) else 0.0,
		"global_blocked":not _host.is_global_cooldown_ready() if is_instance_valid(_host) else false,
	}
	if skill == null:
		if slot_index < 0 or slot_index > 1: status.reason = &"invalid_slot"
		return status
	status.phase = &"blocked"
	if not is_instance_valid(_owner) or _owner.is_dead():
		status.reason = &"owner_dead"
	elif not _owner.is_player_input_enabled() or not is_inside_tree() or get_tree().paused:
		status.reason = &"input_disabled"
	elif not is_instance_valid(_driver):
		status.reason = &"skill_unavailable"
	elif _host.get_active_skill() == skill:
		status.phase = &"casting"
		status.reason = &"action_busy"
	elif _requesting or _driver.is_external_action_in_progress() or _host.get_active_skill() != null or _owner.is_player_dashing():
		status.reason = &"action_busy"
	elif not _host.is_skill_casting_enabled() or _host.is_cast_blocked():
		status.reason = &"cast_blocked"
	elif status.global_blocked:
		status.reason = &"global_cooldown"
	elif not skill.is_ready():
		status.phase = &"cooldown" if status.cooldown_remaining > 0.0 else &"blocked"
		status.reason = &"cooldown" if status.cooldown_remaining > 0.0 else &"skill_unavailable"
	elif _get_input_target(skill) == null:
		status.reason = &"target_missing"
	else:
		status.phase = &"ready"
		status.reason = &""
		status.can_request = true
	return status

# 输入端只供给意图，不替代SkillBase的关系/距离/Condition校验；空锁定绝不传入自动候选。
func _get_input_target(skill: SkillBase) -> Node3D:
	if skill.target_relations == TargetResolver.TargetRelationFlag.SELF:
		return _owner
	return _owner.get_locked_target()

func _reject(slot_index: int, reason: StringName) -> bool:
	slot_rejected.emit(slot_index, reason)
	return false

func _on_slot_requested(slot_index: int) -> void:
	request_slot(slot_index)

# 仅拒绝当前玩家Host的原超距请求；不复制距离公式、不接近/排队、不改变AI的approach消费者。
func _on_approach_requested(context: SkillContext, _required_range: float) -> void:
	if not is_instance_valid(_host): return
	var active := _host.get_active_skill()
	if active == null or active.get_current_context() != context: return
	_request_failure = &"out_of_range"
	_host.cancel_active_skill(&"player_out_of_range")

func _on_action_requested(skill: SkillBase, target: Node3D, effective_cast_time: float) -> void:
	if not is_instance_valid(_host) or _host.get_active_skill() != skill:
		return
	_skill = skill
	_context = skill.get_current_context()
	if not _driver.request_external_action(effective_cast_time, target as UnitBase, skill.get_action_payload(), 0):
		_request_failure = &"action_rejected"
		_host.cancel_active_skill(&"player_action_rejected")
		return
	_serial = _driver.get_external_action_serial()
	var serial := _serial
	if _owner.has_method("set_skill_action_permissions"):
		_owner.call("set_skill_action_permissions", skill.can_move_while_casting, skill.can_turn_while_casting)
	if not _host.confirm_active_action_started(_driver.get_action_launch_transform(), 0):
		_request_failure = &"action_rejected"
		if _serial == serial:
			if _host.get_active_skill() == skill:
				_host.cancel_active_skill(&"player_action_start_failed")
			_clear_action()

func _on_action_lifecycle(request_id: int, action_serial: int, event: StringName) -> void:
	if request_id != 0 or action_serial != _serial or not is_instance_valid(_host) or not is_instance_valid(_skill) or _host.get_active_skill() != _skill:
		return
	match event:
		&"release":
			if _skill.get_current_context() != _context:
				return
			if not _host.release_active_action(_driver.get_action_launch_transform(), 0) and action_serial == _serial:
				_host.cancel_active_skill(&"player_action_release_failed")
		&"finish":
			_host.finish_active_action(0)
		&"cancel":
			_host.cancel_active_skill(&"player_action_cancelled")

func _on_active_skill_changed(skill: SkillBase) -> void:
	if skill == null or is_instance_valid(_skill) and skill != _skill:
		_clear_action()

func _clear_action() -> void:
	var serial := _serial
	_serial = 0
	_skill = null
	_context = null
	if is_instance_valid(_owner) and _owner.has_method("set_skill_action_permissions"):
		_owner.call("set_skill_action_permissions", true, true)
	if serial > 0 and is_instance_valid(_driver) and _driver.get_external_action_serial() == serial:
		_driver.cancel_external_action()

func _exit_tree() -> void:
	if is_instance_valid(_input) and _input.is_connected("slot_requested", _on_slot_requested):
		_input.disconnect("slot_requested", _on_slot_requested)
	unbind_host()
