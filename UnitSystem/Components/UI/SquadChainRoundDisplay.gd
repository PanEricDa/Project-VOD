@tool
class_name SquadChainRoundDisplay
extends CanvasLayer
## 独立只读连击反馈：大号COMBO、终结进度与实际伤害间隔；不处理输入、评分、支付或暂停。
## 本关卡已有连携评价源，默认空则隐藏；队伍、世界与暂停状态均沿用此源，不重复配置。
@export var round_source: SquadChainRoundController

# 结算后保留2个真实秒；沿用本UI既有暂停/演出挂起规则，不受战斗慢放倍率拉长。
const SUMMARY_HOLD_SECONDS: float = 2.0
const PULSE_GROW_SECONDS: float = 0.12
const PULSE_SETTLE_SECONDS: float = 0.10
const READY_COLOR := Color(1.0, 0.78, 0.28, 1.0)
var _bound_round: WeakRef
var _signature: Array = []
var _snapshot: Dictionary = {}
var _summary: Dictionary = {}
var _summary_remaining: float = 0.0
var _shown_round_id: int = 0
var _shown_hits: int = 0
var _pulse_elapsed: float = PULSE_GROW_SECONDS+PULSE_SETTLE_SECONDS
var _last_usec: int = 0

func _ready() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_usec = Time.get_ticks_usec()
	_refresh_binding()
	_render()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	var now := Time.get_ticks_usec()
	var elapsed := maxf(float(now-_last_usec)/1000000.0,0.0)
	_last_usec = now
	_refresh_binding()
	var evaluator := _evaluator()
	var source := evaluator.command_source if evaluator != null else null
	if get_tree().paused or (is_instance_valid(source) and source.is_feedback_suspended()): return
	_advance_pulse(elapsed)
	if _summary_remaining > 0.0:
		_summary_remaining = maxf(_summary_remaining-elapsed,0.0)
		if _summary_remaining == 0.0: _render()

func _refresh_binding() -> void:
	var candidate := round_source if is_instance_valid(round_source) and round_source.is_inside_tree() else null
	var status: Dictionary = candidate.get_round_status() if candidate != null else {}
	var source := candidate.command_source if candidate != null else null
	var scope := source.get_bound_scope() if is_instance_valid(source) else null
	var signature := [_node_id(candidate),_node_id(source),_node_id(scope),status.get("bound",false)]
	if signature == _signature: return
	_detach()
	_signature = signature
	if candidate == null or not status.get("bound",false): return
	_bound_round = weakref(candidate)
	candidate.round_state_changed.connect(_on_round_state)
	candidate.round_finished.connect(_on_round_finished)
	_on_round_state(status)

func _on_round_state(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if _snapshot.get("phase",0) == SquadChainRoundController.Phase.ACTIVE:
		_summary_remaining = 0.0
	_summary = snapshot.get("last_result",{}).duplicate(true)
	_render()

func _on_round_finished(result: Dictionary) -> void:
	_summary = result.duplicate(true)
	_summary_remaining = SUMMARY_HOLD_SECONDS
	_last_usec = Time.get_ticks_usec()
	# 结算信号在IDLE状态发布前发出；立即清除旧ACTIVE显示，不延长业务窗口。
	var evaluator := _evaluator()
	_snapshot = evaluator.get_round_status() if evaluator != null else {}
	_render()

func _render() -> void:
	var panel := get_node_or_null("Panel") as Control
	if panel == null: return
	var active: bool = _snapshot.get("phase",0) == SquadChainRoundController.Phase.ACTIVE
	var shown: Dictionary = _snapshot if active else _summary
	var valid: bool = _evaluator() != null and _snapshot.get("bound",false) and not shown.is_empty() and (active or _summary_remaining > 0.0)
	panel.visible = valid
	if not valid: return
	var number := panel.get_node("VBox/ComboRow/Number") as Label
	var hits: int = shown.get("hit_count",0)
	var round_id: int = shown.get("round_id",0)
	if active and (hits != _shown_hits or round_id != _shown_round_id):
		_pulse_elapsed = 0.0
		number.scale = Vector2.ONE*0.65
	_shown_hits = hits
	_shown_round_id = round_id
	number.text = str(hits)
	number.pivot_offset = number.size*0.5
	var score := panel.get_node("VBox/ScoreProgress") as ProgressBar
	score.value = clampf(float(shown.get("score",0.0))/100.0,0.0,1.0)
	var qualified: bool = shown.get("finisher_ready",false) if active else shown.get("qualified",false)
	score.modulate = READY_COLOR if qualified else Color.WHITE
	var interval := panel.get_node("VBox/DamageInterval") as ProgressBar
	var duration: float = _snapshot.get("interval_seconds",0.0)
	interval.visible = active
	interval.value = clampf(float(_snapshot.get("remaining_seconds",0.0))/duration,0.0,1.0) if active and duration > 0.0 else 0.0

func _advance_pulse(elapsed: float) -> void:
	var number := get_node_or_null("Panel/VBox/ComboRow/Number") as Label
	if number == null: return
	_pulse_elapsed = minf(_pulse_elapsed+elapsed,PULSE_GROW_SECONDS+PULSE_SETTLE_SECONDS)
	var amount: float = 1.0
	if _pulse_elapsed < PULSE_GROW_SECONDS:
		var t := _pulse_elapsed/PULSE_GROW_SECONDS
		amount = lerpf(0.65,1.12,1.0-pow(1.0-t,3.0))
	elif _pulse_elapsed < PULSE_GROW_SECONDS+PULSE_SETTLE_SECONDS:
		var t := (_pulse_elapsed-PULSE_GROW_SECONDS)/PULSE_SETTLE_SECONDS
		amount = lerpf(1.12,1.0,1.0-pow(1.0-t,2.0))
	number.pivot_offset = number.size*0.5
	number.scale = Vector2.ONE*amount

func _node_id(node: Node) -> int:
	return node.get_instance_id() if is_instance_valid(node) else 0

func _evaluator() -> SquadChainRoundController:
	var evaluator = _bound_round.get_ref() if _bound_round != null else null
	return evaluator if is_instance_valid(evaluator) and evaluator.is_inside_tree() else null

func _detach() -> void:
	var evaluator := _evaluator()
	if evaluator != null:
		if evaluator.round_state_changed.is_connected(_on_round_state): evaluator.round_state_changed.disconnect(_on_round_state)
		if evaluator.round_finished.is_connected(_on_round_finished): evaluator.round_finished.disconnect(_on_round_finished)
	_bound_round = null
	_signature.clear()
	_snapshot.clear()
	_summary.clear()
	_summary_remaining = 0.0
	_shown_round_id = 0
	_shown_hits = 0
	_pulse_elapsed = PULSE_GROW_SECONDS+PULSE_SETTLE_SECONDS
	var number := get_node_or_null("Panel/VBox/ComboRow/Number") as Label
	if number != null: number.scale = Vector2.ONE
	_render()

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): _detach()
