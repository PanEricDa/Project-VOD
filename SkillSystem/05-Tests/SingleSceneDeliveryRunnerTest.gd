extends SceneTree

## 通用 DeliveryRunner 的真实行为测试。
##
## 测试使用运行时 PackedScene 和真实节点信号，不依赖具体 Fireball 实现，
## 从而验证执行器只负责交付，投射物仍拥有自己的生命周期。

const RUNNER_PATH := \
	"res://SkillSystem/02-Delivery/SkillDeliveryRunner.gd"

var _failures: Array[String] = []
var _root: Node3D


class RecordingEffect:
	extends SkillEffectBase

	var apply_count: int = 0
	var last_target: Node3D
	var applied_targets: Array[Node3D] = []

	func apply(
		_context: SkillContext,
		_result: SkillDeliveryResult,
		target: Node3D
	) -> bool:
		apply_count += 1
		last_target = target
		applied_targets.append(target)
		return true


class FakeProjectile:
	extends Node3D

	signal projectile_impacted(position: Vector3)

	var received_origin: Vector3 = Vector3.ZERO
	var received_target: Node3D
	var launch_count: int = 0

	func launch(
		_caster: Node3D,
		target: CharacterBody3D,
		origin: Vector3,
		_initial_direction: Vector3,
		_projectile_speed: float,
		_turn_speed_degrees: float,
		_maximum_lifetime: float,
		_impact_radius: float
	) -> bool:
		launch_count += 1
		received_origin = origin
		received_target = target
		return true


class ResolvingFakeProjectile:
	extends FakeProjectile

	signal projectile_targets_resolved(targets: Array[CharacterBody3D])


class SynchronousImpactProjectile:
	extends ResolvingFakeProjectile

	func launch(
		_caster: Node3D,
		target: CharacterBody3D,
		origin: Vector3,
		_initial_direction: Vector3,
		_projectile_speed: float,
		_turn_speed_degrees: float,
		_maximum_lifetime: float,
		_impact_radius: float
	) -> bool:
		launch_count += 1
		received_origin = origin
		received_target = target
		var targets: Array[CharacterBody3D] = [target]
		projectile_targets_resolved.emit(targets)
		projectile_impacted.emit(origin)
		tree_exiting.emit()
		return true


class LaunchExitProjectile:
	extends FakeProjectile

	static var last_instance: Node3D

	func launch(
		_caster: Node3D,
		target: CharacterBody3D,
		origin: Vector3,
		_initial_direction: Vector3,
		_projectile_speed: float,
		_turn_speed_degrees: float,
		_maximum_lifetime: float,
		_impact_radius: float
	) -> bool:
		launch_count += 1
		received_origin = origin
		received_target = target
		last_instance = self
		get_parent().remove_child(self)
		return true


class FalseLaunchProjectile:
	extends FakeProjectile

	func launch(
		_caster: Node3D,
		target: CharacterBody3D,
		origin: Vector3,
		_initial_direction: Vector3,
		_projectile_speed: float,
		_turn_speed_degrees: float,
		_maximum_lifetime: float,
		_impact_radius: float
	) -> bool:
		launch_count += 1
		received_origin = origin
		received_target = target
		return false


class FalseImpactLaunchProjectile:
	extends ResolvingFakeProjectile

	func launch(
		_caster: Node3D,
		target: CharacterBody3D,
		origin: Vector3,
		_initial_direction: Vector3,
		_projectile_speed: float,
		_turn_speed_degrees: float,
		_maximum_lifetime: float,
		_impact_radius: float
	) -> bool:
		launch_count += 1
		received_origin = origin
		received_target = target
		var targets: Array[CharacterBody3D] = [target]
		projectile_targets_resolved.emit(targets)
		projectile_impacted.emit(origin)
		return false


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "DeliveryTestWorld"
	get_root().add_child(_root)
	call_deferred(&"_run_tests")


func _run_tests() -> void:
	if not ResourceLoader.exists(RUNNER_PATH):
		_failures.append("DeliveryRunner script does not exist")
		_finish()
		return
	var runner_script := load(RUNNER_PATH) as Script
	if runner_script == null or not runner_script.can_instantiate():
		_failures.append("DeliveryRunner script does not compile")
		_finish()
		return
	_verify_instant_delivery(runner_script)
	_verify_projectile_delivery(runner_script)
	_verify_projectile_target_resolution(runner_script)
	_verify_projectile_target_removed_before_impact(runner_script)
	_verify_projectile_cancel_clears_runtime_data(runner_script)
	await _verify_synchronous_launch_impact(runner_script)
	await _verify_launch_time_tree_exit(runner_script)
	_verify_false_launch(runner_script)
	_verify_false_launch_with_synchronous_impact(runner_script)
	_verify_invalid_configuration(runner_script)
	_finish()


func _verify_instant_delivery(runner_script: Script) -> void:
	var runner: Node = runner_script.new()
	_root.add_child(runner)
	var caster := Node3D.new()
	var target := CharacterBody3D.new()
	_root.add_child(caster)
	_root.add_child(target)

	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = target
	context.target_position = target.global_position
	context.delivery_parent = _root
	var effect := RecordingEffect.new()
	var effects: Array[SkillEffectBase] = [effect]
	var finished_count: Array[int] = [0]
	runner.delivery_finished.connect(
		func(_context: SkillContext, _result: SkillDeliveryResult) -> void:
			finished_count[0] += 1
	)

	_expect(
		bool(runner.call(
			"execute",
			InstantTargetDeliveryConfig.new(),
			context,
			Transform3D(Basis.IDENTITY, Vector3(4.0, 1.0, 2.0)),
			effects
		)),
		"Instant delivery starts"
	)
	_expect(effect.apply_count == 1, "Instant delivery applies each effect once")
	_expect(effect.last_target == target, "Instant delivery uses resolved target")
	_expect(finished_count[0] == 1, "Instant delivery finishes once")
	_expect(not bool(runner.call("is_busy")), "Instant delivery releases runner")

	var missing_target := context.duplicate_context() as SkillContext
	missing_target.resolved_target = null
	_expect(
		not bool(runner.call(
			"execute",
			InstantTargetDeliveryConfig.new(),
			missing_target,
			Transform3D.IDENTITY,
			effects
		)),
		"Instant delivery rejects a missing target"
	)
	effect.free()
	runner.queue_free()
	caster.queue_free()
	target.queue_free()


func _verify_projectile_delivery(runner_script: Script) -> void:
	var runner: Node = runner_script.new()
	_root.add_child(runner)
	var caster := Node3D.new()
	var target := CharacterBody3D.new()
	_root.add_child(caster)
	_root.add_child(target)
	target.global_position = Vector3(8.0, 0.0, 3.0)

	var projectile_template := FakeProjectile.new()
	var projectile_scene := PackedScene.new()
	_expect(
		projectile_scene.pack(projectile_template) == OK,
		"Fake projectile packs into a real PackedScene"
	)
	projectile_template.free()

	var config := TrackingProjectileDeliveryConfig.new()
	config.projectile_scene = projectile_scene
	config.projectile_speed = 9.0
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = target
	context.delivery_parent = _root
	var launch_origin := Vector3(13.0, 2.0, -7.0)
	var effect := RecordingEffect.new()
	var effects: Array[SkillEffectBase] = [effect]

	_expect(
		bool(runner.call(
			"execute",
			config,
			context,
			Transform3D(Basis.IDENTITY, launch_origin),
			effects
		)),
		"Tracking projectile delivery starts"
	)
	_expect(bool(runner.call("is_busy")), "Runner remains busy during projectile flight")
	var projectile: FakeProjectile
	for child: Node in _root.get_children():
		if child is FakeProjectile:
			projectile = child as FakeProjectile
			break
	_expect(projectile != null, "Tracking delivery spawns exactly one fake projectile")
	if projectile != null:
		_expect(
			projectile.received_origin == launch_origin,
			"Projectile receives the supplied world launch origin"
		)
		_expect(projectile.received_target == target, "Projectile receives resolved target")
		projectile.projectile_impacted.emit(Vector3(8.0, 0.5, 3.0))
	_expect(not bool(runner.call("is_busy")), "Impact releases the runner")
	_expect(effect.apply_count == 1, "Legacy projectile falls back to original target")
	_expect(effect.last_target == target, "Fallback effect uses original target")

	effect.free()
	runner.queue_free()
	caster.queue_free()
	target.queue_free()


func _verify_projectile_target_resolution(runner_script: Script) -> void:
	var runner: Node = runner_script.new()
	_root.add_child(runner)
	var caster := Node3D.new()
	var original_target := CharacterBody3D.new()
	var area_target := CharacterBody3D.new()
	_root.add_child(caster)
	_root.add_child(original_target)
	_root.add_child(area_target)

	var projectile_template := ResolvingFakeProjectile.new()
	var projectile_scene := PackedScene.new()
	_expect(
		projectile_scene.pack(projectile_template) == OK,
		"Resolving fake projectile packs into a real PackedScene"
	)
	projectile_template.free()
	var config := TrackingProjectileDeliveryConfig.new()
	config.projectile_scene = projectile_scene
	config.projectile_speed = 9.0
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = original_target
	context.delivery_parent = _root
	var effect := RecordingEffect.new()
	var effects: Array[SkillEffectBase] = [effect]
	var delivered_targets: Array[Node3D] = []
	runner.delivery_finished.connect(
		func(_context: SkillContext, result: SkillDeliveryResult) -> void:
			delivered_targets.clear()
			delivered_targets.append_array(result.affected_targets)
	)
	_expect(
		bool(runner.call(
			"execute",
			config,
			context,
			Transform3D.IDENTITY,
			effects
		)),
		"Resolving projectile delivery starts"
	)
	var projectile: ResolvingFakeProjectile
	for child: Node in _root.get_children():
		if child is ResolvingFakeProjectile:
			var candidate := child as ResolvingFakeProjectile
			if candidate.received_target == original_target:
				projectile = candidate
				break
	_expect(projectile != null, "Resolving projectile instance is available")
	if projectile != null:
		var resolved_targets: Array[CharacterBody3D] = [original_target, area_target]
		projectile.projectile_targets_resolved.emit(resolved_targets)
		projectile.projectile_impacted.emit(Vector3(2.0, 0.0, 1.0))
	_expect(effect.apply_count == 2, "Resolved targets each receive the generic effect once")
	_expect(
		effect.applied_targets.has(original_target)
			and effect.applied_targets.has(area_target),
		"Resolved targets are delivered without replacement"
	)
	_expect(
		delivered_targets.size() == 2
			and delivered_targets.has(original_target)
			and delivered_targets.has(area_target),
		"Projectile result records every resolved target"
	)

	effect.free()
	runner.queue_free()
	caster.queue_free()
	original_target.queue_free()
	area_target.queue_free()


func _verify_projectile_target_removed_before_impact(
	runner_script: Script
) -> void:
	var runner: Node = runner_script.new()
	_root.add_child(runner)
	var caster := Node3D.new()
	var target := CharacterBody3D.new()
	_root.add_child(caster)
	_root.add_child(target)

	var projectile_template := ResolvingFakeProjectile.new()
	var projectile_scene := PackedScene.new()
	_expect(
		projectile_scene.pack(projectile_template) == OK,
		"Removed-target projectile fixture packs"
	)
	projectile_template.free()
	var config := TrackingProjectileDeliveryConfig.new()
	config.projectile_scene = projectile_scene
	config.projectile_speed = 9.0
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = target
	context.delivery_parent = _root
	var effect := RecordingEffect.new()
	var effects: Array[SkillEffectBase] = [effect]
	var finished_count: Array[int] = [0]
	var delivered_targets: Array[Node3D] = []
	runner.delivery_finished.connect(
		func(_context: SkillContext, result: SkillDeliveryResult) -> void:
			finished_count[0] += 1
			delivered_targets.assign(result.affected_targets)
	)

	_expect(
		bool(runner.call(
			"execute",
			config,
			context,
			Transform3D.IDENTITY,
			effects
		)),
		"Projectile delivery with a removable target starts"
	)
	var projectile: ResolvingFakeProjectile
	for child: Node in _root.get_children():
		if child is ResolvingFakeProjectile:
			var candidate := child as ResolvingFakeProjectile
			if candidate.received_target == target:
				projectile = candidate
				break
	_expect(projectile != null, "Removed-target projectile instance is available")
	if projectile != null:
		var resolved_targets: Array[CharacterBody3D] = [target]
		projectile.projectile_targets_resolved.emit(resolved_targets)
		_root.remove_child(target)
		projectile.projectile_impacted.emit(Vector3(3.0, 0.0, 2.0))
	_expect(finished_count[0] == 1, "Removed-target delivery still finishes once")
	_expect(effect.apply_count == 0, "Removed target receives no effect at impact")
	_expect(
		delivered_targets.is_empty(),
		"Removed target is absent from the authoritative impact result"
	)

	effect.free()
	runner.queue_free()
	caster.queue_free()
	target.queue_free()


func _verify_projectile_cancel_clears_runtime_data(runner_script: Script) -> void:
	var runner: Node = runner_script.new()
	_root.add_child(runner)
	var caster := Node3D.new()
	var stale_target := CharacterBody3D.new()
	var fallback_target := CharacterBody3D.new()
	_root.add_child(caster)
	_root.add_child(stale_target)
	_root.add_child(fallback_target)

	var resolving_template := ResolvingFakeProjectile.new()
	var resolving_scene := PackedScene.new()
	_expect(resolving_scene.pack(resolving_template) == OK, "Cancel fixture packs")
	resolving_template.free()
	var resolving_config := TrackingProjectileDeliveryConfig.new()
	resolving_config.projectile_scene = resolving_scene
	resolving_config.projectile_speed = 9.0
	var stale_context := SkillContext.new()
	stale_context.caster = caster
	stale_context.resolved_target = stale_target
	stale_context.delivery_parent = _root
	var stale_effect := RecordingEffect.new()
	var stale_effects: Array[SkillEffectBase] = [stale_effect]
	_expect(
		bool(runner.call(
			"execute", resolving_config, stale_context, Transform3D.IDENTITY, stale_effects
		)),
		"Cancelable resolving projectile starts"
	)
	var resolving_projectile: ResolvingFakeProjectile
	for child: Node in _root.get_children():
		if child is ResolvingFakeProjectile:
			resolving_projectile = child as ResolvingFakeProjectile
			break
	if resolving_projectile != null:
		var stale_targets: Array[CharacterBody3D] = [stale_target]
		resolving_projectile.projectile_targets_resolved.emit(stale_targets)
	runner.call("cancel", &"test_cancel")

	var fallback_template := FakeProjectile.new()
	var fallback_scene := PackedScene.new()
	_expect(fallback_scene.pack(fallback_template) == OK, "Fallback fixture packs")
	fallback_template.free()
	var fallback_config := TrackingProjectileDeliveryConfig.new()
	fallback_config.projectile_scene = fallback_scene
	fallback_config.projectile_speed = 9.0
	var fallback_context := SkillContext.new()
	fallback_context.caster = caster
	fallback_context.resolved_target = fallback_target
	fallback_context.delivery_parent = _root
	var fallback_effect := RecordingEffect.new()
	var fallback_effects: Array[SkillEffectBase] = [fallback_effect]
	_expect(
		bool(runner.call(
			"execute", fallback_config, fallback_context, Transform3D.IDENTITY, fallback_effects
		)),
		"Delivery starts cleanly after cancellation"
	)
	var fallback_projectile: FakeProjectile
	for child: Node in _root.get_children():
		if child is FakeProjectile and not (child is ResolvingFakeProjectile):
			var candidate := child as FakeProjectile
			if candidate.received_target == fallback_target:
				fallback_projectile = candidate
				break
	_expect(fallback_projectile != null, "Fallback projectile instance is available")
	if fallback_projectile != null:
		fallback_projectile.projectile_impacted.emit(Vector3.ZERO)
	_expect(stale_effect.apply_count == 0, "Cancelled delivery never applies stale effects")
	_expect(
		fallback_effect.apply_count == 1,
		"Next delivery applies its own effect once"
	)
	_expect(
		fallback_effect.last_target == fallback_target,
		"Next delivery does not inherit stale targets"
	)

	stale_effect.free()
	fallback_effect.free()
	runner.queue_free()
	caster.queue_free()
	stale_target.queue_free()
	fallback_target.queue_free()


func _verify_synchronous_launch_impact(runner_script: Script) -> void:
	var runner: Node = runner_script.new()
	_root.add_child(runner)
	var caster := Node3D.new()
	var target := CharacterBody3D.new()
	_root.add_child(caster)
	_root.add_child(target)
	var template := SynchronousImpactProjectile.new()
	var scene := PackedScene.new()
	_expect(scene.pack(template) == OK, "Synchronous impact fixture packs")
	template.free()
	var config := TrackingProjectileDeliveryConfig.new()
	config.projectile_scene = scene
	config.projectile_speed = 9.0
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = target
	context.delivery_parent = _root
	var effect := RecordingEffect.new()
	var effects: Array[SkillEffectBase] = [effect]
	var events: Array[String] = []
	var finished_count: Array[int] = [0]
	var failed_count: Array[int] = [0]
	runner.delivery_started.connect(
		func(_context: SkillContext) -> void:
			events.append("started")
	)
	runner.delivery_finished.connect(
		func(_context: SkillContext, _result: SkillDeliveryResult) -> void:
			finished_count[0] += 1
			events.append("finished")
	)
	runner.delivery_failed.connect(
		func(_context: SkillContext, _reason: StringName) -> void:
			failed_count[0] += 1
			events.append("failed")
	)
	_expect(
		bool(runner.call("execute", config, context, Transform3D.IDENTITY, effects)),
		"Synchronous impact launch is accepted"
	)
	_expect(
		events == ["started"] and finished_count[0] == 0 and failed_count[0] == 0,
		"Synchronous impact starts before its deferred terminal signal"
	)
	_expect(effect.apply_count == 0, "Synchronous impact defers effect application")
	await process_frame
	_expect(effect.apply_count == 1, "Synchronous launch applies its effect after execute returns")
	_expect(
		events == ["started", "finished"]
			and finished_count[0] == 1
			and failed_count[0] == 0,
		"Synchronous impact emits exactly one deferred finished signal"
	)
	_expect(not bool(runner.call("is_busy")), "Deferred synchronous impact releases runner")

	effect.free()
	runner.queue_free()
	caster.queue_free()
	target.queue_free()


func _verify_launch_time_tree_exit(runner_script: Script) -> void:
	var runner: Node = runner_script.new()
	_root.add_child(runner)
	var caster := Node3D.new()
	var target := CharacterBody3D.new()
	_root.add_child(caster)
	_root.add_child(target)
	var template := LaunchExitProjectile.new()
	var scene := PackedScene.new()
	_expect(scene.pack(template) == OK, "Launch-time exit fixture packs")
	template.free()
	var config := TrackingProjectileDeliveryConfig.new()
	config.projectile_scene = scene
	config.projectile_speed = 9.0
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = target
	context.delivery_parent = _root
	var effects: Array[SkillEffectBase] = []
	var events: Array[String] = []
	var finished_count: Array[int] = [0]
	var failed_count: Array[int] = [0]
	runner.delivery_started.connect(
		func(_context: SkillContext) -> void:
			events.append("started")
	)
	runner.delivery_finished.connect(
		func(_context: SkillContext, _result: SkillDeliveryResult) -> void:
			finished_count[0] += 1
			events.append("finished")
	)
	runner.delivery_failed.connect(
		func(_context: SkillContext, _reason: StringName) -> void:
			failed_count[0] += 1
			events.append("failed")
	)
	_expect(
		bool(runner.call("execute", config, context, Transform3D.IDENTITY, effects)),
		"Launch-time exit launch is accepted"
	)
	_expect(
		events == ["started"] and finished_count[0] == 0 and failed_count[0] == 0,
		"Launch-time exit defers its failed terminal signal"
	)
	await process_frame
	_expect(
		events == ["started", "failed"]
			and finished_count[0] == 0
			and failed_count[0] == 1,
		"Launch-time tree exit emits exactly one deferred failed terminal signal"
	)
	_expect(not bool(runner.call("is_busy")), "Deferred launch-time exit releases runner")

	if is_instance_valid(LaunchExitProjectile.last_instance):
		LaunchExitProjectile.last_instance.free()
	runner.queue_free()
	caster.queue_free()
	target.queue_free()


func _verify_false_launch(runner_script: Script) -> void:
	var runner: Node = runner_script.new()
	_root.add_child(runner)
	var caster := Node3D.new()
	var target := CharacterBody3D.new()
	_root.add_child(caster)
	_root.add_child(target)
	var template := FalseLaunchProjectile.new()
	var scene := PackedScene.new()
	_expect(scene.pack(template) == OK, "False launch fixture packs")
	template.free()
	var config := TrackingProjectileDeliveryConfig.new()
	config.projectile_scene = scene
	config.projectile_speed = 9.0
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = target
	context.delivery_parent = _root
	var effect := RecordingEffect.new()
	var effects: Array[SkillEffectBase] = [effect]
	var started_count: Array[int] = [0]
	var terminal_count: Array[int] = [0]
	runner.delivery_started.connect(
		func(_context: SkillContext) -> void:
			started_count[0] += 1
	)
	runner.delivery_finished.connect(
		func(_context: SkillContext, _result: SkillDeliveryResult) -> void:
			terminal_count[0] += 1
	)
	runner.delivery_failed.connect(
		func(_context: SkillContext, _reason: StringName) -> void:
			terminal_count[0] += 1
	)
	_expect(
		not bool(runner.call("execute", config, context, Transform3D.IDENTITY, effects)),
		"Plain false launch rejects delivery"
	)
	_expect(
		started_count[0] == 0 and terminal_count[0] == 0,
		"Plain false launch emits no public Runner signal"
	)
	_expect(effect.apply_count == 0, "Plain false launch applies no effect")
	_expect(not bool(runner.call("is_busy")), "Plain false launch clears Runner state")

	effect.free()
	runner.queue_free()
	caster.queue_free()
	target.queue_free()


func _verify_false_launch_with_synchronous_impact(runner_script: Script) -> void:
	var runner: Node = runner_script.new()
	_root.add_child(runner)
	var caster := Node3D.new()
	var target := CharacterBody3D.new()
	_root.add_child(caster)
	_root.add_child(target)
	var template := FalseImpactLaunchProjectile.new()
	var scene := PackedScene.new()
	_expect(scene.pack(template) == OK, "False synchronous-impact fixture packs")
	template.free()
	var config := TrackingProjectileDeliveryConfig.new()
	config.projectile_scene = scene
	config.projectile_speed = 9.0
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = target
	context.delivery_parent = _root
	var effect := RecordingEffect.new()
	var effects: Array[SkillEffectBase] = [effect]
	var started_count: Array[int] = [0]
	var terminal_count: Array[int] = [0]
	runner.delivery_started.connect(
		func(_context: SkillContext) -> void:
			started_count[0] += 1
	)
	runner.delivery_finished.connect(
		func(_context: SkillContext, _result: SkillDeliveryResult) -> void:
			terminal_count[0] += 1
	)
	runner.delivery_failed.connect(
		func(_context: SkillContext, _reason: StringName) -> void:
			terminal_count[0] += 1
	)
	_expect(
		not bool(runner.call("execute", config, context, Transform3D.IDENTITY, effects)),
		"False launch with synchronous impact rejects delivery"
	)
	_expect(
		started_count[0] == 0 and terminal_count[0] == 0,
		"False launch discards synchronous terminal reports"
	)
	_expect(effect.apply_count == 0, "False synchronous impact applies no effect")
	_expect(not bool(runner.call("is_busy")), "False synchronous impact clears Runner state")

	effect.free()
	runner.queue_free()
	caster.queue_free()
	target.queue_free()


func _verify_invalid_configuration(runner_script: Script) -> void:
	var runner: Node = runner_script.new()
	_root.add_child(runner)
	var context := SkillContext.new()
	context.caster = _root
	context.resolved_target = CharacterBody3D.new()
	_root.add_child(context.resolved_target)
	context.delivery_parent = _root
	var effects: Array[SkillEffectBase] = []
	var child_count_before: int = _root.get_child_count()
	_expect(
		not bool(runner.call(
			"execute",
			TrackingProjectileDeliveryConfig.new(),
			context,
			Transform3D.IDENTITY,
			effects
		)),
		"Invalid tracking config is rejected"
	)
	_expect(
		_root.get_child_count() == child_count_before,
		"Invalid config leaves no runtime child"
	)
	runner.queue_free()
	context.resolved_target.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	if _failures.is_empty():
		print("SingleSceneDeliveryRunnerTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
