@tool
class_name SquadChainCommandDisplay
extends CanvasLayer
## 四槽指令与专注只读反馈；不持有技能或Request，不处理输入、费用、评分或暂停。
## 关联本关卡原指令源，默认空；只影响本显示。
@export var command_source: SquadChainCommandController
## 成功释放后的绿色保留秒数，默认0.3，包含释放强调；0立即清除，仅影响UI。
@export_range(0.0, 3.0, 0.05) var success_hold_seconds: float = 0.3
## 释放前失败/拒绝的红色提示秒数，默认0.3；0关闭，仅影响UI。
@export_range(0.0, 3.0, 0.05) var failure_hold_seconds: float = 0.3
var _bound_source: WeakRef
var _bound_focus: WeakRef
var _focus_signature: Array = []
var _panel_bottom_offset: float = -55.0
var _request_slots: Dictionary = {}
var _success: Array[Dictionary] = [{},{},{},{}]
var _failure: Array[Dictionary] = [{},{},{},{}]
var _last_usec: int = 0
var _cached_confirmation_remaining: Array[float] = [0.0,0.0,0.0,0.0]
const REASONS = {
	&"companion_missing": "未配置伙伴", &"skill_configuration_invalid": "技能未配置",
	&"host_missing": "缺少技能宿主", &"focus_unbound": "尚未绑定战场",
	&"input_disabled": "输入已停用", &"player_unavailable": "玩家不可操作",
	&"pending_full": "等待槽已满", &"insufficient_focus": "专注不足",
	&"cast_unavailable": "当前无法施放", &"target_or_condition_invalid": "没有合法目标",
	&"round_source_missing": "未连接连携批次", &"round_closed": "批次已关闭"
}

func _ready() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := get_node_or_null("Panel") as Control
	if panel != null: _panel_bottom_offset = panel.offset_bottom
	_last_usec = Time.get_ticks_usec()
	_refresh_binding()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	var now := Time.get_ticks_usec()
	var elapsed := maxf(float(now-_last_usec)/1000000.0,0.0)
	_last_usec = now
	_refresh_binding()
	var source := _source()
	if source != null and source.is_feedback_suspended(): return
	_update_focus()
	for slot in range(4):
		_cached_confirmation_remaining[slot] = maxf(0.0,_cached_confirmation_remaining[slot]-elapsed)
		for records in [_success,_failure]:
			if not records[slot].is_empty():
				records[slot].remaining -= elapsed
				if records[slot].remaining <= 0.0: records[slot] = {}
		_update_card(slot)

func _refresh_binding() -> void:
	var old := _source()
	if old == command_source and old != null:
		_refresh_focus_binding()
		return
	_detach()
	if is_instance_valid(command_source):
		_bound_source = weakref(command_source)
		for pair in _connections(command_source):
			pair[0].connect(pair[1])
	for slot in range(4): _update_card(slot)
	_refresh_focus_binding()

func _connections(source: SquadChainCommandController) -> Array:
	return [
		[source.slot_status_changed,_update_card],[source.command_rejected,_on_rejected],
		[source.command_accepted,_on_accepted],[source.command_started,_on_started],
		[source.command_released,_on_released],[source.command_failed,_on_failed],
		[source.command_lifetime_finished,_on_lifetime_finished],[source.scope_changed,_on_scope_changed]]

func _update_card(slot: int) -> void:
	if slot < 0 or slot >= 4: return
	var card := get_node_or_null("Panel/VBox/Cards/Card%d" % (slot+1)) as Control
	if card == null: return
	var source := _source()
	var status: Dictionary = source.get_slot_status(slot) if source != null else {}
	card.modulate = Color.WHITE
	card.get_node("VBox").modulate = Color.WHITE if status.get("can_submit",false) else Color(0.58,0.58,0.58)
	card.get_node("VBox/Actor").text = "%d  %s" % [slot+1,status.get("actor_name","未配置")]
	card.get_node("VBox/Skill").text = status.get("skill_name","—")
	var fee: float = status.get("estimated_cost",-1.0)
	card.get_node("VBox/Cost").text = "专注：%s" % str(fee) if fee >= 0 else "专注：—"
	card.get_node("VBox/Icon").texture = status.get("icon")
	card.get_node("VBox/Icon").visible = status.get("icon") != null
	var phase: StringName = status.get("phase",&"idle")
	var text: String = {&"idle":"待命",&"waiting":"等待空闲",&"approaching":"接近目标",&"casting":"施放中",&"released":"动作收尾"}.get(phase,String(phase))
	var active: int = status.get("active_request_id",0)
	var pending: int = status.get("pending_request_id",0)
	var cached := pending > 0 and active > 0
	if cached and _cached_confirmation_remaining[slot] <= 0.0: text += " · 已缓存"
	var confirmation = card.get_node_or_null("VBox/CachedConfirmation")
	if confirmation != null: confirmation.visible = cached and _cached_confirmation_remaining[slot] > 0.0
	if not status.get("can_submit",false) and phase == &"idle": text = REASONS.get(status.get("reason",&""),"不可用")
	var variation: StringName = &""
	if not _failure[slot].is_empty():
		variation = &"ChainFailed"
		text = _failure[slot].text
	elif phase == &"casting" and active > 0:
		variation = &"ChainCasting"
	elif pending > 0 or (active > 0 and phase in [&"waiting",&"approaching"]):
		variation = &"ChainWaiting"
	elif not _success[slot].is_empty():
		variation = &"ChainCasting"
	var label = card.get_node("VBox/State")
	label.text = text
	var border = card.get_node_or_null("StateBorder")
	if border != null:
		border.theme_type_variation = variation
		border.visible = variation != &""

func _on_accepted(request: SkillCommandRequest) -> void:
	var source := _source()
	if source == null: return
	for slot in range(4):
		var actor = source.companions[slot]
		if is_instance_valid(actor) and actor.get_instance_id() == request.caster_instance_id:
			_request_slots[request.request_id] = slot
			if source.get_slot_status(slot).active_request_id > 0: _cached_confirmation_remaining[slot] = 0.3
			_update_card(slot)
			return

func _on_started(slot: int, fact: SkillPresentationContext) -> void:
	if slot < 0 or slot >= 4 or fact == null: return
	_request_slots[fact.command_request_id] = slot
	_update_card(slot)

func _on_released(id: int, _cost: float) -> void:
	var slot := _find_slot(id)
	if slot < 0: return
	var duration := _duration(success_hold_seconds)
	_success[slot] = {"id":id,"remaining":duration} if duration > 0 else {}
	_update_card(slot)

func _on_failed(slot: int, id: int, reason: StringName) -> void:
	_request_slots.erase(id)
	_show_failure(slot,id,reason)

func _on_rejected(slot: int, reason: StringName) -> void: _show_failure(slot,0,reason)

func _show_failure(slot: int, id: int, reason: StringName) -> void:
	if slot < 0 or slot >= 4: return
	var duration := _duration(failure_hold_seconds)
	_failure[slot] = {"id":id,"remaining":duration,"text":REASONS.get(reason,"施放失败")} if duration > 0 else {}
	_update_card(slot)

func _on_lifetime_finished(id: int, _round: int) -> void: _request_slots.erase(id)

func _on_scope_changed(_scope: Node) -> void:
	_detach_focus()
	_request_slots.clear()
	for slot in range(4):
		_success[slot] = {}
		_failure[slot] = {}
		_cached_confirmation_remaining[slot] = 0.0
		_update_card(slot)
	_last_usec = Time.get_ticks_usec()

func _find_slot(id: int) -> int:
	if _request_slots.has(id): return _request_slots[id]
	var source := _source()
	if source != null:
		for slot in range(4):
			var status := source.get_slot_status(slot)
			if status.active_request_id == id or status.pending_request_id == id: return slot
	return -1

func _duration(value: float) -> float: return value if is_finite(value) and value >= 0 else 0.0
func _source() -> SquadChainCommandController:
	var source = _bound_source.get_ref() if _bound_source != null else null
	return source if is_instance_valid(source) and source.is_inside_tree() else null

func _detach() -> void:
	_detach_focus()
	var old := _source()
	if old != null:
		for pair in _connections(old):
			if pair[0].is_connected(pair[1]): pair[0].disconnect(pair[1])
	_bound_source = null
	_on_scope_changed(null)


func _node_id(node: Node) -> int:
	return node.get_instance_id() if is_instance_valid(node) else 0

func _refresh_focus_binding() -> void:
	var source := _source()
	var pool := source.focus_source if source != null and is_instance_valid(source.focus_source) else null
	var scope := source.get_bound_scope() if source != null else null
	var signature := [_node_id(source),_node_id(pool),_node_id(scope),_node_id(pool.get_bound_scope()) if pool != null else 0]
	if signature == _focus_signature: return
	_detach_focus()
	_focus_signature = signature
	if source == null or pool == null or scope == null or pool.get_bound_scope() != scope: return
	_bound_focus = weakref(pool)
	pool.focus_changed.connect(_on_focus_changed)
	_update_focus()

func _on_focus_changed(_current: float, _reserved: float, _available: float) -> void:
	_update_focus()

func _update_focus() -> void:
	var area := get_node_or_null("Panel/VBox/Focus") as Control
	if area == null: return
	var pool = _bound_focus.get_ref() if _bound_focus != null else null
	area.visible = is_instance_valid(pool)
	if area.visible:
		var capacity: float = maxf(pool.get_maximum_focus(),0.001)
		area.get_node("Values").text = "专注 %.0f  /  预留 %.0f  /  可用 %.0f" % [pool.get_current_focus(),pool.get_reserved_focus(),pool.get_available_focus()]
		area.get_node("Bars/UsedAndReserved").value = clampf(pool.get_current_focus()/capacity,0.0,1.0)
		area.get_node("Bars/Available").value = clampf(pool.get_available_focus()/capacity,0.0,1.0)
	var panel := get_node_or_null("Panel") as Control
	if panel != null:
		panel.offset_top = _panel_bottom_offset-maxf(160.0,panel.get_combined_minimum_size().y)
		panel.offset_bottom = _panel_bottom_offset

func _detach_focus() -> void:
	var pool = _bound_focus.get_ref() if _bound_focus != null else null
	if is_instance_valid(pool) and pool.focus_changed.is_connected(_on_focus_changed):
		pool.focus_changed.disconnect(_on_focus_changed)
	_bound_focus = null
	_focus_signature.clear()
	_update_focus()

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): _detach()
