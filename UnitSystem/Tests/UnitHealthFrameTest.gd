extends SceneTree

## 验证 UnitHealthFrame 对单个 UnitBase 的绑定、信号驱动更新与生命周期契约。
## 本测试只使用公开方法与稳定节点路径，不访问组件私有字段。

const FRAME_PATH := "res://UnitSystem/Components/UI/UnitHealthFrame.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ResourceLoader.exists(FRAME_PATH), "UnitHealthFrame scene exists")
	if not ResourceLoader.exists(FRAME_PATH):
		_finish()
		return

	var frame_scene := load(FRAME_PATH) as PackedScene
	var unit_scene := load(UNIT_PATH) as PackedScene
	_expect(frame_scene != null and unit_scene != null, "fixtures load")
	if frame_scene == null or unit_scene == null:
		_finish()
		return

	var frame := frame_scene.instantiate() as Control
	var first_unit := unit_scene.instantiate() as UnitBase
	first_unit.name = "测试玩家"
	first_unit.maximum_health = 200.0
	first_unit.starting_health_percentage = 75.0
	root.add_child(first_unit)
	root.add_child(frame)
	await process_frame
	_expect(
		_has_property(frame, &"damage_hold_duration")
		and _has_property(frame, &"damage_decay_duration"),
		"damage trail timings are configurable"
	)
	if _has_property(frame, &"damage_hold_duration"):
		frame.set("damage_hold_duration", 0.04)
	if _has_property(frame, &"damage_decay_duration"):
		frame.set("damage_decay_duration", 0.08)

	_expect(frame.has_method(&"bind_unit"), "bind_unit is public")
	_expect(frame.has_method(&"unbind_unit"), "unbind_unit is public")
	_expect(frame.has_method(&"set_presentation_mode"), "presentation mode is public")
	_expect(frame.has_method(&"refresh_immediately"), "refresh is public")
	_expect(frame.has_method(&"is_bound"), "binding query is public")
	frame.call(&"bind_unit", first_unit)
	await process_frame

	var name_label := frame.get_node(^"FrameContent/CoreInfo/Header/NameLabel") as Label
	var state_label := frame.get_node(^"FrameContent/CoreInfo/Header/StateLabel") as Label
	var health_bar := frame.get_node(^"FrameContent/CoreInfo/HealthBar") as ProgressBar
	var centered_health_value := frame.get_node_or_null(
		^"FrameContent/CoreInfo/HealthBar/HealthValue"
	) as Label
	var legacy_health_value := frame.get_node_or_null(
		^"FrameContent/CoreInfo/HealthValue"
	) as Label
	var health_value := (
		centered_health_value
		if centered_health_value != null
		else legacy_health_value
	)
	var damage_bar := frame.get_node_or_null(
		^"FrameContent/CoreInfo/HealthBar/DamageBar"
	) as ProgressBar
	var health_border := frame.get_node_or_null(
		^"FrameContent/CoreInfo/HealthBar/HealthBorder"
	) as Panel
	var extension_slot := frame.get_node(^"FrameContent/ExtensionSlot") as Control
	var frame_style := frame.get_theme_stylebox(&"panel") as StyleBoxFlat
	_expect(
		frame_style != null
		and is_zero_approx(frame_style.bg_color.a)
		and _style_has_no_border(frame_style),
		"unit frame has no dark panel or outer border"
	)
	_expect(
		name_label.get_theme_font_size(&"font_size") == 36,
		"player name font is doubled to 36 pixels"
	)
	frame.call(&"set_presentation_mode", 1)
	_expect(
		name_label.get_theme_font_size(&"font_size") == 30,
		"compact ally name font is doubled to 30 pixels"
	)
	frame.call(&"set_presentation_mode", 0)
	_expect(
		centered_health_value != null
		and centered_health_value.get_parent() == health_bar,
		"health value is overlaid inside the health bar"
	)
	if centered_health_value != null:
		_expect(
			centered_health_value.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
			and centered_health_value.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
			"health value is centered in both axes"
		)
		_expect(
			centered_health_value.get_theme_color(&"font_outline_color").is_equal_approx(Color.BLACK)
			and centered_health_value.get_theme_constant(&"outline_size") >= 3,
			"health value uses a readable black outline"
		)
	_expect(health_border != null, "health bar has an independent white border")
	if health_border != null:
		var border_style := health_border.get_theme_stylebox(&"panel") as StyleBoxFlat
		_expect(
			border_style != null
			and border_style.border_color.is_equal_approx(Color.WHITE)
			and _style_has_uniform_border(border_style, 2),
			"health bar border is uniformly two-pixel white"
		)
	_expect(damage_bar != null, "damage trail bar exists behind current health")
	if damage_bar != null:
		_expect(
			_fill_color_is(damage_bar, Color(0.92, 0.16, 0.12, 1.0)),
			"damage trail uses the configured red fill"
		)
	_expect(frame.visible and bool(frame.call(&"is_bound")), "binding shows frame")
	_expect(name_label.text == "测试玩家", "node name is the display-name fallback")
	_expect(health_value.text == "150 / 200", "initial health text is current over maximum")
	_expect(is_equal_approx(health_bar.value, 0.75), "initial ratio is correct")
	_expect(
		_fill_color_is(health_bar, Color(0.59, 0.82, 0.20, 1.0)),
		"seventy-five percent health interpolates halfway from yellow to green"
	)
	_expect(not state_label.visible and not extension_slot.visible, "unused state and extension stay collapsed")

	first_unit.apply_damage(50.0)
	_expect(health_value.text == "100 / 200", "damage updates text from signal")
	_expect(is_equal_approx(health_bar.value, 0.5), "damage updates ratio from signal")
	_expect(
		_fill_color_is(health_bar, Color(1.0, 0.82, 0.12, 1.0)),
		"half health is yellow"
	)
	if damage_bar != null:
		_expect(
			is_equal_approx(damage_bar.value, 0.75),
			"damage trail initially preserves the previous health ratio (value=%s)"
			% damage_bar.value
		)
	await create_timer(0.02).timeout
	first_unit.apply_damage(20.0)
	if damage_bar != null:
		_expect(
			is_equal_approx(damage_bar.value, 0.75),
			"repeated damage preserves the longest undisappeared red trail (value=%s)"
			% damage_bar.value
		)
		await create_timer(0.16).timeout
		_expect(
			is_equal_approx(damage_bar.value, 0.4),
			"red trail decays to current health after hold and decay durations"
		)

	first_unit.apply_healing(20.0)
	await process_frame
	_expect(health_value.text == "100 / 200", "healing updates text from signal")
	if damage_bar != null:
		_expect(
			is_equal_approx(damage_bar.value, 0.5),
			"healing cancels and synchronizes the damage trail"
		)

	var comparison_frame := frame_scene.instantiate() as Control
	var comparison_unit := unit_scene.instantiate() as UnitBase
	comparison_unit.name = "满血单位"
	comparison_unit.maximum_health = 100.0
	root.add_child(comparison_unit)
	root.add_child(comparison_frame)
	await process_frame
	comparison_frame.call(&"bind_unit", comparison_unit)
	await process_frame
	var comparison_health_bar := comparison_frame.get_node(
		^"FrameContent/CoreInfo/HealthBar"
	) as ProgressBar
	_expect(
		_fill_color_is(comparison_health_bar, Color(0.18, 0.82, 0.28, 1.0)),
		"full health is green"
	)
	first_unit.apply_damage(50.0)
	await process_frame
	_expect(
		_fill_color_is(health_bar, Color(0.96, 0.49, 0.12, 1.0)),
		"quarter health interpolates halfway from red to yellow"
	)
	_expect(
		_fill_color_is(comparison_health_bar, Color(0.18, 0.82, 0.28, 1.0)),
		"one unit changing health does not recolor another frame"
	)

	first_unit.apply_damage(9999.0)
	await process_frame
	_expect(frame.visible, "dead unit keeps its stable frame")
	_expect(state_label.visible and state_label.text == "倒下", "death state is explicit")
	_expect(health_value.text == "0 / 200", "lethal damage displays zero")
	_expect(first_unit.revive(40.0), "fixture revives")
	await process_frame
	_expect(not state_label.visible, "revive clears death state")
	_expect(health_value.text == "40 / 200", "revive restores health display")
	if damage_bar != null:
		await create_timer(0.16).timeout
		_expect(
			is_equal_approx(damage_bar.value, 0.2),
			"revive cancels the lethal damage tween and keeps both bars synchronized"
		)

	frame.call(&"unbind_unit")
	first_unit.apply_healing(10.0)
	await process_frame
	_expect(not frame.visible and not bool(frame.call(&"is_bound")), "unbind hides and clears")
	_expect(health_value.text == "0 / 0", "unbind resets the visible data")
	first_unit.apply_healing(10.0)
	await process_frame
	_expect(health_value.text == "0 / 0", "old source no longer updates after unbind")

	var second_unit := unit_scene.instantiate() as UnitBase
	second_unit.name = "第二单位"
	second_unit.maximum_health = 80.0
	root.add_child(second_unit)
	await process_frame
	frame.call(&"bind_unit", second_unit)
	frame.call(&"bind_unit", second_unit)
	second_unit.apply_damage(10.0)
	await process_frame
	_expect(health_value.text == "70 / 80", "repeat binding does not duplicate signal behavior")
	second_unit.queue_free()
	await process_frame
	_expect(not frame.visible and not bool(frame.call(&"is_bound")), "source tree exit unbinds safely")

	comparison_frame.queue_free()
	comparison_unit.queue_free()
	frame.queue_free()
	first_unit.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## 返回对象是否公开指定属性，避免 RED 阶段因尚未新增导出字段产生引擎级无效 set 错误。
func _has_property(object: Object, property_name: StringName) -> bool:
	for property_data: Dictionary in object.get_property_list():
		if StringName(property_data.get("name", &"")) == property_name:
			return true
	return false


## 读取 ProgressBar 当前实际填充样式并比较颜色；没有 StyleBoxFlat 时安全失败。
func _fill_color_is(progress: ProgressBar, expected: Color) -> bool:
	var fill_style := progress.get_theme_stylebox(&"fill") as StyleBoxFlat
	return fill_style != null and fill_style.bg_color.is_equal_approx(expected)


## 返回 StyleBoxFlat 是否完全没有边框，用于验证 HUD 外层不再形成黑色底框。
func _style_has_no_border(style: StyleBoxFlat) -> bool:
	return _style_has_uniform_border(style, 0)


## 返回 StyleBoxFlat 四边是否都使用指定宽度。
func _style_has_uniform_border(style: StyleBoxFlat, width: int) -> bool:
	return (
		style.border_width_left == width
		and style.border_width_top == width
		and style.border_width_right == width
		and style.border_width_bottom == width
	)


func _finish() -> void:
	if _failures.is_empty():
		print("UnitHealthFrameTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("UnitHealthFrameTest: FAIL (%d)" % _failures.size())
	quit(1)
