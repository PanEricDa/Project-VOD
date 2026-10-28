extends SceneTree

## 真实单位状态驱动头顶血条圆点；检验增加、刷新、到期、死亡与满血显示。
const UNIT_SCENE := "res://UnitSystem/Base/00_UnitBase.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var unit := (load(UNIT_SCENE) as PackedScene).instantiate() as UnitBase
	root.add_child(unit)
	await process_frame
	var bar := unit.get_node(^"WorldUIRoot/WorldHealthBar") as WorldHealthBar
	var status := unit.get_status_effect_component() as StatusEffectComponent
	var row := bar.get_node_or_null(^"HealthBarViewport/DebuffDots") as HBoxContainer
	_expect(row != null, "head bar has a debuff row")
	_expect(status.has_signal(&"named_status_changed"), "named status exposes changes to UI")
	if row == null or not status.has_signal(&"named_status_changed"):
		_finish(unit)
		return
	_expect(row.get_child_count() == 0 and not bar.visible, "full healthy unit starts without a marker")
	_expect(status.apply_named_status(&"burning", 4.0), "burning applies")
	_expect(row.get_child_count() == 1 and bar.visible, "burning draws one marker even at full health")
	await process_frame
	if row.get_child_count() == 1:
		var dot := row.get_child(0) as Panel
		var style := dot.get_theme_stylebox(&"panel") as StyleBoxFlat
		_expect(style != null and style.bg_color == Color(1.0, 0.31, 0.12), "burning marker is orange-red")
		var health_root := bar.get_node(^"HealthBarViewport/BarRoot") as Control
		_expect(dot.size == Vector2(12, 12), "debuff marker is 1.5 times the previous 8-pixel size")
		_expect(
			is_equal_approx(row.position.x + dot.position.x, health_root.position.x),
			"first marker aligns with the health bar's left edge"
		)
		_expect(
			is_equal_approx(health_root.position.y - (row.position.y + dot.size.y), 4.0),
			"marker has a four-pixel gap above the health bar"
		)
		_expect(row.alignment == BoxContainer.ALIGNMENT_BEGIN, "future markers append toward the right")
	_expect(status.apply_named_status(&"burning", 4.0), "burning refreshes")
	_expect(row.get_child_count() == 1, "refresh does not duplicate the marker")
	status.advance_effects(4.1)
	_expect(row.get_child_count() == 0 and not bar.visible, "expiry removes the marker and hides a full-health bar")
	# 实际属性修正驱动图标，而非额外的命名状态或UI倒计时。
	status.set_physics_process(false)
	var defense_source := Node.new()
	var other_source := Node.new()
	var buff_source := Node.new()
	unit.add_child(defense_source)
	unit.add_child(other_source)
	unit.add_child(buff_source)
	status.apply_modifier(buff_source,StatusEffectComponent.ModifierStat.DEFENSE,20.0,30.0)
	status.apply_modifier(buff_source,StatusEffectComponent.ModifierStat.ATTACK_POWER,-5.0,30.0)
	_expect(row.get_child_count() == 0, "defense buff and attack debuff do not masquerade as defense reduction")
	status.apply_modifier(defense_source,StatusEffectComponent.ModifierStat.DEFENSE,-25.0,15.0,0,StatusEffectComponent.ModifierMode.PERCENT)
	_expect(row.get_child_count() == 1 and bar.visible and row.has_node("DefenseDownDot"), "percentage defense reduction shows one dot even at full health")
	var defense_dot := row.get_node_or_null("DefenseDownDot") as Panel
	if defense_dot != null:
		var defense_style := defense_dot.get_theme_stylebox(&"panel") as StyleBoxFlat
		_expect(defense_style.bg_color == Color(0.62,0.4,1.0), "defense reduction marker is purple, distinct from burning")
		_expect(defense_dot.custom_minimum_size == Vector2(12,12), "defense marker uses the existing size")
	status.advance_effects(10.0)
	status.apply_modifier(defense_source,StatusEffectComponent.ModifierStat.DEFENSE,-25.0,15.0,0,StatusEffectComponent.ModifierMode.PERCENT)
	status.apply_named_status(&"burning",30.0)
	await process_frame
	_expect(row.get_child_count() == 2 and row.get_child(0).name == &"BurningDot" and row.get_child(1).name == &"DefenseDownDot", "burning and armor break coexist without overlap")
	if row.get_child_count() == 2:
		_expect((row.get_child(1) as Control).position.x > (row.get_child(0) as Control).position.x, "defense marker appends to the right")
	status.apply_modifier(other_source,StatusEffectComponent.ModifierStat.DEFENSE,-2.0,2.0)
	_expect(row.get_child_count() == 2, "multiple defense reductions share one marker")
	status.advance_effects(2.1)
	_expect(row.has_node("DefenseDownDot"), "one source expiring does not hide a remaining defense reduction")
	status.advance_effects(13.0)
	_expect(row.get_child_count() == 1 and row.has_node("BurningDot"), "last refreshed defense reduction expiry removes only its own marker")
	status.apply_modifier(defense_source,StatusEffectComponent.ModifierStat.DEFENSE,-2.0,15.0)
	_expect(row.has_node("DefenseDownDot"), "flat defense reduction uses the same marker")
	status.remove_modifiers_from_source(defense_source)
	_expect(not row.has_node("DefenseDownDot") and row.has_node("BurningDot"), "explicit removal updates the marker immediately")
	var transient_source := Node.new()
	unit.add_child(transient_source)
	status.apply_modifier(transient_source,StatusEffectComponent.ModifierStat.DEFENSE,-2.0,1.0)
	transient_source.free()
	status.advance_effects(1.1)
	_expect(not row.has_node("DefenseDownDot") and row.has_node("BurningDot"), "source disappearing before expiry still removes the marker safely")
	status.apply_modifier(defense_source,StatusEffectComponent.ModifierStat.DEFENSE,-25.0,15.0,0,StatusEffectComponent.ModifierMode.PERCENT)
	bar.bind_health_source(unit)
	_expect(row.get_child_count() == 2, "rebinding the same source does not duplicate markers")
	bar.unbind_health_source()
	_expect(row.get_child_count() == 0 and status.modifier_changed.get_connections().is_empty() and status.modifier_removed.get_connections().is_empty(), "unbind clears dots and releases modifier signal subscriptions")
	bar.bind_health_source(unit)
	_expect(row.get_child_count() == 2, "late binding immediately restores existing burning and defense reduction")
	status.apply_bound_status(&"temporary_threat",unit,&"ui_test",8.0,Callable(unit,"get_instance_id"))
	_expect(row.get_child_count()==3 and row.has_node("TemporaryThreatDot"),"temporary threat adds its own third dot beside burning and defense down")
	var mark := row.get_node_or_null("TemporaryThreatDot") as Panel
	if mark != null:
		_expect(mark.get_theme_stylebox("panel").bg_color==Color(1.0,0.25,0.6),"temporary threat marker is rose, distinct from burning and defense down")
	status.remove_named_status(&"temporary_threat")
	_expect(row.get_child_count()==2 and not row.has_node("TemporaryThreatDot"),"temporary threat removal preserves other dots")
	unit.apply_damage(9999.0)
	_expect(row.get_child_count() == 0 and not bar.visible, "death clears the marker and hides the bar")
	_finish(unit)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish(unit: Node) -> void:
	unit.queue_free()
	for failure: String in failures:
		push_error(failure)
	print("WorldHealthBarDebuffTest: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
