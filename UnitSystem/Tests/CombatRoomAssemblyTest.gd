extends SceneTree
## 正式入口装配契约：基础房间不复制，系统唯一、引用同域、预览逻辑不进入正式战斗。
const ROOM := "res://Scenes/CombatRoom.tscn"
const COMPONENTS := [
	"SquadFocusComponent", "SquadChainCommandController", "SquadChainCommandDisplay", "SquadChainRoundDisplay",
	"ChainSkillPresentationController", "SquadChainRoundController",
	"SquadFinisherSelectionController", "SquadFinisherSelectionDisplay", "SquadFinisherExecutionController"
]
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	_expect(ResourceLoader.exists(ROOM), "complete playable CombatRoom exists")
	if not ResourceLoader.exists(ROOM):
		_finish()
		return
	var packed := load(ROOM) as PackedScene
	_expect(packed.get_state().get_base_scene_state() != null, "room inherits existing map instead of copying units")
	_expect(ResourceLoader.get_resource_uid(ROOM) != ResourceUID.INVALID_ID, "official scene UID registered")
	var configured: String = ProjectSettings.get_setting("application/run/main_scene","")
	var resolved := ResourceUID.get_id_path(ResourceUID.text_to_id(configured)) if configured.begins_with("uid://") else configured
	_expect(resolved == ROOM,"F5 starts fully assembled room")
	var scene := packed.instantiate() as Node3D
	var configured_focus := scene.get_node("SquadFocusComponent") as SquadFocusComponent
	var configured_initial := clampf(configured_focus.initial_focus,0.0,configured_focus.maximum_focus)
	var configured_difficulty := configured_focus.focus_gain_difficulty
	root.add_child(scene)
	current_scene = scene
	for frame: int in range(5): await process_frame
	await physics_frame
	_expect(scene.get_script() == null,"no preview bootstrap in production room")
	for component: String in COMPONENTS:
		_expect(scene.get_node_or_null(component) != null,"visible system node: "+component)
		var count := 0
		for child: Node in scene.get_children():
			if String(child.name).begins_with(component): count += 1
		_expect(count == 1,"one system owner: "+component)
	if not failures.is_empty():
		scene.free()
		await process_frame
		_finish()
		return
	var focus := scene.get_node("SquadFocusComponent") as SquadFocusComponent
	var command := scene.get_node("SquadChainCommandController") as SquadChainCommandController
	var evaluation := scene.get_node("SquadChainRoundController") as SquadChainRoundController
	var presentation := scene.get_node("ChainSkillPresentationController") as ChainSkillPresentationController
	var selection := scene.get_node("SquadFinisherSelectionController") as SquadFinisherSelectionController
	var execution := scene.get_node("SquadFinisherExecutionController") as SquadFinisherExecutionController
	_expect(focus.get_bound_scope() == scene and command.get_bound_scope() == scene,"actual room is shared world")
	_expect(is_equal_approx(focus.focus_gain_difficulty,configured_difficulty),"assembly preserves human configured focus difficulty")
	_expect(is_equal_approx(focus.get_current_focus(),configured_initial),"starting resource follows Inspector configuration without preview bootstrap")
	_expect(command.focus_source == focus and evaluation.command_source == command,"focus command and evaluation connected")
	_expect(presentation.command_source == command and presentation.camera_source == scene.get_node("CameraRig"),"shared original camera and command")
	_expect(selection.round_source == evaluation and selection.pause_source == presentation.pause_source,"one evaluation and pause source")
	_expect(execution.selection_source == selection and execution.camera_source == presentation.camera_source,"selection executes with original camera")
	_expect(scene.get_node("SquadChainCommandDisplay").command_source == command and scene.get_node("SquadChainRoundDisplay").round_source == evaluation,"four-slot UI and real score wired")
	_expect(scene.get_node("SquadFinisherSelectionDisplay").selection_source == selection,"finisher UI wired")
	_expect(not "阶段二" in scene.get_node("SquadChainCommandDisplay/Panel/VBox/Title").text,"complete room UI must not label itself a stage-two-only preview")
	_expect(evaluation.call("_configuration_valid"),"current human configured scoring and adaptive window are usable")
	var names := ["Guardian","Priest","Caster","Archer"]
	for index: int in range(4):
		var actor := scene.get_node(names[index]) as AllyBase
		_expect(command.companions[index] == actor,"fixed button order "+str(index+1))
		var host := actor.get_node("SkillHost") as SkillHostComponent
		_expect(host.get_equipped_regular_skills().size() == 2 and host.get_combo_skill() != null,"two normal and separate chain skills "+names[index])
		var combo := host.get_combo_skill()
		_expect(combo.cast_effect_scene != null and combo.cast_effect_scene.resource_path == "res://Effects/Skills/Shared/ReleaseAccentFlash.tscn","formal source equips shared flash without preview overrides "+names[index])
		_expect(combo.cast_effect_anchor == SkillBase.PresentationAnchor.CASTER_FEET and is_equal_approx(combo.cast_effect_start_ratio,0.5),"formal flash uses caster feet and half-cast timing "+names[index])
		if index == 2:
			_expect(host.get_finisher_skill() != null and host.get_finisher_skill().cinematic_profile.cinematic_mode == 1,"Caster equips accepted B finisher")
		elif index == 0:
			_expect(host.get_finisher_skill() != null and host.get_finisher_skill().skill_id == &"guardian_armor_break_finisher","Guardian equips self-centered armor break finisher")
		elif index == 3:
			_expect(host.get_finisher_skill() != null and host.get_finisher_skill().skill_id == &"archer_power_shot_finisher","Archer equips single-target power shot finisher")
		elif names[index] == "Priest":
			_expect(host.get_finisher_skill() != null and host.get_finisher_skill().skill_id == &"holy_blessing_finisher","Priest equips friendly damage blessing finisher")
		else:
			_expect(host.get_finisher_skill() == null,"no invented finisher for "+names[index])
	_expect(evaluation.get_round_status().bound and evaluation.peek_current_round() == 0,"real round provider bound without artificial round")
	scene.free()
	await process_frame
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0),"room teardown restores time ownership")
	# 历史入口保留独立装配和原用途，不因正式入口增加而出现第二套控制器。
	for path: String in ["res://Scenes/Previews/SquadChainCommandPreview.tscn","res://Scenes/Previews/SquadFinisherSelectionPreview.tscn"]:
		var preview := load(path).instantiate() as Node
		var command_count := 0
		for child: Node in preview.get_children():
			if child is SquadChainCommandController: command_count += 1
		_expect(command_count == 1,"preview has one commander "+path)
		preview.free()
	_finish()
func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message: String in failures: printerr("FAIL: ",message)
	print("CombatRoomAssemblyTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
