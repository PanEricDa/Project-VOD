class_name GamePauseCoordinator
extends Node
## 单世界暂停/慢速所有权与纯释放时钟；慢速只设置time_scale，不自行推进战斗逻辑。
## battle_paused为树暂停事实，presentation_allowed仅普通/强调可真，显式暂停优先。
signal pause_state_changed(battle_paused: bool, presentation_allowed: bool)
const TREE_OWNER: StringName = &"_vod_pause_coordinator"
var _scope_ref: WeakRef
var _tokens: Dictionary = {}
var _instances: Dictionary = {}
var _next_token: int = 1
var _accent_token: int = 0
var _accent_ids: Dictionary = {}
var _accent_frame: int = -1
var _accent_start_usec: int = 0
var _accent_duration: float = 0.0
var _resume_frame: int = -1
var _normal_advanced: bool = true
var _baseline_paused: bool = false
var _owns_pause_session: bool = false
var _last_state: Array = []
var _detaching: bool = false
var _scale_tokens: Dictionary = {}
var _scale_baseline: float = 1.0
var _owns_scale: bool = false

func _ready() -> void: process_mode = Node.PROCESS_MODE_ALWAYS

## scope_root须同树有效世界；null解绑，拒绝第二个管理器或自身不属于世界。
func bind_scope(scope_root: Node) -> bool:
	if scope_root == get_bound_scope(): return scope_root != null
	if scope_root != null:
		if not is_inside_tree() or not is_instance_valid(scope_root) or not scope_root.is_inside_tree() or scope_root.get_tree() != get_tree() or not (scope_root == self or scope_root.is_ancestor_of(self)): return false
		var existing = (get_tree().get_meta(TREE_OWNER) if get_tree().has_meta(TREE_OWNER) else null)
		if existing is WeakRef and is_instance_valid(existing.get_ref()) and existing.get_ref() != self:
			push_warning("同一SceneTree只允许一个GamePauseCoordinator。")
			return false
	_unbind(true)
	if scope_root == null: return true
	_scope_ref = weakref(scope_root)
	_baseline_paused = get_tree().paused
	get_tree().set_meta(TREE_OWNER,weakref(self))
	scope_root.tree_exiting.connect(_on_scope_exiting)
	_publish_state()
	return true

## 返回当前有效绑定世界，仅弱引用，未绑定返回null。
func get_bound_scope() -> Node: return _from_ref(_scope_ref)

## 正身份、0—0.3有限真实秒数、同世界owner；同帧取最大，不按迟到通知续时，0表示无新持有。
@warning_ignore("shadowed_variable_base_class")
func request_release_accent(presentation_id: int, duration_seconds: float, owner: Node) -> int:
	if presentation_id <= 0 or not is_finite(duration_seconds) or duration_seconds <= 0.0 or duration_seconds > 0.3 or not _valid_owner(owner): return 0
	if _accent_ids.has(presentation_id): return 0
	var frame := Engine.get_physics_frames()
	if _accent_token != 0:
		if frame == _accent_frame:
			_accent_ids[presentation_id] = true
			_accent_duration = maxf(_accent_duration,duration_seconds)
		return 0
	if not _normal_advanced: return 0
	_accent_ids.clear()
	_accent_ids[presentation_id] = true
	_accent_frame = frame
	_accent_start_usec = Time.get_ticks_usec()
	_accent_duration = duration_seconds
	_accent_token = _new_token(owner,&"release_accent",true)
	return _accent_token

## 显式暂停，owner须属于本世界，reason诊断键；返回正token，由同一调用方幂等释放。
@warning_ignore("shadowed_variable_base_class")
func acquire_pause(owner: Node, reason: StringName) -> int:
	if not _valid_owner(owner): return 0
	return _new_token(owner,reason,false)

## owner须同绑定世界；本token冻结全部战斗与普通表现，仅允许持有凭证的镜头过渡推进。
## 菜单或其他暂停优先；返回正token，由调用方用release_pause释放，不能借此推进技能时钟。
@warning_ignore("shadowed_variable_base_class")
func acquire_cinematic_transition_pause(owner: Node) -> int:
	if not _valid_owner(owner): return 0
	return _new_token(owner,&"cinematic_transition",false,true)

## token须为仍存活的镜头过渡凭证；任何其他暂停持有或外部基线暂停都会阻止该过渡。
func can_advance_cinematic_transition(token: int) -> bool:
	if not _tokens.has(token) or _baseline_paused or not bool(_tokens[token].get("camera_transition",false)): return false
	if not _valid_owner(_from_ref(_tokens[token].owner)): return false
	return _tokens.size() == 1

## 只释放对应token；未知/重复token无操作，不解除其他持有者。
func release_pause(token: int) -> void:
	if not _tokens.has(token): return
	_tokens.erase(token)
	if token == _accent_token:
		_accent_token = 0
		_resume_frame = Engine.get_physics_frames()
		_normal_advanced = false
	_apply_pause()

## owner须同绑定世界；scale为有限0<值<=1的绝对速度上限，reason为诊断键；失败返回0。
## 多持有取最慢且不加速原基线；调用方用release_time_scale释放自己的token，不影响暂停。
@warning_ignore("shadowed_variable_base_class")
func acquire_time_scale(owner: Node, scale: float, reason: StringName) -> int:
	if not _valid_owner(owner) or not is_finite(scale) or scale <= 0.0 or scale > 1.0: return 0
	if not _owns_scale:
		_scale_baseline = Engine.time_scale
		_owns_scale = true
	var token := _next_token
	_next_token += 1
	_scale_tokens[token] = {"owner":weakref(owner),"scale":scale,"reason":reason}
	_apply_time_scale()
	return token

## 幂等释放本次慢速token；未知/重复不操作，最后持有释放恢复申请前倍率，不解除暂停。
func release_time_scale(token: int) -> void:
	if not _scale_tokens.has(token): return
	_scale_tokens.erase(token)
	_apply_time_scale()

func _apply_time_scale() -> void:
	if not _owns_scale: return
	var value := _scale_baseline
	for record: Dictionary in _scale_tokens.values(): value = minf(value,record.scale)
	Engine.time_scale = value
	if _scale_tokens.is_empty(): _owns_scale = false

## 仅当前强调暂停，且无显式持有及外部基线时为真。
func is_release_accent_only() -> bool:
	return has_release_accent() and not _baseline_paused and not _has_explicit()
## 当前强调区间是否仍存活，不等价于当前是否允许表现。
func has_release_accent() -> bool: return _accent_token != 0 and _tokens.has(_accent_token)
## 普通战斗/纯强调允许表现；显式或外部暂停禁止，不自动解除它们。
func is_presentation_allowed() -> bool:
	if not is_inside_tree(): return false
	if _baseline_paused or _has_explicit(): return false
	return not get_tree().paused or is_release_accent_only()

## 在add_child之前登记纯视觉/声音，id为正；弱引用并保留原模式，拒绝战斗/碰撞子树。
func register_release_instance(presentation_id: int, instance: Node) -> bool:
	if presentation_id <= 0 or get_bound_scope() == null or not is_instance_valid(instance) or instance.is_queued_for_deletion() or not _pure(instance): return false
	if instance.is_inside_tree() and not get_bound_scope().is_ancestor_of(instance): return false
	var id := instance.get_instance_id()
	if _instances.has(id): return true
	_instances[id] = {"node":weakref(instance),"mode":instance.process_mode,"entered":instance.is_inside_tree(),"presentation_id":presentation_id}
	_set_instance_clock(instance)
	return true

@warning_ignore("shadowed_variable_base_class")
func _new_token(owner: Node, reason: StringName, accent: bool, camera_transition: bool = false) -> int:
	if _tokens.is_empty() and not _owns_pause_session:
		_baseline_paused = get_tree().paused
		_owns_pause_session = true
	var token := _next_token
	_next_token += 1
	_tokens[token] = {"owner":weakref(owner),"reason":reason,"accent":accent,"camera_transition":camera_transition}
	# 强调token必须在状态发布前可见，确保首帧不把本次原生动画改成PAUSABLE。
	if accent: _accent_token = token
	_apply_pause()
	return token

func _process(_delta: float) -> void:
	if get_bound_scope() == null: return
	for token in _scale_tokens.keys():
		if not _valid_owner(_from_ref(_scale_tokens[token].owner)): release_time_scale(token)
	for token in _tokens.keys():
		if not _valid_owner(_from_ref(_tokens[token].owner)): release_pause(token)
	if has_release_accent() and float(Time.get_ticks_usec()-_accent_start_usec)/1000000.0 >= _accent_duration:
		release_pause(_accent_token)
	for id in _instances.keys():
		var record: Dictionary = _instances[id]
		var instance = record.node.get_ref()
		if not is_instance_valid(instance):
			_instances.erase(id)
		elif instance.is_inside_tree():
			record.entered = true
			if not get_bound_scope().is_ancestor_of(instance):
				instance.process_mode = record.mode
				_instances.erase(id)
			else: _set_instance_clock(instance)
		elif record.entered:
			instance.process_mode = record.mode
			_instances.erase(id)
	_publish_state()

func _physics_process(_delta: float) -> void:
	if is_inside_tree() and not get_tree().paused and Engine.get_physics_frames() > _resume_frame:
		_normal_advanced = true
		_accent_ids.clear()

func _apply_pause() -> void:
	if not is_inside_tree(): return
	if not _tokens.is_empty(): get_tree().paused = true
	elif _owns_pause_session:
		get_tree().paused = _baseline_paused
		_owns_pause_session = false
	for record in _instances.values():
		var instance = record.node.get_ref()
		if is_instance_valid(instance): _set_instance_clock(instance)
	_publish_state()

func _publish_state() -> void:
	if not is_inside_tree(): return
	var state: Array = [get_tree().paused,is_presentation_allowed()]
	if state == _last_state: return
	_last_state = state
	pause_state_changed.emit(state[0],state[1])

func _set_instance_clock(instance: Node) -> void:
	instance.process_mode = Node.PROCESS_MODE_ALWAYS if is_presentation_allowed() else Node.PROCESS_MODE_PAUSABLE

func _has_explicit() -> bool:
	for record in _tokens.values():
		if not record.accent: return true
	return false

@warning_ignore("shadowed_variable_base_class")
func _valid_owner(owner: Node) -> bool:
	var scope := get_bound_scope()
	return scope != null and is_instance_valid(owner) and owner.is_inside_tree() and not owner.is_queued_for_deletion() and (owner == scope or scope.is_ancestor_of(owner))

func _pure(node: Node) -> bool:
	if node is UnitBase or node is SkillBase or node is SkillHostComponent or node is SkillDeliveryRunner or node is CollisionObject3D:
		push_warning("释放时钟只接受纯表现，拒绝单位、技能、交付或碰撞节点。")
		return false
	for child in node.get_children():
		if child.process_mode != Node.PROCESS_MODE_INHERIT:
			push_warning("释放资产子节点须使用INHERIT处理模式。")
			return false
		if not _pure(child): return false
	return true

func _from_ref(reference: WeakRef) -> Node:
	var node = reference.get_ref() if reference != null else null
	return node if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() else null

func _on_scope_exiting() -> void: _unbind(true)

func _unbind(world_exit: bool) -> void:
	if _detaching: return
	_detaching = true
	_scale_tokens.clear()
	_apply_time_scale()
	var scope = _scope_ref.get_ref() if _scope_ref != null else null
	if is_instance_valid(scope) and scope.tree_exiting.is_connected(_on_scope_exiting):
		scope.tree_exiting.disconnect(_on_scope_exiting)
	for record in _instances.values():
		var instance = record.node.get_ref()
		if is_instance_valid(instance): instance.process_mode = record.mode
	_instances.clear()
	var preserve := not world_exit and _has_explicit()
	if preserve and _owns_pause_session:
		# Godot先退出子节点再通知世界；下一渲染帧才能区分整世界退出与仅卸载本组件。
		get_tree().process_frame.connect(_restore_after_exit.bind(get_tree(),_scope_ref,_baseline_paused),CONNECT_ONE_SHOT)
	_tokens.clear()
	_accent_token = 0
	_accent_ids.clear()
	if is_inside_tree():
		if _owns_pause_session and not preserve: get_tree().paused = _baseline_paused
		var existing = (get_tree().get_meta(TREE_OWNER) if get_tree().has_meta(TREE_OWNER) else null)
		if existing is WeakRef and existing.get_ref() == self: get_tree().remove_meta(TREE_OWNER)
	_owns_pause_session = false
	_scope_ref = null
	_detaching = false
	_publish_state()

static func _restore_after_exit(tree: SceneTree, scope_ref: WeakRef, baseline: bool) -> void:
	var scope = scope_ref.get_ref() if scope_ref != null else null
	if is_instance_valid(scope) and scope.is_inside_tree():
		push_warning("暂停协调器仍有显式持有者时被单独卸载；保留暂停，请修正装配。")
	elif not tree.has_meta(TREE_OWNER):
		tree.paused = baseline

func _exit_tree() -> void: _unbind(false)
## 撤回单个本方已登记纯表现实例并恢复其原处理模式；调用方只传自己登记的实例，重复/未知无操作。
## 用于表现组件解绑，不影响实例存活、其他实例或任何暂停token。
func unregister_release_instance(instance: Node) -> void:
	if not is_instance_valid(instance): return
	var id := instance.get_instance_id()
	if not _instances.has(id): return
	instance.process_mode = _instances[id].mode
	_instances.erase(id)