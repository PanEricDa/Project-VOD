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
	if row.get_child_count() == 1:
		var dot := row.get_child(0) as Panel
		var style := dot.get_theme_stylebox(&"panel") as StyleBoxFlat
		_expect(style != null and style.bg_color == Color(1.0, 0.31, 0.12), "burning marker is orange-red")
		var health_root := bar.get_node(^"HealthBarViewport/BarRoot") as Control
		_expect(row.position.y + dot.size.y <= health_root.position.y, "marker sits above the health bar")
	_expect(status.apply_named_status(&"burning", 4.0), "burning refreshes")
	_expect(row.get_child_count() == 1, "refresh does not duplicate the marker")
	status.advance_effects(4.1)
	_expect(row.get_child_count() == 0 and not bar.visible, "expiry removes the marker and hides a full-health bar")
	status.apply_named_status(&"burning", 4.0)
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
