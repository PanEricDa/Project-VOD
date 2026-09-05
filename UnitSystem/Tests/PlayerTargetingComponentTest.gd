extends SceneTree

## 真实 PlayerTargetingComponent 与正式锁定特效（TargetLockIndicator）的集成契约测试。
## 使用真实 UnitBase 持有者、目标与组件场景验证锁定状态、信号语义、Debug 圆环与正式特效的
## 分离配置、单实例复用、跟随、切换与主动解除；所有断言通过公开接口与稳定节点路径完成。
## 对计划新增的配置字段使用 in 守卫的鸭子访问，保证实施前测试可编译且以预期原因失败。

const COMPONENT_SCENE_PATH := (
	"res://UnitSystem/Components/Targeting/PlayerTargetingComponent.tscn"
)
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
## 无头环境下推进进入动画的计时安全余量，单位为秒。
const TIME_MARGIN := 0.08

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(
		ResourceLoader.exists(COMPONENT_SCENE_PATH),
		"targeting component scene exists"
	)
	var component_scene := load(COMPONENT_SCENE_PATH) as PackedScene
	var unit_scene := load(UNIT_SCENE_PATH) as PackedScene
	_expect(
		component_scene != null and unit_scene != null,
		"targeting fixtures load"
	)
	if component_scene == null or unit_scene == null:
		_finish()
		return

	_world = Node3D.new()
	_world.name = "PlayerTargetingComponentTestWorld"
	root.add_child(_world)
	await _test_existing_interface_contract()
	await _test_formal_indicator_integration()
	await _test_degradation_cases()
	if is_instance_valid(_world):
		_world.queue_free()
	await process_frame
	_finish()


## 验证既有公开锁定接口与信号语义在接入正式特效前后保持不变。
func _test_existing_interface_contract() -> void:
	var fixture := await _make_fixture()
	var component: PlayerTargetingComponent = fixture.component
	var first: UnitBase = fixture.first
	var events := _make_signal_recorder(component)

	_expect(
		component.request_lock(first),
		"request_lock accepts a valid hostile target"
	)
	_expect(
		component.get_locked_target() == first,
		"get_locked_target returns the locked unit"
	)
	_expect(events.size() == 1, "a successful lock broadcasts exactly once")
	_expect(
		component.request_lock(first),
		"re-locking the same target still succeeds"
	)
	_expect(
		events.size() == 1,
		"re-locking the same target does not rebroadcast"
	)
	_expect(
		not component.get_locked_target_direction().is_zero_approx(),
		"the locked direction stays a usable horizontal vector"
	)
	component.clear_locked_target()
	_expect(
		component.get_locked_target() == null,
		"clear_locked_target releases the business lock"
	)
	_expect(
		events.size() == 2 and events[1] == null,
		"clearing broadcasts null exactly once"
	)
	component.clear_locked_target()
	_expect(
		events.size() == 2,
		"clearing without a target stays silent"
	)
	await _dispose_fixture(fixture)


## 验证 Debug 圆环默认关闭、正式特效单实例进入/跟随/切换/解除与退出中断。
func _test_formal_indicator_integration() -> void:
	var fixture := await _make_fixture()
	var component: PlayerTargetingComponent = fixture.component
	var first: UnitBase = fixture.first
	var second: UnitBase = fixture.second
	var events := _make_signal_recorder(component)

	var debug_node := (
		component.get_node_or_null(^"TargetLockRangeIndicator")
			as MeshInstance3D
	)
	_expect(debug_node != null, "the debug range indicator node remains present")
	if debug_node != null:
		_expect(
			not debug_node.visible,
			"the debug ring stays hidden by default"
		)
	_expect(
		component.get("formal_indicator_scene") != null,
		"a default formal indicator scene is configured"
	)
	var indicator_height := 0.03
	if "formal_indicator_height" in component:
		indicator_height = float(component.get("formal_indicator_height"))

	_expect(component.request_lock(first), "the first lock succeeds")
	if debug_node != null:
		_expect(
			not debug_node.visible,
			"locking does not reveal the debug ring"
		)
	var indicators := _collect_formal_indicators(component)
	_expect(
		indicators.size() == 1,
		"locking creates exactly one formal indicator instance"
	)
	var indicator: TargetLockIndicator = (
		indicators[0] if indicators.size() > 0 else null
	)
	if indicator == null:
		await _dispose_fixture(fixture)
		return
	_expect(
		indicator.is_effect_visible()
			and indicator.get_effect_state() == TargetLockIndicator.EffectState.ENTER,
		"the formal indicator enters on the first lock"
	)
	_expect(
		indicator.global_position.is_equal_approx(
			first.global_position + Vector3.UP * indicator_height
		),
		"the formal indicator sits at the target foot position"
	)
	_expect(
		events.size() == 1,
		"the formal effect adds no extra signal broadcasts"
	)

	await _wait_seconds(indicator.enter_duration + TIME_MARGIN)
	_expect(
		indicator.get_effect_state() == TargetLockIndicator.EffectState.MAINTAIN,
		"the formal indicator reaches MAINTAIN after the enter duration"
	)
	first.position = Vector3(2.5, 0.0, 0.5)
	await physics_frame
	await physics_frame
	_expect(
		indicator.global_position.is_equal_approx(
			first.global_position + Vector3.UP * indicator_height
		),
		"the formal indicator follows the moving target"
	)
	_expect(
		indicator.get_effect_state() == TargetLockIndicator.EffectState.MAINTAIN,
		"following keeps the MAINTAIN state"
	)
	_expect(
		component.request_lock(first),
		"re-locking the same target still succeeds with the effect"
	)
	_expect(
		_collect_formal_indicators(component).size() == 1,
		"re-locking keeps a single formal instance"
	)
	_expect(
		events.size() == 1,
		"re-locking stays silent with the effect"
	)
	_expect(
		indicator.get_effect_state() == TargetLockIndicator.EffectState.MAINTAIN,
		"re-locking does not replay the enter state"
	)

	_expect(
		component.request_lock(second),
		"switching to the second target succeeds"
	)
	_expect(
		component.get_locked_target() == second,
		"the business lock switches immediately"
	)
	_expect(
		events.size() == 2,
		"switching broadcasts exactly once"
	)
	_expect(
		_collect_formal_indicators(component).size() == 1,
		"switching reuses the single formal instance without exit copies"
	)
	_expect(
		indicator.global_position.is_equal_approx(
			second.global_position + Vector3.UP * indicator_height
		),
		"the reused instance jumps to the new target foot position"
	)
	_expect(
		indicator.get_effect_state() == TargetLockIndicator.EffectState.ENTER,
		"switching replays the enter state on the reused instance"
	)

	var position_before_clear := indicator.global_position
	component.clear_locked_target()
	_expect(
		component.get_locked_target() == null,
		"clearing releases the business lock immediately"
	)
	_expect(
		events.size() == 3 and events[2] == null,
		"clearing broadcasts null exactly once with the effect"
	)
	_expect(
		indicator.get_effect_state() == TargetLockIndicator.EffectState.EXIT,
		"clearing starts the exit state on the formal indicator"
	)
	_expect(
		indicator.global_position.is_equal_approx(position_before_clear),
		"the exit keeps the last synced world position"
	)
	_expect(
		component.request_lock(first),
		"re-locking during the running exit succeeds"
	)
	_expect(
		indicator.get_effect_state() == TargetLockIndicator.EffectState.ENTER,
		"a new lock interrupts the running exit"
	)
	_expect(
		indicator.global_position.is_equal_approx(
			first.global_position + Vector3.UP * indicator_height
		),
		"the interrupted exit moves to the new target position"
	)
	await _dispose_fixture(fixture)


## 验证关闭正式特效、缺失资源与开启 Debug 时互不影响锁定能力和另一类显示。
func _test_degradation_cases() -> void:
	var disabled_fixture := await _make_fixture(
		func(component: PlayerTargetingComponent) -> void:
			if "formal_indicator_enabled" in component:
				component.set("formal_indicator_enabled", false)
	)
	var disabled_component: PlayerTargetingComponent = disabled_fixture.component
	var disabled_events := _make_signal_recorder(disabled_component)
	_expect(
		_collect_formal_indicators(disabled_component).size() == 0,
		"a disabled formal effect creates no instance"
	)
	_expect(
		disabled_component.request_lock(disabled_fixture.first),
		"locking still works with the formal effect disabled"
	)
	_expect(
		disabled_component.get_locked_target() == disabled_fixture.first
			and disabled_events.size() == 1,
		"the disabled effect keeps lock state and signal semantics"
	)
	_expect(
		not disabled_component.get_locked_target_direction().is_zero_approx(),
		"the locked direction works with the effect disabled"
	)
	var disabled_debug := (
		disabled_component.get_node_or_null(^"TargetLockRangeIndicator")
			as MeshInstance3D
	)
	if disabled_debug != null:
		_expect(
			not disabled_debug.visible,
			"disabling the formal effect never reveals the debug ring"
		)
	await _dispose_fixture(disabled_fixture)

	var null_scene_fixture := await _make_fixture(
		func(component: PlayerTargetingComponent) -> void:
			if "formal_indicator_scene" in component:
				component.set("formal_indicator_scene", null)
	)
	var null_scene_component: PlayerTargetingComponent = (
		null_scene_fixture.component
	)
	var null_scene_events := _make_signal_recorder(null_scene_component)
	_expect(
		_collect_formal_indicators(null_scene_component).size() == 0,
		"a missing formal scene creates no instance"
	)
	_expect(
		null_scene_component.request_lock(null_scene_fixture.first),
		"locking still works without a formal scene resource"
	)
	_expect(
		null_scene_component.get_locked_target() == null_scene_fixture.first
			and null_scene_events.size() == 1,
		"the missing resource keeps lock state and signal semantics"
	)
	_expect(
		not null_scene_component.get_locked_target_direction().is_zero_approx(),
		"the locked direction works without a formal scene"
	)
	await physics_frame
	await physics_frame
	await _dispose_fixture(null_scene_fixture)

	var debug_fixture := await _make_fixture(
		func(component: PlayerTargetingComponent) -> void:
			component.set("indicator_enabled", true)
	)
	var debug_component: PlayerTargetingComponent = debug_fixture.component
	var debug_node := (
		debug_component.get_node_or_null(^"TargetLockRangeIndicator")
			as MeshInstance3D
	)
	_expect(
		debug_node != null and debug_node.visible,
		"an explicitly enabled debug ring stays visible"
	)
	_expect(
		debug_component.request_lock(debug_fixture.first),
		"locking works with the debug ring visible"
	)
	_expect(
		_collect_formal_indicators(debug_component).size() == 1,
		"the formal effect coexists with the enabled debug ring"
	)
	if debug_node != null:
		_expect(
			debug_node.visible,
			"the formal effect never hides the debug ring"
		)
	await _dispose_fixture(debug_fixture)


## 建立一名 team 1 持有者、挂载真实组件并创建两名 team 2 锁定目标的夹具。
## prep_component 在组件进入场景树之前调用，用于预置启用或资源降级配置。
func _make_fixture(
	prep_component: Callable = Callable()
) -> Dictionary:
	var holder := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	holder.name = "FixtureHolder"
	holder.team_id = 1
	_world.add_child(holder)
	var component := (
		(load(COMPONENT_SCENE_PATH) as PackedScene).instantiate()
		as PlayerTargetingComponent
	)
	component.name = "TargetingSystem"
	if prep_component.is_valid():
		prep_component.call(component)
	holder.add_child(component)
	var first := _make_target("FirstTarget", Vector3(1.5, 0.0, -1.0))
	var second := _make_target("SecondTarget", Vector3(-1.2, 0.0, -2.0))
	await process_frame
	_expect(
		component.configure(holder),
		"the component configures with its owner"
	)
	return {
		"holder": holder,
		"component": component,
		"first": first,
		"second": second,
	}


## 创建一名加入 enemy_targets 分组的 team 2 目标单位。
func _make_target(target_name: String, target_position: Vector3) -> UnitBase:
	var target := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	target.name = target_name
	target.team_id = 2
	target.position = target_position
	target.add_to_group(&"enemy_targets")
	_world.add_child(target)
	return target


## 记录 locked_target_changed 的全部广播，供次数与载荷断言使用。
func _make_signal_recorder(component: PlayerTargetingComponent) -> Array:
	var events: Array = []
	component.locked_target_changed.connect(
		func(target: UnitBase) -> void:
			events.append(target)
	)
	return events


## 收集组件子树内全部 TargetLockIndicator 实例，验证单实例契约。
func _collect_formal_indicators(node: Node) -> Array:
	var found: Array = []
	if node is TargetLockIndicator:
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_collect_formal_indicators(child))
	return found


## 只清理本夹具创建的持有者与目标；组件随持有者一同释放。
func _dispose_fixture(fixture: Dictionary) -> void:
	for key: String in ["holder", "first", "second"]:
		var node := fixture.get(key) as Node
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PlayerTargetingComponentTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("PlayerTargetingComponentTest: FAIL (%d)" % _failures.size())
	quit(1)
