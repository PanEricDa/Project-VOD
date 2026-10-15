@tool
class_name ChainSkillPresentationController
extends Node
## 关卡级只读事实协调；不激活/取消技能、不支付费用，不创建全队施放队列。
## 原四伙伴指令源，默认空；世界与槽归属只从此读取。
@export var command_source: SquadChainCommandController
## 当前原CameraRig，默认空；缺失只跳过镜头，不影响其他通道。
@export var camera_source: CameraFollowController
## 本组件场景预填可见PauseCoordinator；缺失仅跳过停顿与时钟登记。
@export var pause_source: GamePauseCoordinator
var _source_ref: WeakRef
var _camera_ref: WeakRef
var _pause_ref: WeakRef
var _scope_ref: WeakRef
var _candidates: Dictionary = {}
var _owner_id: int = 0
var _sequence: int = 0
var _accent_tokens: Array[int] = []
var _signature: Array = []
const ASSEMBLY_OWNER: StringName = &"_chain_presentation_owner"
var _claims: Array[WeakRef] = []
var _release_instances: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_assembly()

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	_refresh_assembly()
	var camera = _camera()
	var pause = _pause()
	if _owner_id != 0 and _candidates.has(_owner_id):
		var current: Dictionary = _candidates[_owner_id]
		if current.released and (pause == null or not pause.has_release_accent()): _finish(_owner_id)
	for id in _candidates.keys():
		if not _candidates.has(id): continue
		var record: Dictionary = _candidates[id]
		var fact: SkillPresentationContext = record.fact
		var actor := fact.get_source()
		if actor == null or (actor is UnitBase and actor.is_dead()):
			_finish(id)
			continue
		if not get_tree().paused and not record.released:
			record.elapsed += maxf(delta,0.0)
			if record.elapsed > maxf(fact.effective_cast_time,0.0)+1.0:
				push_warning("连携施法镜头看门狗回收构图；不改变技能或费用。")
				_finish(id)
	for instance_id in _release_instances.keys():
		var instance = _release_instances[instance_id].get_ref()
		if not is_instance_valid(instance) or not instance.is_inside_tree(): _release_instances.erase(instance_id)
	if pause == null or not pause.has_release_accent(): _accent_tokens.clear()
	if camera == null: _owner_id = 0

func _refresh_assembly() -> void:
	var signature: Array = [_id(command_source),_id(camera_source),_id(pause_source)]
	if signature == _signature: return
	_detach()
	_signature = signature
	if not is_instance_valid(command_source): return
	_source_ref = weakref(command_source)
	_camera_ref = weakref(camera_source) if is_instance_valid(camera_source) else null
	_pause_ref = weakref(pause_source) if is_instance_valid(pause_source) else null
	command_source.scope_changed.connect(_on_scope_changed)
	command_source.command_started.connect(_on_started)
	command_source.command_failed.connect(_on_failed)
	command_source.command_release_instance_prepared.connect(_on_prepared)
	command_source.command_release_presentation_started.connect(_on_presented)
	_on_scope_changed(command_source.get_bound_scope())

func _on_scope_changed(scope: Node) -> void:
	_detach_scope()
	if not is_instance_valid(scope) or not scope.is_inside_tree() or not scope.is_ancestor_of(self): return
	var pause := _pause()
	var source := _source()
	var camera := _camera()
	if source == null: return
	if camera != null and not scope.is_ancestor_of(camera):
		push_warning("连携镜头必须位于同一绑定世界；跳过镜头。")
		_camera_ref = null
		camera = null
	if pause != null and not scope.is_ancestor_of(pause):
		push_warning("暂停协调器必须位于同一绑定世界；跳过停顿。")
		_pause_ref = null
		pause = null
	var channels: Array[Node] = [source]
	if camera != null: channels.append(camera)
	if pause != null: channels.append(pause)
	# 先原子检查所有共享消费者，再触碰镜头/输入注入。拒绝的重复组件必须完全惰性。
	for channel in channels:
		var holder = channel.get_meta(ASSEMBLY_OWNER) if channel.has_meta(ASSEMBLY_OWNER) else null
		if holder is WeakRef and is_instance_valid(holder.get_ref()) and holder.get_ref() != self:
			push_warning("共享指令源、镜头或暂停协调器已由另一连携表现组件接管；拒绝重复装配。")
			return
	if pause != null and not pause.bind_scope(scope): return
	for channel in channels:
		channel.set_meta(ASSEMBLY_OWNER,weakref(self))
		_claims.append(weakref(channel))
	_scope_ref = weakref(scope)
	source.set_presentation_pause_source(pause)
	if camera != null: camera.set_presentation_pause_source(pause)

func _valid(fact: SkillPresentationContext) -> bool:
	var scope = _scope_ref.get_ref() if _scope_ref != null else null
	return fact != null and fact.is_chain_root and is_instance_valid(scope) and scope.is_inside_tree() and not scope.is_queued_for_deletion() and fact.get_world() == scope and _source() != null and _source().get_bound_scope() == scope

func _on_started(_slot: int, fact: SkillPresentationContext) -> void:
	if not _valid(fact) or _candidates.has(fact.presentation_id): return
	_sequence += 1
	_candidates[fact.presentation_id] = {"fact":fact,"order":_sequence,"elapsed":0.0,"released":false}
	_choose_candidate()

func _choose_candidate() -> void:
	if _owner_id != 0: return
	var camera := _camera()
	if camera == null: return
	var ids := _candidates.keys()
	ids.sort_custom(func(a, b): return _candidates[a].order < _candidates[b].order)
	for id in ids:
		var record: Dictionary = _candidates[id]
		if record.released or not _valid(record.fact): continue
		var fact: SkillPresentationContext = record.fact
		if camera.begin_presentation_focus(id,fact.get_source(),fact.get_camera_profile()):
			_owner_id = id
			return

func _on_prepared(_slot: int, fact: SkillPresentationContext, instance: Node) -> void:
	var pause := _pause()
	if _valid(fact) and pause != null and pause.register_release_instance(fact.presentation_id,instance):
		_release_instances[instance.get_instance_id()] = weakref(instance)

func _on_presented(_slot: int, fact: SkillPresentationContext) -> void:
	if not _valid(fact): return
	var pause := _pause()
	if pause != null:
		var token := pause.request_release_accent(fact.presentation_id,fact.pause_duration_seconds,self)
		if token > 0: _accent_tokens.append(token)
	if _candidates.has(fact.presentation_id):
		_candidates[fact.presentation_id].released = true
		if fact.presentation_id != _owner_id or fact.pause_duration_seconds <= 0.0 or pause == null or not pause.has_release_accent():
			_finish(fact.presentation_id)

func _on_failed(_slot: int, request_id: int, _reason: StringName) -> void:
	for id in _candidates.keys():
		if _candidates[id].fact.command_request_id == request_id: _finish(id)

func _finish(id: int) -> void:
	_candidates.erase(id)
	if id != _owner_id: return
	var camera := _camera()
	if camera != null: camera.end_presentation_focus(id)
	_owner_id = 0
	_choose_candidate()

func _owns(node: Node) -> bool:
	if not is_instance_valid(node) or not node.has_meta(ASSEMBLY_OWNER): return false
	var holder = node.get_meta(ASSEMBLY_OWNER)
	return holder is WeakRef and holder.get_ref() == self

func _detach_scope() -> void:
	var camera := _camera()
	var pause := _pause()
	var source := _source()
	if _owns(camera):
		camera.clear_presentation_focus()
		camera.set_presentation_pause_source(null)
	if _owns(source): source.set_presentation_pause_source(null)
	if _owns(pause):
		for token in _accent_tokens: pause.release_pause(token)
		for reference in _release_instances.values():
			var instance = reference.get_ref()
			if is_instance_valid(instance): pause.unregister_release_instance(instance)
		# 这里只撤回本表现组件。指令重绑不等于世界销毁，不解除菜单等其他持有者。
		# 协调器自行监听真实世界退出，负责该世界的最终清理。
	for reference in _claims:
		var channel = reference.get_ref()
		if _owns(channel): channel.remove_meta(ASSEMBLY_OWNER)
	_claims.clear()
	_release_instances.clear()
	_accent_tokens.clear()
	_candidates.clear()
	_owner_id = 0
	_scope_ref = null

func _detach() -> void:
	_detach_scope()
	var source := _source()
	if source != null:
		var connections: Array = [
			[source.scope_changed,_on_scope_changed],[source.command_started,_on_started],
			[source.command_failed,_on_failed],[source.command_release_instance_prepared,_on_prepared],
			[source.command_release_presentation_started,_on_presented]]
		for connection in connections:
			if connection[0].is_connected(connection[1]): connection[0].disconnect(connection[1])
	_source_ref = null
	_camera_ref = null
	_pause_ref = null

func _source() -> SquadChainCommandController: return _ref(_source_ref) as SquadChainCommandController
func _camera() -> CameraFollowController: return _ref(_camera_ref) as CameraFollowController
func _pause() -> GamePauseCoordinator: return _ref(_pause_ref) as GamePauseCoordinator
func _ref(reference: WeakRef) -> Node:
	var value = reference.get_ref() if reference != null else null
	return value if is_instance_valid(value) and value.is_inside_tree() else null
func _id(node: Node) -> int: return node.get_instance_id() if is_instance_valid(node) else 0

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if command_source == null: warnings.append("请选择本关卡原四伙伴指令源。")
	if camera_source == null: warnings.append("未选择CameraRig：将跳过镜头。")
	if pause_source == null: warnings.append("未选择PauseCoordinator：将跳过停顿与独立时钟。")
	return warnings

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): _detach()