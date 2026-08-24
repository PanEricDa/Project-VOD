class_name AllySkillRequestBridge
extends Node

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")

@export_category("Automatic Requests")
## 总开关默认关闭。只有具体职业源场景显式开启后，组件才会向 Host 发起 AI 请求。
@export var enabled: bool = false

## 自动请求的最短轮询间隔。技能自身的决策延迟、技能冷却和公共冷却仍由 SkillSystem 管理。
@export_range(0.05, 5.0, 0.05, "or_greater") var request_interval: float = 0.25

## 开启后，即使 AllyBase 尚未进入战斗，也允许 Host 尝试寻找可用技能和合法目标。
## 该选项主要用于治疗、增益等不依赖敌人感知的技能。
@export var request_while_out_of_combat: bool = false

## 离开战斗且不允许脱战请求时，取消尚未完成的技能，避免残留施法和移动意图。
@export var cancel_on_combat_exit: bool = true

@export_category("Assembly")
## 指向同一角色下的独立 SkillHostComponent。桥接器只调用 Host 公共接口，不依赖 AllyBase 类型。
@export_node_path("Node") var skill_host_path: NodePath = ^"../SkillHostComponent"

var skill_host: Node
var combat_active: bool = false
var preferred_target: Node3D
var request_timer_remaining: float = 0.0

var approach_target: Node3D
var approach_range: float = 0.0
var approach_tolerance: float = 0.0
var facing_target: Node3D
var movement_locked: bool = false


func _ready() -> void:
	_resolve_skill_host()


func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(skill_host):
		return
	if not combat_active and not request_while_out_of_combat:
		return
	request_timer_remaining = maxf(request_timer_remaining - maxf(delta, 0.0), 0.0)
	if request_timer_remaining > 0.0:
		return
	request_timer_remaining = maxf(request_interval, 0.05)
	# 请求失败是正常控制流：可能没有合法目标、技能仍在冷却，或 Host 已有活动技能。
	# 桥接器只在下个轮询周期重试，不创建额外计时任务，也不自行修改任何技能状态。
	skill_host.call(
		"request_best_skill",
		preferred_target if is_instance_valid(preferred_target) else null,
		Vector3.INF,
		SkillContextType.RequestMode.AI
	)


## AllyBase 每帧只提供战斗上下文；技能选择、目标合法性和施法执行仍属于 SkillSystem。
func set_combat_context(active: bool, target: Node3D = null) -> void:
	var was_active: bool = combat_active
	combat_active = active
	preferred_target = target if is_instance_valid(target) else null
	if combat_active:
		return
	if was_active and cancel_on_combat_exit and not request_while_out_of_combat:
		_cancel_host_request(&"combat_exited")
	_clear_runtime_intents()


func clear_combat_context() -> void:
	set_combat_context(false, null)


func is_requesting_enabled() -> bool:
	return enabled


func has_approach_request() -> bool:
	return is_instance_valid(approach_target) and approach_target.is_inside_tree()


func get_approach_target() -> Node3D:
	return approach_target if has_approach_request() else null


func get_approach_range() -> float:
	return maxf(approach_range, 0.0)


func get_approach_tolerance() -> float:
	return maxf(approach_tolerance, 0.0)


func get_facing_target() -> Node3D:
	return facing_target if is_instance_valid(facing_target) and facing_target.is_inside_tree() else null


func is_movement_locked() -> bool:
	return movement_locked


func _resolve_skill_host() -> void:
	_disconnect_skill_host()
	skill_host = get_node_or_null(skill_host_path)
	if not is_instance_valid(skill_host):
		return
	_connect_host_signal(&"active_skill_changed", Callable(self, "_on_active_skill_changed"))
	_connect_host_signal(&"approach_requested", Callable(self, "_on_approach_requested"))
	_connect_host_signal(&"facing_requested", Callable(self, "_on_facing_requested"))
	_connect_host_signal(&"movement_lock_requested", Callable(self, "_on_movement_lock_requested"))


func _connect_host_signal(signal_name: StringName, callback: Callable) -> void:
	if not skill_host.has_signal(signal_name):
		return
	if not skill_host.is_connected(signal_name, callback):
		skill_host.connect(signal_name, callback)


func _disconnect_skill_host() -> void:
	if not is_instance_valid(skill_host):
		return
	var bindings: Array[Array] = [
		[&"active_skill_changed", Callable(self, "_on_active_skill_changed")],
		[&"approach_requested", Callable(self, "_on_approach_requested")],
		[&"facing_requested", Callable(self, "_on_facing_requested")],
		[&"movement_lock_requested", Callable(self, "_on_movement_lock_requested")],
	]
	for binding: Array in bindings:
		var signal_name: StringName = binding[0]
		var callback: Callable = binding[1]
		if skill_host.has_signal(signal_name) and skill_host.is_connected(signal_name, callback):
			skill_host.disconnect(signal_name, callback)


func _on_approach_requested(context: RefCounted, cast_range: float, tolerance: float) -> void:
	var typed_context: SkillContextType = context as SkillContextType
	approach_target = typed_context.resolved_target if typed_context != null else null
	approach_range = maxf(cast_range, 0.0)
	approach_tolerance = maxf(tolerance, 0.0)


func _on_facing_requested(context: RefCounted) -> void:
	# Host 在 QUEUED 状态先请求朝向，再仅在超出距离时请求接近；因此先清除旧接近意图，
	# 同一物理帧若仍需接近，随后到达的 approach_requested 会重新写入最新目标。
	_clear_approach_intent()
	var typed_context: SkillContextType = context as SkillContextType
	facing_target = typed_context.resolved_target if typed_context != null else null


func _on_movement_lock_requested(locked: bool) -> void:
	movement_locked = locked
	if movement_locked:
		_clear_approach_intent()


func _on_active_skill_changed(skill: Node3D) -> void:
	if not is_instance_valid(skill):
		_clear_runtime_intents()


func _clear_approach_intent() -> void:
	approach_target = null
	approach_range = 0.0
	approach_tolerance = 0.0


func _clear_runtime_intents() -> void:
	_clear_approach_intent()
	facing_target = null
	movement_locked = false


func _cancel_host_request(reason: StringName) -> void:
	if is_instance_valid(skill_host) and skill_host.has_method(&"cancel_active_skill"):
		skill_host.call("cancel_active_skill", reason)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not has_node(skill_host_path):
		warnings.append("AllySkillRequestBridge requires a valid SkillHostComponent path.")
	return warnings


func _exit_tree() -> void:
	if enabled and cancel_on_combat_exit:
		_cancel_host_request(&"bridge_exited")
	_disconnect_skill_host()
	_clear_runtime_intents()
	skill_host = null

