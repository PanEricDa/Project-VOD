class_name StatusEffectComponent
extends Node

## 单位临时 Buff 与 Debuff 的统一运行时管理器。## 本组件不保存角色基础属性，也不参与死亡生命周期；它只维护可叠加、可刷新、可到期的属性修正，并由 UnitBase 的 getter 汇总为有效属性。

## 可修正攻击力、防御及造成伤害倍率；移动速度为预留。OUTGOING_DAMAGE以1为基础倍率，不影响治疗。
enum ModifierStat {
	ATTACK_POWER,
	DEFENSE,
	MOVEMENT_SPEED,
	OUTGOING_DAMAGE,
}

## 属性数值的运算方式；FLAT 为固定点数，PERCENT 为百分比点（-25表示降低25%）。
## 所有固定修正先相加，再乘 max(1+百分比修正总和/100,0)，不改写基础属性。
enum ModifierMode {
	FLAT,
	PERCENT,
}

## 同一效果再次施加时的处理规则。## REFRESH 更新同来源同属性的数值与剩余时间；STACK 保留多个独立层；REPLACE 清除该属性的全部旧修正后写入新修正。
enum StackingRule {
	REFRESH,
	STACK,
	REPLACE,
}

## 临时效果被添加或刷新后发送。## source 为运行时效果来源，stat 表示修正属性，amount 在 FLAT 模式为固定增减值、PERCENT 模式为百分比点，remaining_duration 为剩余秒数；-1 表示永久直到被主动移除。
signal modifier_changed(source: Object, stat: ModifierStat, amount: float, remaining_duration: float)
## 临时效果被移除、到期或因单位死亡清理时发送。## source 已失效时传 null；调用方不得依赖来源仍处于场景树。
signal modifier_removed(source: Object, stat: ModifierStat)
## 命名状态新增或刷新时 active 为 true，到期、主动清除或死亡清理时为 false；status_id 为发生变化的状态标识。
signal named_status_changed(status_id: StringName, active: bool)


# 属性修正与命名绑定状态共用纯视觉记录；不持有单位，也没有第二个倒计时。
class StatusVisualRecord extends RefCounted:
	## 可选视觉资产及弱实例引用；真实状态决定出现/刷新/移除。
	var visual_scene: PackedScene
	var visual_ref: WeakRef

class ModifierRecord extends StatusVisualRecord:
	## 创建此修正的运行时对象实例 ID；用于同来源刷新和主动清理，不作为 Inspector 配置。
	var source_instance_id: int = 0
	## 创建此修正的对象引用；仅用于信号通知，Node 销毁后须用 is_instance_valid 判定并按空来源通知。
	var source: Object
	## 被修正的属性枚举。
	var stat: ModifierStat
	## 运算方式，与 amount 一起解释数值；默认固定修正兼容旧效果。
	var modifier_mode: ModifierMode = ModifierMode.FLAT
	## 固定点数或百分比点；允许负数以表达 Debuff。
	var amount: float = 0.0
	## 剩余持续秒数；-1 表示永久效果。
	var remaining_duration: float = -1.0


## 被挂载的单位。## 仅能通过 configure_owner() 设置，防止 Buff 容器意外管理错误的角色。
var _owner_unit: UnitBase
## 当前全部生效中的修正记录；只由本组件改写，外部只能经公开接口施加或清除效果。
var _active_modifiers: Array[ModifierRecord] = []
## 命名限时状态的剩余秒数；与属性修正分离，状态 ID 可供技能连锁读取。
var _named_status_remaining: Dictionary = {}


func _ready() -> void:
	if get_parent() is UnitBase:
		configure_owner(get_parent() as UnitBase)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	advance_effects(delta)


## 注入本组件所属单位。## owner_unit 必须有效；更换持有者会断开旧死亡信号并清空旧单位残留的全部修正。
func configure_owner(owner_unit: UnitBase) -> bool:
	if _owner_unit == owner_unit:
		return is_instance_valid(_owner_unit)
	_disconnect_owner()
	clear_all_modifiers()
	clear_all_named_statuses()
	if not is_instance_valid(owner_unit):
		_owner_unit = null
		return false
	_owner_unit = owner_unit
	if not _owner_unit.died.is_connected(_on_owner_died):
		_owner_unit.died.connect(_on_owner_died)
	return true


## 添加或刷新一个临时属性修正。## source 用于识别同一效果来源；duration_seconds 大于等于 0 表示限时，负数表示永久；REFRESH 不会重复叠加同来源同属性同运算方式。
## modifier_mode 默认 FLAT 兼容旧五参数调用；PERCENT 的 amount=-25 表示降低25%，同属性百分比点相加。
## visual_scene为可选Node3D持续视觉，挂在受益单位下；刷新复用，到期/移除/死亡销毁，默认空不生成。
func apply_modifier(
	source: Object,
	stat: ModifierStat,
	amount: float,
	duration_seconds: float,
	stacking_rule: StackingRule = StackingRule.REFRESH,
	modifier_mode: ModifierMode = ModifierMode.FLAT,
	visual_scene: PackedScene = null
) -> bool:
	if not is_instance_valid(_owner_unit) or _owner_unit.is_dead() or not is_instance_valid(source):
		return false
	if stat not in [0,1,2,3] or stacking_rule not in [0,1,2] or modifier_mode not in [0,1] or not is_finite(amount) or not is_finite(duration_seconds):
		return false
	var source_id: int = source.get_instance_id()
	var normalized_duration: float = duration_seconds if duration_seconds < 0.0 else maxf(duration_seconds, 0.0)
	if stacking_rule == StackingRule.REFRESH:
		for record: ModifierRecord in _active_modifiers:
			if record.source_instance_id == source_id and record.stat == stat and record.modifier_mode == modifier_mode:
				record.amount = amount
				record.remaining_duration = normalized_duration
				record.source = source
				_sync_modifier_visual(record, visual_scene)
				modifier_changed.emit(source, stat, amount, normalized_duration)
				return true
	elif stacking_rule == StackingRule.REPLACE:
		_remove_matching_stat(stat)

	var created := ModifierRecord.new()
	created.source_instance_id = source_id
	created.source = source
	created.stat = stat
	created.modifier_mode = modifier_mode
	created.amount = amount
	created.remaining_duration = normalized_duration
	_active_modifiers.append(created)
	_sync_modifier_visual(created, visual_scene)
	modifier_changed.emit(source, stat, amount, normalized_duration)
	return true


## 推进全部限时修正的倒计时。## delta 必须为非负秒数；到期修正将在本次调用内移除，永久效果不会被推进。
func advance_effects(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	for token: int in _bound_statuses.keys():
		if not _bound_statuses.has(token): continue
		var bound: Dictionary = _bound_statuses[token]
		bound.remaining = maxf(float(bound.remaining)-delta,0.0)
		if bound.remaining <= 0.0 or not _valid_bound_source(bound.source_ref.get_ref() as UnitBase):
			remove_bound_status(token)
	for status_id: StringName in _named_status_remaining.keys():
		var remaining: float = maxf(float(_named_status_remaining[status_id]) - delta, 0.0)
		if remaining <= 0.0:
			_named_status_remaining.erase(status_id)
			if not has_named_status(status_id): _publish_named_status(status_id)
		else:
			_named_status_remaining[status_id] = remaining
	for index: int in range(_active_modifiers.size() - 1, -1, -1):
		var record := _active_modifiers[index]
		if record.remaining_duration < 0.0:
			continue
		record.remaining_duration = maxf(record.remaining_duration - delta, 0.0)
		if record.remaining_duration <= 0.0:
			_remove_at(index)


## 返回指定属性在所有生效状态下的固定修正总和，不混入百分比点，保持旧查询语义。## 正值为 Buff、负值为 Debuff；未存在任何修正时返回 0。
func get_modifier_total(stat: ModifierStat) -> float:
	var total: float = 0.0
	for record: ModifierRecord in _active_modifiers:
		if record.stat == stat and record.modifier_mode == ModifierMode.FLAT:
			total += record.amount
	return total


## 根据指定属性和当前基础值计算有效属性；base_value 不被改写。
## 先加固定修正，再乘所有百分比点之和对应的倍率；结果不低于0，未配置状态时仍安全归一。
func get_modified_value(stat: ModifierStat, base_value: float) -> float:
	var percentage_points: float = 0.0
	for record: ModifierRecord in _active_modifiers:
		if record.stat == stat and record.modifier_mode == ModifierMode.PERCENT:
			percentage_points += record.amount
	return maxf((base_value+get_modifier_total(stat))*maxf(1.0+percentage_points/100.0,0.0),0.0)


## 查询指定属性是否存在仍在容器中生效的负向修正；stat 使用 ModifierStat 枚举。
## 固定值与百分比均支持，不与正向Buff抵消后再判断，不暴露内部记录或增加独立计时。
func has_negative_modifier(stat: ModifierStat) -> bool:
	for record: ModifierRecord in _active_modifiers:
		if record.stat == stat and record.amount < 0.0:
			return true
	return false


## 返回当前效果数量，仅供 Inspector 调试、测试与未来状态栏读取。## 不返回内部记录，避免外部绕过叠加和清理规则。
func get_active_modifier_count() -> int:
	return _active_modifiers.size()


## 施加或刷新一个命名状态；status_id 不得为空，duration_seconds 为有限且大于零的秒数。
## 同 ID 再次施加会把剩余时间刷新为本次时长，不叠加属性修正或状态层数。
func apply_named_status(status_id: StringName, duration_seconds: float) -> bool:
	if (
		not is_instance_valid(_owner_unit)
		or _owner_unit.is_dead()
		or status_id == &""
		or not is_finite(duration_seconds)
		or duration_seconds <= 0.0
	):
		return false
	_named_status_remaining[status_id] = duration_seconds
	_publish_named_status(status_id,true)
	return true


## 查询指定 ID 是否仍有正数剩余时间；空 ID 或已到期状态返回 false。
func has_named_status(status_id: StringName) -> bool:
	if status_id == &"": return false
	if float(_named_status_remaining.get(status_id,0.0)) > 0.0: return true
	for record: Dictionary in _bound_statuses.values():
		if record.status_id == status_id and record.remaining > 0.0: return true
	return false


## 移除指定的命名状态；status_id 不能为空。仅当状态当前存在时返回 true，
## 并发送一次 named_status_changed(status_id, false)；不影响其他状态或属性修正。
func remove_named_status(status_id: StringName) -> bool:
	var existed := has_named_status(status_id)
	if status_id == &"" or not existed: return false
	_named_status_remaining.erase(status_id)
	var tokens: Array[int] = []
	for token: int in _bound_statuses:
		if _bound_statuses[token].status_id == status_id: tokens.append(token)
	for token: int in tokens: remove_bound_status(token)
	if tokens.is_empty() and not has_named_status(status_id):
		_publish_named_status(status_id)
	return true


## 返回当前状态 ID 的副本，供一次命中的前置状态快照使用；调用方不能修改容器内部记录。
func get_active_status_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for status_id: StringName in _named_status_remaining.keys():
		if has_named_status(status_id):
			ids.append(status_id)
	for record: Dictionary in _bound_statuses.values():
		if record.remaining > 0.0 and not ids.has(record.status_id): ids.append(record.status_id)
	return ids


## 清空全部命名状态并逐个发送移除信号；死亡或更换持有单位时调用，不影响属性 Modifier。
func clear_all_named_statuses() -> void:
	var removed_ids := get_active_status_ids()
	var removed: Array = _bound_statuses.values()
	for record: Dictionary in _suspended_bound.values():
		record.invalidated = true
		removed.append(record)
	_suspended_bound.clear()
	_bound_epoch += 1
	_named_status_remaining.clear()
	_bound_statuses.clear()
	for token: int in _prepared_bound.keys(): discard_bound_status(token)
	for record: Dictionary in removed: _dispose_bound(record,true)
	for status_id: StringName in removed_ids:
		if not has_named_status(status_id): _publish_named_status(status_id)


## 清理指定来源创建的全部效果。## source 必须是原始效果对象；适用于驱散、技能卸载或外部状态结束。
func remove_modifiers_from_source(source: Object) -> void:
	if source == null:
		return
	var source_id: int = source.get_instance_id()
	for index: int in range(_active_modifiers.size() - 1, -1, -1):
		if _active_modifiers[index].source_instance_id == source_id:
			_remove_at(index)


## 清空全部临时与永久属性修正。## 单位死亡或状态容器更换持有者时调用；不会改写 UnitBase 的基础属性配置。
func clear_all_modifiers() -> void:
	for index: int in range(_active_modifiers.size() - 1, -1, -1):
		_remove_at(index)


func _on_owner_died(_source: Node) -> void:
	clear_all_modifiers()
	clear_all_named_statuses()


func _remove_matching_stat(stat: ModifierStat) -> void:
	for index: int in range(_active_modifiers.size() - 1, -1, -1):
		if _active_modifiers[index].stat == stat:
			_remove_at(index)


func _remove_at(index: int) -> void:
	if index < 0 or index >= _active_modifiers.size():
		return
	var record := _active_modifiers[index]
	_active_modifiers.remove_at(index)
	_clear_modifier_visual(record)
	modifier_removed.emit(record.source if is_instance_valid(record.source) else null, record.stat)


func _disconnect_owner() -> void:
	if is_instance_valid(_owner_unit) and _owner_unit.died.is_connected(_on_owner_died):
		_owner_unit.died.disconnect(_on_owner_died)
	_owner_unit = null



# 视觉不承担状态逻辑；同记录刷新仅在资产变化或旧实例失效时重建。
func _sync_modifier_visual(record: StatusVisualRecord, scene: PackedScene) -> void:
	var existing := record.visual_ref.get_ref() as Node3D if record.visual_ref != null else null
	if record.visual_scene == scene and is_instance_valid(existing) and not existing.is_queued_for_deletion():
		return
	_clear_modifier_visual(record)
	if scene == null or not is_instance_valid(_owner_unit) or not _owner_unit.is_inside_tree():
		return
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		push_warning("StatusEffectComponent: status_visual_scene must have a Node3D root.")
		return
	var container := _owner_unit.get_node_or_null(^"StatusModifierVisuals") as Node3D
	if container == null:
		container = Node3D.new()
		container.name = "StatusModifierVisuals"
		_owner_unit.add_child(container)
	instance.set_meta(&"presentation_source_ref", weakref(_owner_unit))
	record.visual_scene = scene
	record.visual_ref = weakref(instance)
	container.add_child(instance)

func _clear_modifier_visual(record: StatusVisualRecord) -> void:
	var visual := record.visual_ref.get_ref() as Node3D if record.visual_ref != null else null
	record.visual_ref = null
	record.visual_scene = null
	if is_instance_valid(visual):
		# 可选纯视觉收尾；状态记录已经移除，不因淡出继续提供数值。
		if visual.has_method(&"finish_presentation"):
			visual.call(&"finish_presentation")
		else:
			visual.hide()
			visual.queue_free()

func _exit_tree() -> void:
	_accepting_bound = false
	clear_all_named_statuses()
	for record: ModifierRecord in _active_modifiers:
		_clear_modifier_visual(record)


# 绑定状态只保存一份remaining；token/连接/准备表均为内部运行时身份，不导出到Inspector。
var _bound_statuses: Dictionary = {}
# 同命名状态在本单位只保留一份视觉；多来源共享，不改变各来源原有独立仇恨/时间。
var _bound_status_visuals: Dictionary = {}
# 仅用于多个视觉资产的稳定选择；只有成功提交才递增，失败回滚不改变旧视觉顺序。
var _bound_visual_revision: int = 0
# 刷新提交期间暂存的旧代仍须接收外部终止；绝不恢复已被终止或清表的记录。
var _suspended_bound: Dictionary = {}
var _published_named_statuses: Dictionary = {}
var _prepared_bound: Dictionary = {}
var _next_bound_token: int = 0
var _bound_epoch: int = 0
var _accepting_bound: bool = true
var _departing_bound_sources: Dictionary = {}

## source须树内存活，status_id/effect_key非空，duration_seconds为有限正战斗秒；on_removed绑定外部效果的幂等清理，不应依赖技能节点。
## 同来源同状态同effect_key刷新；成功返回true，失败不改变旧记录。
func apply_bound_status(status_id: StringName, source: UnitBase, effect_key: StringName, duration_seconds: float, on_removed: Callable) -> bool:
	var token := prepare_bound_status(status_id,source,effect_key,duration_seconds,on_removed)
	return token > 0 and commit_bound_status(token)

## 仅准备一代记录并返回正token；参数约束同apply_bound_status，不开始计时、不替换旧状态或发送变化。
func prepare_bound_status(status_id: StringName, source: UnitBase, effect_key: StringName, duration_seconds: float, on_removed: Callable) -> int:
	if not _valid_bound_source(source) or status_id == &"" or effect_key == &"" or not is_finite(duration_seconds) or duration_seconds <= 0.0 or not on_removed.is_valid():
		return 0
	_next_bound_token += 1
	var token := _next_bound_token
	_prepared_bound[token] = {"token":token,"status_id":status_id,"source_id":source.get_instance_id(),"source_ref":weakref(source),"effect_key":effect_key,"remaining":duration_seconds,"cleanup":on_removed,"previous":_find_bound_token(status_id,source.get_instance_id(),effect_key),"epoch":_bound_epoch}
	return token

## 提交prepare返回的token；可选on_commit须返回bool，先安装本代再调用以原子绑定外部效果，返回false则保留旧有效记录。
## 通知回调中新建/取消的记录优先，旧提交绝不覆盖新代。
## visual_scene为可选Node3D持续视觉，默认空；成功提交才显示，刷新复用，失败保留旧视觉，时长由状态统一管理。
func commit_bound_status(token: int, on_commit: Callable = Callable(), visual_scene: PackedScene = null) -> bool:
	if not _prepared_bound.has(token): return false
	var record: Dictionary = _prepared_bound[token]
	record.visual_scene = visual_scene
	if not _valid_bound_source(record.source_ref.get_ref() as UnitBase) or record.epoch != _bound_epoch or _find_bound_token(record.status_id,record.source_id,record.effect_key) != record.previous:
		discard_bound_status(token)
		return false
	_prepared_bound.erase(token)
	var previous: Dictionary = _bound_statuses.get(record.previous,{})
	if not previous.is_empty(): _suspended_bound[previous.token] = previous
	_bound_statuses.erase(record.previous)
	_bound_statuses[token] = record
	_watch_bound_source(record)
	var attached: bool = true
	if on_commit.is_valid():
		var outcome: Variant = on_commit.call()
		attached = outcome is bool and bool(outcome)
	if not attached or not _bound_statuses.has(token):
		var owned_current: bool = _bound_statuses.has(token)
		_bound_statuses.erase(token)
		_dispose_bound(record,true)
		_suspended_bound.erase(record.previous)
		# 清理回调可能死亡、清表或重建：必须在回调之后重新校验，不使用过期的回滚资格。
		if owned_current and record.epoch == _bound_epoch and _valid_bound_source(record.source_ref.get_ref() as UnitBase) and not previous.is_empty() and not previous.get("invalidated",false) and not previous.get("disposed",false) and _find_bound_token(record.status_id,record.source_id,record.effect_key)==0:
			_bound_statuses[previous.token] = previous
		elif not previous.is_empty():
			_dispose_bound(previous,true)
		_publish_named_status(record.status_id)
		return false
	_suspended_bound.erase(record.previous)
	if not previous.is_empty(): _dispose_bound(previous,true)
	if not _bound_statuses.has(token): return false
	_bound_visual_revision += 1
	record.visual_revision = _bound_visual_revision
	_publish_named_status(record.status_id,true)
	return _bound_statuses.has(token)

## 撤销尚未提交的准备记录并断开本代预注册连接；不执行旧记录清理，也不影响已生效记录。
func discard_bound_status(token: int) -> void:
	if not _prepared_bound.has(token): return
	var record: Dictionary = _prepared_bound[token]
	_prepared_bound.erase(token)
	_dispose_bound(record,false)

## 只移除token指定的已提交一代；先从容器脱离再通知/清理，重复或旧token返回false。
func remove_bound_status(token: int) -> bool:
	if not _bound_statuses.has(token): return false
	var record: Dictionary = _bound_statuses[token]
	_bound_statuses.erase(token)
	_dispose_bound(record,true)
	_sync_bound_status_visual(record.status_id)
	if not has_named_status(record.status_id): _publish_named_status(record.status_id)
	return true

## 将外部终止信号绑定到一代状态；信号必须携带一个int身份，只有其值等于external_token时才解除bound_token。
## 只保存发出者弱引用和信号名，移除/失败/离树断连；不识别外部具体效果类别。
func bind_external_status_removal(bound_token: int, external_end_signal: Signal, external_token: int) -> bool:
	var record: Dictionary = _prepared_bound.get(bound_token,_bound_statuses.get(bound_token,{}))
	if record.is_empty() or external_end_signal.is_null() or external_token <= 0 or record.has("external_ref"): return false
	var emitter: Object = external_end_signal.get_object()
	if not is_instance_valid(emitter): return false
	var callback: Callable = func(ended_token: int) -> void:
		_on_bound_external_end(ended_token,bound_token,external_token)
	record.external_ref = weakref(emitter)
	record.external_name = external_end_signal.get_name()
	record.external_callback = callback
	external_end_signal.connect(callback)
	return true

func _valid_bound_source(source: UnitBase) -> bool:
	return _accepting_bound and is_inside_tree() and is_instance_valid(_owner_unit) and not _owner_unit.is_dead() and _owner_unit.is_inside_tree() and is_instance_valid(source) and source.is_inside_tree() and not source.is_queued_for_deletion() and not source.is_dead() and not _departing_bound_sources.has(source.get_instance_id())

func _find_bound_token(status_id: StringName, source_id: int, key: StringName) -> int:
	for token: int in _bound_statuses:
		var row: Dictionary = _bound_statuses[token]
		if row.status_id==status_id and row.source_id==source_id and row.effect_key==key: return token
	return 0

func _watch_bound_source(record: Dictionary) -> void:
	var source: UnitBase = record.source_ref.get_ref() as UnitBase
	if not is_instance_valid(source): return
	var token: int = record.token
	var died_callback: Callable = func(killer: Node) -> void: _on_bound_source_died(killer,token)
	var exit_callback: Callable = func() -> void: _on_bound_source_exit(token)
	source.died.connect(died_callback)
	source.tree_exiting.connect(exit_callback)
	record.died_callback = died_callback
	record.exit_callback = exit_callback

func _dispose_bound(record: Dictionary, cleanup: bool) -> void:
	if record.get("disposed",false): return
	record.disposed = true
	var source: UnitBase = record.source_ref.get_ref() as UnitBase
	if is_instance_valid(source):
		if record.has("died_callback") and source.died.is_connected(record.died_callback): source.died.disconnect(record.died_callback)
		if record.has("exit_callback") and source.tree_exiting.is_connected(record.exit_callback): source.tree_exiting.disconnect(record.exit_callback)
	if record.has("external_ref"):
		var emitter: Object = record.external_ref.get_ref()
		if is_instance_valid(emitter) and emitter.is_connected(record.external_name,record.external_callback):
			emitter.disconnect(record.external_name,record.external_callback)
	if cleanup and record.cleanup.is_valid(): record.cleanup.call()

func _on_bound_source_died(_killer: Node, token: int) -> void:
	remove_bound_status(token)

func _on_bound_source_exit(token: int) -> void:
	if _bound_statuses.has(token):
		var record: Dictionary = _bound_statuses[token]
		var source: UnitBase = record.source_ref.get_ref() as UnitBase
		var id: int = record.source_id
		_departing_bound_sources[id] = true
		if is_instance_valid(source): source.tree_exited.connect(func() -> void: _departing_bound_sources.erase(id),CONNECT_ONE_SHOT)
	remove_bound_status(token)

func _on_bound_external_end(external_token: int, bound_token: int, expected_token: int) -> void:
	if external_token != expected_token: return
	if _suspended_bound.has(bound_token):
		_suspended_bound[bound_token].invalidated = true
	elif _prepared_bound.has(bound_token): discard_bound_status(bound_token)
	else: remove_bound_status(bound_token)

func _publish_named_status(status_id: StringName, refresh: bool = false) -> void:
	var active := has_named_status(status_id)
	var previous: bool = bool(_published_named_statuses.get(status_id,false))
	if active: _published_named_statuses[status_id] = true
	else: _published_named_statuses.erase(status_id)
	if active != previous or (active and refresh): named_status_changed.emit(status_id,active)
	# 通知可能同步移除/刷新；按通知后的实际记录同步，不把旧快照的标记重新放回。
	_sync_bound_status_visual(status_id)

func _sync_bound_status_visual(status_id: StringName) -> void:
	var scene: PackedScene
	var latest_revision: int = -1
	for record: Dictionary in _bound_statuses.values():
		if record.status_id == status_id and record.remaining > 0.0 and record.get("visual_scene") is PackedScene and int(record.get("visual_revision",0)) > latest_revision:
			scene = record.visual_scene
			latest_revision = int(record.get("visual_revision",0))
	var visual_record := _bound_status_visuals.get(status_id) as StatusVisualRecord
	if scene == null:
		if visual_record != null:
			_bound_status_visuals.erase(status_id)
			_clear_modifier_visual(visual_record)
		return
	if visual_record == null:
		visual_record = StatusVisualRecord.new()
		_bound_status_visuals[status_id] = visual_record
	_sync_modifier_visual(visual_record,scene)

func _enter_tree() -> void:
	_accepting_bound = true
