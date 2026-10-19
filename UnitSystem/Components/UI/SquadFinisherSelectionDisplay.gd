@tool
class_name SquadFinisherSelectionDisplay
extends CanvasLayer
## 终结十字纯显示；不接收输入，不持有暂停或技能，不计算评分。
## 本世界选择源，默认空隐藏；四伙伴及真实倒计时从只读状态取得。
@export var selection_source: SquadFinisherSelectionController
var _source_ref: WeakRef
var _snapshot: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_binding()
	_render()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	_refresh_binding()
	_render()

func _refresh_binding() -> void:
	var source := selection_source if is_instance_valid(selection_source) and selection_source.is_inside_tree() and not selection_source.is_queued_for_deletion() else null
	if source == _source() and source != null: return
	_detach()
	if source == null: return
	_source_ref = weakref(source)
	source.selection_state_changed.connect(_on_state)
	_snapshot = source.get_selection_status()

func _on_state(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_render()

func _render() -> void:
	var root := get_node_or_null("Root") as Control
	if root == null: return
	var phase: int = _snapshot.get("phase",0)
	root.visible = phase != 0 and _source() != null
	if not root.visible: return
	var cross := root.get_node("Cross") as Control
	var elapsed: float = _snapshot.get("presentation_elapsed_seconds",0.0)
	var opacity := 1.0
	var expansion := 1.0
	if phase == SquadFinisherSelectionController.Phase.OPENING:
		opacity = clampf(elapsed/0.12,0,1)
		expansion = lerpf(0.88,1.0,1.0-pow(1.0-opacity,3))
	elif phase == SquadFinisherSelectionController.Phase.CLOSING:
		opacity = 1.0-clampf(elapsed/0.10,0,1)
		expansion = lerpf(0.95,1.0,opacity)
	cross.modulate.a = opacity
	var viewport_size := get_viewport().get_visible_rect().size
	var fit := minf(viewport_size.x/2560.0,viewport_size.y/1440.0)
	fit = minf(1.0,maxf(fit,0.01))*expansion
	cross.scale = Vector2.ONE*fit
	var safe := Vector2(340,300)*fit
	var desired := viewport_size*Vector2(cross.anchor_left,cross.anchor_top)
	cross.position = Vector2(clampf(desired.x,safe.x,viewport_size.x-safe.x),clampf(desired.y,safe.y,viewport_size.y-safe.y))
	var slots: Array = _snapshot.get("slots",[])
	for index in range(4):
		var card := cross.get_node("Slot%d" % (index+1)) as PanelContainer
		var slot: Dictionary = slots[index] if index < slots.size() else {}
		card.get_node("VBox/Actor").text = slot.get("actor_name","未配置")
		card.get_node("VBox/Skill").text = "终结技（接口测试）"
		var selected: bool = _snapshot.get("selected_slot",-1) == index
		card.theme_type_variation = &"FinisherSelected" if selected else &"FinisherOption"
		card.modulate = Color.WHITE if slot.get("available",false) else Color(0.40,0.43,0.48)
	cross.get_node("Countdown").value = _snapshot.get("progress_ratio",0.0)

func _source() -> SquadFinisherSelectionController:
	var source = _source_ref.get_ref() if _source_ref != null else null
	return source if is_instance_valid(source) and source.is_inside_tree() and not source.is_queued_for_deletion() else null

func _detach() -> void:
	var source = _source_ref.get_ref() if _source_ref != null else null
	if is_instance_valid(source) and source.selection_state_changed.is_connected(_on_state): source.selection_state_changed.disconnect(_on_state)
	_source_ref = null
	_snapshot.clear()

func _exit_tree() -> void: _detach()
