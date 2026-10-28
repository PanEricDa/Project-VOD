
@tool
class_name SquadChainCommandController
extends Node
## 关卡级伙伴指令与专注事务；不控制动画/导航、不定义连携窗口或评分，无全局单例。
@export_category("Assembly")
## 固定四个伙伴引用，索引0—3对应1—4；默认四空槽，不压缩空位，重复或跨绑定世界不可用。
@export var companions: Array[AllyBase] = [null, null, null, null]
## 本世界唯一专注组件，默认空；世界/队伍从该组件读取，不配置第二份玩家引用。
@export var focus_source: SquadFocusComponent
@export_category("Commands")
## 全队连携输入等待上一条命令的施法提示；默认关闭以兼容旧场景，正式战斗开启。
## 提示时点复用技能cast_effect_start_ratio；仅限制新连携输入，不影响Q/E、AI、评分或已受理动作。
@export var wait_for_cast_cue: bool = false:
	set(value):
		if wait_for_cast_cue == value: return
		wait_for_cast_cue = value
		_awaiting_cast_cue_request_id = 0
		if is_inside_tree() and not Engine.is_editor_hint(): _notify_slots()
## 从受理到动画真正开始的最长等待秒数，默认8；有限正数，含旧动作/接近，换目标不重置。
@export_range(0.1, 60.0, 0.1, "or_greater") var command_wait_timeout_seconds: float = 8.0
## 根请求受理通知；尚未开始动作，订阅者不能据此认为已经扣费/命中。
signal command_accepted(request: SkillCommandRequest)
## 受理拒绝，slot_index固定0—3，reason为短诊断键，不产生新承诺。
signal command_rejected(slot_index: int, reason: StringName)
## 根交付接受并成功提交费用；request_id正身份，final_cost为实际专注点，不包含子交付。
signal command_released(request_id: int, final_cost: float)
## 根动作和全部根/子交付结束后的清理通知，round_id是原归属，不决定伤害窗口关闭。
signal command_lifetime_finished(request_id: int, round_id: int)
## 此轮仍拥有动作/交付的根请求数；acquire后拒绝也通知0，供轮次所有者回收未开窗空批次。
signal request_activity_changed(round_id: int, live_requests: int)
## 某固定槽只读反馈变化，slot_index不压缩；UI不得计算/修改账目。
signal slot_status_changed(slot_index: int)

## 本槽实际开始施法，presentation只读，不能据此再次扣费。
signal command_started(slot_index: int, presentation: SkillPresentationContext)
## 释放前失败，slot_index固定0—3，request_id原身份；不会对已释放的打空发失败。
signal command_failed(slot_index: int, request_id: int, reason: StringName)
## 本槽根释放的纯表现实例准备；instance尚未进树。
signal command_release_instance_prepared(slot_index: int, presentation: SkillPresentationContext, instance: Node)
## 本槽根释放各通道已启动；供表现协调，不表示伤害结束。
signal command_release_presentation_started(slot_index: int, presentation: SkillPresentationContext)
## 世界解绑先通知null，绑定完成后通知新世界，消费者不得改变指令归属。
signal scope_changed(scope_root: Node)

# 0开放、-1受理事务进行中、正数为等待提示的原请求身份；不导出内部状态。
var _awaiting_cast_cue_request_id: int = 0
var _ledger := ComboCostLedger.new()
var _records: Dictionary = {}
var _generation: int = 0
var _scope: Node
var _player: PlayerBase
var _focus_ref: WeakRef
var _host_connections: Array[Dictionary] = []
var _peek_round: Callable
var _acquire_round: Callable
var _input_enabled: bool = true
var _input_blocks: Dictionary = {}
var _next_input_block: int = 1
var _configuration_signature: Array = []
var _status_signatures: Array = [{}, {}, {}, {}]
var _last_acquired_round: int = 0
var _clearing: bool = false
var _presentation_pause_ref: WeakRef
var _original_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or event.is_echo(): return
	if get_tree().paused and not _accent_input_allowed(): return
	for slot in range(4):
		if event.is_action_pressed(StringName("squad_chain_%d" % (slot + 1))):
			if submit_slot(slot): get_viewport().set_input_as_handled()
			return

func _ready() -> void:
	if Engine.is_editor_hint(): return
	_refresh_configuration()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	_refresh_configuration()
	for index in range(4):
		var status := get_slot_status(index)
		if status != _status_signatures[index]:
			_status_signatures[index] = status
			slot_status_changed.emit(index)

## 停止接收新输入，但不取消已受理动作/缓存；enabled不是Inspector的额外开关。
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	_notify_slots()

## 同绑定世界owner申请新战斗输入阻断，reason为诊断键；失败返回0。不撤销已受理请求。
## 同步持有玩家通用输入许可，供选择/演出隔离新Q/E、移动、攻击和锁定；不修改原基础开关。
@warning_ignore("shadowed_variable_base_class")
func acquire_input_block(owner: Node, reason: StringName) -> int:
	if not _valid_input_owner(owner): return 0
	var token := _next_input_block
	_next_input_block += 1
	var player_token := _player.acquire_input_block(owner,reason) if is_instance_valid(_player) else 0
	_input_blocks[token] = {"owner":weakref(owner),"reason":reason,"player":weakref(_player) if is_instance_valid(_player) else null,"player_token":player_token}
	_notify_slots()
	return token

## 幂等释放本方输入token；不修改set_input_enabled原开关，不影响其他持有者。
func release_input_block(token: int) -> void:
	if not _input_blocks.has(token): return
	var record: Dictionary = _input_blocks[token]
	_input_blocks.erase(token)
	var player = record.player.get_ref() if record.player != null else null
	if is_instance_valid(player): player.release_input_block(record.player_token)
	_notify_slots()

@warning_ignore("shadowed_variable_base_class")
func _valid_input_owner(owner: Node) -> bool:
	return is_instance_valid(_scope) and is_instance_valid(owner) and owner.is_inside_tree() and not owner.is_queued_for_deletion() and (owner == _scope or _scope.is_ancestor_of(owner))

func _has_input_block() -> bool:
	for token in _input_blocks.keys():
		if not _valid_input_owner(_input_blocks[token].owner.get_ref()): release_input_block(token)
	return not _input_blocks.is_empty()

## 注入轮次所有者的无参数int回调；peek仅查询（0=尚无批次），acquire用于真实受理且返回正单调身份。
## 两者缺失时失败关闭，不能让UI刷新分配轮次；切换回调不取消已受理旧请求。
func set_round_source(peek_current: Callable, acquire_for_request: Callable) -> void:
	_peek_round = peek_current
	_acquire_round = acquire_for_request
	_notify_slots()

## 仅当两个回调均与当前提供者一致时撤销；过期所有者不得清除新提供者，不取消原请求。
func clear_round_source(peek_current: Callable, acquire_for_request: Callable) -> void:
	if _peek_round != peek_current or _acquire_round != acquire_for_request: return
	_peek_round = Callable()
	_acquire_round = Callable()
	_notify_slots()

## 四项数字身份必须匹配仍存活且已经成功释放、未失败的请求；不返回内部记录或依赖角色节点存活。
func is_released_request(request_id: int, round_id: int, caster_instance_id: int, scene_scope_id: int) -> bool:
	if not _records.has(request_id): return false
	var record: Dictionary = _records[request_id]
	var request: SkillCommandRequest = record.request
	return record.released and not record.failed and request.round_id == round_id and request.caster_instance_id == caster_instance_id and request.scene_scope_id == scene_scope_id

## 轮次所有者关闭单调费用批次；已经受理的旧动作和交付继续，不取消Host缓存。
func close_round(round_id: int) -> void:
	_ledger.close_round(round_id)
	_notify_slots()

## 显式受理固定槽0—3；true仅表示已预留并缓存，执行由行为层下一物理帧开始。
func submit_slot(slot_index: int) -> bool:
	_refresh_configuration()
	var admission_generation := _generation
	var pool := focus_source
	var owner_ledger := _ledger
	var world := _scope
	var status := get_slot_status(slot_index)
	if not status.can_submit: return _reject(slot_index, status.reason)
	# 先关闭输入再进入会同步发通知的费用事务，避免同帧/同步监听器重入预约。
	if wait_for_cast_cue: _awaiting_cast_cue_request_id = -1
	var accepted := _submit_ready_slot(slot_index, admission_generation, pool, owner_ledger, world)
	if not accepted and _awaiting_cast_cue_request_id == -1:
		_release_cast_cue_gate(-1)
	return accepted

func _submit_ready_slot(slot_index: int, admission_generation: int, pool: SquadFocusComponent, owner_ledger: ComboCostLedger, world: Node) -> bool:
	if not _admission_is_current(admission_generation, pool, owner_ledger, world): return _reject(slot_index, &"admission_invalidated")
	var actor := companions[slot_index]
	var host := actor.get_node_or_null(^"SkillHost") as SkillHostComponent
	var skill := host.get_combo_skill()
	var preferred := _player.get_locked_target()
	if host.prepare_command_context(preferred) == null: return _reject(slot_index, &"target_or_condition_invalid")
	if not _admission_is_current(admission_generation, pool, owner_ledger, world): return _reject(slot_index, &"admission_invalidated")
	var round_value: Variant = _acquire_round.call()
	if not (round_value is int) or int(round_value) <= 0 or int(round_value) < _last_acquired_round:
		return _reject(slot_index, &"round_source_invalid")
	var batch: int = round_value
	if not _admission_is_current(admission_generation, pool, owner_ledger, world):
		_notify_activity(batch)
		return _reject(slot_index, &"admission_invalidated")
	_last_acquired_round = batch
	var id := CombatDamageContext.allocate_id()
	var cost := skill.get_combo_focus_cost()
	if cost == null or not owner_ledger.register_request(id, batch, actor.get_instance_id(), skill.skill_id, cost.base_focus_cost, cost.repeat_focus_cost):
		_notify_activity(batch)
		return _reject(slot_index, &"round_or_cost_invalid")
	var amount := owner_ledger.get_reservation_quote(id)
	if amount < 0.0 or not pool.reserve(id, amount):
		_rollback_admission(id, batch, pool, owner_ledger)
		return _reject(slot_index, &"insufficient_focus")
	if not _admission_is_current(admission_generation, pool, owner_ledger, world) or not pool.can_commit(id, amount):
		_rollback_admission(id, batch, pool, owner_ledger)
		return _reject(slot_index, &"admission_invalidated")
	var request := SkillCommandRequest.create(id, batch, actor, skill, world, command_wait_timeout_seconds, _authorize_release.bind(id, admission_generation))
	if request == null:
		_rollback_admission(id, batch, pool, owner_ledger)
		return _reject(slot_index, &"request_invalid")
	_records[id] = {"request": request, "host": weakref(host), "slot": slot_index, "reserved": amount, "released": false, "failed": false}
	request.lifetime_finished.connect(_on_lifetime_finished.bind(admission_generation))
	if wait_for_cast_cue and _awaiting_cast_cue_request_id == -1: _awaiting_cast_cue_request_id = id
	if not host.enqueue_command(request):
		_fail_record(id, &"host_rejected")
		return _reject(slot_index, &"host_rejected")
	if not _admission_is_current(admission_generation, pool, owner_ledger, world, false) or not _records.has(id) or request.has_failed():
		return _reject(slot_index, &"admission_invalidated")
	command_accepted.emit(request)
	_notify_activity(batch)
	_notify_slots()
	return true

# 外部同步回调后仍属于原会话，不能把旧受理移入新世界/新账本。
# check_input仅用于入队前；Host已受理后的输入禁用不撤销既有请求。
func _admission_is_current(generation: int, pool: SquadFocusComponent, owner_ledger: ComboCostLedger, world: Node, check_input: bool = true) -> bool:
	return generation == _generation and pool == focus_source and owner_ledger == _ledger and is_instance_valid(world) and world == _scope and is_instance_valid(pool) and not pool.is_queued_for_deletion() and pool.get_bound_scope() == world and (not check_input or _input_reason() == &"")

# 回滚只操作原事务所有者；全局唯一ID不会误退款到重绑后的其他请求。
func _rollback_admission(id: int, batch: int, pool: SquadFocusComponent, owner_ledger: ComboCostLedger) -> void:
	owner_ledger.mark_failed(id)
	if is_instance_valid(pool):
		pool.refund(id)
		pool.release_request(id)
	owner_ledger.release_request(id)
	_notify_activity(batch)

## 返回只读值副本；不选择/随机化目标、不登记试算请求，不提供内部Record给UI。
func get_slot_status(slot_index: int) -> Dictionary:
	var status := {"can_submit": false, "reason": &"slot_invalid", "phase": &"idle", "actor_name": "", "skill_name": "", "icon": null, "estimated_cost": -1.0, "active_request_id": 0, "pending_request_id": 0}
	if slot_index < 0 or slot_index >= 4 or companions.size() != 4: return status
	var actor := companions[slot_index]
	if not is_instance_valid(actor) or actor.is_queued_for_deletion():
		status.reason = &"companion_missing"
		return status
	status.actor_name = String(actor.name)
	var host := actor.get_node_or_null(^"SkillHost") as SkillHostComponent
	if host == null:
		status.reason = &"host_missing"
		return status
	status.phase = host.get_command_phase()
	status.active_request_id = host.get_active_command_id()
	status.pending_request_id = host.get_pending_command_id()
	var skill := host.get_combo_skill()
	if skill == null:
		status.reason = &"skill_configuration_invalid"
		return status
	status.skill_name = skill.display_name
	status.icon = skill.icon
	var cost := skill.get_combo_focus_cost()
	status.estimated_cost = cost.base_focus_cost
	var input_reason := _input_reason()
	if input_reason != &"":
		status.reason = input_reason
		return status
	if wait_for_cast_cue and _awaiting_cast_cue_request_id != 0:
		status.reason = &"chain_cue_pending"
		return status
	if companions.count(actor) > 1 or not focus_source.is_party_member(actor) or actor.team_id != _player.team_id:
		status.reason = &"companion_binding_invalid"
		return status
	if actor.is_dead() or not host.is_skill_casting_enabled() or host.is_cast_blocked():
		status.reason = &"cast_unavailable"
		return status
	if not _peek_round.is_valid() or not _acquire_round.is_valid():
		status.reason = &"round_source_missing"
		return status
	var batch: Variant = _peek_round.call()
	if not (batch is int) or int(batch) < 0:
		status.reason = &"round_source_invalid"
		return status
	if int(batch) > 0:
		status.estimated_cost = _ledger.preview_reservation_quote(batch, actor.get_instance_id(), skill.skill_id, cost.base_focus_cost, cost.repeat_focus_cost)
	if status.estimated_cost < 0.0:
		status.reason = &"round_closed"
		return status
	if host.has_pending_command():
		status.reason = &"pending_full"
		return status
	if focus_source.get_available_focus() < status.estimated_cost:
		status.reason = &"insufficient_focus"
		return status
	if not is_finite(command_wait_timeout_seconds) or command_wait_timeout_seconds <= 0.0:
		status.reason = &"timeout_invalid"
		return status
	status.can_submit = true
	status.reason = &""
	return status

func _input_reason() -> StringName:
	if _clearing or not is_instance_valid(_scope) or not is_instance_valid(focus_source) or focus_source.get_bound_scope() != _scope: return &"focus_unbound"
	if not is_inside_tree() or (get_tree().paused and not _accent_input_allowed()) or not _input_enabled or _has_input_block(): return &"input_disabled"
	if not is_instance_valid(_player) or _player.is_dead() or not _player.is_player_input_enabled(): return &"player_unavailable"
	return &""

func _authorize_release(id: int, generation: int) -> bool:
	if generation != _generation or not _records.has(id) or _clearing or not is_instance_valid(_scope) or not is_instance_valid(focus_source) or focus_source.get_bound_scope() != _scope: return false
	var record: Dictionary = _records[id]
	if record.released or record.failed: return false
	var fee := _ledger.get_final_quote(id)
	return fee >= 0.0 and fee <= record.reserved and focus_source.can_commit(id, fee)

func _on_host_released(context: SkillContext, slot: int, generation: int) -> void:
	if generation != _generation or context.command_request == null: return
	var id := context.command_request.request_id
	if not _records.has(id): return
	var record: Dictionary = _records[id]
	if record.released or record.failed or record.request != context.command_request: return
	var fee := _ledger.mark_released(id)
	if fee < 0.0:
		push_error("连携释放顺序未通过账本校验。")
		return
	# 接受事实先记录，保证commit同步通知中的解绑不会将已接受交付当作未释放退款。
	record.released = true
	if not focus_source.commit(id, fee):
		push_error("连携已接受但专注提交失败；应由释放授权提前拒绝。")
		return
	context.command_request.mark_released()
	if generation != _generation or not _records.has(id): return
	# 真实释放是短施法/缺失表现的最终兜底；旧请求不能解除新请求的等待。
	_release_cast_cue_gate(id)
	if generation != _generation or not _records.has(id): return
	command_released.emit(id, fee)
	slot_status_changed.emit(slot)

func _on_host_failed(id: int, reason: StringName, _slot: int, generation: int) -> void:
	if generation != _generation: return
	_fail_record(id, reason)

func _fail_record(id: int, reason: StringName) -> void:
	if not _records.has(id): return
	var record: Dictionary = _records[id]
	if record.released or record.failed: return
	var failed_slot: int = record.slot
	var failed_generation := _generation
	record.failed = true
	_ledger.mark_failed(id)
	var focus = _get_attached_focus()
	if focus != null: focus.refund(id)
	record.request.mark_failed(reason)
	if _records.has(id): _notify_activity(record.request.round_id)
	if failed_generation == _generation and not _clearing:
		_release_cast_cue_gate(id)
		if failed_generation != _generation or _clearing: return
		command_failed.emit(failed_slot, id, reason)
		slot_status_changed.emit(failed_slot)

func _on_lifetime_finished(id: int, batch: int, generation: int) -> void:
	if generation != _generation or not _records.has(id): return
	var slot: int = _records[id].slot
	var focus = _get_attached_focus()
	if focus != null: focus.release_request(id)
	_ledger.release_request(id)
	_records.erase(id)
	_release_cast_cue_gate(id)
	if generation != _generation: return
	command_lifetime_finished.emit(id, batch)
	_notify_activity(batch)
	slot_status_changed.emit(slot)

func _notify_activity(batch: int) -> void:
	var count: int = 0
	for record in _records.values():
		if record.request.round_id == batch: count += 1
	request_activity_changed.emit(batch, count)

func _reject(slot: int, reason: StringName) -> bool:
	command_rejected.emit(slot, reason)
	if slot >= 0 and slot < 4: slot_status_changed.emit(slot)
	return false

func _refresh_configuration() -> void:
	var signature: Array = [focus_source.get_instance_id() if is_instance_valid(focus_source) else 0, companions.size()]
	for actor in companions: signature.append(actor.get_instance_id() if is_instance_valid(actor) else 0)
	if signature == _configuration_signature: return
	_configuration_signature = signature
	_detach_focus()
	if not is_instance_valid(focus_source): return
	_focus_ref = weakref(focus_source)
	focus_source.scope_changed.connect(_on_scope_changed)
	focus_source.focus_changed.connect(_on_focus_changed)
	_on_scope_changed(focus_source.get_bound_scope())

func _get_attached_focus() -> SquadFocusComponent:
	return _focus_ref.get_ref() as SquadFocusComponent if _focus_ref != null and is_instance_valid(_focus_ref.get_ref()) else null

func _on_scope_changed(scope_root: Node) -> void:
	_clear_scope()
	_scope = scope_root
	if not is_instance_valid(_scope): return
	var players: Array[PlayerBase] = []
	_collect_players(_scope, players)
	if players.size() == 1: _player = players[0]
	if companions.size() == 4:
		for slot in range(4):
			var actor := companions[slot]
			if not is_instance_valid(actor) or companions.count(actor) != 1 or not actor.is_inside_tree() or not _scope.is_ancestor_of(actor): continue
			var host := actor.get_node_or_null(^"SkillHost") as SkillHostComponent
			if host == null: continue
			var started := _on_host_started.bind(slot, _generation)
			var prepared := _on_host_prepared.bind(slot, _generation)
			var presented := _on_host_presented.bind(slot, _generation)
			var cue := _on_host_cast_cue.bind(slot, _generation)
			host.cast_cue_reached.connect(cue)
			host.command_action_started.connect(started)
			host.release_instance_prepared.connect(prepared)
			host.release_presentation_started.connect(presented)
			var released := _on_host_released.bind(slot, _generation)
			var failed := _on_host_failed.bind(slot, _generation)
			var changed := _on_host_state_changed.bind(slot, _generation)
			host.skill_released.connect(released)
			host.command_failed.connect(failed)
			host.command_state_changed.connect(changed)
			_host_connections.append({"host": weakref(host), "released": released, "failed": failed, "changed": changed, "started": started, "prepared": prepared, "presented": presented, "cue": cue})
	scope_changed.emit(_scope)
	_notify_slots()

func _collect_players(node: Node, players: Array[PlayerBase]) -> void:
	if node is PlayerBase: players.append(node as PlayerBase)
	for child in node.get_children(): _collect_players(child, players)

func _clear_scope() -> void:
	if _clearing: return
	_clearing = true
	for token in _input_blocks.keys(): release_input_block(token)
	_generation += 1
	_awaiting_cast_cue_request_id = 0
	_scope = null
	_player = null
	scope_changed.emit(null)
	var focus = _get_attached_focus()
	for id in _records.keys():
		var record: Dictionary = _records[id]
		var request: SkillCommandRequest = record.request
		if record.released:
			request.mark_released()
		else:
			_ledger.mark_failed(id)
			if focus != null: focus.refund(id)
			request.mark_failed(&"scope_unbound")
		var host = record.host.get_ref()
		if is_instance_valid(host): host.cancel_command(id, &"scope_unbound")
		if focus != null: focus.release_request(id)
		_ledger.release_request(id)
		_records.erase(id)
	for connection in _host_connections:
		var host = connection.host.get_ref()
		if not is_instance_valid(host): continue
		if host.cast_cue_reached.is_connected(connection.cue): host.cast_cue_reached.disconnect(connection.cue)
		if host.command_action_started.is_connected(connection.started): host.command_action_started.disconnect(connection.started)
		if host.release_instance_prepared.is_connected(connection.prepared): host.release_instance_prepared.disconnect(connection.prepared)
		if host.release_presentation_started.is_connected(connection.presented): host.release_presentation_started.disconnect(connection.presented)
		if host.skill_released.is_connected(connection.released): host.skill_released.disconnect(connection.released)
		if host.command_failed.is_connected(connection.failed): host.command_failed.disconnect(connection.failed)
		if host.command_state_changed.is_connected(connection.changed): host.command_state_changed.disconnect(connection.changed)
	_host_connections.clear()
	_ledger = ComboCostLedger.new()
	_last_acquired_round = 0
	_clearing = false
	_notify_slots()

func _detach_focus() -> void:
	_clear_scope()
	var focus = _get_attached_focus()
	if focus != null:
		if focus.scope_changed.is_connected(_on_scope_changed): focus.scope_changed.disconnect(_on_scope_changed)
		if focus.focus_changed.is_connected(_on_focus_changed): focus.focus_changed.disconnect(_on_focus_changed)
	_focus_ref = null

func _on_focus_changed(_current: float, _reserved: float, _available: float) -> void: _notify_slots()
func _on_host_state_changed(slot: int, generation: int) -> void:
	if generation == _generation: slot_status_changed.emit(slot)
func _notify_slots() -> void:
	for slot in range(4): slot_status_changed.emit(slot)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if companions.size() != 4: warnings.append("请保留四个伙伴槽，空位留空，不压缩索引。")
	if focus_source == null: warnings.append("请选择本关卡的SquadFocusComponent。")
	for actor in companions:
		if is_instance_valid(actor) and companions.count(actor) > 1: warnings.append("同一伙伴不能占用多个指令槽。")
	if not is_finite(command_wait_timeout_seconds) or command_wait_timeout_seconds <= 0.0: warnings.append("指令等待秒数必须有限且大于0。")
	return warnings

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): _detach_focus()

## 返回原指令源当前绑定世界；空表示未装配，不创建或维持新世界。
## 返回当前已绑定玩家，仅只读锁定意图；未绑定/离树返回null，不另搜索或改变玩家锁定。
func get_bound_player() -> PlayerBase:
	return _player if is_instance_valid(_player) and _player.is_inside_tree() else null

func get_bound_scope() -> Node: return _scope if is_instance_valid(_scope) else null

func _valid_presentation(presentation: SkillPresentationContext, slot: int, generation: int) -> bool:
	if generation != _generation or _clearing or presentation == null or not presentation.is_chain_root or presentation.get_world() != _scope: return false
	var id := presentation.command_request_id
	return _records.has(id) and not _records[id].failed and _records[id].slot == slot and _records[id].request.caster_instance_id == (presentation.get_source().get_instance_id() if presentation.get_source() != null else 0)

func _release_cast_cue_gate(request_id: int) -> void:
	if _awaiting_cast_cue_request_id != request_id: return
	_awaiting_cast_cue_request_id = 0
	_notify_slots()

func _on_host_cast_cue(context: SkillContext, slot: int, generation: int) -> void:
	if generation != _generation or _clearing or context == null or context.command_request == null: return
	var id := context.command_request.request_id
	if not _records.has(id): return
	var record: Dictionary = _records[id]
	if record.failed or record.request != context.command_request or record.slot != slot: return
	_release_cast_cue_gate(id)

func _on_host_started(request: SkillCommandRequest, presentation: SkillPresentationContext, slot: int, generation: int) -> void:
	if _valid_presentation(presentation, slot, generation) and _records[presentation.command_request_id].request == request:
		command_started.emit(slot, presentation)

func _on_host_prepared(presentation: SkillPresentationContext, instance: Node, slot: int, generation: int) -> void:
	if _valid_presentation(presentation, slot, generation):
		command_release_instance_prepared.emit(slot, presentation, instance)

func _on_host_presented(presentation: SkillPresentationContext, slot: int, generation: int) -> void:
	if _valid_presentation(presentation, slot, generation):
		command_release_presentation_started.emit(slot, presentation)
## 同世界装配时注入纯强调输入门禁；null恢复原process_mode，不推进Host或AI。
func set_presentation_pause_source(source: GamePauseCoordinator) -> void:
	if _presentation_pause_ref != null:
		process_mode = _original_process_mode
		_presentation_pause_ref = null
	if source == null or source.get_bound_scope() != get_bound_scope(): return
	_original_process_mode = process_mode
	_presentation_pause_ref = weakref(source)
	process_mode = Node.PROCESS_MODE_ALWAYS

## 显式/外部暂停时挂起UI保持；正常或仅强调时不挂起，未装表现遵从原树暂停。
func is_feedback_suspended() -> bool:
	var pause := _presentation_pause_source()
	return not pause.is_presentation_allowed() if pause != null else (is_inside_tree() and get_tree().paused)

func _presentation_pause_source() -> GamePauseCoordinator:
	var pause = _presentation_pause_ref.get_ref() if _presentation_pause_ref != null else null
	if not is_instance_valid(pause) or pause.get_bound_scope() != get_bound_scope(): return null
	return pause

func _accent_input_allowed() -> bool:
	var pause := _presentation_pause_source()
	return pause != null and pause.is_release_accent_only()