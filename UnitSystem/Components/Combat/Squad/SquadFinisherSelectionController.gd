@tool
class_name SquadFinisherSelectionController
extends Node
## 连携闭窗达分后的终结选择接口；只发布选择与日志，不执行技能。
enum Phase { CLOSED, OPENING, SELECTING, CONFIRMED, CLOSING }
@export_category("Assembly")
## 本世界评价源，默认空；四伙伴与指令源沿此引用取得，不重配角色或评分。
@export var round_source: SquadChainRoundController
## 本世界已有暂停协调器，默认空；选择只申请慢速，不新建协调器或解除他人暂停。
@export var pause_source: GamePauseCoordinator
@export_category("Selection")
## 选择时限，单位真实秒，默认3；正有限数，从弹出开始计时，显式暂停期间挂起。
@export_range(0.1,30.0,0.1,"or_greater") var selection_duration_seconds: float = 3.0
## 选择期间绝对速度上限，默认0.05即正常速度5%；须0<值<=1，不影响UI真实时钟。
@export_range(0.001,1.0,0.001) var selection_time_scale: float = 0.05
## snapshot为深复制纯值状态；显示只读，不包含单位或技能实例。
signal selection_state_changed(snapshot: Dictionary)
## selection含原世界/轮次、固定槽0—3、角色数字身份及冻结finisher_multiplier；接收方须复查角色和窗口身份。
## 玩家输入在松开确认后的既有绿色反馈结束时通知；程序化try_select_slot保持直接确认。
signal finisher_selected(selection: Dictionary)
## result为一次窗口的最终原因与原身份；每次最多一次，不储存资格。
signal selection_closed(result: Dictionary)

const Interaction = preload("res://UnitSystem/Components/Input/PressReleaseInputComponent.gd")
const INTERACTION_SCENE: PackedScene = preload("res://UnitSystem/Components/Input/PressReleaseInputComponent.tscn")
const OWNER: StringName = &"_finisher_selection_owner"
const ENTER_SECONDS: float = 0.12
const HOLD_SECONDS: float = 0.12
const EXIT_SECONDS: float = 0.10
var _execution_provider: WeakRef
var _execution_expected: bool = false
var _round_ref: WeakRef
var _pause_ref: WeakRef
var _command_ref: WeakRef
var _scope_ref: WeakRef
var _phase: Phase = Phase.CLOSED
var _generation: int = 0
var _seen_round: int = 0
var _round_id: int = 0
var _scene_id: int = 0
var _duration: float = 0.0
var _elapsed: float = 0.0
var _phase_elapsed: float = 0.0
var _last_usec: int = 0
var _clock_allowed: bool = false
var _selected_slot: int = -1
# 从本轮真实闭窗结果捕获；窗口内不重读后续评分，关闭即恢复1倍。
var _finisher_multiplier: float = 1.0
# 按住的原固定槽；仅表示输入反馈，尚未提交终结技。确认值只含原轮次/角色数字身份。
var _interaction: Interaction
var _pressed_slot: int:
	get: return _interaction.get_pressed_slot() if is_instance_valid(_interaction) else -1
var _pending_selection: Dictionary = {}
var _slow_token: int = 0
var _block_token: int = 0
var _end_reason: StringName = &""
var _end_detail: StringName = &""
var _detaching: bool = false
var _warned_duplicate: bool = false
var _held: Array[bool] = [false,false,false,false]
var _tail: Array[bool] = [false,false,false,false]

func _ready() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_interaction = get_node_or_null("PressReleaseInputComponent") as Interaction
	# 场景与程序化new都使用同一模板；本控制器仍拥有InputMap归属和角色资格。
	if _interaction == null:
		_interaction = INTERACTION_SCENE.instantiate() as Interaction
		add_child(_interaction)
	_refresh_binding()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_held.fill(false)
		_tail.fill(false)
		_clear_slot_press()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	for index in range(4):
		var action := StringName("squad_chain_%d" % (index+1))
		if not event.is_action(action): continue
		var owned_on_entry := _phase != Phase.CLOSED or _tail[index]
		if owned_on_entry: get_viewport().set_input_as_handled()
		if event.is_action_released(action):
			_held[index] = false
			_tail[index] = false
		_refresh_binding()
		if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return
		_sample_clock()
		if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return
		if not owned_on_entry and _phase == Phase.CLOSED and not _tail[index]: return
		get_viewport().set_input_as_handled()
		if event.is_action_pressed(action) and not event.is_echo():
			if _held[index]: return
			_held[index] = true
			_tail[index] = true
			_begin_slot_press(index)
		elif event.is_action_released(action):
			_end_slot_press(index)
		return

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	_refresh_binding()
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return
	_sample_clock()
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return
	if _phase == Phase.CLOSED: return
	if _phase in [Phase.OPENING,Phase.SELECTING] and not _slots().any(func(slot: Dictionary): return slot.available):
		_complete(&"no_available")
		return
	if _pressed_slot >= 0:
		var slot := _slots()[_pressed_slot]
		if not slot.available or not _interaction.matches_selection(_pressed_slot,slot.actor_instance_id): _clear_slot_press()
	_publish()

## 返回只读深复制快照；查询不分配轮次、不改倒计时、不改变战斗。
## pressed_slot为按住预选槽，selected_slot为已确认槽；两者使用固定0—3，-1表示无选择。
func get_selection_status() -> Dictionary:
	return {"phase":_phase,"scene_scope_id":_scene_id,"round_id":_round_id,
		"remaining_seconds":maxf(_duration-_elapsed,0.0),"duration_seconds":_duration,
		"progress_ratio":clampf((_duration-_elapsed)/_duration,0,1) if _duration > 0 else 0.0,
		"selected_slot":_selected_slot,"pressed_slot":_pressed_slot,"finisher_multiplier":_finisher_multiplier,
		"presentation_elapsed_seconds":_phase_elapsed,
		"interaction_allowed":_can_interact(),"slots":_slots()}.duplicate(true)

## slot_index为原固定0—3槽；程序化确认接口，成功直接通知一次，不施法或收费。
## 玩家InputMap按下只预选，按住不自动确认；松开同一键后，先完成绿色反馈再通知执行订阅者。
func try_select_slot(slot_index: int) -> bool:
	return _confirm_slot(slot_index, false)

func _begin_slot_press(slot_index: int) -> void:
	if not _can_interact() or _pressed_slot >= 0: return
	var slot := _slots()[slot_index]
	if not slot.available: return
	if not _interaction.begin_press(slot_index,slot.actor_instance_id): return
	_publish()

func _end_slot_press(slot_index: int) -> void:
	if _pressed_slot != slot_index: return
	var same_actor := _interaction.end_press(slot_index,_slots()[slot_index].actor_instance_id)
	if same_actor and _confirm_slot(slot_index, true): return
	if is_instance_valid(self) and not is_queued_for_deletion() and is_inside_tree(): _publish()

func _clear_slot_press() -> void:
	if is_instance_valid(_interaction): _interaction.cancel_selection()


func _confirm_slot(slot_index: int, wait_for_feedback: bool) -> bool:
	_refresh_binding()
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return false
	_sample_clock()
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return false
	if not _can_interact() or slot_index < 0 or slot_index >= 4: return false
	return _commit_slot_selection(slot_index, wait_for_feedback)

func _commit_slot_selection(slot_index: int, wait_for_feedback: bool) -> bool:
	if _phase not in [Phase.OPENING,Phase.SELECTING] or _elapsed >= _duration or slot_index < 0 or slot_index >= 4: return false
	var slots := _slots()
	if not slots[slot_index].available: return false
	_phase = Phase.CONFIRMED
	_phase_elapsed = 0.0
	_selected_slot = slot_index
	_clear_slot_press()
	_end_reason = &"selected"
	var selection := {"scene_scope_id":_scene_id,"round_id":_round_id,"slot_index":slot_index,
		"actor_instance_id":slots[slot_index].actor_instance_id,"actor_name":slots[slot_index].actor_name,
		"finisher_multiplier":_finisher_multiplier}
	if wait_for_feedback:
		_pending_selection = selection
		_publish()
	else:
		_dispatch_selection(selection)
	return true

func _dispatch_selection(selection: Dictionary) -> void:
	print("[FinisherSelection] 选择终结技 slot=",selection.slot_index+1," actor=",selection.actor_name," round=",selection.round_id)
	var generation := _generation
	finisher_selected.emit(selection.duplicate(true))
	if is_instance_valid(self) and not is_queued_for_deletion() and is_inside_tree() and generation == _generation: _publish()

## reason为诊断键；立即幂等取消并释放本方慢速/输入，异常清理不等待UI。
func cancel_selection(reason: StringName) -> void:
	if _phase != Phase.CLOSED: _complete(&"cancelled",reason)

## 可选实际执行者，只须get_actor_availability接口；首次绑定后缺失将灰显，不退回占位可用性。
## 纯选择接口预览从未配置此接口时保持原行为；拒绝覆盖另一个仍有效的执行者。
func set_execution_provider(provider: Node) -> bool:
	var current := _node(_execution_provider)
	if provider == null: return false
	if current != null and current != provider: return false
	if not provider.has_method("get_actor_availability"): return false
	_execution_provider = weakref(provider)
	_execution_expected = true
	return true

## 只有当前执行者可解除自己的登记；保留实际执行需求，避免卸载后显示可释放的假选项。
func clear_execution_provider(provider: Node) -> void:
	if _node(_execution_provider) == provider: _execution_provider = null

## 实际执行已先取得慢速/输入持有后，立即以selected关闭窗口；不闪回普通速度，不重复选择。
func complete_execution_handoff() -> void:
	if _phase == Phase.CONFIRMED: _complete(&"selected")

func _can_interact() -> bool:
	var pause := _pause()
	return _phase in [Phase.OPENING,Phase.SELECTING] and pause != null and pause.is_presentation_allowed() and _elapsed < _duration

func _refresh_binding() -> void:
	if _detaching: return
	var source := round_source if is_instance_valid(round_source) and round_source.is_inside_tree() and not round_source.is_queued_for_deletion() else null
	var pause := pause_source if is_instance_valid(pause_source) and pause_source.is_inside_tree() and not pause_source.is_queued_for_deletion() else null
	var command := source.command_source if source != null and is_instance_valid(source.command_source) else null
	var scope := command.get_bound_scope() if command != null else null
	if source == _round() and pause == _pause() and command == _command() and scope == _scope() and scope != null: return
	_detach()
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return
	if source == null or pause == null or scope == null or not scope.is_ancestor_of(self) or not scope.is_ancestor_of(source) or pause.get_bound_scope() != scope: return
	var holder = source.get_meta(OWNER) if source.has_meta(OWNER) else null
	if holder is WeakRef and is_instance_valid(holder.get_ref()) and holder.get_ref() != self:
		if not _warned_duplicate:
			_warned_duplicate = true
			push_warning("同一评价源只允许一个终结选择控制器。")
		return
	_round_ref = weakref(source)
	_pause_ref = weakref(pause)
	_command_ref = weakref(command)
	_scope_ref = weakref(scope)
	source.set_meta(OWNER,weakref(self))
	source.finisher_qualified.connect(_on_qualified)
	source.tree_exiting.connect(_on_dependency_exiting)
	pause.tree_exiting.connect(_on_dependency_exiting)
	pause.pause_state_changed.connect(_on_pause_changed)
	command.scope_changed.connect(_on_scope_changed)
	_last_usec = Time.get_ticks_usec()
	_clock_allowed = pause.is_presentation_allowed()

func _on_qualified(result: Dictionary) -> void:
	var source := _round()
	var scope := _scope()
	if _detaching or is_queued_for_deletion() or source == null or scope == null or not result.get("qualified",false): return
	var id: int = result.get("round_id",0)
	var last: Dictionary = source.get_round_status().last_result
	if id <= _seen_round or id <= 0 or result.get("scene_scope_id",0) != scope.get_instance_id() or last.get("round_id",0) != id or not last.get("qualified",false): return
	_seen_round = id
	if _phase != Phase.CLOSED: return
	if not is_finite(selection_duration_seconds) or selection_duration_seconds <= 0 or not is_finite(selection_time_scale) or selection_time_scale <= 0 or selection_time_scale > 1: return
	_round_id = id
	_finisher_multiplier = float(last.get("finisher_multiplier",1.0))
	_scene_id = scope.get_instance_id()
	_duration = selection_duration_seconds
	_elapsed = 0.0
	_phase_elapsed = 0.0
	_selected_slot = -1
	_clear_slot_press()
	_pending_selection.clear()
	_end_reason = &""
	_end_detail = &""
	_phase = Phase.OPENING
	if not _slots().any(func(slot: Dictionary): return slot.available):
		_complete(&"no_available")
		return
	var pause := _pause()
	var command := _command()
	var generation := _generation
	var slow := pause.acquire_time_scale(self,selection_time_scale,&"finisher_selection")
	_slow_token = slow
	var block := command.acquire_input_block(self,&"finisher_selection")
	# 申请会同步发布槽状态，监听者可能已取消、重绑或卸载；未登记返回值也必须回滚。
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree() or generation != _generation or _phase != Phase.OPENING or _pause() != pause or _command() != command:
		if is_instance_valid(command): command.release_input_block(block)
		if is_instance_valid(pause): pause.release_time_scale(slow)
		return
	_block_token = block
	if slow == 0 or block == 0:
		_complete(&"cancelled",&"ownership_unavailable")
		return
	_last_usec = Time.get_ticks_usec()
	_clock_allowed = _pause().is_presentation_allowed()
	for index in range(4):
		_held[index] = Input.is_action_pressed(StringName("squad_chain_%d" % (index+1)))
		_tail[index] = _held[index]
	print("[FinisherSelection] 打开终结选择 round=",id," duration=",_duration)
	_publish()

func _sample_clock() -> void:
	var now := Time.get_ticks_usec()
	var seconds := maxf(float(now-_last_usec)/1000000.0,0.0) if _last_usec > 0 else 0.0
	_last_usec = now
	if _phase == Phase.CLOSED: return
	if _clock_allowed: _advance(seconds)
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return
	var pause := _pause()
	_clock_allowed = pause != null and pause.is_presentation_allowed()

func _advance(seconds: float) -> void:
	_phase_elapsed += seconds
	if _phase in [Phase.OPENING,Phase.SELECTING]:
		_elapsed += seconds
		if _elapsed >= _duration:
			_phase = Phase.CLOSING
			_phase_elapsed = maxf(_elapsed-_duration,0)
			_end_reason = &"timeout"
			_clear_slot_press()
			print("[FinisherSelection] 超时放弃 round=",_round_id)
		elif _phase == Phase.OPENING and _phase_elapsed >= ENTER_SECONDS:
			_phase = Phase.SELECTING
			_phase_elapsed = 0
	elif _phase == Phase.CONFIRMED and _phase_elapsed >= HOLD_SECONDS:
		# 暂停通知会补算暂停前的合法间隔，但绝不能在当前已暂停时交接演出。
		var pause := _pause()
		if pause == null or not pause.is_presentation_allowed(): return
		if not _pending_selection.is_empty():
			var selection := _pending_selection
			_pending_selection = {}
			var slot := int(selection.slot_index)
			var current := _slots()[slot]
			if not current.available or current.actor_instance_id != selection.actor_instance_id:
				_complete(&"cancelled",&"selected_unavailable")
				return
			var generation := _generation
			_dispatch_selection(selection)
			if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return
			if generation != _generation or _phase != Phase.CONFIRMED or _round_id != selection.round_id: return
		_phase = Phase.CLOSING
		_phase_elapsed -= HOLD_SECONDS
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return
	if _phase == Phase.CLOSING and _phase_elapsed >= EXIT_SECONDS: _complete(_end_reason,_end_detail)

func _on_pause_changed(_battle_paused: bool, presentation_allowed: bool) -> void:
	_sample_clock()
	if not is_instance_valid(self) or is_queued_for_deletion(): return
	_clock_allowed = presentation_allowed
	if not presentation_allowed: _clear_slot_press()

func _slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var source := _command()
	var scope := _scope()
	for index in range(4):
		var actor: AllyBase = source.companions[index] if source != null and index < source.companions.size() and is_instance_valid(source.companions[index]) else null
		var reason: StringName = &""
		if actor == null: reason = &"missing"
		elif not actor.is_inside_tree() or actor.is_queued_for_deletion() or scope == null or not scope.is_ancestor_of(actor): reason = &"wrong_scope"
		elif source.companions.count(actor) > 1: reason = &"duplicate"
		elif actor.is_dead(): reason = &"dead"
		if reason == &"" and _execution_expected:
			var provider := _node(_execution_provider)
			reason = provider.call("get_actor_availability", actor) if provider != null else &"execution_unavailable"
		slots.append({"slot_index":index,"actor_instance_id":actor.get_instance_id() if actor != null else 0,
			"actor_name":String(actor.name) if actor != null else "未配置","available":reason == &"","reason":reason})
	return slots

func _complete(reason: StringName, detail: StringName = &"") -> void:
	if _phase == Phase.CLOSED: return
	var result := {"scene_scope_id":_scene_id,"round_id":_round_id,"reason":reason,"detail":detail,"selected_slot":_selected_slot}
	_phase = Phase.CLOSED
	_round_id = 0
	_finisher_multiplier = 1.0
	_scene_id = 0
	_elapsed = 0
	_duration = 0
	_phase_elapsed = 0
	_selected_slot = -1
	_clear_slot_press()
	_pending_selection.clear()
	_release_holds()
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree(): return
	if reason != &"selected" and reason != &"timeout": print("[FinisherSelection] 关闭 reason=",reason," detail=",detail)
	var generation := _generation
	selection_closed.emit(result.duplicate(true))
	if is_instance_valid(self) and not is_queued_for_deletion() and is_inside_tree() and generation == _generation: _publish()

func _release_holds() -> void:
	var slow := _slow_token
	var block := _block_token
	_slow_token = 0
	_block_token = 0
	var pause = _pause_ref.get_ref() if _pause_ref != null else null
	var command = _command_ref.get_ref() if _command_ref != null else null
	if is_instance_valid(pause): pause.release_time_scale(slow)
	if is_instance_valid(command): command.release_input_block(block)

func _on_scope_changed(_world: Node) -> void: _detach()
func _on_dependency_exiting() -> void: _detach()

func _detach() -> void:
	if _detaching: return
	_detaching = true
	_generation += 1
	cancel_selection(&"binding_changed")
	if not is_instance_valid(self): return
	_release_holds()
	var source = _round_ref.get_ref() if _round_ref != null else null
	var pause = _pause_ref.get_ref() if _pause_ref != null else null
	var command = _command_ref.get_ref() if _command_ref != null else null
	if is_instance_valid(source):
		if source.finisher_qualified.is_connected(_on_qualified): source.finisher_qualified.disconnect(_on_qualified)
		if source.tree_exiting.is_connected(_on_dependency_exiting): source.tree_exiting.disconnect(_on_dependency_exiting)
		var holder = source.get_meta(OWNER) if source.has_meta(OWNER) else null
		if holder is WeakRef and holder.get_ref() == self: source.remove_meta(OWNER)
	if is_instance_valid(pause):
		if pause.pause_state_changed.is_connected(_on_pause_changed): pause.pause_state_changed.disconnect(_on_pause_changed)
		if pause.tree_exiting.is_connected(_on_dependency_exiting): pause.tree_exiting.disconnect(_on_dependency_exiting)
	if is_instance_valid(command) and command.scope_changed.is_connected(_on_scope_changed): command.scope_changed.disconnect(_on_scope_changed)
	_round_ref = null
	_pause_ref = null
	_command_ref = null
	_scope_ref = null
	# 轮次身份全局单调；临时解绑不清零已消费水位，避免同一结算重放。
	_detaching = false

func _publish() -> void: selection_state_changed.emit(get_selection_status())
func _node(reference: WeakRef) -> Node:
	var node = reference.get_ref() if reference != null else null
	return node if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() else null
func _round() -> SquadChainRoundController: return _node(_round_ref) as SquadChainRoundController
func _pause() -> GamePauseCoordinator: return _node(_pause_ref) as GamePauseCoordinator
func _command() -> SquadChainCommandController: return _node(_command_ref) as SquadChainCommandController
func _scope() -> Node: return _node(_scope_ref)
func _exit_tree() -> void:
	if not Engine.is_editor_hint(): _detach()
