# Human-Centered Weapon Combat Layout Design

## 1. Goal

Reorganize `WeaponCombatSystem` around a human-readable authoring workflow while
preserving the existing runtime behavior.

The result must support two audiences:

- Designers can configure existing races and weapon types without reading runtime
  scripts or relying on AI to locate files.
- Developers can understand the complete resource structure, ownership and data
  flow directly from the filesystem.

The redesign does not change the validated combat model:

```text
UnitProfile.race
        +
WeaponDefinition.weapon_type
        ↓
WeaponAnimationDatabase
        ↓
AnimationLibrary
        ↓
CharacterAnimationController
```

## 2. Responsibility Boundary

Developers own enum registration:

- Add new values to `UnitProfile.Race`.
- Add new values to `WeaponDefinition.WeaponType`.
- Maintain runtime scripts, validation and typed resource contracts.

Designers own configuration for registered values:

- Create weapon definitions, visuals and scenes.
- Create animation libraries and animation workbenches.
- Add valid `Race + WeaponType` entries to the animation database.
- Configure weapons to use an existing `WeaponType`.

If a designer needs a race or weapon type that is not registered, the designer
submits it to a developer instead of entering a free-form string.

## 3. Filesystem Architecture

Use a numbered workflow and a single authoring entry point:

```text
WeaponCombatSystem/
├── 00-StartHere/
│   ├── README.md
│   └── WeaponCombatSetup.tres
│
├── 01-WeaponDefinitions/
│   └── IronSwordDefinition.tres
│
├── 02-WeaponScenes/
│   └── IronSword/
│       ├── IronSword.tscn
│       └── IronSwordVisual.tscn
│
├── 03-AnimationLibraries/
│   └── PlayerBase/
│       └── PlayerBaseSwordAnimationLibrary.tres
│
├── 04-AnimationWorkbenches/
│   └── PlayerBase/
│       └── PlayerBaseSwordWorkbench.tscn
│
├── 05-Registry/
│   └── WeaponAnimationDatabase.tres
│
├── 06-Runtime/
│   ├── Core/
│   └── Components/
│
└── 07-Tests/
```

`UnitProfile` and concrete unit profiles remain in `UnitSystem`, because they are
unit data rather than weapon-combat assets. Weapon animation libraries move into
`WeaponCombatSystem` so combat authoring assets no longer live under unit data.

## 4. Single Authoring Entry

`WeaponCombatSetup.tres` is an authoring index. It does not participate in runtime
combat and is not a second source of configuration.

It exposes four strongly typed references:

```text
Weapon Combat Setup
├── Animation Database
├── Default Unit Profile
├── Example Weapon Definition
└── Animation Workbench Scene
```

The references point to the real resources. Designers can click each reference in
the Inspector to navigate without memorizing paths. Removing the Setup resource
must not break runtime combat.

## 5. Designer Workflows

### 5.1 Add Another Weapon of an Existing Type

Example: add `SteelSword` using the current sword animations.

1. Duplicate the IronSword definition in `01-WeaponDefinitions`.
2. Create its visual and weapon scene in `02-WeaponScenes/SteelSword`.
3. Set `Weapon Type = SWORD`.
4. Do not create another animation library.
5. Do not add another database entry.

The database describes how a unit category uses a weapon category, not how each
individual weapon looks.

### 5.2 Add a New Weapon Type

Example: add `BOW`.

1. The designer requests `WeaponType.BOW`.
2. A developer registers the enum and updates its validation coverage.
3. The designer creates `PlayerBaseBowAnimationLibrary.tres`.
4. The designer creates `PlayerBaseBowWorkbench.tscn`.
5. The designer adds one database entry:

```text
PLAYER_BASE + BOW → PlayerBaseBowAnimationLibrary
```

### 5.3 Add a New Race

Example: add `ORC`.

1. The designer requests `Race.ORC`.
2. A developer registers the enum and creates `OrcProfile.tres`.
3. The designer creates animation libraries and workbenches only for weapon types
   the Orc actually supports.
4. The designer adds one database entry for every supported combination.

## 6. Naming Rules

Combination resources use:

```text
<UnitType><WeaponType><ResourcePurpose>
```

Examples:

```text
PlayerBaseSwordAnimationLibrary.tres
PlayerBaseSwordWorkbench.tscn
OrcBowAnimationLibrary.tres
OrcBowWorkbench.tscn
```

Concrete weapons use their concrete item name:

```text
IronSwordDefinition.tres
IronSword.tscn
IronSwordVisual.tscn
```

The names remain understandable in Godot search results without relying on their
parent folder.

## 7. Runtime and Validation Rules

- All authoring references use typed Resource fields.
- Every `Race + WeaponType` combination may appear at most once.
- A missing mapping returns `null`.
- A duplicate mapping returns `null` instead of selecting an arbitrary row.
- Invalid animation mappings must not remove a currently valid equipped weapon.
- Animation lookup occurs only during equipment or equipment replacement, never
  during `_process()` or `_physics_process()`.
- IronSword remains visual and skill-socket content only.
- Character animation continues to drive the real `BodyRoot` and `WeaponSocket`.
- Existing three-hit combo, input buffer, combo-reset timeout, hold-to-chain and
  held-combo restart delay remain unchanged.

## 8. Migration Map

| Current content | Destination |
|---|---|
| IronSword definition | `01-WeaponDefinitions/` |
| IronSword scene and visual | `02-WeaponScenes/IronSword/` |
| PlayerBase sword animation library | `03-AnimationLibraries/PlayerBase/` |
| Sword animation workbench | `04-AnimationWorkbenches/PlayerBase/` |
| Weapon animation database | `05-Registry/` |
| Core and component scripts | `06-Runtime/Core` and `06-Runtime/Components` |
| Weapon combat tests | `07-Tests/` |

All scene, resource, test and documentation references must be updated as part of
the same migration. No compatibility duplicate is retained at an old path.

## 9. System Guide

Create:

```text
res://WeaponCombatSystem/00-StartHere/README.md
```

The guide must contain:

- A directory map and the responsibility of every numbered folder.
- The designer configuration workflow.
- The developer responsibility boundary.
- Steps for adding a weapon, weapon type and race.
- Naming rules.
- Common configuration errors and their diagnostic order.
- How to navigate from `WeaponCombatSetup.tres`.
- A short runtime data-flow diagram.

The guide is the canonical human-facing entry point for this subsystem.

## 10. Safety Constraints

- Do not add, remove or modify unit instances in `Scenes/TestScene.tscn`.
- Preserve the current IronSword material and visual construction.
- Do not change attack timings or player input behavior during the layout
  migration.
- Perform path migration atomically so the project is not handed off with mixed
  old and new paths.
- The project is not a Git repository; verification evidence replaces commit
  history for this migration.

## 11. Verification

- Every old WeaponCombatSystem path is absent after migration.
- Every new resource path loads successfully.
- `WeaponCombatSetup.tres` resolves every authoring entry.
- IronSword equips and plays all three attacks.
- Input buffering, combo reset, hold chaining and restart delay remain valid.
- Exact, missing and duplicate database mappings are tested.
- The animation workbench loads the external library against the real PlayerBase
  hierarchy.
- Godot 4.7 completes a full headless editor import with no errors or warnings.
- All UnitSystem and WeaponCombatSystem tests pass.
- `Scenes/TestScene.tscn` retains its pre-migration hash and timestamp.

