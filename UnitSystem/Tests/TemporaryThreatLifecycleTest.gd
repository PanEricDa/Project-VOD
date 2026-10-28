extends SceneTree
## 真实仇恨容器契约；故意改变撤销/合计/衰减/刷新规则时应失败，不依赖源码文本。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _unit(world: Node, team: int) -> UnitBase:
	var unit := UnitBase.new()
	unit.team_id = team
	world.add_child(unit)
	return unit
func _threat(owner: UnitBase) -> EnemyThreatComponent:
	var component := EnemyThreatComponent.new()
	owner.add_child(component)
	component.configure(owner)
	component.set_process(false)
	component.threat_half_life = 0
	return component
func _add(threat: EnemyThreatComponent, source: UnitBase, amount: float) -> void:
	threat.submit_threat(ThreatEvent.create_damage(source,amount))
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var owner := _unit(world,2)
	var source := _unit(world,1)
	var other := _unit(world,1)
	var threat := _threat(owner)
	_check(threat.has_method("upsert_temporary_threat"),"temporary threat API exists")
	if threat.has_method("upsert_temporary_threat"):
		_add(threat,source,100)
		var first: int = threat.call("upsert_temporary_threat",source,&"mark",2000.0)
		_check(first>0 and is_equal_approx(threat.get_threat_for(source),2100),"ordinary100 plus temporary2000")
		_add(threat,source,50)
		_check(is_equal_approx(threat.get_threat_for(source),2150),"ordinary additions never overwrite temporary contribution")
		var refreshed: int = threat.call("upsert_temporary_threat",source,&"mark",2000.0)
		_check(refreshed>first and is_equal_approx(threat.get_threat_for(source),2150),"same source/effect refresh does not stack and gets a new generation")
		_check(not threat.call("remove_temporary_threat",first) and is_equal_approx(threat.get_threat_for(source),2150),"stale token cannot remove refreshed contribution")
		var second: int = threat.call("upsert_temporary_threat",source,&"other",25.0)
		var competitor: int = threat.call("upsert_temporary_threat",other,&"mark",100.0)
		_check(is_equal_approx(threat.get_threat_ratio_against_highest_competitor(source),21.75),"relative ratio includes all temporary records")
		var snapshot := threat.get_threat_snapshot()
		_check(snapshot.size()==2,"snapshot includes temporary-only source once")
		threat.call("remove_temporary_threat",second)
		threat.call("remove_temporary_threat",refreshed)
		_check(is_equal_approx(threat.get_threat_for(source),150),"removal preserves ordinary pool")
		threat.call("remove_temporary_threat",competitor)
		_check(threat.call("upsert_temporary_threat",source,&"bad",NAN)==0,"NaN temporary amount rejected")
		threat.clear_threat()
		var control_owner := _unit(world,2)
		var control := _threat(control_owner)
		threat.threat_half_life = 1
		control.threat_half_life = 1
		_add(threat,source,100)
		_add(control,source,100)
		var decayed: int = threat.call("upsert_temporary_threat",source,&"decay",2000.0)
		for index: int in range(60):
			threat._process(0.01)
			control._process(0.01)
		_add(threat,source,50)
		_add(control,source,50)
		for index: int in range(60):
			threat._process(0.01)
			control._process(0.01)
		threat.call("remove_temporary_threat",decayed)
		_check(is_equal_approx(threat.get_threat_for(source),control.get_threat_for(source)),"expiry retains independently decayed ordinary threat, not total-minus-initial")
		threat.clear_threat()
		var prepared: int = threat.call("prepare_temporary_threat",source,&"pending",2000.0)
		_check(threat.get_threat_for(source)==0,"prepared contribution is invisible")
		threat.clear_threat()
		_check(not threat.call("commit_temporary_threat",prepared),"clear invalidates pending commits")
	_test_bound_lifecycle(world)
	_test_reentrant_bound_lifecycle(world)
	await _test_bound_clock(world)
	_test_review_regressions(world)
	world.free()
	await process_frame
	for message: String in failures: printerr("FAIL: ",message)
	print("TemporaryThreatLifecycleTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


# 最终独立review的三个反例：实际调用组件，修正前分别验证失败，之后防止回滚复活旧状态。
func _test_review_regressions(world: Node3D) -> void:
	var owner := _unit(world,2)
	var source := _unit(world,1)
	var threat := _threat(owner)
	var status := _status(owner)
	_bind(threat,status,source,&"revive",8)
	source.apply_damage(100000)
	_check(source.revive(50),"source can revive in place")
	_check(_bind(threat,status,source,&"revive",8)>0 and status.has_named_status(&"temporary_threat"),"review1 revived source can receive temporary threat again")
	threat.clear_threat()
	source = _unit(world,1)
	_check(_bind(threat,status,source,&"faction",8)>0,"review2 initial binding exists")
	threat.temporary_threat_removed.connect(func(_token: int): source.team_id=2,CONNECT_ONE_SHOT)
	var refreshed := _bind(threat,status,source,&"faction",8)
	_check(refreshed==0 and threat.get_threat_for(source)==0 and not status.has_named_status(&"temporary_threat"),"review2 terminated suspended old generation cannot be restored after hostility changes")
	source.team_id=1
	threat.clear_threat()
	_check(_bind(threat,status,source,&"clear",8)>0,"review3 initial binding exists")
	var prepared: int = status.call("prepare_bound_status",&"temporary_threat",source,&"clear",8.0,Callable(status,"clear_all_named_statuses"))
	_check(not status.call("commit_bound_status",prepared,func(): return false),"review3 intentionally failed commit")
	_check(not status.has_named_status(&"temporary_threat") and threat.get_threat_for(source)==0,"review3 cleanup clear request cannot be undone by restoring an old record")

func _test_bound_clock(world: Node3D) -> void:
	var owner := _unit(world,2)
	var source := _unit(world,1)
	var threat := _threat(owner)
	var status := _status(owner)
	status.set_physics_process(true)
	var original_scale := Engine.time_scale
	Engine.time_scale = 0.05
	# 先越过切换time_scale时已捕获旧delta的启动帧，再创建状态；不将启动补帧误作新时钟。
	await process_frame
	await process_frame
	_bind(threat,status,source,&"clock",0.1)
	for index: int in range(12): await physics_frame
	_check(status.has_named_status(&"temporary_threat"),"5 percent world time advances only0.01 battle-seconds across12physics frames")
	Engine.time_scale = original_scale
	paused = true
	await create_timer(0.12,true,false,true).timeout
	_check(status.has_named_status(&"temporary_threat"),"paused world does not advance the bound timer")
	paused = false
	await create_timer(0.16,true,false,true).timeout
	_check(not status.has_named_status(&"temporary_threat") and threat.get_threat_for(source)==0,"normal world time resumes and expires the same bound timer")

func _test_reentrant_bound_lifecycle(world: Node3D) -> void:
	var owner := _unit(world,2)
	var source := _unit(world,1)
	var threat := _threat(owner)
	var status := _status(owner)
	_bind(threat,status,source,&"mark",8)
	var replacement := [0]
	var once := [false]
	threat.temporary_threat_removed.connect(func(_token: int):
		if once[0]: return
		once[0] = true
		replacement[0] = _bind(threat,status,source,&"mark",8)
	)
	status.remove_named_status(&"temporary_threat")
	_check(replacement[0]>0 and status.has_named_status(&"temporary_threat") and threat.get_threat_for(source)==2000,"cleanup reentry preserves its new generation")
	threat.clear_threat()
	# 另一个容器只测试退出回调，避免上面的observer继续干扰。
	var owner2 := _unit(world,2)
	var threat2 := _threat(owner2)
	var status2 := _status(owner2)
	var leaving := _unit(world,1)
	_bind(threat2,status2,leaving,&"exit",8)
	var attempted := [-1]
	var leaving_ref: WeakRef = weakref(leaving)
	threat2.temporary_threat_removed.connect(func(_token: int):
		attempted[0] = _bind(threat2,status2,leaving_ref.get_ref() as UnitBase,&"exit",8)
	)
	world.remove_child(leaving)
	_check(attempted[0]==0 and not status2.has_named_status(&"temporary_threat") and threat2.get_threat_snapshot().is_empty(),"source exit cleanup rejects reentrant new effects immediately")
	leaving.free()

# 状态与账本真实绑定；省略绑定/刷新隔离/聚合查询会使这些行为断言失败。
func _status(owner: UnitBase) -> StatusEffectComponent:
	var status := StatusEffectComponent.new()
	owner.add_child(status)
	status.configure_owner(owner)
	status.set_physics_process(false)
	return status
func _bind(threat: Node, status: Node, source: UnitBase, key: StringName, duration: float) -> int:
	var contribution: int = threat.call("prepare_temporary_threat",source,key,2000.0)
	var bound: int = status.call("prepare_bound_status",&"temporary_threat",source,key,duration,Callable(threat,"remove_temporary_threat").bind(contribution))
	if bound <= 0:
		threat.call("discard_temporary_threat",contribution)
		return 0
	status.call("bind_external_status_removal",bound,threat.temporary_threat_removed,contribution)
	if not status.call("commit_bound_status",bound,Callable(threat,"commit_temporary_threat").bind(contribution)):
		status.call("discard_bound_status",bound)
		threat.call("discard_temporary_threat",contribution)
		return 0
	return bound
func _test_bound_lifecycle(world: Node3D) -> void:
	var owner := _unit(world,2)
	var source := _unit(world,1)
	var other := _unit(world,1)
	var threat := _threat(owner)
	var status := _status(owner)
	_check(status.has_method("prepare_bound_status"),"bound status API exists")
	if not status.has_method("prepare_bound_status"): return
	_add(threat,source,100)
	var bound := _bind(threat,status,source,&"mark",8)
	_check(bound>0 and status.has_named_status(&"temporary_threat") and threat.get_threat_for(source)==2100,"committed binding is queryable on both sides")
	_add(threat,source,50)
	status.advance_effects(8.01)
	_check(not status.has_named_status(&"temporary_threat") and threat.get_threat_for(source)==150,"8s expiry removes temporary contribution only")
	bound = _bind(threat,status,source,&"mark",8)
	status.advance_effects(4)
	var refreshed := _bind(threat,status,source,&"mark",8)
	_check(refreshed>bound and not status.call("remove_bound_status",bound),"old state token cannot remove refreshed status")
	status.advance_effects(4.1)
	_check(status.has_named_status(&"temporary_threat") and threat.get_threat_for(source)==2150,"refresh extends duration without stacking")
	var rejected: int = status.call("prepare_bound_status",&"temporary_threat",source,&"mark",8.0,Callable(threat,"remove_temporary_threat").bind(-1))
	_check(not status.call("commit_bound_status",rejected,func(): return false),"failed attachment is rejected")
	_check(status.has_named_status(&"temporary_threat") and threat.get_threat_for(source)==2150,"failed attachment preserves old state/contribution")
	status.call("discard_bound_status",rejected)
	status.advance_effects(4)
	_check(not status.has_named_status(&"temporary_threat") and threat.get_threat_for(source)==150,"failed refresh does not extend old remaining lifetime")
	_bind(threat,status,source,&"mark",1)
	_bind(threat,status,other,&"mark",8)
	var inactive_events := [0]
	status.named_status_changed.connect(func(id: StringName,active: bool):
		if id==&"temporary_threat" and not active: inactive_events[0]+=1
	)
	status.advance_effects(1.1)
	_check(status.has_named_status(&"temporary_threat") and inactive_events[0]==0,"partial source expiry never reports aggregate inactive")
	_check(status.get_active_status_ids().has(&"temporary_threat"),"bound states included in hit status snapshot")
	status.remove_named_status(&"temporary_threat")
	_check(not status.has_named_status(&"temporary_threat") and threat.get_threat_for(other)==0 and inactive_events[0]==1,"remove_named_status clears remaining bound source once")
	_bind(threat,status,source,&"mark",8)
	threat.clear_threat()
	_check(not status.has_named_status(&"temporary_threat"),"clear_threat immediately removes bound status")
	_bind(threat,status,source,&"mark",8)
	source.apply_damage(100000)
	_check(threat.get_threat_for(source)==0 and not status.has_named_status(&"temporary_threat"),"source death clears both sides synchronously")
	_bind(threat,status,other,&"mark",8)
	world.remove_child(other)
	_check(not status.has_named_status(&"temporary_threat"),"source tree exit clears both sides")
	other.free()
	var third := _unit(world,1)
	_bind(threat,status,third,&"mark",8)
	owner.apply_damage(100000)
	_check(threat.get_threat_for(third)==0 and not status.has_named_status(&"temporary_threat"),"owner death clears contributions and status")

