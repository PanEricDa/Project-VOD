@tool
extends CanvasLayer
class_name SquadChainCommandDisplay
## 只读固定四槽指令反馈；不处理点击、目标选择或专注账目。
## 关联本关卡指令控制器；默认空时显示未配置，影响此显示，不改变控制器执行。
@export var command_source: SquadChainCommandController
var _bound_source: WeakRef
var _feedback: Array[String] = ["", "", "", ""]
var _feedback_remaining: Array[float] = [0.0, 0.0, 0.0, 0.0]
const REASONS = {
	&"companion_missing": "未配置伙伴", &"skill_configuration_invalid": "技能未配置",
	&"host_missing": "缺少技能宿主", &"focus_unbound": "尚未绑定战场",
	&"input_disabled": "输入已停用", &"player_unavailable": "玩家不可操作",
	&"pending_full": "等待槽已满", &"insufficient_focus": "专注不足",
	&"cast_unavailable": "当前无法施放", &"target_or_condition_invalid": "没有合法目标",
	&"round_source_missing": "未连接连携批次", &"round_closed": "批次已关闭"
}
func _ready() -> void:
	if not Engine.is_editor_hint(): _refresh_binding()
func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	_refresh_binding()
	for slot in range(4):
		if _feedback_remaining[slot] > 0.0:
			_feedback_remaining[slot] = maxf(0.0, _feedback_remaining[slot] - delta)
			if _feedback_remaining[slot] == 0.0:
				_feedback[slot] = ""
				_update_card(slot)
func _refresh_binding() -> void:
	var old = _bound_source.get_ref() if _bound_source != null else null
	if old == command_source and is_instance_valid(old): return
	_detach()
	if is_instance_valid(command_source):
		_bound_source = weakref(command_source)
		command_source.slot_status_changed.connect(_update_card)
		command_source.command_rejected.connect(_on_rejected)
	for slot in range(4): _update_card(slot)
func _update_card(slot: int) -> void:
	if slot < 0 or slot >= 4: return
	var card := get_node_or_null("Panel/VBox/Cards/Card%d" % (slot + 1)) as Control
	if card == null: return
	var source = _bound_source.get_ref() if _bound_source != null else null
	var status: Dictionary = source.get_slot_status(slot) if is_instance_valid(source) else {}
	card.modulate = Color.WHITE if status.get("can_submit", false) else Color(0.58, 0.58, 0.58)
	card.get_node("VBox/Actor").text = "%d  %s" % [slot + 1, status.get("actor_name", "未配置")]
	card.get_node("VBox/Skill").text = status.get("skill_name", "—")
	var fee: float = status.get("estimated_cost", -1.0)
	card.get_node("VBox/Cost").text = "专注：%s" % str(fee) if fee >= 0.0 else "专注：—"
	card.get_node("VBox/Icon").texture = status.get("icon")
	card.get_node("VBox/Icon").visible = status.get("icon") != null
	var phase: StringName = status.get("phase", &"idle")
	var text: String = {&"idle": "待命", &"waiting": "等待空闲", &"approaching": "接近目标", &"casting": "施放中", &"released": "动作收尾"}.get(phase, String(phase))
	if status.get("pending_request_id", 0) > 0 and status.get("active_request_id", 0) > 0: text += " · 已缓存"
	if not status.get("can_submit", false) and phase == &"idle": text = REASONS.get(status.get("reason", &""), "不可用")
	if not _feedback[slot].is_empty(): text = _feedback[slot]
	card.get_node("VBox/State").text = text
func _on_rejected(slot: int, reason: StringName) -> void:
	if slot < 0 or slot >= 4: return
	_feedback[slot] = REASONS.get(reason, "请求未受理")
	_feedback_remaining[slot] = 1.5
	_update_card(slot)
func _detach() -> void:
	var old = _bound_source.get_ref() if _bound_source != null else null
	if is_instance_valid(old):
		if old.slot_status_changed.is_connected(_update_card): old.slot_status_changed.disconnect(_update_card)
		if old.command_rejected.is_connected(_on_rejected): old.command_rejected.disconnect(_on_rejected)
	_bound_source = null
func _exit_tree() -> void:
	if not Engine.is_editor_hint(): _detach()
