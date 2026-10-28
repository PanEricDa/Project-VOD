@tool
class_name SquadFinisherExecutionController
extends Node
## 世界级终结演出协调：只持有时间/镜头/输入和本次主要视觉完成任务，不执行技能伤害。
## 只读值快照，包含phase/发出/落地/视觉待办/原因；不把单位引用交给UI。
signal execution_state_changed(snapshot: Dictionary)
## 正常或异常终态仅一次，snapshot保留最后计数；不是五颗必然命中的承诺。
signal execution_ended(snapshot: Dictionary)

@export_category("Assembly")
## 本世界已有终结选择源；角色、指令、评价和暂停沿此引用取得，默认空不启用。
@export var selection_source: SquadFinisherSelectionController
## 可选现有CameraRig控制器；默认空跳过镜头，仍保持技能交付与时间清理。
@export var camera_source: CameraFollowController

var _selection: WeakRef
var _scope: WeakRef
var _pause: WeakRef
var _command: WeakRef
var _host: WeakRef
var _skill: WeakRef
var _context: SkillContext
var _pending_context: SkillContext
var _profile: SkillCinematicProfile
var _clock: SkillExecutionClock
var _phase: StringName = &"idle"
var _request_id: int = 0
var _scope_id: int = 0
var _slow_token: int = 0
var _input_token: int = 0
var _released: bool = false
var _emission_done: bool = false
var _delivery_done: bool = false
var _launched: int = 0
var _landed: int = 0
var _tasks: Dictionary = {}
var _elapsed: float = 0.0
var _watchdog: float = 10.0
var _reason: StringName = &""
var _generation: int = 0
var _last_selection_round: int = 0
var _finishing: bool = false
var _detaching: bool = false
var _transition_pause_token: int = 0
var _camera_ref: WeakRef
var _pending_release_transform: Transform3D = Transform3D.IDENTITY

func _ready() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_binding()

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	_refresh_binding()
	if _phase == &"idle": return
	if _phase in [&"enter_closeup",&"exit_closeup"] and (_camera() == null or camera_source != _camera() or not _camera().is_cinematic_active()):
		cancel_execution(&"camera_unavailable")
		return
	if _clock != null: _elapsed += _clock.get_presentation_delta(delta, false)
	_poll_owned_tasks()
	if _phase == &"returning":
		if _camera() == null or not _camera().is_cinematic_active():
			_end_execution(&"completed")
		return
	if _elapsed > _watchdog:
		push_warning("[FinisherExecution] main presentation watchdog request=%d phase=%s" % [_request_id, _phase])
		cancel_execution(&"presentation_watchdog")
		return
	execution_state_changed.emit(get_execution_status())

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or get_tree().paused: return
	if _phase == &"pending":
		var host := _node(_host) as SkillHostComponent
		var context := _pending_context
		_pending_context = null
		if host == null or not host.activate_finisher(context):
			cancel_execution(&"activation_rejected")
	elif _phase == &"release_pending":
		_commit_pending_release()

## actor使用原四伙伴实例；空字符串为可立即开始，其余为灰显诊断原因，不付费、不抢占。
func get_actor_availability(actor: AllyBase) -> StringName:
	if _phase != &"idle" or _finishing: return &"execution_busy"
	var world := _node(_scope)
	if world == null or not is_instance_valid(actor) or not world.is_ancestor_of(actor) or actor.is_dead(): return &"actor_unavailable"
	var host := actor.get_node_or_null("SkillHost") as SkillHostComponent
	var skill := host.get_finisher_skill() if host != null else null
	if skill == null: return &"finisher_not_equipped"
	if skill.cinematic_profile == null or not skill.cinematic_profile.validate_configuration().is_empty(): return &"cinematic_invalid"
	if host.prepare_finisher_context(_preferred_target()) == null: return &"cast_unavailable"
	return &""

## 预览/剧情可显式提出同一真实终结请求；正式玩法由选择事件调用，不伪造资格或直接生成火球。
## scatter_seed为本次局部种子，0随机；preview_mode=-1保留技能模式，否则只覆盖本次私有快照。
## finisher_multiplier为原轮冻结的评分威力，默认1兼容直接预览；须有限且>=1，不重新计算或叠乘旧请求倍率。
func begin_finisher(actor: AllyBase, scatter_seed: int = 0, preview_mode: int = -1, finisher_multiplier: float = 1.0) -> bool:
	if not is_finite(finisher_multiplier) or finisher_multiplier < 1.0: return false
	_refresh_binding()
	if get_actor_availability(actor) != &"": return false
	var host := actor.get_node("SkillHost") as SkillHostComponent
	var skill := host.get_finisher_skill()
	var context := host.prepare_finisher_context(_preferred_target())
	if context == null: return false
	_generation += 1
	_clock = SkillExecutionClock.new()
	_clock.configure(_node(_scope))
	context.execution_clock = _clock
	context.scatter_seed = scatter_seed
	context.finisher_multiplier = finisher_multiplier
	_profile = context.cinematic_profile_snapshot.duplicate() as SkillCinematicProfile
	if preview_mode in [0,1]: _profile.cinematic_mode = preview_mode as SkillCinematicProfile.CinematicMode
	context.cinematic_profile_snapshot = _profile
	_context = null
	_pending_context = context
	_host = weakref(host)
	_skill = weakref(skill)
	_request_id = 0
	_launched = 0
	_landed = 0
	_released = false
	_emission_done = false
	_delivery_done = false
	_tasks.clear()
	_elapsed = 0
	_reason = &""
	_watchdog = _derive_budget(skill, _profile)
	_phase = &"pending"
	_connect_execution(host, skill)
	if _profile.cinematic_mode == SkillCinematicProfile.CinematicMode.HOLD_THROUGH_IMPACTS and not host.set_finisher_release_gate(self):
		cancel_execution(&"release_gate_unavailable")
		return false
	var pause := _node(_pause) as GamePauseCoordinator
	var command := _node(_command) as SquadChainCommandController
	var generation := _generation
	var slow := pause.acquire_time_scale(self, _profile.world_time_scale, &"finisher_execution")
	if generation != _generation or _phase != &"pending":
		if is_instance_valid(pause): pause.release_time_scale(slow)
		return false
	_slow_token = slow
	if slow == 0:
		cancel_execution(&"ownership_unavailable")
		return false
	var block := command.acquire_input_block(self, &"finisher_execution")
	if generation != _generation or _phase != &"pending":
		if is_instance_valid(command): command.release_input_block(block)
		return false
	_input_token = block
	if block == 0:
		cancel_execution(&"ownership_unavailable")
		return false
	execution_state_changed.emit(get_execution_status())
	return true

## 只取消本执行协调，停止未发并释放本方token；已释放投射物不当成纯视觉删除，退回世界时间继续。
func cancel_execution(reason: StringName = &"cancelled") -> void:
	if _phase == &"idle" or _finishing: return
	var generation := _generation
	var context := _context
	var host := _node(_host) as SkillHostComponent
	var skill := _node(_skill) as SkillBase
	if skill != null and _request_id > 0: skill.stop_pending_emission(_request_id)
	if generation != _generation: return
	if host != null and host.get_finisher_action_context() == context and context != null:
		host.cancel_active_skill(reason)
	if generation != _generation: return
	_end_execution(reason)

## 深复制调试值，空闲时保留上一轮数据，不改变任何时钟或战斗。
func get_execution_status() -> Dictionary:
	return {"phase":_phase,"request_id":_request_id,"scene_scope_id":_scope_id,"launched":_launched,
		"landed":_landed,"main_effects_pending":_tasks.size(),"emission_done":_emission_done,
		"delivery_done":_delivery_done,"reason":_reason,"mode":_profile.cinematic_mode if _profile != null else -1,
		"elapsed_seconds":_elapsed}.duplicate(true)

func _refresh_binding() -> void:
	if _detaching: return
	var selection := selection_source if is_instance_valid(selection_source) and selection_source.is_inside_tree() else null
	var command := selection.round_source.command_source if selection != null and is_instance_valid(selection.round_source) else null
	var world := command.get_bound_scope() if is_instance_valid(command) else null
	var pause := selection.pause_source if selection != null else null
	if selection == _node(_selection) and world == _node(_scope) and pause == _node(_pause) and world != null: return
	_detach()
	if selection == null or world == null or not world.is_ancestor_of(self) or not is_instance_valid(pause) or pause.get_bound_scope() != world: return
	if not selection.set_execution_provider(self): return
	_selection = weakref(selection)
	_scope = weakref(world)
	_scope_id = world.get_instance_id()
	_pause = weakref(pause)
	_command = weakref(command)
	_last_selection_round = 0
	selection.finisher_selected.connect(_on_selected)
	selection.tree_exiting.connect(_on_dependency_exiting)
	world.tree_exiting.connect(_on_dependency_exiting)

func _on_selected(selection: Dictionary) -> void:
	var source := _node(_selection) as SquadFinisherSelectionController
	var command := _node(_command) as SquadChainCommandController
	var round_id: int = selection.get("round_id", 0)
	if source == null or command == null or selection.get("scene_scope_id", 0) != _scope_id or round_id <= _last_selection_round: return
	var status := source.get_selection_status()
	if status.phase != SquadFinisherSelectionController.Phase.CONFIRMED or status.round_id != round_id or status.selected_slot != selection.get("slot_index", -1): return
	_last_selection_round = round_id
	var slot: int = selection.get("slot_index", -1)
	if slot < 0 or slot >= command.companions.size(): return
	var actor := command.companions[slot]
	if not is_instance_valid(actor) or actor.get_instance_id() != selection.get("actor_instance_id", 0): return
	# 读取当前已验证窗口的冻结值，不信任外部可修改的选择消息或后来轮次。
	begin_finisher(actor,0,-1,float(status.get("finisher_multiplier",1.0)))
	if is_instance_valid(source): source.complete_execution_handoff()

func _connect_execution(host: SkillHostComponent, skill: SkillBase) -> void:
	_camera_ref = weakref(camera_source) if is_instance_valid(camera_source) else null
	var camera := _camera()
	if camera != null and not camera.cinematic_transition_finished.is_connected(_on_camera_transition_finished):
		camera.cinematic_transition_finished.connect(_on_camera_transition_finished)
	host.finisher_action_started.connect(_on_action_started)
	host.finisher_action_cancelled.connect(_on_action_cancelled)
	skill.delivery_started.connect(_on_delivery_started)
	skill.delivery_finished.connect(_on_delivery_finished)
	skill.delivery_failed.connect(_on_delivery_failed)
	skill.skill_failed.connect(_on_skill_failed)
	skill.emission_finished.connect(_on_emission_finished)
	skill.projectile_launched.connect(_on_projectile_launched)
	skill.projectile_landed.connect(_on_projectile_landed)
	skill.impact_presentation_prepared.connect(_on_impact_prepared)

func _disconnect_execution() -> void:
	var camera := _camera()
	if camera != null and camera.cinematic_transition_finished.is_connected(_on_camera_transition_finished):
		camera.cinematic_transition_finished.disconnect(_on_camera_transition_finished)
	var host := _node(_host) as SkillHostComponent
	var skill := _node(_skill) as SkillBase
	if host != null:
		host.clear_finisher_release_gate(self)
		for entry in [[host.finisher_action_started,_on_action_started],[host.finisher_action_cancelled,_on_action_cancelled]]:
			if entry[0].is_connected(entry[1]): entry[0].disconnect(entry[1])
	if skill != null:
		for entry in [[skill.delivery_started,_on_delivery_started],[skill.delivery_finished,_on_delivery_finished],
			[skill.delivery_failed,_on_delivery_failed],[skill.skill_failed,_on_skill_failed],[skill.emission_finished,_on_emission_finished],
			[skill.projectile_launched,_on_projectile_launched],[skill.projectile_landed,_on_projectile_landed],[skill.impact_presentation_prepared,_on_impact_prepared]]:
			if entry[0].is_connected(entry[1]): entry[0].disconnect(entry[1])

func _on_action_started(context: SkillContext) -> void:
	if _phase != &"pending" or context == null or context.purpose != SkillContext.Purpose.FINISHER or context.execution_clock != _clock: return
	_context = context
	_request_id = context.execution_id
	_phase = &"windup"
	var camera := _camera()
	if camera != null:
		var source := context.caster
		var pose := source.global_transform
		var visual := source.get_node_or_null("Visual") as Node3D
		if visual != null: pose.basis = visual.global_basis
		var skill := _node(_skill) as SkillBase
		if skill != null:
			var camera_profile := skill.camera_effect_profile as SkillCinematicCameraProfile
			if camera_profile != null and camera.begin_cinematic(_request_id,pose,camera_profile,_clock,source) and _profile.cinematic_mode == SkillCinematicProfile.CinematicMode.HOLD_THROUGH_IMPACTS:
				_phase = &"enter_closeup"
				_clock.hold_action(true)
				_begin_transition_pause()

## Host在原release_action标记处调用；只接受本次根身份，true表示进入等待而非已发射。
## launch_transform为该帧的世界发射姿态；退镜完成后仍走原SkillBase提交和成本/目标检查。
func request_finisher_release(context: SkillContext, launch_transform: Transform3D) -> bool:
	if _phase != &"windup" or not _matches(context) or _released or not launch_transform.is_finite(): return false
	var skill := _node(_skill) as SkillBase
	if skill == null or not skill.can_release_action():
		cancel_execution(&"target_invalid_on_release")
		return false
	var camera := _camera()
	if camera == null or not camera.is_cinematic_active():
		var host := _node(_host) as SkillHostComponent
		return host != null and host.commit_finisher_release(self,context,launch_transform)
	_pending_release_transform = launch_transform
	_clock.hold_action(true)
	_phase = &"exit_closeup"
	var radius := 0.0
	if skill.delivery is ArcProjectileDeliveryConfig:
		var config := skill.delivery as ArcProjectileDeliveryConfig
		if config.destination_mode == ArcProjectileDeliveryConfig.DestinationMode.RANDOM_GROUND_CIRCLE:
			radius = config.scatter_radius_m+config.impact_radius_m
	elif skill.delivery is InstantTargetDeliveryConfig:
		var config := skill.delivery as InstantTargetDeliveryConfig
		if config.target_collection_mode == InstantTargetDeliveryConfig.TargetCollectionMode.CASTER_RADIUS:
			radius = config.effect_radius
	camera.show_cinematic_area(_request_id,context.resolved_target.global_position,radius)
	return _begin_transition_pause()

func _begin_transition_pause() -> bool:
	var pause := _node(_pause) as GamePauseCoordinator
	var camera := _camera()
	if pause == null or camera == null:
		cancel_execution(&"transition_unavailable")
		return false
	var generation := _generation
	var token := pause.acquire_cinematic_transition_pause(self)
	if generation != _generation or _phase not in [&"enter_closeup",&"exit_closeup"]:
		if is_instance_valid(pause): pause.release_pause(token)
		return false
	_transition_pause_token = token
	if token == 0 or not camera.bind_cinematic_transition_pause(_request_id,pause,token):
		cancel_execution(&"transition_pause_unavailable")
		return false
	return true

func _on_camera_transition_finished(request_id: int, phase: StringName) -> void:
	if request_id != _request_id or _finishing: return
	if _phase == &"enter_closeup" and phase == &"close":
		_phase = &"windup"
		_clock.hold_action(false)
	elif _phase == &"exit_closeup" and phase == &"area":
		# 仍保持动画门闩，下一物理帧真正发射后才能继续后摇。
		_phase = &"release_pending"
	else: return
	_release_transition_pause()

func _release_transition_pause() -> void:
	var token := _transition_pause_token
	_transition_pause_token = 0
	var pause := _node(_pause) as GamePauseCoordinator
	if pause != null: pause.release_pause(token)

func _commit_pending_release() -> void:
	var host := _node(_host) as SkillHostComponent
	var generation := _generation
	var accepted := host != null and host.commit_finisher_release(self,_context,_pending_release_transform)
	if generation != _generation: return
	if not accepted:
		cancel_execution(&"release_rejected")
		return
	if _clock != null: _clock.hold_action(false)

func _camera() -> CameraFollowController:
	return _node(_camera_ref) as CameraFollowController

func _on_delivery_started(context: SkillContext) -> void:
	if not _matches(context) or _released: return
	_released = true
	if _profile.cinematic_mode == SkillCinematicProfile.CinematicMode.RETURN_ON_RELEASE:
		_phase = &"free_combat"
		_release_controls(true)
	else:
		_phase = &"bombardment"

func _on_emission_finished(context: SkillContext) -> void:
	if not _matches(context): return
	_emission_done = true
	_maybe_complete()

func _on_projectile_launched(context: SkillContext, _index: int, _point: Vector3) -> void:
	if _matches(context): _launched += 1

func _on_projectile_landed(context: SkillContext, _index: int, _point: Vector3) -> void:
	if _matches(context): _landed += 1

func _on_impact_prepared(context: SkillContext, instance: Variant) -> void:
	if not _matches(context) or not is_instance_valid(instance): return
	if instance.has_method("set_execution_clock"): instance.call("set_execution_clock", _clock)
	if not instance.has_signal("effect_finished"):
		push_warning("[FinisherExecution] impact missing effect_finished; effect cannot hold cinematic.")
		return
	var id: int = instance.get_instance_id()
	if _tasks.has(id): return
	var generation := _generation
	_tasks[id] = {"node":weakref(instance),"entered":false}
	instance.connect("effect_finished", _on_impact_finished.bind(id, generation), CONNECT_ONE_SHOT)
	instance.tree_exiting.connect(_on_impact_finished.bind(id, generation), CONNECT_ONE_SHOT)

func _on_impact_finished(id: int, generation: int) -> void:
	if generation != _generation or not _tasks.has(id): return
	_tasks.erase(id)
	_maybe_complete()

func _poll_owned_tasks() -> void:
	for id in _tasks.keys():
		var instance := _node(_tasks[id].node)
		if instance == null:
			var raw = _tasks[id].node.get_ref()
			if not is_instance_valid(raw) or raw.is_queued_for_deletion() or _tasks[id].entered: _tasks.erase(id)
		else:
			if not _tasks[id].entered and instance.has_method("get_remaining_seconds"):
				var remaining: float = instance.call("get_remaining_seconds")
				if is_finite(remaining) and remaining >= 0.0: _watchdog = maxf(_watchdog, _elapsed + remaining + 1.0)
			_tasks[id].entered = true
			if instance.has_method("is_playing") and not instance.call("is_playing"): _tasks.erase(id)
	_maybe_complete()

func _on_delivery_finished(context: SkillContext, _result: SkillDeliveryResult) -> void:
	if not _matches(context): return
	_delivery_done = true
	# 非多发交付没有独立发射门闩，交付终态本身表明无待发。
	var skill := _node(_skill) as SkillBase
	if skill == null or not skill.delivery is ArcProjectileDeliveryConfig: _emission_done = true
	_maybe_complete()

func _on_delivery_failed(context: SkillContext, reason: StringName) -> void:
	if not _matches(context): return
	_delivery_done = true
	_emission_done = true
	_reason = reason
	_maybe_complete()

func _on_skill_failed(context: SkillContext, reason: StringName) -> void:
	if _matches(context) and not _released: cancel_execution(reason)

func _on_action_cancelled(context: SkillContext, reason: StringName) -> void:
	if not _matches(context): return
	if not _released:
		_end_execution(reason)
	else:
		_reason = reason
		_emission_done = true
		_maybe_complete()

func _maybe_complete() -> void:
	if _finishing or _phase in [&"idle",&"pending",&"windup",&"returning"]: return
	if not _emission_done or not _delivery_done or not _tasks.is_empty(): return
	if _profile.cinematic_mode == SkillCinematicProfile.CinematicMode.HOLD_THROUGH_IMPACTS and _camera() != null and _camera().is_cinematic_active():
		_release_controls(false)
		_phase = &"returning"
		_disconnect_execution()
	else:
		_end_execution(_reason if not _reason.is_empty() else &"completed")

func _release_controls(immediate: bool) -> void:
	_release_transition_pause()
	if _clock != null:
		_clock.hold_action(false)
		_clock.use_world_time()
	var pause := _node(_pause) as GamePauseCoordinator
	var command := _node(_command) as SquadChainCommandController
	var slow := _slow_token
	var block := _input_token
	_slow_token = 0
	_input_token = 0
	if pause != null: pause.release_time_scale(slow)
	if command != null: command.release_input_block(block)
	var camera := _camera()
	if camera != null: camera.end_cinematic(_request_id, immediate)

func _end_execution(reason: StringName) -> void:
	if _finishing or _phase == &"idle": return
	_finishing = true
	_reason = reason
	_generation += 1
	_phase = &"idle"
	_release_controls(true)
	_disconnect_execution()
	_tasks.clear()
	_camera_ref = null
	_pending_release_transform = Transform3D.IDENTITY
	_context = null
	_pending_context = null
	_host = null
	_skill = null
	_clock = null
	_finishing = false
	var status := get_execution_status()
	execution_ended.emit(status)
	if is_instance_valid(self): execution_state_changed.emit(status)

func _derive_budget(skill: SkillBase, profile: SkillCinematicProfile) -> float:
	var budget := maxf(profile.action_animation.length, skill.get_effective_cast_time()) + 3.0
	if skill.delivery is ArcProjectileDeliveryConfig:
		var config := skill.delivery as ArcProjectileDeliveryConfig
		budget += (config.shot_count - 1) * config.shot_interval_seconds
		var projectile := config.projectile_scene.instantiate()
		var lifetime = projectile.get("maximum_lifetime")
		if lifetime is float: budget += maxf(lifetime, 0.0)
		projectile.free()
	return budget

func _matches(context: SkillContext) -> bool:
	return context != null and _request_id > 0 and context.execution_id == _request_id and context.damage_context != null and context.damage_context.scene_scope_id == _scope_id

func _preferred_target() -> UnitBase:
	var command := _node(_command) as SquadChainCommandController
	var player := command.get_bound_player() if command != null else null
	return player.get_locked_target() if player != null else null

func _on_dependency_exiting() -> void: _detach()

func _detach() -> void:
	if _detaching: return
	_detaching = true
	cancel_execution(&"binding_changed")
	var selection := _node(_selection) as SquadFinisherSelectionController
	var world := _node(_scope)
	if selection != null:
		if selection.finisher_selected.is_connected(_on_selected): selection.finisher_selected.disconnect(_on_selected)
		if selection.tree_exiting.is_connected(_on_dependency_exiting): selection.tree_exiting.disconnect(_on_dependency_exiting)
		selection.clear_execution_provider(self)
	if world != null and world.tree_exiting.is_connected(_on_dependency_exiting): world.tree_exiting.disconnect(_on_dependency_exiting)
	_selection = null
	_scope = null
	_pause = null
	_command = null
	_detaching = false

func _node(reference: WeakRef) -> Node:
	var node = reference.get_ref() if reference != null else null
	return node if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() else null

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): _detach()
