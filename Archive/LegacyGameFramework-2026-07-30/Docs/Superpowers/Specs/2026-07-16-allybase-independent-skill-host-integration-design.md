# AllyBase Independent SkillHost Safe Integration Design

Date: 2026-07-16
Godot target: 4.7

## Objective

Mount the new independent `SkillHostComponent` foundation on `AllyBase.tscn` so every inherited ally has a stable new-system `SkillSocket`. Configure owner/runtime-parent injection and synchronize action blocking and shared cooldowns, while preserving all existing AllyBase AI, movement, formation, attack, legacy skill, and TestScene behavior.

This phase provides manual/open request entry points only. It does not automatically choose or cast any new-system skill.

## Scene Assembly

Add local nodes to the AllyBase source scene:

```text
AllyBase
├── HealthComponent
├── FactionComponent
├── SkillHostComponent
│   └── SkillSocket
├── VisualRoot
│   ├── AttackModuleSocket
│   └── SkillModuleSocket
└── existing nodes
```

`SkillHostComponent` is assembled as local nodes using the new Host script rather than a nested PackedScene instance. This preserves the Host contract while allowing inherited ally scenes to add profession skills beneath the inherited `SkillSocket` without enabling editable children on an external scene instance.

The old `VisualRoot/SkillModuleSocket` remains untouched and is never mixed with the new socket.

## AllyBase Fields and Resolution

Add:

```gdscript
const IndependentSkillHostType = preload(
    "res://SkillSystem/Core/SkillHostComponent.gd"
)

@export_node_path("Node")
var independent_skill_host_path: NodePath = ^"SkillHostComponent"

var independent_skill_host: IndependentSkillHostType
```

During `_ready()`, resolve the configured path and call:

```gdscript
independent_skill_host.configure_owner(self, get_tree().current_scene)
```

A missing or invalid Host path is safe: push one configuration error, leave the reference null, and preserve all existing behavior.

The Host performs its existing direct-child discovery under `SkillSocket`. An empty socket is valid.

## Public Adapter API

AllyBase exposes thin forwarding methods:

```gdscript
func get_independent_skill_host() -> Node

func request_independent_skill(
    skill_id: StringName,
    target: Node3D = null,
    target_position: Vector3 = Vector3.INF,
    request_mode: int = 0
) -> bool

func request_best_independent_skill(
    target: Node3D = null,
    target_position: Vector3 = Vector3.INF,
    request_mode: int = 1
) -> bool
```

These methods return false when the Host is missing or rejects the request. They do not search for targets, modify movement, or automatically retry.

## Action Exclusion

Each AllyBase physics frame updates the Host cast-blocked flag from existing action state:

```text
blocked = current normal attack is playing
       OR current legacy skill is casting
```

This prevents a queued new-system skill from starting during an existing action. It does not cancel that queued skill.

Existing normal-attack and legacy-skill begin paths add a reciprocal check: if the new Host currently owns a SkillBase in `CASTING`, those old actions do not begin. Decision wait and queued/range approach do not block old actions; only active casting does.

No running action is interrupted by this integration.

## Shared Cooldown Synchronization

The existing AllyBase `basic_attack_global_cooldown_remaining` remains the compatibility value in this phase.

Old-to-new synchronization occurs only at existing action start points:

- Successful normal-attack request starts the Host global cooldown with `basic_attack_global_cooldown`.
- Legacy skill `cast_started` starts the Host global cooldown with `basic_attack_global_cooldown`.

New-to-old synchronization listens to Host `global_cooldown_started(duration)` and applies:

```gdscript
basic_attack_global_cooldown_remaining = max(
    basic_attack_global_cooldown_remaining,
    duration
)
```

Synchronization never shortens either cooldown. The callback does not call Host again, preventing signal recursion.

The Host continues updating its own timer. AllyBase continues updating its legacy timer. They share start/extension events but retain independent countdown storage for compatibility.

## Explicit Non-Behavior

This phase does not:

- Call `request_best_independent_skill()` automatically.
- Select an enemy, lowest-health ally, self target, or ground position.
- Connect Host `approach_requested`, `facing_requested`, or `movement_lock_requested` to AllyBase movement.
- Give the new Host ownership of navigation, facing, formation, or combat wandering.
- Add HolyLight or another new skill to an ally profession.
- Modify Mage, Healer, Guardian, Warrior, Ranger, EnemyBase, Hero, or TestScene.
- Delete, disable, or migrate the legacy skill system.

Therefore an empty Host is behaviorally inert, and even an equipped new skill only acts after an external caller explicitly invokes one of the new request methods.

## Error Handling

- Missing Host node: initialization records one clear error; forwarding methods return false.
- Duplicate signal connection: check `is_connected()` before connecting.
- Owner reconfiguration: rely on Host's public `configure_owner()` behavior.
- Missing skill ID, target rejection, cooldown, or action blocking: preserve Host return/state semantics; AllyBase adds no special retry.
- Host removal at runtime: validate the instance on every public forwarding and synchronization path.

## Validation

Create `Tests/AllyIndependentSkillHostAssemblyTest.gd` to verify:

- AllyBase source scene contains exact `SkillHostComponent/SkillSocket` paths.
- Host script and default Inspector values match the independent Host scene contract.
- Existing direct/inherited ally scenes receive the nodes.
- `_ready()` injects AllyBase as owner and the current scene as delivery parent.
- Empty SkillSocket registers zero skills and causes no automatic request.
- Public forwarding safely rejects a missing skill.
- A test-only new SkillBase under SkillSocket is discovered and can be requested manually.
- Host global cooldown start extends the legacy AllyBase cooldown.
- Successful legacy normal attack and legacy skill-start callbacks extend Host cooldown.
- Existing action activity sets Host cast blocking.
- New-system CASTING blocks old attack/cast begin paths without cancelling them.
- Existing Ally, attack, legacy skill, and independent SkillSystem tests remain green.
- Godot 4.7 headless smoke has no new warnings or errors.
- TestScene length, timestamp, and SHA-256 remain unchanged.

## Documentation Update

Update `SkillSystem/Docs/Architecture.md` and `SkillSystem/README.md` with the new optional AllyBase adapter location and the important statement that target selection and movement integration remain deferred.

## Deferred Scope

- Automatic new-system skill scheduling.
- Friendly target search and lowest-health selection for HolyLight.
- Enemy target selection for offensive skills.
- Host approach/facing/movement-lock integration.
- Migration of existing profession skills.
- Consolidation of the two cooldown storage fields.
