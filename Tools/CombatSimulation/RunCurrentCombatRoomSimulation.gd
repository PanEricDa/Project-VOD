extends SceneTree

const SIMULATOR_SCRIPT := preload("res://Tools/CombatSimulation/CombatNumericalSimulator.gd")

func _initialize() -> void:
	var simulator := SIMULATOR_SCRIPT.new()
	for scenario: Dictionary in [
		{"name": "Pack A", "warriors": 3, "archers": 0},
		{"name": "Pack A+B", "warriors": 5, "archers": 2},
		{"name": "All Packs", "warriors": 8, "archers": 4},
	]:
		var result := simulator.run_scenario(int(scenario.warriors), int(scenario.archers), 1000, 20260804)
		print(JSON.stringify({"scenario": scenario.name, "result": result}))
	quit(0)
