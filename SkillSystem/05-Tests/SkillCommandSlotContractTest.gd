extends SceneTree
## 连携配置与请求数据的行为契约；通过真实Host/Skill与信号检查独立性、非法配置及终态。
var failures: Array[String] = []
var _finished: int = 0
const HOST = preload("res://SkillSystem/01-Core/SkillHostComponent.tscn")
const SKILL = preload("res://SkillSystem/01-Core/SkillBase.tscn")

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var request_path = "res://SkillSystem/01-Core/SkillCommandRequest.gd"
	var cost_path = "res://SkillSystem/03-Extensions/ComboFocusCost.gd"
	if not ResourceLoader.exists(request_path) or not ResourceLoader.exists(cost_path):
		_expect(false, "Request lifecycle and configurable focus cost must exist")
		_finish()
		return
	var scope = Node3D.new()
	root.add_child(scope)
	var caster = Node3D.new()
	scope.add_child(caster)
	var host = HOST.instantiate()
	caster.add_child(host)
	if not host.has_method(&"get_combo_skill"):
		_expect(false, "Host must expose independent combo slot")
		scope.free()
		_finish()
		return
	var a = _add_skill(host, &"regular")
	var b = _add_skill(host, &"combo")
	var cost = load(cost_path).new()
	b.add_child(cost)
	var regular_slots: Array[SkillBase] = [a, null]
	host.regular_skills = regular_slots
	host.set("combo_skill", b)
	_expect(host.call("get_combo_skill") == b, "independent combo equipped")
	_expect(not host.get_equipped_regular_skills().has(b), "automatic selection excludes combo")
	_expect(host.get_regular_skill(0) == a, "regular unchanged")
	_expect(a.call("get_combo_focus_cost") == null, "regular skill does not need combo cost")
	b.skill_id = a.skill_id
	_expect(host.call("get_combo_skill") == null, "mutated duplicate ID rejected")
	b.skill_id = &"combo"
	var other_caster = Node3D.new()
	scope.add_child(other_caster)
	var other_host = HOST.instantiate()
	other_caster.add_child(other_host)
	var foreign = _add_skill(other_host, &"foreign")
	foreign.add_child(load(cost_path).new())
	host.set("combo_skill", foreign)
	_expect(host.call("get_combo_skill") == null, "foreign Host instance rejected")
	host.set("combo_skill", b)
	host.set("combo_skill", a)
	_expect(host.call("get_combo_skill") == null, "same regular instance rejected")
	host.set("combo_skill", b)
	host.finisher_skill = b
	_expect(host.call("get_combo_skill") == null, "same finisher instance rejected")
	host.finisher_skill = null
	host.unregister_skill(b)
	_expect(host.call("get_combo_skill") == null, "unregistered combo rejected")
	host.register_skill(b)
	var extra = load(cost_path).new()
	b.add_child(extra)
	_expect(b.call("get_combo_focus_cost") == null, "duplicate costs rejected")
	extra.free()
	_expect(b.call("get_combo_focus_cost") == cost, "single cost valid")
	b.remove_child(cost)
	_expect(host.call("get_combo_skill") == null, "missing cost disables combo")
	b.add_child(cost)
	for invalid in [-1.0, INF, NAN]:
		cost.base_focus_cost = invalid
		_expect(b.call("get_combo_focus_cost") == null, "invalid base cost rejected")
	cost.base_focus_cost = 20.0
	cost.repeat_focus_cost = -1.0
	_expect(b.call("get_combo_focus_cost") == null, "negative repeat rejected")
	cost.repeat_focus_cost = 10.0
	var rq_script = load(request_path)
	var rq = rq_script.create(101, 100, caster, b, scope, 8.0, Callable(self, "_allow"))
	_expect(rq != null and rq.authorize_release(), "valid request authorization")
	_expect(rq_script.create(0, 100, caster, b, scope, 8.0, Callable(self, "_allow")) == null, "invalid root identity rejected")
	_expect(rq_script.create(103, 100, caster, b, scope, INF, Callable(self, "_allow")) == null, "nonfinite wait rejected")
	_expect(rq_script.create(104, 100, caster, foreign, scope, 8.0, Callable(self, "_allow")) == null, "foreign skill request rejected")
	var unauthorized = rq_script.create(105, 100, caster, b, scope, 8.0, Callable())
	_expect(not unauthorized.authorize_release(), "missing authorizer fails closed")
	var ctx = SkillContext.new()
	ctx.set("command_request", rq)
	ctx.set("purpose", 1)
	ctx.damage_context = CombatDamageContext.create(caster, scope, CombatDamageContext.Origin.CHAIN, 101, 100, &"combo")
	var copy = ctx.duplicate_context()
	_expect(copy.get("command_request") == rq and copy.get("purpose") == 1, "request shared and purpose copied")
	_expect(copy.damage_context != ctx.damage_context and copy.damage_context.request_id == 101, "provenance copied independently")
	rq.lifetime_finished.connect(_on_finished)
	_expect(rq.retain_delivery(200), "new token retained")
	_expect(not rq.retain_delivery(200), "duplicate token rejected")
	rq.tick_wait(7.0)
	_expect(not rq.has_wait_expired(), "deadline not early")
	rq.mark_action_started()
	rq.tick_wait(5.0)
	_expect(not rq.has_wait_expired(), "wait stops at animation start")
	rq.mark_released()
	rq.mark_failed(&"late")
	rq.mark_action_finished()
	_expect(_finished == 0 and rq.has_released() and not rq.has_failed(), "action done does not end flying delivery or undo success")
	rq.finish_delivery(999)
	_expect(_finished == 0, "unknown token cannot end request")
	rq.finish_delivery(200)
	rq.finish_delivery(200)
	rq.mark_action_finished()
	_expect(_finished == 1 and not rq.retain_delivery(201), "lifetime once and cannot reopen")
	var waiting = rq_script.create(102, 100, caster, b, scope, 8.0, Callable(self, "_allow"))
	waiting.tick_wait(8.0)
	_expect(waiting.has_wait_expired(), "deadline inclusive")
	waiting.mark_failed(&"timeout")
	caster.free()
	_expect(rq.get_caster() == null and rq.get_skill() == null, "weak owners do not retain freed nodes")
	scope.free()
	_finish()

func _add_skill(host: SkillHostComponent, id: StringName) -> SkillBase:
	var skill = SKILL.instantiate() as SkillBase
	skill.skill_id = id
	host.get_node("SkillSocket").add_child(skill)
	host.register_skill(skill)
	return skill

func _allow() -> bool:
	return true

func _on_finished(_request_id: int, _round_id: int) -> void:
	_finished += 1

func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _finish() -> void:
	for f in failures: push_error(f)
	if failures.is_empty(): print("SkillCommandSlotContractTest: PASS")
	quit(0 if failures.is_empty() else 1)
