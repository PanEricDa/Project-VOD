class_name PlayerSkillBar
extends CanvasLayer
## 玩家两槽只读显示；不处理施放输入、不推进冷却、不管理装备。
## 唯一数据来源；默认空安全显示空槽。拖入同玩家PlayerSkillController，不重复配置技能或键位。
@export var skill_source: PlayerSkillController

const FEEDBACK_SECONDS: float = 0.25
const REASONS: Dictionary = {
	&"input_disabled":"输入停用", &"owner_dead":"已倒下", &"action_busy":"动作中",
	&"cast_blocked":"无法施法", &"global_cooldown":"共享冷却", &"cooldown":"冷却中",
	&"skill_unavailable":"暂不可用", &"action_rejected":"动作失败", &"empty_slot":"空槽",
}
var _bound: WeakRef
var _feedback: Array[Dictionary] = [{},{}]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh_immediately()

func _process(_delta: float) -> void:
	refresh_immediately()

## source为同玩家的控制器；幂等，null等同解绑。仅管理UI监听，不改变技能执行。
func bind_source(source: PlayerSkillController) -> void:
	skill_source = source
	_sync_binding()
	_refresh_cards()

## 只解除本UI连接及短反馈；不取消技能、不修改Host、Input或动作。
func unbind_source() -> void:
	skill_source = null
	_detach()
	_refresh_cards()

## 只读立即刷新；冷却取SkillBase真值，短反馈使用真实时钟，暂停不推进战斗冷却。
func refresh_immediately() -> void:
	_sync_binding()
	_refresh_cards()

func _source() -> PlayerSkillController:
	return _bound.get_ref() as PlayerSkillController if _bound != null else null

func _sync_binding() -> void:
	if _source() == skill_source and is_instance_valid(skill_source): return
	_detach()
	if not is_instance_valid(skill_source): return
	_bound = weakref(skill_source)
	skill_source.slot_accepted.connect(_on_accepted)
	skill_source.slot_rejected.connect(_on_rejected)

func _detach() -> void:
	var source := _source()
	if is_instance_valid(source):
		if source.slot_accepted.is_connected(_on_accepted): source.slot_accepted.disconnect(_on_accepted)
		if source.slot_rejected.is_connected(_on_rejected): source.slot_rejected.disconnect(_on_rejected)
	_bound = null
	_feedback = [{},{}]

func _refresh_cards() -> void:
	if not is_inside_tree(): return
	var source := _source()
	for slot: int in range(2):
		var card := get_node_or_null("Panel/Cards/Card%d" % slot) as Control
		if card == null: continue
		var status: Dictionary = source.get_slot_status(slot) if is_instance_valid(source) else {}
		var configured: bool = status.get("configured",false)
		var title: String = status.get("skill_name","")
		card.get_node("Content/Name").text = title if configured else "空槽"
		var texture: Texture2D = status.get("icon")
		card.get_node("Content/Icon").texture = texture
		card.get_node("Content/Icon").visible = texture != null
		card.get_node("Content/Placeholder").visible = texture == null
		card.get_node("Content/Placeholder").text = title.left(1) if configured else "—"
		card.get_node("Content/Key").text = _key_label(status.get("input_action",&""))
		var remaining: float = status.get("cooldown_remaining",0.0)
		var duration: float = status.get("cooldown_duration",0.0)
		card.get_node("Cooldown").value = clampf(remaining/duration,0.0,1.0) if duration > 0.0 else 0.0
		var phase: StringName = status.get("phase",&"empty")
		var reason: StringName = status.get("reason",&"empty_slot")
		var text: String = "%.1fs" % remaining if remaining > 0.0 else REASONS.get(reason,"就绪")
		if phase == &"casting": text = "施放中"
		var feedback: Dictionary = _feedback[slot]
		if not feedback.is_empty() and Time.get_ticks_usec() >= feedback.until_usec:
			_feedback[slot] = {}
			feedback = {}
		var variation: StringName = &"PlayerSkillCasting" if phase == &"casting" else &""
		if not feedback.is_empty():
			variation = &"PlayerSkillFailed" if feedback.failed else &"PlayerSkillCasting"
			if feedback.failed: text = REASONS.get(feedback.reason,"无法施放")
		var pressed: bool = status.get("pressed",false)
		if pressed:
			variation = &"PlayerSkillSelected"
			text = "松开施放"
		var highlighted := pressed or variation == &"PlayerSkillCasting"
		card.pivot_offset = card.size*0.5
		var scale_percent := card.get_theme_constant("selected_scale_percent","SelectionFeedback")
		card.scale = Vector2.ONE*(float(scale_percent)/100.0 if highlighted else 1.0)
		var border := card.get_node("Feedback") as Panel
		border.theme_type_variation = variation
		border.visible = not variation.is_empty()
		card.get_node("Content/State").text = text
		card.get_node("Content").modulate = Color.WHITE if status.get("can_request",false) or phase == &"casting" else Color(0.56,0.56,0.56)

func _key_label(action: StringName) -> String:
	if action.is_empty() or not InputMap.has_action(action): return "—"
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			return OS.get_keycode_string(code)
	var events := InputMap.action_get_events(action)
	return events[0].as_text() if not events.is_empty() else "—"

func _on_accepted(slot: int, _skill: SkillBase) -> void:
	if slot < 0 or slot > 1: return
	_feedback[slot] = {"failed":false,"reason":&"","until_usec":Time.get_ticks_usec()+int(FEEDBACK_SECONDS*1000000.0)}
	_refresh_cards()

func _on_rejected(slot: int, reason: StringName) -> void:
	if slot < 0 or slot > 1: return
	_feedback[slot] = {"failed":true,"reason":reason,"until_usec":Time.get_ticks_usec()+int(FEEDBACK_SECONDS*1000000.0)}
	_refresh_cards()

func _exit_tree() -> void:
	_detach()
