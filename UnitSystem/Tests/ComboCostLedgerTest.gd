extends SceneTree
## 捕捉非连续重复漏计、失败误计、预留不足及关闭轮次丢失旧请求。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var path = "res://UnitSystem/Components/Combat/Squad/ComboCostLedger.gd"
	if not ResourceLoader.exists(path):
		failures.append("cost ledger missing")
		_finish()
		return
	var l = load(path).new()
	_expect(l.register_request(11, 1, 100, &"arrow", 20.0, 10.0), "register first")
	_expect(l.register_request(12, 1, 100, &"arrow", 20.0, 10.0), "register pending second")
	_expect(l.get_reservation_quote(12) == 30.0, "pending predecessor upper bound")
	_expect(l.register_request(11, 1, 100, &"arrow", 20.0, 10.0), "same registration idempotent")
	_expect(not l.register_request(11, 1, 100, &"arrow", 21.0, 10.0), "conflicting registration rejected")
	_expect(l.mark_released(12) == -1.0, "same actor cannot overtake pending predecessor")
	l.release_request(12)
	_expect(l.get_reservation_quote(12) == 30.0, "pending request release refused")
	var promised = SquadFocusComponent.new()
	promised.auto_bind_parent = false
	promised.initial_focus = 50.0
	root.add_child(promised)
	_expect(promised.reserve(12, l.get_reservation_quote(12)) and promised.get_reserved_focus() == 30.0, "reserve failed-predecessor upper bound in real pool")
	l.mark_failed(11)
	l.mark_failed(11)
	_expect(l.mark_released(11) == -1.0 and l.get_final_quote(11) == -1.0, "failed terminal cannot release")
	_expect(l.get_final_quote(12) == 20.0 and l.mark_released(12) == 20.0, "failed predecessor no repeat")
	_expect(l.mark_released(12) == 20.0, "release callback idempotent")
	_expect(promised.commit(12, l.mark_released(12)) and promised.get_current_focus() == 30.0 and promised.get_reserved_focus() == 0.0, "failure releases ten points of excess promise")
	promised.free()
	l.register_request(13, 1, 200, &"fire", 20.0, 10.0)
	l.mark_released(13)
	l.register_request(14, 1, 100, &"arrow", 20.0, 10.0)
	_expect(l.get_final_quote(14) == 30.0, "non-adjacent same actor skill increments")
	l.close_round(1)
	_expect(not l.register_request(15, 1, 100, &"arrow", 20.0, 10.0), "closed round rejects new")
	_expect(l.mark_released(14) == 30.0, "old accepted request still settles")
	l.register_request(21, 2, 100, &"arrow", 20.0, 10.0)
	_expect(l.get_final_quote(21) == 20.0, "new round starts fresh")
	_expect(not l.register_request(22, 2, 100, &"arrow", INF, 10.0), "nonfinite rejected")
	_expect(l.get_final_quote(999) == -1.0, "unknown not free")
	var focus = SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 50.0
	root.add_child(focus)
	focus.reserve(21, l.get_reservation_quote(21))
	_expect(focus.commit(21, l.mark_released(21)) and focus.get_current_focus() == 30.0, "ledger quote commits exact amount")
	for id in [11, 12, 13, 14]: l.release_request(id)
	_expect(not l.register_request(16, 1, 100, &"arrow", 20.0, 10.0), "closed ID cannot reopen after cleanup")
	focus.free()
	_finish()
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for f in failures: push_error(f)
	if failures.is_empty(): print("ComboCostLedgerTest: PASS")
	quit(0 if failures.is_empty() else 1)
