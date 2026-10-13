class_name SquadFocusDebugDisplay
extends CanvasLayer
## 开发只读显示，不计算专注、费用或伤害；可替换而不影响战斗。
## 指定场景中的专注组件；默认空时安全隐藏，绑定不转移资源所有权。
@export var focus_source: SquadFocusComponent
## 是否显示开发条，默认关闭；只影响画面，不影响资源积累。
@export var debug_enabled: bool = false:
	set(value):
		debug_enabled = value
		if is_node_ready(): visible = value and is_instance_valid(_bound_focus)
var _bound_focus: SquadFocusComponent
@onready var _values: Label = $Panel/VBox/Values
@onready var _bar: ProgressBar = $Panel/VBox/Bar

func _ready() -> void:
	visible = false
	bind_focus(focus_source)
func _exit_tree() -> void:
	unbind_focus()

## 绑定有效组件并立即读取当前数值；null 或已失效时隐藏，不修改池状态。
func bind_focus(source: SquadFocusComponent) -> void:
	unbind_focus()
	if not is_instance_valid(source): return
	_bound_focus = source
	source.focus_changed.connect(_on_focus_changed)
	source.tree_exiting.connect(_on_source_exiting)
	_on_focus_changed(source.get_current_focus(), source.get_reserved_focus(), source.get_available_focus())

## 清理监听和运行时引用，不清空配置字段，不扣费或退款。
func unbind_focus() -> void:
	if is_instance_valid(_bound_focus):
		if _bound_focus.focus_changed.is_connected(_on_focus_changed): _bound_focus.focus_changed.disconnect(_on_focus_changed)
		if _bound_focus.tree_exiting.is_connected(_on_source_exiting): _bound_focus.tree_exiting.disconnect(_on_source_exiting)
	_bound_focus = null
	visible = false

func _on_source_exiting() -> void:
	unbind_focus()
func _on_focus_changed(current: float, reserved: float, available: float) -> void:
	if not is_instance_valid(_bound_focus) or not is_instance_valid(_values): return
	visible = debug_enabled
	_values.text = "总量 %.1f   预留 %.1f   可用 %.1f" % [current, reserved, available]
	_bar.max_value = _bound_focus.get_maximum_focus()
	_bar.value = current
