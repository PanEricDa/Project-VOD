class_name IndependentSkillHostComponent
extends Node

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")
const SKILL_BASE_PATH := "res://SkillSystem/01-Core/SkillBase.gd"
## 新 UnitSystem 角色视觉约定：Visual 插槽内的具体 Visual 场景提供这个发射点。
## SkillHost 只读取该公开节点契约，不持有任何职业或具体技能场景引用。
const VISUAL_SLOT_PATH: NodePath = ^"Visual"
const PROJECTILE_ORIGIN_PATH: NodePath = ^"CharacterRoot/WeaponSocket/ProjectileOrigin"

signal skill_registered(skill: Node3D)
signal skill_unregistered(skill: Node3D)
signal active_skill_changed(skill: Node3D)
signal cast_started(context: RefCounted)
signal global_cooldown_started(duration: float)
signal global_cooldown_finished()
signal approach_requested(context: RefCounted, cast_range: float, tolerance: float)
signal facing_requested(context: RefCounted)
signal movement_lock_requested(locked: bool)

@export_category("Skill Socket")
@export_node_path("Node") var skill_socket_path: NodePath = ^"SkillSocket"
@export var auto_discover_skills: bool = true
## 启用后，SkillHost 会将自己的直接 Node3D 父节点自动视为施法者。
## 该选项让 Host 能预置在 UnitBase 中，同时仍允许其他独立场景关闭自动装配后手动配置 Owner。
@export var auto_configure_parent_owner: bool = true

@export_category("Global Cooldown")
@export_range(0.0, 30.0, 0.05, "or_greater") var global_cooldown_duration: float = 1.0

var skill_owner: Node3D
var runtime_delivery_parent: Node
var registered_skills: Array[Node3D] = []
var active_skill: Node3D
var global_cooldown_remaining: float = 0.0
var cast_blocked: bool = false
var skill_casting_enabled: bool = true
var _use_external_global_cooldown: bool = false
var _external_global_cooldown_blocked: bool = false
var movement_locked: bool = false
var random_generator := RandomNumberGenerator.new()


func _ready() -> void:
	random_generator.randomize()
	if auto_discover_skills:
		discover_skills()
	if auto_configure_parent_owner:
		call_deferred("_configure_parent_owner")


## 延迟到本帧所有场景节点完成 _ready() 后再注入施法者。
## 这样 SkillSocket 内的技能已经被发现并注册，configure_owner() 会一次性同步给全部技能。
func _configure_parent_owner() -> void:
	if is_instance_valid(skill_owner):
		return
	var parent_owner: Node3D = get_parent() as Node3D
	if parent_owner != null:
		configure_owner(parent_owner)


func _physics_process(delta: float) -> void:
	if not _use_external_global_cooldown and global_cooldown_remaining > 0.0:
		global_cooldown_remaining = maxf(global_cooldown_remaining - delta, 0.0)
		if global_cooldown_remaining <= 0.0:
			global_cooldown_finished.emit()
	_process_active_skill()


## 配置角色和 Delivery 的世界父节点；未指定时回退到当前主场景。
func configure_owner(caster: Node3D, delivery_parent: Node = null) -> void:
	skill_owner = caster
	runtime_delivery_parent = delivery_parent
	if not is_instance_valid(runtime_delivery_parent) and is_instance_valid(caster):
		var tree: SceneTree = caster.get_tree()
		if tree != null:
			runtime_delivery_parent = tree.current_scene
	for skill: Node3D in registered_skills:
		if is_instance_valid(skill):
			skill.call("configure_owner", skill_owner, self)


## 注册一个实现 Independent SkillBase 契约的技能节点。
func register_skill(skill: Node3D) -> bool:
	if not is_instance_valid(skill) or registered_skills.has(skill):
		return false
	var script: Script = skill.get_script() as Script
	if script == null or not _script_inherits_path(script, SKILL_BASE_PATH):
		return false
	registered_skills.append(skill)
	_connect_skill(skill)
	skill.call("configure_owner", skill_owner, self)
	skill_registered.emit(skill)
	return true


func unregister_skill(skill: Node3D) -> bool:
	if not is_instance_valid(skill) or not registered_skills.has(skill):
		return false
	if active_skill == skill:
		skill.call("cancel_skill", &"unregistered")
		_release_active_skill()
	_disconnect_skill(skill)
	skill.call("reset_skill")
	skill.call("configure_owner", null, null)
	registered_skills.erase(skill)
	skill_unregistered.emit(skill)
	return true


## 只扫描 SkillSocket 的直接子节点，避免误注册技能内部节点。
func discover_skills() -> void:
	var socket: Node = get_node_or_null(skill_socket_path)
	if not is_instance_valid(socket):
		return
	for child: Node in socket.get_children():
		if child is Node3D:
			register_skill(child as Node3D)


func request_skill(
	skill_id: StringName,
	target: Node3D = null,
	target_position: Vector3 = Vector3.INF,
	request_mode: int = SkillContextType.RequestMode.MANUAL
) -> bool:
	if not skill_casting_enabled or is_instance_valid(active_skill):
		return false
	for skill: Node3D in registered_skills:
		if is_instance_valid(skill) and skill.call("get_skill_id") == skill_id:
			return _request_selected_skill(skill, target, target_position, request_mode)
	return false


func request_best_skill(
	target: Node3D = null,
	target_position: Vector3 = Vector3.INF,
	request_mode: int = SkillContextType.RequestMode.AI
) -> bool:
	if not skill_casting_enabled or is_instance_valid(active_skill):
		return false
	var highest_priority: int = -2147483648
	var candidates: Array[Node3D] = []
	for skill: Node3D in registered_skills:
		if not is_instance_valid(skill):
			continue
		var context: SkillContextType = _create_context(target, target_position, request_mode)
		if not bool(skill.call("can_request", context)):
			continue
		var priority: int = int(skill.call("get_ai_priority"))
		if priority > highest_priority:
			highest_priority = priority
			candidates = [skill]
		elif priority == highest_priority:
			candidates.append(skill)
	if candidates.is_empty():
		return false
	var selected: Node3D = candidates[random_generator.randi_range(0, candidates.size() - 1)]
	return _request_selected_skill(selected, target, target_position, request_mode)


func cancel_active_skill(reason: StringName = &"cancelled") -> void:
	if is_instance_valid(active_skill):
		active_skill.call("cancel_skill", reason)
	_release_active_skill()


func set_cast_blocked(blocked: bool) -> void:
	cast_blocked = blocked


## 供沉默、剧情和特殊状态等外部系统统一开关技能释放。
func set_skill_casting_enabled(enabled: bool) -> void:
	if skill_casting_enabled == enabled:
		return
	skill_casting_enabled = enabled
	if not skill_casting_enabled:
		cancel_active_skill(&"casting_disabled")


func is_skill_casting_enabled() -> bool:
	return skill_casting_enabled


## AI 行为状态机启用后，SkillHost 不再独自维护行动 GCD。
func set_use_external_global_cooldown(active: bool) -> void:
	_use_external_global_cooldown = active
	if active:
		global_cooldown_remaining = 0.0


func set_external_global_cooldown_blocked(blocked: bool) -> void:
	_external_global_cooldown_blocked = blocked


## 启动或延长公共冷却；负覆盖值使用 Inspector 默认值。
func start_global_cooldown(duration_override: float = -1.0) -> void:
	var duration: float = (
		maxf(duration_override, 0.0)
		if duration_override >= 0.0
		else maxf(global_cooldown_duration, 0.0)
	)
	global_cooldown_remaining = maxf(global_cooldown_remaining, duration)
	global_cooldown_started.emit(global_cooldown_remaining)
	if global_cooldown_remaining <= 0.0:
		global_cooldown_finished.emit()


func get_global_cooldown_remaining() -> float:
	return global_cooldown_remaining


func is_global_cooldown_ready() -> bool:
	return _use_external_global_cooldown or global_cooldown_remaining <= 0.0


func get_registered_skills() -> Array[Node3D]:
	return registered_skills.duplicate()


func get_active_skill() -> Node3D:
	return active_skill if is_instance_valid(active_skill) else null


## 返回当前施法者的统一世界空间发射变换。
##
## SkillSocket 是普通 Node 容器，位于其中的 SkillBase 不会继承 CharacterBody3D 的
## Node3D 变换；因此技能自身的内部 Marker 只能作为旧场景兼容回退，不能作为新
## UnitSystem 的正式世界坐标来源。这里复用角色 Visual 的唯一有效 ProjectileOrigin，
## 使蓄力表现和投射物从角色武器插槽的同一个位置开始。
func get_skill_origin_transform(fallback_transform: Transform3D) -> Transform3D:
	if not is_instance_valid(skill_owner):
		return fallback_transform
	var visual_slot := skill_owner.get_node_or_null(VISUAL_SLOT_PATH) as Node3D
	if visual_slot == null:
		return fallback_transform
	var resolved_origin: Node3D
	var valid_origin_count: int = 0
	for child: Node in visual_slot.get_children():
		var visual_instance := child as Node3D
		if visual_instance == null:
			continue
		var candidate := visual_instance.get_node_or_null(
			PROJECTILE_ORIGIN_PATH
		) as Node3D
		if candidate == null:
			continue
		valid_origin_count += 1
		resolved_origin = candidate
	## 多个有效 Visual 会使发射位置含糊；安全回退可避免随机选中错误模型。
	if valid_origin_count != 1 or resolved_origin == null:
		return fallback_transform
	return resolved_origin.global_transform


## 返回已装备技能中最高 AI 优先级技能的施法距离，用于 AI 在等待冷却时保持合理站位。
func get_preferred_cast_range() -> float:
	var highest_priority: int = -2147483648
	var preferred_range: float = 0.0
	for skill: Node3D in registered_skills:
		if not is_instance_valid(skill):
			continue
		var priority: int = int(skill.call("get_ai_priority"))
		if priority > highest_priority:
			highest_priority = priority
			preferred_range = maxf(float(skill.call("get_cast_range")), 0.0)
	return preferred_range


func _request_selected_skill(
	skill: Node3D,
	target: Node3D,
	target_position: Vector3,
	request_mode: int
) -> bool:
	var context: SkillContextType = _create_context(target, target_position, request_mode)
	if not bool(skill.call("request_skill", context)):
		return false
	active_skill = skill
	active_skill_changed.emit(active_skill)
	return true


func _create_context(
	target: Node3D,
	target_position: Vector3,
	request_mode: int
) -> SkillContextType:
	var context: SkillContextType = SkillContextType.new()
	context.request_mode = request_mode as SkillContextType.RequestMode
	context.caster = skill_owner
	context.host = self
	context.requested_target = target
	context.target_position = target_position
	context.delivery_parent = runtime_delivery_parent
	return context


func _process_active_skill() -> void:
	if not is_instance_valid(active_skill):
		active_skill = null
		_set_movement_locked(false)
		return
	var state: int = int(active_skill.call("get_state"))
	var context: SkillContextType = active_skill.call("get_current_context") as SkillContextType
	match state:
		1: # DECISION_WAIT
			return
		2: # QUEUED
			if context == null or not is_instance_valid(context.resolved_target):
				cancel_active_skill(&"invalid_target")
				return
			facing_requested.emit(context)
			if not bool(active_skill.call("is_target_in_cast_range")):
				approach_requested.emit(
					context,
					float(active_skill.call("get_cast_range")),
					float(active_skill.call("get_cast_range_tolerance"))
				)
				return
			if (
				cast_blocked
				or _external_global_cooldown_blocked
				or not is_global_cooldown_ready()
			):
				return
			active_skill.call("begin_cast")
		3: # CASTING
			if context != null:
				facing_requested.emit(context)
			_set_movement_locked(not bool(active_skill.call("can_move_during_cast")))
		_: # READY / COOLDOWN
			_release_active_skill()


func _connect_skill(skill: Node3D) -> void:
	var bindings: Array[Array] = [
		[skill.cast_started, Callable(self, "_on_skill_cast_started").bind(skill)],
		[skill.delivery_launched, Callable(self, "_on_skill_delivery_launched").bind(skill)],
		[skill.cast_failed, Callable(self, "_on_skill_terminal").bind(skill)],
		[skill.cast_cancelled, Callable(self, "_on_skill_terminal").bind(skill)],
	]
	for binding: Array in bindings:
		var source_signal: Signal = binding[0]
		var callback: Callable = binding[1]
		if not source_signal.is_connected(callback):
			source_signal.connect(callback)


func _disconnect_skill(skill: Node3D) -> void:
	var bindings: Array[Array] = [
		[skill.cast_started, Callable(self, "_on_skill_cast_started").bind(skill)],
		[skill.delivery_launched, Callable(self, "_on_skill_delivery_launched").bind(skill)],
		[skill.cast_failed, Callable(self, "_on_skill_terminal").bind(skill)],
		[skill.cast_cancelled, Callable(self, "_on_skill_terminal").bind(skill)],
	]
	for binding: Array in bindings:
		var source_signal: Signal = binding[0]
		var callback: Callable = binding[1]
		if source_signal.is_connected(callback):
			source_signal.disconnect(callback)


func _on_skill_cast_started(_context: RefCounted, skill: Node3D) -> void:
	if active_skill == skill:
		if not _use_external_global_cooldown:
			start_global_cooldown()
		_set_movement_locked(not bool(skill.call("can_move_during_cast")))
		cast_started.emit(_context)


func _on_skill_delivery_launched(
	_context: RefCounted,
	_agent: Node3D,
	skill: Node3D
) -> void:
	if active_skill == skill:
		_release_active_skill()


func _on_skill_terminal(
	_context: RefCounted,
	_reason: StringName,
	skill: Node3D
) -> void:
	if active_skill == skill:
		_release_active_skill()


func _release_active_skill() -> void:
	if active_skill == null and not movement_locked:
		return
	active_skill = null
	active_skill_changed.emit(null)
	_set_movement_locked(false)


func _set_movement_locked(locked: bool) -> void:
	if movement_locked == locked:
		return
	movement_locked = locked
	movement_lock_requested.emit(movement_locked)


func _script_inherits_path(script: Script, expected_path: String) -> bool:
	var cursor: Script = script
	while cursor != null:
		if cursor.resource_path == expected_path:
			return true
		cursor = cursor.get_base_script()
	return false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not has_node(skill_socket_path):
		warnings.append("SkillHostComponent requires a valid SkillSocket node path.")
	return warnings


func _exit_tree() -> void:
	cancel_active_skill(&"host_exited")
	var skills: Array[Node3D] = registered_skills.duplicate()
	for skill: Node3D in skills:
		if is_instance_valid(skill):
			unregister_skill(skill)
