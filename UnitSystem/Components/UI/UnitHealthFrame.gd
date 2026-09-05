class_name UnitHealthFrame
extends PanelContainer

## 屏幕空间队伍 HUD 的单个单位生命信息框。
## 本组件只通过 UnitBase 的公开 getter 与信号读取生命状态，负责名称回退显示、
## 当前/最大生命文本、生命进度条、“倒下”死亡标记与玩家/紧凑伙伴展示切换；
## 它不修改单位数据、不参与战斗结算，也不依赖任何 AI 或玩家专属组件。
## 场景内样式全部使用 StyleBoxFlat 子资源，不引用外部 Theme 或资源文件。

enum PresentationMode {
	PLAYER,
	COMPACT_ALLY,
}

## 玩家模式下名称文本的字号，单位为像素。
const PLAYER_NAME_FONT_SIZE: int = 18
## 玩家模式下数值文本的字号，单位为像素。
const PLAYER_VALUE_FONT_SIZE: int = 16
## 紧凑伙伴模式下名称文本的字号，单位为像素。
const ALLY_NAME_FONT_SIZE: int = 15
## 紧凑伙伴模式下数值文本的字号，单位为像素。
const ALLY_VALUE_FONT_SIZE: int = 13
## 玩家模式下核心信息（名称/进度条/数值）的纵向间距，单位为像素。
const PLAYER_CONTENT_SEPARATION: int = 6
## 紧凑伙伴模式下核心信息的纵向间距，单位为像素。
const ALLY_CONTENT_SEPARATION: int = 4
## 单位倒下时整框使用的半透明灰暗色。
const DEAD_FRAME_MODULATE: Color = Color(0.55, 0.55, 0.55, 0.9)
## 存活与复活后恢复的原始色。
const ALIVE_FRAME_MODULATE: Color = Color.WHITE
## 死亡标记显示的固定文本。
const DEAD_STATE_TEXT: String = "倒下"
## 无绑定或生命上限非正数时显示的占位生命文本。
const EMPTY_HEALTH_TEXT: String = "0 / 0"

@onready var _name_label: Label = %NameLabel
@onready var _state_label: Label = %StateLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_value: Label = %HealthValue
@onready var _extension_slot: MarginContainer = %ExtensionSlot
@onready var _core_info: VBoxContainer = %CoreInfo

## 当前绑定的单位；null 或已失效表示信息框处于未绑定隐藏态。
var _bound_unit: UnitBase
## 当前展示模式；只影响字号、间距与扩展槽，不影响绑定数据。
var _presentation_mode: PresentationMode = PresentationMode.PLAYER


## 将信息框绑定到一个有效 UnitBase。重复绑定会先安全断开旧单位；传入 null 等同解绑。
func bind_unit(unit: UnitBase) -> void:
	if unit == _bound_unit and is_instance_valid(unit):
		refresh_immediately()
		return
	unbind_unit()
	if not is_instance_valid(unit):
		return
	_bound_unit = unit
	_connect_unit_signals()
	visible = true
	refresh_immediately()


## 断开当前单位的全部信号并隐藏信息框；不会修改单位本身。
func unbind_unit() -> void:
	_disconnect_unit_signals()
	_bound_unit = null
	_reset_display()
	visible = false


## 切换玩家或紧凑伙伴展示；只影响字号、间距和扩展槽，不改变绑定数据。
func set_presentation_mode(mode: PresentationMode) -> void:
	_presentation_mode = mode
	_apply_presentation_mode()


## 从当前绑定单位的 getter 重新读取全部显示值；无有效绑定时安全隐藏。
func refresh_immediately() -> void:
	if not is_instance_valid(_bound_unit):
		unbind_unit()
		return
	_update_health(
		_bound_unit.get_current_health(),
		_bound_unit.get_maximum_health()
	)
	_name_label.text = _bound_unit.name
	_set_dead_state(_bound_unit.is_dead())


## 返回当前是否持有有效 UnitBase 绑定。
func is_bound() -> bool:
	return is_instance_valid(_bound_unit)


## 连接当前绑定单位的生命信号与 tree_exiting；全部连接前检查 is_connected() 防止重复。
func _connect_unit_signals() -> void:
	if not is_instance_valid(_bound_unit):
		return
	if not _bound_unit.health_changed.is_connected(_on_health_changed):
		_bound_unit.health_changed.connect(_on_health_changed)
	if not _bound_unit.died.is_connected(_on_unit_died):
		_bound_unit.died.connect(_on_unit_died)
	if not _bound_unit.revived.is_connected(_on_unit_revived):
		_bound_unit.revived.connect(_on_unit_revived)
	if not _bound_unit.tree_exiting.is_connected(_on_bound_unit_tree_exiting):
		_bound_unit.tree_exiting.connect(_on_bound_unit_tree_exiting)


## 断开当前绑定单位的全部信号；单位已失效时直接返回，避免访问已释放实例。
func _disconnect_unit_signals() -> void:
	if not is_instance_valid(_bound_unit):
		return
	if _bound_unit.health_changed.is_connected(_on_health_changed):
		_bound_unit.health_changed.disconnect(_on_health_changed)
	if _bound_unit.died.is_connected(_on_unit_died):
		_bound_unit.died.disconnect(_on_unit_died)
	if _bound_unit.revived.is_connected(_on_unit_revived):
		_bound_unit.revived.disconnect(_on_unit_revived)
	if _bound_unit.tree_exiting.is_connected(_on_bound_unit_tree_exiting):
		_bound_unit.tree_exiting.disconnect(_on_bound_unit_tree_exiting)


## 把全部显示值复位为未绑定的中性状态；由 unbind_unit() 在隐藏前调用。
func _reset_display() -> void:
	_name_label.text = ""
	_health_value.text = EMPTY_HEALTH_TEXT
	_health_bar.value = 0.0
	_set_dead_state(false)


## 生命值发生实际变化时同步文本与进度条；参数来自 UnitBase.health_changed 信号。
func _on_health_changed(
	_previous_health: float,
	current_health: float,
	maximum_health: float,
	_source: Node
) -> void:
	_update_health(current_health, maximum_health)


## 单位死亡时保持框体与槽位不变，仅刷新为零生命并进入倒下视觉状态。
func _on_unit_died(_source: Node) -> void:
	refresh_immediately()


## 单位复活时重新读取 getter，不只信任信号参数，保证最大生命同时正确。
func _on_unit_revived(_current_health: float, _source: Node) -> void:
	refresh_immediately()


## 绑定单位即将离开场景树时立即解绑并隐藏，防止残留回调。
func _on_bound_unit_tree_exiting() -> void:
	unbind_unit()


## 以安全上限更新进度条比例与数值文本；上限不大于零时比例固定为 0。
func _update_health(current_health: float, maximum_health: float) -> void:
	var safe_maximum := maxf(maximum_health, 0.0)
	var health_ratio := 0.0
	if safe_maximum > 0.0:
		health_ratio = clampf(current_health / safe_maximum, 0.0, 1.0)
	_health_bar.value = health_ratio
	_health_value.text = "%d / %d" % [int(roundf(current_health)), int(roundf(safe_maximum))]


## 切换倒下视觉状态：显示“倒下”并将整框调暗，复活时恢复。
func _set_dead_state(dead: bool) -> void:
	_state_label.visible = dead
	if dead:
		_state_label.text = DEAD_STATE_TEXT
		self_modulate = DEAD_FRAME_MODULATE
	else:
		self_modulate = ALIVE_FRAME_MODULATE


## 按展示模式应用字号、间距与扩展槽可见性；扩展槽仅在玩家模式且已有内容时显示。
func _apply_presentation_mode() -> void:
	var is_player_mode := _presentation_mode == PresentationMode.PLAYER
	_name_label.add_theme_font_size_override(
		"font_size",
		PLAYER_NAME_FONT_SIZE if is_player_mode else ALLY_NAME_FONT_SIZE
	)
	_health_value.add_theme_font_size_override(
		"font_size",
		PLAYER_VALUE_FONT_SIZE if is_player_mode else ALLY_VALUE_FONT_SIZE
	)
	_core_info.add_theme_constant_override(
		"separation",
		PLAYER_CONTENT_SEPARATION if is_player_mode else ALLY_CONTENT_SEPARATION
	)
	_extension_slot.visible = (
		is_player_mode and _extension_slot.get_child_count() > 0
	)


## 组件自身离开场景树时断开单位信号，防止场景卸载后残留回调。
func _exit_tree() -> void:
	_disconnect_unit_signals()
