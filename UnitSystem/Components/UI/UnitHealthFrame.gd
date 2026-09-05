class_name UnitHealthFrame
extends PanelContainer

## 屏幕空间队伍 HUD 的单个单位生命信息框。
## 本组件只通过 UnitBase 的公开 getter 与信号读取生命状态，负责名称回退显示、
## 当前/最大生命文本、红色损血残影、按比例渐变的生命进度条、“倒下”死亡标记，
## 以及玩家、紧凑伙伴和顶部目标三种展示切换；
## 它不修改单位数据、不参与战斗结算，也不依赖任何 AI 或玩家专属组件。
## 场景内样式全部使用 StyleBoxFlat 子资源，不引用外部 Theme 或资源文件。

enum PresentationMode {
	PLAYER,
	COMPACT_ALLY,
	TARGET,
}

## 玩家模式下名称文本的字号，单位为像素。
const PLAYER_NAME_FONT_SIZE: int = 36
## 玩家模式下数值文本的字号，单位为像素。
const PLAYER_VALUE_FONT_SIZE: int = 16
## 紧凑伙伴模式下名称文本的字号，单位为像素。
const ALLY_NAME_FONT_SIZE: int = 30
## 紧凑伙伴模式下数值文本的字号，单位为像素。
const ALLY_VALUE_FONT_SIZE: int = 13
## 顶部目标模式下名称文本的字号，单位为像素。
const TARGET_NAME_FONT_SIZE: int = 30
## 顶部目标模式下生命数值文本的字号，单位为像素。
const TARGET_VALUE_FONT_SIZE: int = 16
## 玩家模式下核心信息（名称/进度条/数值）的纵向间距，单位为像素。
const PLAYER_CONTENT_SEPARATION: int = 6
## 紧凑伙伴模式下核心信息的纵向间距，单位为像素。
const ALLY_CONTENT_SEPARATION: int = 4
## 顶部目标模式下名称与生命条的纵向间距，单位为像素。
const TARGET_CONTENT_SEPARATION: int = 4
## 单位倒下时整框使用的半透明灰暗色。
const DEAD_FRAME_MODULATE: Color = Color(0.55, 0.55, 0.55, 0.9)
## 存活与复活后恢复的原始色。
const ALIVE_FRAME_MODULATE: Color = Color.WHITE
## 死亡标记显示的固定文本。
const DEAD_STATE_TEXT: String = "倒下"
## 无绑定或生命上限非正数时显示的占位生命文本。
const EMPTY_HEALTH_TEXT: String = "0 / 0"

@export_category("Damage Trail")
## 实时生命条下降后，红色损血残影保持不动的时间，单位为秒；默认 0.12，设为 0 会立即开始消退，只影响本 HUD 信息框。
@export_range(0.0, 2.0, 0.01, "or_greater")
var damage_hold_duration: float = 0.12
## 红色损血残影从旧生命位置收缩到当前生命位置的时间，单位为秒；默认 0.35，设为 0 会在停留结束后立即同步，只影响本 HUD 信息框。
@export_range(0.0, 3.0, 0.01, "or_greater")
var damage_decay_duration: float = 0.35

@export_category("Health Colors")
## 生命比例为 100% 时的实时生命条颜色；默认绿色，只影响当前信息框的生命填充。
@export var healthy_health_color: Color = Color(0.18, 0.82, 0.28, 1.0)
## 生命比例到达颜色中点时的实时生命条颜色；默认黄色，只影响当前信息框的生命填充。
@export var warning_health_color: Color = Color(1.0, 0.82, 0.12, 1.0)
## 生命比例为 0% 时的实时生命条颜色；默认红色，只影响当前信息框的生命填充。
@export var critical_health_color: Color = Color(0.92, 0.16, 0.12, 1.0)
## 黄色中点对应的生命比例，取值 0.01～0.99；默认 0.5 表示 50%，其上向绿色插值、其下向红色插值。
@export_range(0.01, 0.99, 0.01)
var warning_health_ratio: float = 0.5
## 受到伤害后暂时保留的损失生命颜色；默认红色，只影响当前信息框的损血残影。
@export var damage_trail_color: Color = Color(0.92, 0.16, 0.12, 1.0)

@onready var _name_label: Label = %NameLabel
@onready var _state_label: Label = %StateLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _damage_bar: ProgressBar = %DamageBar
@onready var _health_value: Label = %HealthValue
@onready var _extension_slot: MarginContainer = %ExtensionSlot
@onready var _core_info: VBoxContainer = %CoreInfo

## 当前绑定的单位；null 或已失效表示信息框处于未绑定隐藏态。
var _bound_unit: UnitBase
## 当前展示模式；只影响字号、间距与扩展槽，不影响绑定数据。
var _presentation_mode: PresentationMode = PresentationMode.PLAYER
## 当前红色损血残影的唯一 Tween；连续受伤会终止旧实例并从保留值重新计时。
var _damage_tween: Tween
## 每个信息框独占的实时生命填充样式，避免一个单位变色影响其他实例。
var _health_fill_style: StyleBoxFlat
## 每个信息框独占的损血残影样式，用于应用可配置颜色而不污染场景共享子资源。
var _damage_fill_style: StyleBoxFlat


func _ready() -> void:
	_sanitize_visual_configuration()
	_make_fill_styles_local()
	_apply_presentation_mode()


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
	_kill_damage_tween()
	_bound_unit = null
	_reset_display()
	visible = false


## 切换玩家、紧凑伙伴或顶部目标展示；只影响字号、对齐、间距和扩展槽，不改变绑定数据。
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
	_damage_bar.value = _health_bar.value
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
	_damage_bar.value = 0.0
	_apply_health_color(0.0)
	_set_dead_state(false)


## 生命值发生实际变化时同步文本、渐变色与进度条；伤害保留红色残影，治疗立即同步残影。
## 参数全部来自 UnitBase.health_changed 信号，不会读取或修改伤害来源。
func _on_health_changed(
	previous_health: float,
	current_health: float,
	maximum_health: float,
	_source: Node
) -> void:
	var previous_ratio := _calculate_health_ratio(previous_health, maximum_health)
	var current_ratio := _calculate_health_ratio(current_health, maximum_health)
	_update_health(current_health, maximum_health)
	if current_health < previous_health:
		_damage_bar.value = maxf(float(_damage_bar.value), previous_ratio)
		_start_damage_decay(current_ratio)
		return
	_kill_damage_tween()
	_damage_bar.value = current_ratio


## 单位死亡时保持框体与槽位不变，仅刷新为零生命并进入倒下视觉状态。
func _on_unit_died(_source: Node) -> void:
	if is_instance_valid(_bound_unit):
		_update_health(
			_bound_unit.get_current_health(),
			_bound_unit.get_maximum_health()
		)
	_set_dead_state(true)


## 单位复活时重新读取 getter，不只信任信号参数，保证最大生命同时正确。
func _on_unit_revived(_current_health: float, _source: Node) -> void:
	refresh_immediately()


## 绑定单位即将离开场景树时立即解绑并隐藏，防止残留回调。
func _on_bound_unit_tree_exiting() -> void:
	unbind_unit()


## 以安全上限更新进度条比例与数值文本；上限不大于零时比例固定为 0。
func _update_health(current_health: float, maximum_health: float) -> void:
	var safe_maximum := maxf(maximum_health, 0.0)
	var health_ratio := _calculate_health_ratio(current_health, safe_maximum)
	_health_bar.value = health_ratio
	_apply_health_color(health_ratio)
	_health_value.text = "%d / %d" % [int(roundf(current_health)), int(roundf(safe_maximum))]


## 返回钳制到 0～1 的生命比例；生命上限不大于零时固定返回 0，供数值、颜色与损血残影共用。
func _calculate_health_ratio(current_health: float, maximum_health: float) -> float:
	if maximum_health <= 0.0:
		return 0.0
	return clampf(current_health / maximum_health, 0.0, 1.0)


## 根据当前生命比例计算红→黄→绿的连续颜色，并只写入当前信息框独占的填充样式。
func _apply_health_color(health_ratio: float) -> void:
	if not is_instance_valid(_health_fill_style):
		return
	var ratio := clampf(health_ratio, 0.0, 1.0)
	if ratio <= warning_health_ratio:
		_health_fill_style.bg_color = critical_health_color.lerp(
			warning_health_color,
			ratio / warning_health_ratio
		)
		return
	_health_fill_style.bg_color = warning_health_color.lerp(
		healthy_health_color,
		(ratio - warning_health_ratio) / (1.0 - warning_health_ratio)
	)


## 从当前红色保留值开始计时并收缩到实时生命比例；连续受伤会刷新唯一 Tween。
func _start_damage_decay(target_ratio: float) -> void:
	_kill_damage_tween()
	if damage_hold_duration <= 0.0 and damage_decay_duration <= 0.0:
		_damage_bar.value = target_ratio
		return
	_damage_tween = create_tween()
	if damage_hold_duration > 0.0:
		_damage_tween.tween_interval(damage_hold_duration)
	if damage_decay_duration > 0.0:
		_damage_tween.tween_property(
			_damage_bar,
			^"value",
			target_ratio,
			damage_decay_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_damage_tween.tween_callback(
			func() -> void:
				_damage_bar.value = target_ratio
		)


## 终止并清除当前损血残影 Tween；解绑、治疗、复活和退出场景时统一调用。
func _kill_damage_tween() -> void:
	if is_instance_valid(_damage_tween):
		_damage_tween.kill()
	_damage_tween = null


## 钳制可配置时间与颜色中点，确保运行时不会产生负时长或颜色插值除零。
func _sanitize_visual_configuration() -> void:
	damage_hold_duration = maxf(damage_hold_duration, 0.0)
	damage_decay_duration = maxf(damage_decay_duration, 0.0)
	warning_health_ratio = clampf(warning_health_ratio, 0.01, 0.99)


## 为当前实例复制实时与损血填充样式并应用导出颜色，避免 PackedScene 多实例共享修改。
func _make_fill_styles_local() -> void:
	_health_fill_style = _health_bar.get_theme_stylebox(&"fill").duplicate() as StyleBoxFlat
	if not is_instance_valid(_health_fill_style):
		_health_fill_style = StyleBoxFlat.new()
	_health_bar.add_theme_stylebox_override(&"fill", _health_fill_style)
	_damage_fill_style = _damage_bar.get_theme_stylebox(&"fill").duplicate() as StyleBoxFlat
	if not is_instance_valid(_damage_fill_style):
		_damage_fill_style = StyleBoxFlat.new()
	_damage_fill_style.bg_color = damage_trail_color
	_damage_bar.add_theme_stylebox_override(&"fill", _damage_fill_style)
	_apply_health_color(0.0)


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
	var is_target_mode := _presentation_mode == PresentationMode.TARGET
	_name_label.add_theme_font_size_override(
		"font_size",
		(
			PLAYER_NAME_FONT_SIZE
			if is_player_mode
			else TARGET_NAME_FONT_SIZE if is_target_mode else ALLY_NAME_FONT_SIZE
		)
	)
	_health_value.add_theme_font_size_override(
		"font_size",
		(
			PLAYER_VALUE_FONT_SIZE
			if is_player_mode
			else TARGET_VALUE_FONT_SIZE if is_target_mode else ALLY_VALUE_FONT_SIZE
		)
	)
	_core_info.add_theme_constant_override(
		"separation",
		(
			PLAYER_CONTENT_SEPARATION
			if is_player_mode
			else TARGET_CONTENT_SEPARATION if is_target_mode else ALLY_CONTENT_SEPARATION
		)
	)
	_name_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
		if is_target_mode
		else HORIZONTAL_ALIGNMENT_LEFT
	)
	_extension_slot.visible = (
		is_player_mode and _extension_slot.get_child_count() > 0
	)


## 组件自身离开场景树时断开单位信号，防止场景卸载后残留回调。
func _exit_tree() -> void:
	_kill_damage_tween()
	_disconnect_unit_signals()
