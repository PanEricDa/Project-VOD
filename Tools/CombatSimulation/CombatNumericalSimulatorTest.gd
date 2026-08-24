extends SceneTree

const SIMULATOR_SCRIPT := preload("res://Tools/CombatSimulation/CombatNumericalSimulator.gd")

func _initialize() -> void:
	var simulator := SIMULATOR_SCRIPT.new()
	var result: Dictionary = simulator.run_scenario(3, 0, 8, 8)
	if result.get("trials", 0) != 8 or not result.has("win_rate") or not result.has("average_duration"):
		push_error("CombatNumericalSimulatorTest: expected scenario statistics are missing")
		quit(1)
		return
	print("CombatNumericalSimulatorTest: PASS")
	quit(0)
