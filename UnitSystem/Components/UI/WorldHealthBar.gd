class_name WorldHealthBar
extends Node3D

## 血条外侧仇恨提示的有限视觉状态。
## NONE 不显示；WARNING 表示该单位正处于玩家锁定敌人的 100% 至 125% 仇恨风险区；CURRENT_TARGET 表示该敌人当前锁定此单位。
enum ThreatIndicatorState {
	NONE,
	WARNING,
	CURRENT_TARGET,
}

## 可拆卸的世界空间头顶血条。
##
## 本组件只订阅 UnitBase 已公开的生命信号。UnitBase 不持有本组件的引用，因此删除
## WorldHealthBar 或整个 WorldUIRoot 都不会影响生命、战斗、移动和索敌逻辑。

@export_category("Placement")
## 血条相对于单位根节点的局部偏移。不同身高角色可以在继承场景中单独覆盖。
@export var local_offset: Vector3 = Vector3(0.0, 1.15, 0.0)

@export_category("Visibility")
## 最后一次受到有效伤害后，血条保持完全可见的时间。
@export_range(0.0, 30.0, 0.1) var visible_duration: float = 2.5
## 可见时间结束后的淡出时长。设置为零时立即隐藏。
@export_range(0.0, 2.0, 0.01) var fade_duration: float = 0.2

@export_category("Damage Trail")
## 绿色生命条下降后，红色损血条开始收缩前的停留时间。
@export_range(0.0, 2.0, 0.01) var damage_hold_duration: float = 0.12
## 红色损血条从旧生命位置收缩到当前生命位置所需的时间。
@export_range(0.0, 3.0, 0.01) var damage_decay_duration: float = 0.35

@export_category("Layout")
## SubViewport 的像素尺寸。世界中的实际尺寸由 BarSprite.pixel_size 决定。
@export var bar_pixel_size: Vector2i = Vector2i(128, 16)
## 白色外框宽度，单位为 UI 像素。
@export_range(0, 8, 1) var border_width: int = 2
## 血条四角的圆角半径，单位为 UI 像素。
@export_range(0, 16, 1) var corner_radius: int = 5

@export_category("Colors")
## 当前实时生命颜色。
@export var health_color: Color = Color(0.18, 0.82, 0.28, 1.0)
## 受到伤害后暂时保留的损失生命颜色。
@export var damage_color: Color = Color(0.92, 0.16, 0.12, 1.0)
## 没有生命填充区域的半透明黑色。
@export var empty_color: Color = Color(0.0, 0.0, 0.0, 0.68)
## 血条外框颜色。
@export var border_color: Color = Color(1.0, 1.0, 1.0, 0.95)

@export_category("Threat Outline")
## 红色当前目标框与黄色仇恨风险框距离血条本体的外侧留白，单位为 UI 像素。
## 默认 3；修改后只扩展本组件的 SubViewport 留白并调整仇恨框位置，不改变绿色生命条、红色损血条或白色边框本体尺寸。
@export_range(0, 16, 1) var threat_outline_margin: int = 3:
	set(value):
		threat_outline_margin = maxi(value, 0)
		if not is_node_ready():
			return
		_configure_layout()

## 红色当前目标框与黄色仇恨风险框自身的线宽，单位为 UI 像素。
## 默认 2；仅影响仇恨提示外框，不会改动普通白色血条边框的 border_width 参数。
@export_range(1, 12, 1) var threat_outline_width: int = 2:
	set(value):
		threat_outline_width = maxi(value, 1)
		if not is_node_ready():
			return
		_apply_threat_outline_style()

@onready var _viewport: SubViewport = $HealthBarViewport
@onready var _bar_root: Control = $HealthBarViewport/BarRoot
@onready var _empty_slot: Panel = $HealthBarViewport/BarRoot/EmptySlot
@onready var _damage_progress: ProgressBar = \
	$HealthBarViewport/BarRoot/DamageBar
@onready var _health_progress: ProgressBar = \
	$HealthBarViewport/BarRoot/HealthBar
@onready var _border: Panel = $HealthBarViewport/BarRoot/Border
@onready var _threat_outline: Panel = $HealthBarViewport/BarRoot/ThreatOutline
@onready var _bar_sprite: Sprite3D = $BarSprite

var _health_source: UnitBase
var _damage_tween: Tween
var _visibility_tween: Tween
## 当前仅由玩家仇恨焦点控制器写入的外框视觉状态。
## 此字段不参与生命、伤害、目标选择或仇恨结算，仅决定本组件是否强制保持可见。
var _threat_indicator_state: ThreatIndicatorState = ThreatIndicatorState.NONE


func _ready() -> void:
	_sanitize_configuration()
	position = local_offset
	_configure_layout()
	_configure_styles()
	_bar_sprite.texture = _viewport.get_texture()
	hide_immediately()
	# 延后一帧绑定，确保继承场景中的 UnitBase 已完成初始生命值初始化。
	call_deferred(&"_auto_bind_ancestor")


func _exit_tree() -> void:
	unbind_health_source()


## 绑定新的生命数据来源。重复绑定同一个单位只刷新数值，不重复连接信号。
func bind_health_source(source: UnitBase) -> void:
	if source == _health_source and is_instance_valid(_health_source):
		refresh_immediately()
		return

	unbind_health_source()
	if not is_instance_valid(source):
		return

	_health_source = source
	if not _health_source.health_changed.is_connected(_on_health_changed):
		_health_source.health_changed.connect(_on_health_changed)
	if not _health_source.damaged.is_connected(_on_damaged):
		_health_source.damaged.connect(_on_damaged)
	if not _health_source.died.is_connected(_on_health_source_died):
		_health_source.died.connect(_on_health_source_died)
	refresh_immediately()


## 断开当前生命来源并停止全部 UI 动画。解绑不会改变单位的任何状态。
func unbind_health_source() -> void:
	if is_instance_valid(_health_source):
		if _health_source.health_changed.is_connected(_on_health_changed):
			_health_source.health_changed.disconnect(_on_health_changed)
		if _health_source.damaged.is_connected(_on_damaged):
			_health_source.damaged.disconnect(_on_damaged)
		if _health_source.died.is_connected(_on_health_source_died):
			_health_source.died.disconnect(_on_health_source_died)
	_health_source = null
	_kill_damage_tween()
	hide_immediately()


## 立即从当前生命来源读取数值。该方法只同步显示，不主动显示隐藏中的血条。
func refresh_immediately() -> void:
	if not is_instance_valid(_health_source):
		return
	if _health_source.is_dead():
		hide_immediately()
		return
	var ratio: float = _calculate_ratio(
		_health_source.get_current_health(),
		_health_source.get_maximum_health()
	)
	_health_progress.value = ratio
	_damage_progress.value = ratio
	if ratio < 1.0:
		_show_indefinitely()


## 显示血条并从头开始隐藏倒计时。连续伤害会安全刷新同一条 Tween。
func show_temporarily() -> void:
	_show_immediately()
	if _threat_indicator_state != ThreatIndicatorState.NONE:
		return
	if not _is_current_health_full():
		return

	_visibility_tween = create_tween()
	if visible_duration > 0.0:
		_visibility_tween.tween_interval(visible_duration)
	if fade_duration > 0.0:
		_visibility_tween.tween_property(
			_bar_sprite,
			^"modulate:a",
			0.0,
			fade_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_visibility_tween.tween_callback(_finish_visibility_hide)


## 显示血条但不创建隐藏倒计时，用于所有未满血状态。
func _show_indefinitely() -> void:
	_show_immediately()


func _show_immediately() -> void:
	_kill_visibility_tween()
	# 每个单位拥有独立 SubViewport；仅显示期间持续刷新，避免隐藏血条浪费渲染。
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	visible = true
	_bar_sprite.modulate.a = 1.0


## 立即隐藏并恢复透明度，供初始化、解绑和外部 UI 管理使用。
func hide_immediately() -> void:
	_kill_visibility_tween()
	visible = false
	_bar_sprite.modulate.a = 1.0
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## 返回组件当前是否持有有效生命来源。
func is_bound() -> bool:
	return is_instance_valid(_health_source)


## 设置本血条外侧的玩家仇恨提示状态。
## state 只能使用 ThreatIndicatorState 枚举值；非预期值会安全回退为 NONE。任何非 NONE 状态都会保持该血条可见，但不会改写生命值或仇恨数据。
func set_threat_indicator_state(state: int) -> void:
	var normalized_state: ThreatIndicatorState = (
		state as ThreatIndicatorState
		if state >= ThreatIndicatorState.NONE
		and state <= ThreatIndicatorState.CURRENT_TARGET
		else ThreatIndicatorState.NONE
	)
	if _threat_indicator_state == normalized_state:
		return
	_threat_indicator_state = normalized_state
	_apply_threat_outline_style()
	if _threat_indicator_state != ThreatIndicatorState.NONE:
		_show_immediately()
		return
	if _is_current_health_full():
		hide_immediately()
	else:
		_show_indefinitely()


## 清除本血条外侧的玩家仇恨提示。
## 该方法等同设置 NONE，供焦点控制器在玩家解锁、仇恨清表、目标失效或离树时统一调用。
func clear_threat_indicator() -> void:
	set_threat_indicator_state(ThreatIndicatorState.NONE)


func _auto_bind_ancestor() -> void:
	if is_bound():
		return
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor is UnitBase:
			bind_health_source(ancestor as UnitBase)
			return
		ancestor = ancestor.get_parent()


func _on_health_changed(
	previous_health: float,
	current_health: float,
	maximum_health: float,
	_source: Node
) -> void:
	if is_instance_valid(_health_source) and _health_source.is_dead():
		hide_immediately()
		return
	var previous_ratio: float = _calculate_ratio(
		previous_health,
		maximum_health
	)
	var current_ratio: float = _calculate_ratio(
		current_health,
		maximum_health
	)
	_health_progress.value = current_ratio
	if current_ratio < 1.0:
		_show_indefinitely()
	elif visible:
		show_temporarily()

	if current_health < previous_health:
		# 连续受伤时保留尚未消退的更长红条，形成自然的累计损血反馈。
		_damage_progress.value = maxf(
			float(_damage_progress.value),
			previous_ratio
		)
		return

	# 治疗或复活不产生红色损血反馈，也不主动显示隐藏的血条。
	_kill_damage_tween()
	_damage_progress.value = current_ratio


func _on_damaged(_amount: float, _source: Node) -> void:
	if is_instance_valid(_health_source) and _health_source.is_dead():
		return
	show_temporarily()
	_start_damage_decay()


## 单位死亡时立即隐藏血条并停止渲染；解绑与复活后的显示仍由现有信号路径管理。
func _on_health_source_died(_source: Node) -> void:
	_kill_damage_tween()
	_threat_indicator_state = ThreatIndicatorState.NONE
	_apply_threat_outline_style()
	hide_immediately()


func _start_damage_decay() -> void:
	_kill_damage_tween()
	var target_ratio: float = float(_health_progress.value)
	if (
		damage_hold_duration <= 0.0
		and damage_decay_duration <= 0.0
	):
		_damage_progress.value = target_ratio
		return

	_damage_tween = create_tween()
	if damage_hold_duration > 0.0:
		_damage_tween.tween_interval(damage_hold_duration)
	if damage_decay_duration > 0.0:
		_damage_tween.tween_property(
			_damage_progress,
			^"value",
			target_ratio,
			damage_decay_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_damage_tween.tween_callback(
			func() -> void:
				_damage_progress.value = target_ratio
		)


func _finish_visibility_hide() -> void:
	if _threat_indicator_state != ThreatIndicatorState.NONE:
		_show_immediately()
		return
	visible = false
	_bar_sprite.modulate.a = 1.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_visibility_tween = null


func _kill_damage_tween() -> void:
	if is_instance_valid(_damage_tween):
		_damage_tween.kill()
	_damage_tween = null


func _kill_visibility_tween() -> void:
	if is_instance_valid(_visibility_tween):
		_visibility_tween.kill()
	_visibility_tween = null


func _sanitize_configuration() -> void:
	visible_duration = maxf(visible_duration, 0.0)
	fade_duration = maxf(fade_duration, 0.0)
	damage_hold_duration = maxf(damage_hold_duration, 0.0)
	damage_decay_duration = maxf(damage_decay_duration, 0.0)
	bar_pixel_size.x = maxi(bar_pixel_size.x, 1)
	bar_pixel_size.y = maxi(bar_pixel_size.y, 1)
	border_width = maxi(border_width, 0)
	corner_radius = maxi(corner_radius, 0)
	threat_outline_margin = maxi(threat_outline_margin, 0)
	threat_outline_width = maxi(threat_outline_width, 1)


func _configure_layout() -> void:
	var viewport_size := Vector2i(
		bar_pixel_size.x + threat_outline_margin * 2,
		bar_pixel_size.y + threat_outline_margin * 2
	)
	_viewport.size = viewport_size
	# 血条本体维持原尺寸并向内平移，外框向外扩展的像素完整落在 SubViewport 渲染范围内。
	_bar_root.position = Vector2(
		threat_outline_margin,
		threat_outline_margin
	)
	_bar_root.size = Vector2(bar_pixel_size)
	_threat_outline.offset_left = -threat_outline_margin
	_threat_outline.offset_top = -threat_outline_margin
	_threat_outline.offset_right = threat_outline_margin
	_threat_outline.offset_bottom = threat_outline_margin
	_health_progress.min_value = 0.0
	_health_progress.max_value = 1.0
	_health_progress.step = 0.001
	_damage_progress.min_value = 0.0
	_damage_progress.max_value = 1.0
	_damage_progress.step = 0.001


func _configure_styles() -> void:
	var empty_style := StyleBoxFlat.new()
	empty_style.bg_color = empty_color
	_set_corner_radius(empty_style, corner_radius)
	_empty_slot.add_theme_stylebox_override(&"panel", empty_style)

	var transparent_background := StyleBoxFlat.new()
	transparent_background.bg_color = Color.TRANSPARENT
	var damage_style := StyleBoxFlat.new()
	damage_style.bg_color = damage_color
	_set_corner_radius(damage_style, corner_radius)
	var health_style := StyleBoxFlat.new()
	health_style.bg_color = health_color
	_set_corner_radius(health_style, corner_radius)
	_damage_progress.add_theme_stylebox_override(
		&"background",
		transparent_background
	)
	_damage_progress.add_theme_stylebox_override(&"fill", damage_style)
	_health_progress.add_theme_stylebox_override(
		&"background",
		transparent_background.duplicate()
	)
	_health_progress.add_theme_stylebox_override(&"fill", health_style)

	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color.TRANSPARENT
	border_style.border_color = border_color
	border_style.border_width_left = border_width
	border_style.border_width_top = border_width
	border_style.border_width_right = border_width
	border_style.border_width_bottom = border_width
	_set_corner_radius(border_style, corner_radius)
	_border.add_theme_stylebox_override(&"panel", border_style)
	_apply_threat_outline_style()


func _apply_threat_outline_style() -> void:
	if not is_instance_valid(_threat_outline):
		return
	_threat_outline.visible = _threat_indicator_state != ThreatIndicatorState.NONE
	if not _threat_outline.visible:
		return
	var outline_style := StyleBoxFlat.new()
	outline_style.bg_color = Color.TRANSPARENT
	outline_style.border_color = (
		Color(1.0, 0.16, 0.12, 1.0)
		if _threat_indicator_state == ThreatIndicatorState.CURRENT_TARGET
		else Color(1.0, 0.82, 0.12, 1.0)
	)
	outline_style.border_width_left = threat_outline_width
	outline_style.border_width_top = threat_outline_width
	outline_style.border_width_right = threat_outline_width
	outline_style.border_width_bottom = threat_outline_width
	_set_corner_radius(outline_style, corner_radius + 2)
	_threat_outline.add_theme_stylebox_override(&"panel", outline_style)


func _set_corner_radius(style: StyleBoxFlat, radius: int) -> void:
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius


func _calculate_ratio(current_health: float, maximum_health: float) -> float:
	if maximum_health <= 0.0:
		return 0.0
	return clampf(current_health / maximum_health, 0.0, 1.0)


func _is_current_health_full() -> bool:
	if not is_instance_valid(_health_source):
		return true
	return is_equal_approx(
		_health_source.get_current_health(),
		_health_source.get_maximum_health()
	)
