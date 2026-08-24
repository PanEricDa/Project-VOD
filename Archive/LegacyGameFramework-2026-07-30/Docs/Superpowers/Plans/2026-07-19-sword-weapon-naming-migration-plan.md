# Sword Weapon Naming Migration Implementation Plan

**Goal:** Rename the generic sword type and the concrete iron sword so folders, scenes, resources, tests and references use one unambiguous naming scheme.

**Architecture:** `SwordBase.tscn` remains the shared sword animation parent. `IronSword.tscn` inherits it, contains `IronSwordVisual.tscn`, and is referenced by `IronSwordDefinition.tres`.

## Constraints

- Do not modify `res://Scenes/TestScene.tscn`.
- Preserve all weapon animations, inheritance, equipment and combo behavior.
- Exclude generated `.godot` cache files from manual rewriting.

## Completed migration

- [x] Updated tests to expect the new paths and confirmed the tests failed before the assets were moved.
- [x] Moved the generic type scene to `01-WeaponTypes/Sword/SwordBase.tscn`.
- [x] Moved the concrete weapon files to `00-Weapons/IronSword/`.
- [x] Renamed scene roots to `SwordBase`, `IronSword` and `IronSwordVisual`.
- [x] Updated `IronSwordDefinition.tres` to use `iron_sword` and `Iron Sword`.
- [x] Updated `PlayerBase.tscn`, tests and project documentation.
- [x] Confirmed source filenames and contents no longer contain the old naming.

## Verification

- [x] Removed the two empty legacy directories.
- [x] Ran all UnitSystem and WeaponCombatSystem SceneTree tests.
- [x] Ran a Godot 4.7 headless editor filesystem scan.
- [x] Refreshed MCP and verified `SwordBase`, `IronSword` and `PlayerBase` load.
- [x] Confirmed `Scenes/TestScene.tscn` remains unchanged.
