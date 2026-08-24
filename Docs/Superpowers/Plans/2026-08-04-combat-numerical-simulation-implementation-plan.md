# Combat Numerical Simulation Implementation Plan

**Goal:** Provide a repeatable offline balance simulation for the current room snapshots.

1. Add a failing headless contract test for a simulator API returning scenario statistics.
2. Implement a standalone GDScript simulator under `Tools/CombatSimulation` with seeded Monte Carlo trials.
3. Run it for the three current Pack combinations and save its report under `Docs/SimulationReports`.
4. Verify the simulator test and a Godot editor scan.
