extends SceneTree

## 头顶血条组件的独立行为契约测试。
##
## 测试使用真实 UnitBase、真实场景树信号和真实 Tween 时间推进，确保组件不需要
## PlayerBase、AIUnitBase、武器或技能代码也能工作。

const HEALTH_BAR_SCENE_PATH := \
	"res://UnitSystem/Components/UI/WorldHealthBar.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(
		ResourceLoader.exists(HEALTH_BAR_SCENE_PATH),
		"WorldHealthBar scene exists"
	)
	if not ResourceLoader.exists(HEALTH_BAR_SCENE_PATH):
		_finish()
		return

	var scene := load(HEALTH_BAR_SCENE_PATH) as PackedScene
	_expect(scene != null, "WorldHealthBar scene loads as PackedScene")
	_expect(
		ResourceLoader.get_resource_uid(HEALTH_BAR_SCENE_PATH)
			!= ResourceUID.INVALID_ID,
		"WorldHealthBar scene has a valid editor-indexed UID"
	)
	if scene == null:
		_finish()
		return

	var unit := (
		load(UNIT_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	var health_bar := scene.instantiate() as Node3D
	_expect(unit != null and health_bar != null, "runtime fixtures instantiate")
	if unit == null or health_bar == null:
		_finish()
		return

	var world_ui_root := unit.get_node_or_null(^"WorldUIRoot") as Node3D
	var default_health_bar := unit.get_node_or_null(
		^"WorldUIRoot/WorldHealthBar"
	) as Node3D
	_expect(world_ui_root != null, "UnitBase provides a WorldUIRoot slot")
	_expect(
		default_health_bar != null
		and default_health_bar.get_script() == health_bar.get_script(),
		"UnitBase assembles the default WorldHealthBar component"
	)
	_expect(
		not unit.has_method(&"show_health_bar")
		and not unit.has_method(&"hide_health_bar"),
		"UnitBase exposes no reverse dependency on the UI component"
	)

	# 使用很短但留有多帧余量的时间，验证真实计时而不把测试拖慢。
	health_bar.set("visible_duration", 0.40)
	health_bar.set("fade_duration", 0.02)
	health_bar.set("damage_hold_duration", 0.05)
	health_bar.set("damage_decay_duration", 0.04)

	root.add_child(unit)
	unit.add_child(health_bar)
	await process_frame

	var has_public_interface: bool = (
		health_bar.has_method(&"bind_health_source")
		and health_bar.has_method(&"unbind_health_source")
		and health_bar.has_method(&"refresh_immediately")
		and health_bar.has_method(&"show_temporarily")
		and health_bar.has_method(&"hide_immediately")
		and health_bar.has_method(&"is_bound")
	)
	_expect(
		has_public_interface,
		"WorldHealthBar exposes the complete public interface"
	)
	if not has_public_interface:
		await _cleanup(unit)
		return
	_expect(not health_bar.visible, "health bar starts hidden")
	_expect(bool(health_bar.call("is_bound")), "health bar auto-binds UnitBase ancestor")

	var health_progress := health_bar.get_node_or_null(
		^"HealthBarViewport/BarRoot/HealthBar"
	) as Range
	var damage_progress := health_bar.get_node_or_null(
		^"HealthBarViewport/BarRoot/DamageBar"
	) as Range
	var viewport := health_bar.get_node_or_null(
		^"HealthBarViewport"
	) as SubViewport
	var threat_outline := health_bar.get_node_or_null(
		^"HealthBarViewport/BarRoot/ThreatOutline"
	) as Panel
	_expect(
		health_progress != null
		and damage_progress != null
		and viewport != null,
		"green health and red damage ranges exist"
	)
	if (
		health_progress == null
		or damage_progress == null
		or viewport == null
	):
		await _cleanup(unit)
		return
	_expect(
		threat_outline != null and not threat_outline.visible,
		"health bar starts without a threat focus outline"
	)
	_expect(
		health_bar.has_method(&"set_threat_indicator_state")
		and health_bar.has_method(&"clear_threat_indicator"),
		"health bar exposes focused threat outline controls"
	)
	if threat_outline == null:
		await _cleanup(unit)
		return

	health_bar.call("set_threat_indicator_state", 1)
	_expect(
		threat_outline.visible and health_bar.visible,
		"warning threat state shows a yellow outline and keeps the bar visible"
	)
	health_bar.call("set_threat_indicator_state", 2)
	_expect(
		threat_outline.visible,
		"current-target threat state keeps its outer outline visible"
	)
	health_bar.call("clear_threat_indicator")
	_expect(
		not threat_outline.visible,
		"clearing threat state hides the outer outline"
	)

	_expect(
		is_equal_approx(health_progress.value, 1.0)
		and is_equal_approx(damage_progress.value, 1.0),
		"initial ranges match full health"
	)
	_expect(
		viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"hidden health bar disables its private viewport"
	)
	_expect(
		viewport.size == Vector2i(102, 22),
		"viewport reserves a three-pixel margin around the bar for the threat outline"
	)
	health_bar.set("threat_outline_margin", 5)
	health_bar.set("threat_outline_width", 4)
	_expect(
		viewport.size == Vector2i(106, 26),
		"independent threat outline margin is configurable without changing the health bar size"
	)
	health_bar.call("set_threat_indicator_state", 2)
	var active_outline_style := threat_outline.get_theme_stylebox(&"panel") as StyleBoxFlat
	_expect(
		active_outline_style != null and active_outline_style.border_width_left == 4,
		"independent threat outline width controls only the threat frame line width"
	)
	health_bar.call("clear_threat_indicator")

	unit.apply_damage(25.0)
	_expect(health_bar.visible, "effective damage shows the health bar")
	_expect(
		viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"visible health bar enables viewport rendering"
	)
	_expect(
		is_equal_approx(health_progress.value, 0.75),
		"green range updates immediately after damage"
	)
	_expect(
		is_equal_approx(damage_progress.value, 1.0),
		"red range initially preserves the previous health ratio"
	)

	await create_timer(0.25).timeout
	_expect(
		is_equal_approx(damage_progress.value, 0.75),
		"red range decays to the current health ratio"
	)
	_expect(health_bar.visible, "bar remains visible before its configured timeout")

	# 第二次伤害必须重新开始可见倒计时，而不是沿用第一次伤害的剩余时间。
	unit.apply_damage(10.0)
	await create_timer(0.25).timeout
	_expect(health_bar.visible, "repeated damage resets the visibility timeout")
	await create_timer(0.25).timeout
	_expect(
		health_bar.visible,
		"bar remains visible after timeout while health is below full"
	)
	_expect(
		viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"injured health bar keeps its private viewport rendering"
	)

	unit.apply_healing(20.0)
	await process_frame
	_expect(health_bar.visible, "partially healed health bar remains visible")
	_expect(
		is_equal_approx(health_progress.value, 0.85)
		and is_equal_approx(damage_progress.value, 0.85),
		"healing synchronizes both ranges without a red trail"
	)
	unit.apply_healing(15.0)
	await create_timer(0.5).timeout
	_expect(not health_bar.visible, "full health bar hides after its configured timeout")
	_expect(
		viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"full hidden health bar stops its private viewport rendering"
	)

	unit.apply_damage(5.0)
	_expect(health_bar.visible, "damage shows the health bar before the death test")
	unit.apply_damage(9999.0)
	_expect(
		not health_bar.visible,
		"death hides the health bar immediately"
	)
	_expect(
		viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"dead hidden health bar stops its private viewport rendering"
	)

	health_bar.call("unbind_health_source")
	var value_before_unbound_damage: float = health_progress.value
	unit.apply_damage(5.0)
	await process_frame
	_expect(not bool(health_bar.call("is_bound")), "unbind clears the health source")
	_expect(
		is_equal_approx(health_progress.value, value_before_unbound_damage),
		"unbound health changes no longer update the component"
	)

	await _cleanup(unit)


func _cleanup(unit: Node) -> void:
	unit.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("WorldHealthBarTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
