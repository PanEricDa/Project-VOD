@tool
class_name SkillHostComponent
extends Node
## Host已完成动作身份迁移后通知；request为本次根，presentation是可空只读事实。
## 终结动作确认开始，context为本次带正身份的根请求，不表示成功释放。
signal finisher_action_started(context: SkillContext)
## 已核对动作身份的水平位移意图，displacement单位米；terminal末段必须先消费。
signal skill_motion_step_requested(request_id: int, action_serial: int, displacement: Vector3, terminal: bool)
## 硬取消匹配动作；自然terminal不会发此通知，避免抹掉末段。
signal skill_motion_cancel_requested(request_id: int, action_serial: int)
var _motion_action_serial: int = -1
var _motion_action_id: int = -1
var _motion_component: SkillMotionComponent
var _motion_terminal: bool = false

## 接收当前驱动的动画事实；不依赖SkillState.CASTING，释放后的后摇仍有效。
func consume_action_motion_sample(request_id: int, action_serial: int, sample: Dictionary) -> void:
	if action_serial != _motion_action_serial or request_id != _motion_action_id: return
	if not is_instance_valid(_motion_component) or not _motion_component.is_inside_tree() or not is_instance_valid(_active_skill) or _motion_component.get_parent() != _active_skill:
		_clear_motion_action()
		return
	var result := _motion_component.sample_motion(request_id, action_serial, sample)
	if not bool(result.get("accepted",false)): return
	_motion_terminal = bool(result.get("terminal",false))
	skill_motion_step_requested.emit(request_id, action_serial, result.displacement, _motion_terminal)


func _on_motion_component_exiting() -> void:
	_clear_motion_action()


func _clear_motion_action(preserve_terminal: bool = false) -> void:
	if _motion_action_serial >= 1 and not (preserve_terminal and _motion_terminal):
		if is_instance_valid(_motion_component): _motion_component.cancel_motion(_motion_action_id, _motion_action_serial)
		skill_motion_cancel_requested.emit(_motion_action_id, _motion_action_serial)
	if is_instance_valid(_motion_component) and _motion_component.tree_exiting.is_connected(_on_motion_component_exiting):
		_motion_component.tree_exiting.disconnect(_on_motion_component_exiting)
	_motion_component = null
	_motion_action_serial = -1
	_motion_action_id = -1
	_motion_terminal = false

## 终结待发项目已结束，request_id仅用于匹配当前动作门闩。
signal finisher_emission_finished(request_id: int)
## 终结动作遭硬中断；已释放时只停止未发，旧在途保留。
signal finisher_action_cancelled(context: SkillContext, reason: StringName)
signal command_action_started(request: SkillCommandRequest, presentation: SkillPresentationContext)
## 当前原动作达到技能自身施法提示时点；context只读，不代表成功释放/命中，不改变动作锁。
signal cast_cue_reached(context: SkillContext)
## 已注册技能的纯表现实例准备事实；禁止用于更改动作/费用。
signal release_instance_prepared(presentation: SkillPresentationContext, instance: Node)
## 已注册技能的成功释放表现启动事实，按快照归属转发。
signal release_presentation_started(presentation: SkillPresentationContext)

## 单位级技能插槽和动作请求中介。
##
## Host 管理技能装配、AI 延迟、活动技能和公共冷却，但不播放动画、不读取
## DeliveryConfig，也不依赖任何具体 AI 或角色脚本。

signal skill_registered(skill: SkillBase)
signal skill_unregistered(skill: SkillBase)
signal active_skill_changed(skill: SkillBase)
signal action_requested(
	skill: SkillBase,
	target: Node3D,
	effective_cast_time: float
)
signal approach_requested(context: SkillContext, cast_range: float)
signal facing_requested(context: SkillContext)
signal movement_lock_requested(locked: bool)
signal skill_released(context: SkillContext)
## 某个指令失败/取消；仅报告身份与原因，队伍所有者统一退款，成功释放不回滚。
signal command_failed(request_id: int, reason: StringName)
## 等待/动作阶段改变，供只读界面更新；不表示接受交付或付款。
signal command_state_changed()
signal global_cooldown_started(duration: float)
signal global_cooldown_finished()

@export_category("Assembly")
## 开启后自动注册固定 SkillSocket 子节点下的全部 SkillBase；关闭时需由外部手动调用 register_skill()。
@export var auto_discover_skills: bool = true
## 开启后将本节点的 Node3D 父节点作为施法者自动注入；关闭用于由外部显式指定施法者的特殊装配。
@export var auto_configure_parent_owner: bool = true

@export_category("Skill Slots")
## 常规技能节点引用；数组索引即槽号，默认两个空槽。只影响本单位的普通 AI、显式常规请求与后续爆发选技，不修改技能自身配置。
@export var regular_skills: Array[SkillBase] = [null, null]:
	set(value):
		regular_skills = value
		if is_inside_tree():
			update_configuration_warnings()
## 终结技节点引用；默认空，不参加普通 AI 选择，仅供本单位专用请求入口使用。
@export var finisher_skill: SkillBase = null:
	set(value):
		finisher_skill = value
		if is_inside_tree():
			update_configuration_warnings()

## 连携技能独立节点引用；默认空，不参加普通AI选择，需直接费用组件且不与其他槽共享实例。
@export var combo_skill: SkillBase = null:
	set(value):
		combo_skill = value
		if is_inside_tree():
			update_configuration_warnings()

@export_category("Global Cooldown")
@export_range(0.0, 30.0, 0.05, "or_greater")
## Host 独立管理公共冷却时使用的基础时长，单位为秒；由 Ally 行为层接管时该值不会参与实际计时。
var global_cooldown_duration: float = 1.0

var _caster: Node3D
var _delivery_parent: Node
var _registered_skills: Array[SkillBase] = []
var _active_skill: SkillBase
var _pending_context: SkillContext
var _pending_command: SkillCommandRequest
var _active_command: SkillCommandRequest
var _active_action_context: SkillContext
var _finisher_release_gate: WeakRef
var _action_state_provider: Node
var _cancelling_command_id: int = 0
var _skill_casting_enabled: bool = true
var _cast_blocked: bool = false
var _use_external_global_cooldown: bool = false
var _external_global_cooldown_blocked: bool = false
var _global_cooldown_remaining: float = 0.0
var _movement_locked: bool = false
## 由单位装配层注入的只读感知候选提供者；Host 不依赖具体 AI 组件类型。
var _target_candidate_provider: Node
var _editor_slot_signature: PackedInt64Array


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if auto_configure_parent_owner:
		var parent := get_parent() as Node3D
		if parent != null:
			configure_owner(parent)
	if auto_discover_skills:
		discover_skills()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if get_finisher_action_context() != null and not _command_cast_allowed():
		cancel_active_skill(&"finisher_cast_unavailable")
	if (_pending_command != null or _active_command != null) and not _command_cast_allowed():
		_cancel_all_commands(&"command_cast_unavailable")
	if not _use_external_global_cooldown and _global_cooldown_remaining > 0.0:
		_global_cooldown_remaining = maxf(
			_global_cooldown_remaining - delta,
			0.0
		)
		if _global_cooldown_remaining <= 0.0:
			global_cooldown_finished.emit()

	if (
		is_instance_valid(_active_skill)
		and _pending_command == null
		and _active_command == null
		and _active_skill.get_state() == SkillBase.SkillState.QUEUED
	):
		_active_skill.try_request_action()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var signature := PackedInt64Array()
	signature.append(regular_skills.size())
	for skill_value: Variant in regular_skills:
		signature.append(skill_value.get_instance_id() if is_instance_valid(skill_value) else 0)
	signature.append(finisher_skill.get_instance_id() if is_instance_valid(finisher_skill) else 0)
	signature.append(combo_skill.get_instance_id() if is_instance_valid(combo_skill) else 0)
	if signature != _editor_slot_signature:
		_editor_slot_signature = signature
		update_configuration_warnings()


func configure_owner(caster: Node3D, delivery_parent: Node = null) -> void:
	_caster = caster
	_delivery_parent = delivery_parent
	if not is_instance_valid(_delivery_parent) and is_instance_valid(caster):
		var tree: SceneTree = caster.get_tree()
		if tree != null:
			_delivery_parent = (
				tree.current_scene
				if is_instance_valid(tree.current_scene)
				else tree.root
			)
	for skill: SkillBase in _registered_skills:
		if is_instance_valid(skill) and not skill.is_queued_for_deletion():
			skill.configure_owner(_caster, self, _delivery_parent)


func register_skill(skill: SkillBase) -> bool:
	if not is_instance_valid(skill) or skill.is_queued_for_deletion() or skill in _registered_skills:
		return false
	for registered: SkillBase in _registered_skills:
		if not is_instance_valid(registered) or registered.is_queued_for_deletion():
			continue
		if registered.skill_id == skill.skill_id:
			return false
	_registered_skills.append(skill)
	skill.configure_owner(_caster, self, _delivery_parent)
	_connect_skill(skill)
	skill_registered.emit(skill)
	update_configuration_warnings()
	return true


func unregister_skill(skill: SkillBase) -> bool:
	if not is_instance_valid(skill) or skill.is_queued_for_deletion() or skill not in _registered_skills:
		return false
	if _active_skill == skill:
		cancel_active_skill(&"skill_unregistered")
	_disconnect_skill(skill)
	_registered_skills.erase(skill)
	skill.configure_owner(null, null, null)
	skill_unregistered.emit(skill)
	update_configuration_warnings()
	return true


func discover_skills() -> void:
	var socket := get_node_or_null(^"SkillSocket")
	if socket == null:
		return
	for child: Node in socket.get_children():
		if child is SkillBase:
			register_skill(child as SkillBase)


## 读取从零开始的常规槽号；越界、空槽、跨 Host、重复或未注册引用均返回 null，原索引不压缩。
func get_regular_skill(slot_index: int) -> SkillBase:
	if slot_index < 0 or slot_index >= regular_skills.size():
		return null
	var skill_value: Variant = regular_skills[slot_index]
	if not is_instance_valid(skill_value):
		return null
	var skill := skill_value as SkillBase
	if not _is_slot_skill_valid(skill):
		return null
	for prior_index: int in range(slot_index):
		if regular_skills[prior_index] == skill:
			return null
	return skill


## 按槽号顺序返回本 Host 有效常规技能的列表副本；供普通 AI 使用，列表下标不是原槽号。
func get_equipped_regular_skills() -> Array[SkillBase]:
	var result: Array[SkillBase] = []
	for slot_index: int in range(regular_skills.size()):
		var skill := get_regular_skill(slot_index)
		if skill != null:
			result.append(skill)
	return result


## 读取本 Host 有效终结技；与任何常规槽冲突或未注册时返回 null。
func get_finisher_skill() -> SkillBase:
	if not _is_slot_skill_valid(finisher_skill):
		return null
	for slot_index: int in range(regular_skills.size()):
		if get_regular_skill(slot_index) == finisher_skill:
			return null
	return finisher_skill


## 返回有效连携实例；结构/注册/ID/其他槽冲突与费用不合法都返回null。
func get_combo_skill() -> SkillBase:
	if not _is_slot_skill_valid(combo_skill) or combo_skill.skill_id.is_empty():
		return null
	if combo_skill in regular_skills or combo_skill == finisher_skill:
		return null
	for skill: SkillBase in _registered_skills:
		if is_instance_valid(skill) and skill != combo_skill and skill.skill_id == combo_skill.skill_id:
			return null
	return combo_skill if combo_skill.get_combo_focus_cost() != null else null


## 注入动作占用查询者，只须is_action_in_progress接口；不要求具体AI类，null可卸载。
func set_action_state_provider(provider: Node) -> void:
	_action_state_provider = provider


## 连携预检共享技能目标/条件/成本规则；不激活、不支付、不冻结本次目标，范围外仍可接近。
func prepare_command_context(preferred_target: UnitBase = null) -> SkillContext:
	var skill := get_combo_skill()
	if skill == null or not _command_cast_allowed(): return null
	var target: Node3D
	if is_instance_valid(_target_candidate_provider) and _target_candidate_provider.has_method(&"get_locked_target"):
		target = _target_candidate_provider.call(&"get_locked_target") as Node3D
	var context := _create_context(target, _get_candidate_snapshot(), Vector3.INF, SkillContext.RequestSource.EXPLICIT, false)
	context.purpose = SkillContext.Purpose.CHAIN
	context.preferred_target = preferred_target
	var prepared := skill.prepare_request(context)
	# 只在既有CURRENT模式的旧AI目标失效时请求其原策略刷新；不写入玩家锁定。
	if prepared == null and skill.target_selection_mode == TargetResolver.TargetSelectionMode.CURRENT_COMBAT_TARGET and not TargetResolver.is_candidate_valid(_caster, target, skill.target_relations, skill.require_targetable, skill.require_alive) and is_instance_valid(_target_candidate_provider) and _target_candidate_provider.has_method(&"refresh_target"):
		_target_candidate_provider.call(&"refresh_target")
		context.requested_target = _target_candidate_provider.call(&"get_locked_target") as Node3D
		context.candidate_targets = _get_candidate_snapshot()
		prepared = skill.prepare_request(context)
	return prepared


## 只缓存一条尚未开始的根请求；true是受理，不在本调用播放动画或释放。
func enqueue_command(request: SkillCommandRequest) -> bool:
	if request == null or _pending_command != null or not _command_cast_allowed() or request.has_failed() or request.has_released() or request.has_action_started():
		return false
	if request.get_caster() != _caster or request.get_skill() != get_combo_skill() or not is_instance_valid(_delivery_parent) or request.scene_scope_id != _delivery_parent.get_instance_id():
		return false
	_pending_command = request
	command_state_changed.emit()
	return true


## 是否有一条未开始请求，包括接近与等待旧动作；不包含已开始动作。
func has_pending_command() -> bool: return _pending_command != null
## 从动画开始到动作终结的占用；技能释放/READY不提前解锁。
func has_command_action_lock() -> bool: return get_finisher_action_context() != null or _active_command != null and _active_command.has_action_started() and not _active_command.has_action_finished()
## 返回等待请求身份；空为0，供只读显示与带ID回调。
func get_pending_command_id() -> int: return _pending_command.request_id if _pending_command != null else 0
## 返回已开始动作身份；空为0，不能用此识别旧投射物。
func get_active_command_id() -> int: return _active_command.request_id if _active_command != null else (_active_action_context.execution_id if get_finisher_action_context() != null else 0)
## 只读指令动作阶段，与技能冷却/交付结束分开。
func get_command_phase() -> StringName:
	if _active_command != null: return &"released" if _active_command.has_released() else &"casting"
	if _pending_command != null:
		if is_instance_valid(_active_skill) and _active_skill == _pending_command.get_skill() and _active_skill.get_state() == SkillBase.SkillState.QUEUED: return &"approaching"
		return &"waiting"
	return &"idle"


## 行为层每物理帧推进一次；true表示本帧由等待/接近/动作接管，不等于已释放。
## preferred_target是当前玩家敌方锁定，delta是本帧有限非负秒数，换目标不重置截止。
func advance_pending_command(preferred_target: UnitBase, delta: float) -> bool:
	if _pending_command != null:
		_pending_command.tick_wait(delta)
		if _pending_command.has_wait_expired(): cancel_command(_pending_command.request_id, &"command_wait_timeout")
	if not _command_cast_allowed():
		_cancel_all_commands(&"command_cast_unavailable")
		return false
	if has_command_action_lock(): return true
	if _pending_command == null: return false
	if is_instance_valid(_action_state_provider) and _action_state_provider.has_method(&"is_action_in_progress") and _action_state_provider.call(&"is_action_in_progress"):
		return true
	var request := _pending_command
	var skill := request.get_skill()
	if skill == null or skill != get_combo_skill():
		cancel_command(request.request_id, &"command_skill_invalid")
		return true
	if is_instance_valid(_active_skill) and _active_skill != skill:
		if _active_skill.get_state() == SkillBase.SkillState.CASTING: return true
		cancel_active_skill(&"unstarted_action_yields")
	var context := prepare_command_context(preferred_target)
	if context == null:
		cancel_command(request.request_id, &"command_target_invalid")
		return true
	context.command_request = request
	context.damage_context = CombatDamageContext.create(_caster, _delivery_parent, CombatDamageContext.Origin.CHAIN, request.request_id, request.round_id, request.skill_id)
	if _active_skill == skill:
		if skill.get_state() == SkillBase.SkillState.QUEUED and not skill.refresh_queued_request(context):
			cancel_command(request.request_id, &"command_preflight_failed")
		return true
	if not _begin_decision(skill, context):
		cancel_command(request.request_id, &"command_activation_failed")
	return true


## 取消指定等待或活动动作；只发一次事实通知、不取消其他已释放在途交付、不支付/退款。
func cancel_command(request_id: int, reason: StringName) -> void:
	if _cancelling_command_id != 0: return
	var request: SkillCommandRequest
	if _pending_command != null and _pending_command.request_id == request_id:
		request = _pending_command
		_pending_command = null
	elif _active_command != null and _active_command.request_id == request_id:
		request = _active_command
		_active_command = null
	if request == null: return
	_cancelling_command_id = request_id
	if is_instance_valid(_active_skill) and _active_skill == request.get_skill() and _active_action_context != null and _active_action_context.command_request == request:
		_active_skill.cancel_skill(reason)
		_release_active_skill()
	request.mark_action_finished()
	command_failed.emit(request_id, reason)
	_cancelling_command_id = 0
	command_state_changed.emit()


func _cancel_all_commands(reason: StringName) -> void:
	if _active_command != null: cancel_command(_active_command.request_id, reason)
	if _pending_command != null: cancel_command(_pending_command.request_id, reason)


func _command_cast_allowed() -> bool:
	return is_instance_valid(_caster) and _caster.is_inside_tree() and not _caster.is_queued_for_deletion() and _skill_casting_enabled and not _cast_blocked and not (_caster.has_method(&"is_dead") and _caster.call(&"is_dead"))


func _context_matches_active(context: SkillContext) -> bool:
	return context != null and _active_action_context != null and context == _active_action_context


func _is_slot_skill_structurally_valid(skill: SkillBase) -> bool:
	if not is_instance_valid(skill) or skill.is_queued_for_deletion():
		return false
	var socket := get_node_or_null(^"SkillSocket")
	return socket != null and skill.get_parent() == socket


func _is_slot_skill_valid(skill: SkillBase) -> bool:
	return _is_slot_skill_structurally_valid(skill) and skill in _registered_skills


## 明确请求 skill_id 对应技能；target 为指定目标，candidate_targets 为候选快照，
## target_position 为可选世界落点（INF 表示未指定）；source 默认 EXPLICIT，
## 仅自主决策调用应传 AI_AUTOMATIC。所有底层合法性检查仍正常执行。
func request_skill(
	skill_id: StringName,
	target: Node3D,
	candidate_targets: Array[Node3D] = [],
	target_position: Vector3 = Vector3.INF,
	source: int = SkillContext.RequestSource.EXPLICIT
) -> bool:
	if not _can_start_request():
		return false
	var skill := _find_skill(skill_id)
	if skill == null or skill not in get_equipped_regular_skills():
		return false
	return _request_resolved_skill(skill, target, candidate_targets, target_position, source)


## 显式请求已装备终结技。target 为指定目标（可空但仍须通过技能目标规则）；candidate_targets 是本次候选快照；
## target_position 是世界落点，INF 表示未指定。返回 true 表示请求受理，不表示技能已释放或命中。
func request_finisher(
	target: Node3D,
	candidate_targets: Array[Node3D] = [],
	target_position: Vector3 = Vector3.INF
) -> bool:
	return activate_finisher(prepare_finisher_context(target, candidate_targets, target_position))

## 只读预检已装配终结技；preferred_target为合法时优先的玩家意图，候选与位置沿用原规则。
## 不考虑将被抢占的动作忙碌/GCD，不绕过死亡、封锁、技能自身冷却、条件、成本或即时射程。
func prepare_finisher_context(preferred_target: Node3D = null, candidates: Array[Node3D] = [], target_position: Vector3 = Vector3.INF) -> SkillContext:
	var skill := get_finisher_skill()
	if skill == null or not _command_cast_allowed(): return null
	var target := preferred_target
	if is_instance_valid(_target_candidate_provider) and _target_candidate_provider.has_method(&"get_locked_target"):
		var current := _target_candidate_provider.call(&"get_locked_target") as Node3D
		if is_instance_valid(current): target = current
	var context := _create_context(target, candidates if not candidates.is_empty() else _get_candidate_snapshot(), target_position, SkillContext.RequestSource.EXPLICIT, false)
	context.purpose = SkillContext.Purpose.FINISHER
	context.preferred_target = preferred_target
	context.damage_context = CombatDamageContext.create(_caster, _delivery_parent, CombatDamageContext.Origin.FINISHER, 0, 0, skill.skill_id)
	if not skill.can_start_in_place(context): return null
	return skill.prepare_request(context)

## 接受本Host预检产生的context；调用方可预先注入请求时钟/局部种子，不得跨世界或宿主。
## 先再验证后分配身份并抢占；仍从SkillBase.activate进入同一管线，true仅为请求受理。
func activate_finisher(context: SkillContext) -> bool:
	var skill := get_finisher_skill()
	if context == null or skill == null or not _command_cast_allowed() or context.host != self or context.caster != _caster or context.delivery_parent != _delivery_parent or context.purpose != SkillContext.Purpose.FINISHER or not skill.can_start_in_place(context):
		return false
	var prepared := skill.prepare_request(context)
	if prepared == null: return false
	prepared.execution_id = CombatDamageContext.allocate_id()
	prepared.damage_context = CombatDamageContext.create(_caster, _delivery_parent, CombatDamageContext.Origin.FINISHER, prepared.execution_id, 0, skill.skill_id)
	_cancel_all_commands(&"finisher_preempted")
	cancel_active_skill(&"finisher_preempted")
	if is_instance_valid(_action_state_provider) and _action_state_provider.has_method(&"cancel_current_action"):
		_action_state_provider.call(&"cancel_current_action")
	if not _command_cast_allowed() or get_finisher_skill() != skill: return false
	return _begin_decision(skill, prepared)

## 当前终结动作的独立context；已释放后仍保留到动作结束，不把在途火球当作动作占用。
func get_finisher_action_context() -> SkillContext:
	return _active_action_context if _active_action_context != null and _active_action_context.purpose == SkillContext.Purpose.FINISHER else null


func _request_resolved_skill(
	skill: SkillBase,
	target: Node3D,
	candidate_targets: Array[Node3D],
	target_position: Vector3,
	source: int
) -> bool:
	var context := _create_context(
		target,
		candidate_targets,
		target_position,
		source,
		true
	)
	if not skill.can_request(context):
		return false
	# 显式请求已经由外部调用者完成了“何时施放”的决定，因此必须立即进入技能流程。
	# AI 的随机犹豫只属于自动选择入口，不能污染玩家指令、剧情事件或测试调用。
	return _begin_decision(skill, context)


func request_best_skill(target: Node3D) -> bool:
	if not _can_start_request():
		return false
	## 每轮决策只读取一次快照，确保所有候选技能基于相同的感知时刻评估。
	var candidate_targets: Array[Node3D] = _get_candidate_snapshot()
	var selected: SkillBase = null
	var selected_context: SkillContext = null
	for skill_value: Variant in _registered_skills:
		if not is_instance_valid(skill_value):
			continue
		var skill := skill_value as SkillBase
		if skill == null or skill.is_queued_for_deletion() or skill not in get_equipped_regular_skills():
			continue
		if not skill.automatic_cast_enabled or not skill.is_ready():
			continue
		# Host 只提供未经分类的候选集合。友军、敌军、自身、距离和 Conditions
		# 均由当前 SkillBase 的既有配置统一解析，防止行为层复制技能规则。
		var context := _create_context(
			target,
			candidate_targets,
			Vector3.INF,
			SkillContext.RequestSource.AI_AUTOMATIC,
			false
		)
		if not skill.can_request(context):
			continue
		if selected == null or skill.ai_priority > selected.ai_priority:
			selected = skill
			selected_context = context
	if selected == null:
		return false
	return _begin_decision(selected, selected_context)


## 注入只读的技能候选提供者。
##
## Provider 只需实现 get_perceived_candidates(maximum_distance)，无需继承某个
## SkillSystem 类型；传入 null 可安全卸载。
func set_target_candidate_provider(provider: Node) -> void:
	_target_candidate_provider = provider


## 返回当前 Provider，仅用于装配验证和运行时调试，不暴露为 Inspector NodePath。
func get_target_candidate_provider() -> Node:
	return (
		_target_candidate_provider
		if is_instance_valid(_target_candidate_provider)
		else null
	)


func _get_candidate_snapshot() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	if (
		not is_instance_valid(_target_candidate_provider)
		or not _target_candidate_provider.has_method(
			&"get_perceived_candidates"
		)
	):
		return candidates
	var value: Variant = _target_candidate_provider.call(
		&"get_perceived_candidates",
		-1.0
	)
	if not value is Array:
		return candidates
	for candidate_value: Variant in value:
		if (
			is_instance_valid(candidate_value)
			and candidate_value is Node3D
		):
			candidates.append(candidate_value as Node3D)
	return candidates


## 确认动画真正开始；普通expected=0兼容旧调用，连携必须为本等待请求正ID。
func confirm_active_action_started(cast_transform: Transform3D, expected_request_id: int = 0) -> bool:
	var request := _pending_command if _pending_command != null and _active_skill == _pending_command.get_skill() else _active_command
	if request != null and expected_request_id != request.request_id: return false
	if request == null and expected_request_id != get_active_command_id(): return false
	var started_skill := _active_skill
	var started_context := _active_action_context
	if not is_instance_valid(started_skill) or not started_skill.confirm_action_started(cast_transform): return false
	# cast_started监听器可以同步取消或切换动作；不能在旧确认栈内绑定新/空技能。
	if _active_skill != started_skill or _active_action_context != started_context: return false
	_motion_component = _active_skill.get_motion_component()
	if _motion_component != null and not _motion_component.tree_exiting.is_connected(_on_motion_component_exiting):
		_motion_component.tree_exiting.connect(_on_motion_component_exiting)
	_motion_action_id = expected_request_id
	_motion_action_serial = int(_action_state_provider.call("get_external_action_serial")) if is_instance_valid(_action_state_provider) and _action_state_provider.has_method("get_external_action_serial") else -1
	_motion_terminal = false
	if request != null:
		if _pending_command != request or request.has_failed() or not is_instance_valid(_active_skill): return false
		request.mark_action_started()
		_active_command = request
		_pending_command = null
		command_state_changed.emit()
		if _active_command == request and not request.has_failed() and is_instance_valid(_active_skill):
			command_action_started.emit(request, _active_skill.get_current_presentation_context())
	elif get_finisher_action_context() != null:
		finisher_action_started.emit(_active_action_context)
	return true


## provider为同世界终结协调器，须提供request_finisher_release(context,transform)->bool；不替换普通技能管线。
## 同时只允许一个仍存活的提供者；成功只表示取得延迟释放协调权，不启动动作。
func set_finisher_release_gate(provider: Node) -> bool:
	var prior: Node = _finisher_release_gate.get_ref() as Node if _finisher_release_gate != null else null
	if is_instance_valid(prior) and prior != provider: return false
	if not is_instance_valid(provider) or not is_instance_valid(_delivery_parent) or not _delivery_parent.is_ancestor_of(provider) or not provider.has_method("request_finisher_release"): return false
	_finisher_release_gate = weakref(provider)
	return true

## 仅provider本人可清除等待接口；旧协调器清理不得移除新提供者。
func clear_finisher_release_gate(provider: Node) -> void:
	if _finisher_release_gate != null and _finisher_release_gate.get_ref() == provider: _finisher_release_gate = null

## 镜头到位后由当前provider提交原context和发射姿态；身份/宿主/封锁仍须合法，只执行原SkillBase管线。
func commit_finisher_release(provider: Node, context: SkillContext, launch_transform: Transform3D) -> bool:
	if _finisher_release_gate == null or _finisher_release_gate.get_ref() != provider or context == null or get_finisher_action_context() != context or not _command_cast_allowed(): return false
	return is_instance_valid(_active_skill) and _active_skill.release_action(launch_transform)

## 从动作释放标记请求交付；连携需匹配当前正ID，迟到/重复标记不命中新动作。
## 若已安装终结释放门闩，true仅表示等待请求已受理，镜头到位后才由commit_finisher_release真正交付。
func release_active_action(launch_transform: Transform3D, expected_request_id: int = 0) -> bool:
	if _active_command != null:
		if expected_request_id != _active_command.request_id or _active_command.has_released(): return false
	elif expected_request_id != get_active_command_id(): return false
	var context := get_finisher_action_context()
	var gate := _finisher_release_gate.get_ref() as Node if _finisher_release_gate != null else null
	if context != null and is_instance_valid(gate):
		return bool(gate.call("request_finisher_release",context,launch_transform))
	return is_instance_valid(_active_skill) and _active_skill.release_action(launch_transform)


## 关闭本动作；expected标识不匹配不修改任何请求，保留另一条等待指令。
func finish_active_action(expected_request_id: int = 0) -> void:
	if _active_command != null:
		if expected_request_id != _active_command.request_id: return
		var request := _active_command
		if not request.has_released():
			cancel_command(request.request_id, &"action_finished_before_release")
			return
		_active_command = null
		if is_instance_valid(_active_skill): _active_skill.finish_action()
		_release_active_skill(true)
		request.mark_action_finished()
		command_state_changed.emit()
		return
	if expected_request_id != get_active_command_id() or not is_instance_valid(_active_skill): return
	_active_skill.finish_action()
	_release_active_skill(true)


## 取消当前执行，reason为终态原因；监听器可同步开始新请求，旧取消栈只清理原技能及context。
func cancel_active_skill(reason: StringName = &"cancelled") -> void:
	var finisher := get_finisher_action_context()
	if finisher != null:
		var skill := get_active_skill()
		if skill != null: skill.stop_pending_emission(finisher.execution_id)
		if not _context_matches_active(finisher): return
		if skill != null: skill.cancel_skill(reason)
		# cancel_skill的终态回调可能已关闭旧动作并同步受理新动作，只能清理原身份。
		if not _context_matches_active(finisher): return
		_release_active_skill()
		finisher_action_cancelled.emit(finisher, reason)
		return
	if _active_command != null:
		cancel_command(_active_command.request_id, reason)
		return
	if _pending_command != null and _active_skill == _pending_command.get_skill():
		cancel_command(_pending_command.request_id, reason)
		return
	var cancelled_skill := get_active_skill()
	var cancelled_context := _active_action_context
	if is_instance_valid(cancelled_skill):
		cancelled_skill.cancel_skill(reason)
	# 普通终态也可能同步解锁并受理新动作；不能用旧取消栈覆盖新context。
	if _active_skill != cancelled_skill or _active_action_context != cancelled_context:
		return
	_release_active_skill()


func set_cast_blocked(blocked: bool) -> void:
	_cast_blocked = blocked
	if blocked:
		_cancel_all_commands(&"cast_blocked")
		if get_finisher_action_context() != null: cancel_active_skill(&"cast_blocked")


## 返回实际施法封锁，供指令资格/UI只读使用；不包含冷却或动作忙碌。
func is_cast_blocked() -> bool:
	return _cast_blocked


func set_skill_casting_enabled(enabled: bool) -> void:
	_skill_casting_enabled = enabled
	if not enabled:
		_cancel_all_commands(&"skill_casting_disabled")
		cancel_active_skill(&"skill_casting_disabled")


func is_skill_casting_enabled() -> bool:
	return _skill_casting_enabled


func set_use_external_global_cooldown(active: bool) -> void:
	_use_external_global_cooldown = active
	if active:
		_global_cooldown_remaining = 0.0


func set_external_global_cooldown_blocked(blocked: bool) -> void:
	_external_global_cooldown_blocked = blocked


func start_global_cooldown(duration_override: float = -1.0) -> void:
	if _use_external_global_cooldown:
		return
	var duration: float = (
		duration_override
		if duration_override >= 0.0
		else global_cooldown_duration
	)
	_global_cooldown_remaining = maxf(duration, 0.0)
	global_cooldown_started.emit(_global_cooldown_remaining)
	if _global_cooldown_remaining <= 0.0:
		global_cooldown_finished.emit()


func get_global_cooldown_remaining() -> float:
	return _global_cooldown_remaining


func is_global_cooldown_ready() -> bool:
	return (
		not _external_global_cooldown_blocked
		and (
			_use_external_global_cooldown
			or _global_cooldown_remaining <= 0.0
		)
	)


func get_registered_skills() -> Array[SkillBase]:
	return _registered_skills.duplicate()


func get_active_skill() -> SkillBase:
	return _active_skill if is_instance_valid(_active_skill) else null


## 返回当前已激活技能是否仍占用角色的普通攻击链路。
## 只有已排队接近、已请求动作或正在施法的技能会返回 true；成功释放后的犹豫、技能冷却
## 与就绪状态均返回 false，使拥有普攻资格的 AI 能在共享行动冷却结束后继续普攻填充。
func is_active_skill_action_in_progress() -> bool:
	var active_skill := get_active_skill()
	if not is_instance_valid(active_skill):
		return false
	return active_skill.get_state() in [
		SkillBase.SkillState.QUEUED,
		SkillBase.SkillState.ACTION_REQUESTED,
		SkillBase.SkillState.CASTING,
	]


## 返回当前技能是否仅处于 AI 决策等待。
## 当前随机犹豫统一由 SkillBase 在成功释放后维护，因此 Host 不再保留前置等待并始终返回 false。
func is_waiting_for_ai_decision() -> bool:
	return false


## 返回当前被注入的施法者，仅用于装配验证、调试与外部适配层读取。
##
## 该值不是 Inspector 配置项；正常场景装配时始终由 Host 的父 Unit 自动提供。
func get_skill_owner() -> Node3D:
	return _caster if is_instance_valid(_caster) else null


func get_preferred_cast_range() -> float:
	if is_instance_valid(_active_skill):
		return maxf(_active_skill.cast_range, 0.0)
	var selected: SkillBase = null
	for skill_value: Variant in _registered_skills:
		if not is_instance_valid(skill_value):
			continue
		var skill := skill_value as SkillBase
		if skill == null or skill.is_queued_for_deletion() or skill not in get_equipped_regular_skills():
			continue
		if (
			not skill.automatic_cast_enabled
			or (selected != null and skill.ai_priority <= selected.ai_priority)
		):
			continue
		selected = skill
	# 该接口描述的是当前技能装配所要求的战术站位，而不是“这一帧能否施法”。
	# 技能冷却只由 request_best_skill() 处理；若在这里过滤冷却中的技能，
	# 纯施法 AI 会在每次释放后错误地退回武器的近战距离。
	return maxf(selected.cast_range, 0.0) if selected != null else 0.0


func _can_start_request() -> bool:
	if (
		is_instance_valid(_caster)
		and _caster.has_method(&"is_dead")
		and bool(_caster.call(&"is_dead"))
	):
		# 死亡是运行时资格，不改写用户配置的技能总开关。
		return false
	return (
		_skill_casting_enabled
		and not _cast_blocked
		and is_global_cooldown_ready()
		and not is_instance_valid(_active_skill)
		and _pending_command == null and _active_command == null
		and is_instance_valid(_caster)
	)


func _begin_decision(
	skill: SkillBase,
	context: SkillContext
) -> bool:
	_active_skill = skill
	_pending_context = context
	active_skill_changed.emit(_active_skill)
	# AI 自动选择只决定“使用哪个技能”，而不是延迟首发动作。
	# 成功释放后的随机犹豫由 SkillBase 自己维护，Host 不保留等待中的 pending skill。
	_activate_pending_request()
	return is_instance_valid(_active_skill)


func _activate_pending_request() -> void:
	if not is_instance_valid(_active_skill) or _pending_context == null:
		_release_active_skill()
		return
	var context: SkillContext = _pending_context
	_pending_context = null
	if not _active_skill.activate(context):
		_release_active_skill()


func _create_context(
	target: Node3D,
	candidate_targets: Array[Node3D],
	target_position: Vector3,
	source: int,
	explicit_target_requested: bool
) -> SkillContext:
	var context := SkillContext.new()
	context.caster = _caster
	context.host = self
	context.requested_target = target
	context.candidate_targets.assign(candidate_targets)
	context.target_position = target_position
	context.delivery_parent = _delivery_parent
	context.request_source = source
	context.explicit_target_requested = explicit_target_requested
	return context


func _find_skill(skill_id: StringName) -> SkillBase:
	for skill_value: Variant in _registered_skills:
		if not is_instance_valid(skill_value):
			continue
		var skill := skill_value as SkillBase
		if skill == null or skill.is_queued_for_deletion():
			continue
		if skill.skill_id == skill_id:
			return skill
	return null


func _connect_skill(skill: SkillBase) -> void:
	skill.emission_finished.connect(_on_finisher_emission_finished)
	skill.cast_cue_reached.connect(_on_skill_cast_cue_reached)
	skill.release_instance_prepared.connect(_on_skill_release_instance_prepared)
	skill.release_presentation_started.connect(_on_skill_release_presentation_started)
	skill.action_requested.connect(_on_skill_action_requested)
	skill.cast_range_required.connect(_on_skill_cast_range_required)
	skill.delivery_started.connect(_on_skill_delivery_started)
	skill.skill_failed.connect(_on_skill_terminal)
	skill.skill_cancelled.connect(_on_skill_terminal)


func _disconnect_skill(skill: SkillBase) -> void:
	var connections: Array[Array] = [
		[skill.emission_finished, Callable(self, &"_on_finisher_emission_finished")],
		[skill.cast_cue_reached, Callable(self, &"_on_skill_cast_cue_reached")],
		[skill.release_instance_prepared, Callable(self, &"_on_skill_release_instance_prepared")],
		[skill.release_presentation_started, Callable(self, &"_on_skill_release_presentation_started")],
		[skill.action_requested, Callable(self, &"_on_skill_action_requested")],
		[skill.cast_range_required, Callable(self, &"_on_skill_cast_range_required")],
		[skill.delivery_started, Callable(self, &"_on_skill_delivery_started")],
		[skill.skill_failed, Callable(self, &"_on_skill_terminal")],
		[skill.skill_cancelled, Callable(self, &"_on_skill_terminal")],
	]
	for connection: Array in connections:
		var signal_value: Signal = connection[0] as Signal
		var callback: Callable = connection[1] as Callable
		if signal_value.is_connected(callback):
			signal_value.disconnect(callback)


func _on_skill_cast_cue_reached(context: SkillContext) -> void:
	if _context_matches_active(context): cast_cue_reached.emit(context)


func _on_finisher_emission_finished(context: SkillContext) -> void:
	if _context_matches_active(context) and context.purpose == SkillContext.Purpose.FINISHER:
		finisher_emission_finished.emit(context.execution_id)

func _on_skill_action_requested(
	skill: SkillBase,
	target: Node3D,
	effective_cast_time: float
) -> void:
	if skill != _active_skill:
		return
	var context: SkillContext = skill.get_current_context()
	_active_action_context = context
	facing_requested.emit(context)
	_set_movement_locked(not skill.can_move_while_casting)
	# 施法时间在 Skill 层计算完成后作为只读请求数据向外传递。
	# 动作控制器不得在播放或回调阶段反向访问 Skill、Host 或 Unit 重新读取该值。
	action_requested.emit(skill, target, effective_cast_time)


func _on_skill_cast_range_required(
	context: SkillContext,
	required_range: float
) -> void:
	if is_instance_valid(_active_skill):
		_active_action_context = context
		approach_requested.emit(context, required_range)


func _on_skill_delivery_started(context: SkillContext) -> void:
	if not _context_matches_active(context): return
	skill_released.emit(context)
	if context.purpose == SkillContext.Purpose.CHAIN:
		command_state_changed.emit()
		return
	if not _use_external_global_cooldown:
		start_global_cooldown()


func _on_skill_terminal(
	_context: SkillContext,
	_reason: StringName
) -> void:
	if not _context_matches_active(_context): return
	if _context.purpose == SkillContext.Purpose.FINISHER:
		var skill := get_active_skill()
		if skill != null: skill.stop_pending_emission(_context.execution_id)
		if not _context_matches_active(_context): return
		_release_active_skill()
		finisher_action_cancelled.emit(_context, _reason)
		return
	if _context.command_request != null:
		if _cancelling_command_id == _context.command_request.request_id: return
		if not _context.command_request.has_released():
			cancel_command(_context.command_request.request_id, _reason)
		return
	if is_instance_valid(_active_skill) and _active_skill.get_state() not in [SkillBase.SkillState.QUEUED, SkillBase.SkillState.ACTION_REQUESTED, SkillBase.SkillState.CASTING]:
		_release_active_skill()


func _release_active_skill(preserve_terminal: bool = false) -> void:
	_clear_motion_action(preserve_terminal)
	_active_skill = null
	_pending_context = null
	_active_action_context = null
	_set_movement_locked(false)
	active_skill_changed.emit(null)


func _set_movement_locked(locked: bool) -> void:
	if _movement_locked == locked:
		return
	_movement_locked = locked
	movement_lock_requested.emit(locked)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if get_node_or_null(^"SkillSocket") == null:
		warnings.append("SkillHostComponent requires its fixed SkillSocket child.")
	var ids: Dictionary = {}
	var socket := get_node_or_null(^"SkillSocket")
	if socket != null:
		for child: Node in socket.get_children():
			if not child is SkillBase:
				continue
			var id: StringName = (child as SkillBase).skill_id
			if ids.has(id):
				warnings.append("技能 ID %s 重复；请为每个技能设置唯一 ID。" % String(id))
			else:
				ids[id] = child
	var seen: Array[SkillBase] = []
	for slot_index: int in range(regular_skills.size()):
		var skill: SkillBase = regular_skills[slot_index]
		if skill == null:
			continue
		if not _is_slot_skill_structurally_valid(skill):
			warnings.append("常规槽 %d 引用了非本 SkillSocket 的技能；请清空或重新选择本单位技能。" % slot_index)
			continue
		if ids.get(skill.skill_id) != skill:
			warnings.append("常规槽 %d 的技能 ID %s 与其他技能重复，运行时无法注册；请修改技能 ID。" % [slot_index, String(skill.skill_id)])
			continue
		if skill in seen:
			warnings.append("常规槽 %d 重复引用同一技能；请改选其他技能或留空。" % slot_index)
			continue
		seen.append(skill)
	if finisher_skill != null:
		if not _is_slot_skill_structurally_valid(finisher_skill):
			warnings.append("终结技槽引用了非本 SkillSocket 的技能；请清空或重新选择本单位技能。")
		elif ids.get(finisher_skill.skill_id) != finisher_skill:
			warnings.append("终结技槽的技能 ID %s 与其他技能重复，运行时无法注册；请修改技能 ID。" % String(finisher_skill.skill_id))
		elif finisher_skill in seen:
			warnings.append("终结技槽与常规槽重复引用同一技能；请改选其他技能或留空。")
	if is_instance_valid(combo_skill):
		if not _is_slot_skill_structurally_valid(combo_skill):
			warnings.append("连携槽必须引用本SkillSocket中的技能。")
		elif ids.get(combo_skill.skill_id) != combo_skill:
			warnings.append("连携槽技能ID重复或为空，无法注册。")
		elif combo_skill in regular_skills or combo_skill == finisher_skill:
			warnings.append("连携槽不能与常规或终结槽引用同一实例。")
		elif combo_skill.get_combo_focus_cost() == null:
			warnings.append("连携技能须挂一个直接ComboFocusCost，费用必须有限非负。")
	return warnings


func _exit_tree() -> void:
	_clear_motion_action()
	_cancel_all_commands(&"host_exiting")
	_action_state_provider = null
	for skill_value: Variant in _registered_skills.duplicate():
		if not is_instance_valid(skill_value):
			continue
		var skill := skill_value as SkillBase
		if skill != null and not skill.is_queued_for_deletion():
			_disconnect_skill(skill)
	_registered_skills.clear()
	_active_skill = null
	_target_candidate_provider = null

func _presentation_registered(presentation: SkillPresentationContext) -> bool:
	if presentation == null or presentation.get_world() == null: return false
	for skill in _registered_skills:
		if is_instance_valid(skill) and skill.get_instance_id() == presentation.skill_instance_id: return true
	return false

func _on_skill_release_instance_prepared(presentation: SkillPresentationContext, instance: Node) -> void:
	if _presentation_registered(presentation): release_instance_prepared.emit(presentation, instance)

func _on_skill_release_presentation_started(presentation: SkillPresentationContext) -> void:
	if _presentation_registered(presentation): release_presentation_started.emit(presentation)