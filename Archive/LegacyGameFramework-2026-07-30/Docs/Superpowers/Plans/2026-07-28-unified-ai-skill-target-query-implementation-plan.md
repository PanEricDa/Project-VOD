# AI Unified Skill Target Query Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the skill system's overlapping target-source and scene-wide candidate scan with one Inspector-facing relation flag set, one selection-mode enum, and candidates supplied by the existing AI perception component.

**Architecture:** `AITargetingComponent` remains the sole persistent hostile-lock and perception component. It exposes a read-only candidate snapshot; `SkillHostComponent` injects that snapshot into each automatic request; `TargetResolver` performs relation/validity filtering and selection; `SkillBase` stores only the final target in `SkillContext.resolved_target`. Explicit requests remain authoritative through an internal context flag and never have their supplied target replaced by automatic selection.

**Tech Stack:** Godot 4.7, GDScript 4.7, SceneTree headless tests, typed Godot scenes/resources.

## Global Constraints

- Preserve the existing `AITargetingComponent.selection_policy` and `DefaultNearestEnemy.tres` behavior for persistent combat locking.
- Skill Inspector targeting contains only `Target Relations`, `Target Selection Mode`, `Require Targetable`, `Require Alive`, and `Cast Range`.
- Do not create a per-skill target policy Resource.
- Use `team_id` relationship methods exposed by `UnitBase`; `faction_id` remains descriptive.
- Automatic queries use the unit's acquisition `targeting_radius`, never its one-metre retention extension.
- A temporary skill target must never overwrite or clear `AITargetingComponent.locked_target`.
- Do not change animation, Delivery, cooldown, damage, healing values, projectiles, or weapon attack range.
- Do not add or modify any unit instance in `res://Scenes/TestScene.tscn`.
- All identifiers are English; new code comments explain behavior in detailed Simplified Chinese.
- The project is not a Git repository; replace commit steps with recorded passing verification checkpoints.

---

## File Structure

### Create

- `SkillSystem/01-Core/TargetResolver.gd`
  - Owns relation flags, selection modes, candidate validation, and selection algorithms.
- `SkillSystem/05-Tests/TargetResolverTest.gd`
  - Unit-tests all relation combinations, validity filters, and selection modes.

### Modify

- `SkillSystem/01-Core/SkillContext.gd`
  - Adds an internal `explicit_target_requested` flag copied with the context.
- `SkillSystem/01-Core/SkillBase.gd`
  - Replaces `TargetSource` and single-value `TargetRelation` with relation flags and a selection mode.
- `SkillSystem/01-Core/SkillHostComponent.gd`
  - Accepts a candidate provider and stops scanning `skill_target_candidates`.
- `UnitSystem/Components/Targeting/AI/AITargetingComponent.gd`
  - Exposes the read-only perception snapshot.
- `UnitSystem/AI/Ally/AllyBase2.gd`
  - Injects the existing targeting component into the SkillHost.
- `UnitSystem/Base/00_UnitBase.gd`
  - Removes obsolete global skill-candidate group registration after migration.
- `SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn`
  - Configures hostile/current-combat-target behavior with the new fields.
- `SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn`
  - Configures friendly/nearest behavior with the new fields.
- Existing targeting, skill-core, host, and runtime tests listed in the tasks below.

---

### Task 1: Add the Pure TargetResolver

**Files:**

- Create: `SkillSystem/01-Core/TargetResolver.gd`
- Create: `SkillSystem/05-Tests/TargetResolverTest.gd`
- Modify: `UnitSystem/Base/00_UnitBase.gd`
- Modify: `UnitSystem/Tests/UnitRootConfigurationTest.gd`

**Interfaces:**

- Consumes: `Node3D` capability methods `is_targetable()`, `is_dead()`, `is_friendly_to(Node)`, `is_hostile_to(Node)`, `is_neutral_to(Node)`, and `get_health_ratio()`.
- Produces:

```gdscript
class_name TargetResolver
extends RefCounted

enum TargetRelationFlag {
    SELF = 1,
    FRIENDLY = 2,
    HOSTILE = 4,
    NEUTRAL = 8,
}

enum TargetSelectionMode {
    CURRENT_COMBAT_TARGET,
    NEAREST,
    RANDOM,
    LOWEST_HEALTH_RATIO,
}

static func resolve_target(
    owner: Node3D,
    candidates: Array[Node3D],
    current_combat_target: Node3D,
    relation_flags: int,
    selection_mode: TargetSelectionMode,
    require_targetable: bool,
    require_alive: bool,
    random: RandomNumberGenerator = null
) -> Node3D

static func is_candidate_valid(
    owner: Node3D,
    candidate_value: Variant,
    relation_flags: int,
    require_targetable: bool,
    require_alive: bool
) -> bool
```

- [ ] **Step 1: Write the failing resolver tests**

Create a lightweight `TestUnit extends Node3D` fixture with team, health, alive, and targetable capabilities. Cover:

```gdscript
_expect(
    TargetResolver.is_candidate_valid(
        owner,
        owner,
        TargetResolver.TargetRelationFlag.SELF,
        true,
        true
    ),
    "SELF accepts the owner"
)
_expect(
    not TargetResolver.is_candidate_valid(
        owner,
        friendly,
        TargetResolver.TargetRelationFlag.SELF,
        true,
        true
    ),
    "SELF rejects another friendly"
)
_expect(
    TargetResolver.is_candidate_valid(
        owner,
        friendly,
        TargetResolver.TargetRelationFlag.FRIENDLY,
        true,
        true
    ),
    "FRIENDLY accepts a same-team non-owner"
)
_expect(
    TargetResolver.is_candidate_valid(
        owner,
        owner,
        (
            TargetResolver.TargetRelationFlag.SELF
            | TargetResolver.TargetRelationFlag.FRIENDLY
        ),
        true,
        true
    ),
    "relation flags support combinations"
)
```

Also assert:

- Hostile and neutral matching.
- Invalid/freed/non-`Node3D` values return false without type errors.
- `require_targetable` rejects an untargetable target only when enabled.
- `require_alive` rejects a dead target only when enabled.
- `CURRENT_COMBAT_TARGET` returns the valid supplied current target and does not fall back silently when it is invalid.
- `NEAREST` uses horizontal X/Z distance.
- `RANDOM` returns one member of the filtered set using a seeded `RandomNumberGenerator`.
- `LOWEST_HEALTH_RATIO` selects the lowest ratio and rejects candidates missing `get_health_ratio()`.
- Empty or invalid candidates return `null`.

- [ ] **Step 2: Add failing UnitBase capability-boundary assertions**

Extend `UnitRootConfigurationTest.gd` so a valid non-`UnitBase` `Node3D` and an invalid/freed value can be passed to all three relationship methods without a typed-call error:

```gdscript
var unrelated_node := Node3D.new()
root.add_child(unrelated_node)
_expect(
    not unit.is_friendly_to(unrelated_node),
    "friendly relation safely rejects a non-UnitBase node"
)
_expect(
    not unit.is_hostile_to(unrelated_node),
    "hostile relation safely rejects a non-UnitBase node"
)
_expect(
    not unit.is_neutral_to(unrelated_node),
    "neutral relation safely rejects a non-UnitBase node"
)
```

- [ ] **Step 3: Run the resolver and UnitBase tests to verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/TargetResolverTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/UnitRootConfigurationTest.gd'
```

Expected: resolver test fails because `TargetResolver` does not exist; the UnitBase test exposes the typed relationship-parameter boundary.

- [ ] **Step 4: Make UnitBase relationship capabilities safe for generic callers**

Change the three relationship method parameters from `UnitBase` to `Variant`, validate first, then cast:

```gdscript
func is_friendly_to(other_value: Variant) -> bool:
    if not is_instance_valid(other_value) or not other_value is UnitBase:
        return false
    var other := other_value as UnitBase
    return (
        team_id != 0
        and other.team_id != 0
        and team_id == other.team_id
    )
```

Apply the same boundary to `is_hostile_to()` and `is_neutral_to()`. A valid non-`UnitBase` node is not silently considered neutral; all three methods return `false`. Existing team semantics for two valid units remain unchanged.

- [ ] **Step 5: Implement the minimal resolver**

Implement relation matching with bitwise checks. Normalize candidates once, remove duplicate instance IDs, and never retain candidate state between calls.

Core dispatch:

```gdscript
static func resolve_target(
    owner: Node3D,
    candidates: Array[Node3D],
    current_combat_target: Node3D,
    relation_flags: int,
    selection_mode: TargetSelectionMode,
    require_targetable: bool,
    require_alive: bool,
    random: RandomNumberGenerator = null
) -> Node3D:
    if not is_instance_valid(owner):
        return null
    if selection_mode == TargetSelectionMode.CURRENT_COMBAT_TARGET:
        return (
            current_combat_target
            if is_candidate_valid(
                owner,
                current_combat_target,
                relation_flags,
                require_targetable,
                require_alive
            )
            else null
        )
    var valid_candidates := _collect_valid_candidates(
        owner,
        candidates,
        relation_flags,
        require_targetable,
        require_alive
    )
    match selection_mode:
        TargetSelectionMode.NEAREST:
            return _select_nearest(owner, valid_candidates)
        TargetSelectionMode.RANDOM:
            return _select_random(valid_candidates, random)
        TargetSelectionMode.LOWEST_HEALTH_RATIO:
            return _select_lowest_health_ratio(valid_candidates)
    return null
```

`is_candidate_valid()` must accept `Variant` so freed targets are rejected before typed conversion. It must verify the required capability exists before calling it; calls into `UnitBase` are now safe because its relation methods also validate the generic argument.

- [ ] **Step 6: Run the resolver and UnitBase tests to verify GREEN**

Run both Task 1 commands again.

Expected: both tests print `PASS`, exit code `0`.

- [ ] **Step 7: Record checkpoint**

Record that the isolated resolver contract passes before integrating it into existing skill code.

---

### Task 2: Expose Read-Only Perception Candidates

**Files:**

- Modify: `UnitSystem/Components/Targeting/AI/AITargetingComponent.gd`
- Modify: `UnitSystem/Tests/AITargetingComponentTest.gd`

**Interfaces:**

- Consumes: existing `_owner_unit`, `_targeting_radius`, `get_overlapping_bodies()`.
- Produces:

```gdscript
func get_perceived_candidates(
    maximum_distance: float = -1.0
) -> Array[Node3D]
```

- [ ] **Step 1: Add failing candidate-provider assertions**

Extend `AITargetingComponentTest.gd` with fixtures that prove:

```gdscript
var perceived := component.get_perceived_candidates()
_expect(first_enemy in perceived, "provider returns an overlapping unit in acquisition range")
_expect(
    retention_only_enemy not in perceived,
    "provider excludes units that are only inside retention range"
)
_expect(
    component.get_locked_target() == locked_before_query,
    "candidate query does not mutate persistent lock"
)
```

Also verify:

- A custom smaller `maximum_distance` filters the same Area snapshot.
- The owner is excluded.
- Duplicate bodies are not returned twice.
- Suspended or disabled detection returns an empty array.
- Friendly units are returned unclassified; relation filtering is not performed here.

- [ ] **Step 2: Run the targeting test to verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/AITargetingComponentTest.gd'
```

Expected: FAIL because `get_perceived_candidates()` is missing.

- [ ] **Step 3: Implement the provider without changing lock selection**

Add:

```gdscript
func get_perceived_candidates(
    maximum_distance: float = -1.0
) -> Array[Node3D]:
    var candidates: Array[Node3D] = []
    if (
        not _configured
        or not detection_enabled
        or is_detection_suspended()
        or not is_instance_valid(_owner_unit)
    ):
        return candidates
    var query_radius: float = (
        _targeting_radius
        if maximum_distance < 0.0
        else minf(maximum_distance, _targeting_radius)
    )
    var seen_ids: Dictionary = {}
    for body: Node3D in get_overlapping_bodies():
        if (
            not is_instance_valid(body)
            or body == _owner_unit
            or not body.is_inside_tree()
            or seen_ids.has(body.get_instance_id())
        ):
            continue
        var offset: Vector3 = body.global_position - _owner_unit.global_position
        offset.y = 0.0
        if offset.length() > query_radius:
            continue
        seen_ids[body.get_instance_id()] = true
        candidates.append(body)
    return candidates
```

Do not route `refresh_target()` through this new method in the same task. Persistent lock selection continues using its existing typed `Array[UnitBase]` and `TargetSelectionPolicy`.

- [ ] **Step 4: Run targeting regressions**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/AITargetingComponentTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/TargetSelectionPolicyTest.gd'
```

Expected: both tests print `PASS`; existing enemy lock stability remains unchanged.

- [ ] **Step 5: Record checkpoint**

Record that the new provider is read-only and does not alter the existing targeting Policy contract.

---

### Task 3: Migrate SkillBase to the Simplified Target Configuration

**Files:**

- Modify: `SkillSystem/01-Core/SkillContext.gd`
- Modify: `SkillSystem/01-Core/SkillBase.gd`
- Modify: `SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd`

**Interfaces:**

- Consumes:

```gdscript
TargetResolver.resolve_target(...)
TargetResolver.is_candidate_valid(...)
```

- Produces:

```gdscript
# SkillContext
var explicit_target_requested: bool = false

# SkillBase exported configuration
@export_flags("Self", "Friendly", "Hostile", "Neutral")
var target_relations: int = TargetResolver.TargetRelationFlag.HOSTILE

@export var target_selection_mode: TargetResolver.TargetSelectionMode = \
    TargetResolver.TargetSelectionMode.CURRENT_COMBAT_TARGET

@export var require_targetable: bool = true
@export var require_alive: bool = true
```

- [ ] **Step 1: Update SkillBase tests to the new contract and verify RED**

Replace the old property expectations:

```gdscript
for property_name: StringName in [
    &"target_relations",
    &"target_selection_mode",
    &"cast_range",
    &"require_targetable",
    &"require_alive",
    &"validate_target_on_release",
]:
    _expect(_has_property(skill, property_name), "SkillBase exposes " + property_name)
```

Add cases proving:

- Explicit request with `explicit_target_requested = true` uses `requested_target` even when selection mode is `NEAREST`.
- Explicit request still rejects the wrong relation, dead, and untargetable targets.
- Automatic `NEAREST` selects from `candidate_targets`.
- Automatic `SELF | FRIENDLY + LOWEST_HEALTH_RATIO` can select the owner when it has the lowest health ratio.
- Automatic `CURRENT_COMBAT_TARGET` validates `requested_target` and does not fall back to another candidate.
- `duplicate_context()` copies `explicit_target_requested`.
- Freed targets still fail safely without typed-argument errors.

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd'
```

Expected: FAIL because the new fields and resolution semantics are not implemented.

- [ ] **Step 2: Add the explicit-request context flag**

In `SkillContext.gd` add:

```gdscript
var explicit_target_requested: bool = false
```

In `duplicate_context()` add:

```gdscript
copy.explicit_target_requested = explicit_target_requested
```

- [ ] **Step 3: Replace SkillBase's overlapping target configuration**

Delete:

```gdscript
enum TargetSource
enum TargetRelation
@export var target_source
@export var target_relation
```

Add the exported fields from this task's interface block. Keep `cast_range`, `validate_target_on_release`, animation, Delivery, cooldown, and AI timing fields unchanged.

- [ ] **Step 4: Route resolution and validity through TargetResolver**

Replace `_resolve_target()` with:

```gdscript
func _resolve_target(context: SkillContext) -> Node3D:
    if context.explicit_target_requested:
        return (
            context.requested_target
            if TargetResolver.is_candidate_valid(
                _skill_owner,
                context.requested_target,
                target_relations,
                require_targetable,
                require_alive
            )
            else null
        )
    var candidates: Array[Node3D] = context.candidate_targets.duplicate()
    if (
        target_relations & TargetResolver.TargetRelationFlag.SELF
        and _skill_owner not in candidates
    ):
        candidates.append(_skill_owner)
    return TargetResolver.resolve_target(
        _skill_owner,
        candidates,
        context.requested_target,
        target_relations,
        target_selection_mode,
        require_targetable,
        require_alive
    )
```

Replace the relation/targetable body of `_is_candidate_valid()` with `TargetResolver.is_candidate_valid(...)`, retaining the optional cast-range check in `SkillBase`.

- [ ] **Step 5: Run SkillBase and resolver tests**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/TargetResolverTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd'
```

Expected: both tests print `PASS`.

- [ ] **Step 6: Record checkpoint**

Record that one skill scene now owns one non-overlapping targeting configuration and explicit requests remain deterministic.

---

### Task 4: Replace SkillHost's Scene-Wide Scan with an Injected Provider

**Files:**

- Modify: `SkillSystem/01-Core/SkillHostComponent.gd`
- Modify: `SkillSystem/05-Tests/SingleSceneSkillHostTest.gd`

**Interfaces:**

- Consumes:

```gdscript
provider.get_perceived_candidates(maximum_distance: float = -1.0) -> Array[Node3D]
```

- Produces:

```gdscript
func set_target_candidate_provider(provider: Node) -> void
func get_target_candidate_provider() -> Node
```

- [ ] **Step 1: Write a failing provider-driven Host test**

Add a fixture:

```gdscript
class CandidateProvider:
    extends Node

    var candidates: Array[Node3D] = []
    var query_count: int = 0

    func get_perceived_candidates(
        _maximum_distance: float = -1.0
    ) -> Array[Node3D]:
        query_count += 1
        return candidates.duplicate()
```

Remove test group registration and inject this provider. Assert:

```gdscript
host.call("set_target_candidate_provider", provider)
_expect(
    bool(host.call("request_best_skill", enemy)),
    "automatic request uses injected perception candidates"
)
_expect(provider.query_count == 1, "one automatic decision reads one snapshot")
```

Also verify:

- A node elsewhere in `skill_target_candidates` is ignored.
- Explicit `request_skill()` works without a provider.
- Automatic request without a provider returns false without warnings/errors.
- The context generated by `request_skill()` has `explicit_target_requested == true`.
- The context generated by `request_best_skill()` has `explicit_target_requested == false`.

- [ ] **Step 2: Run Host test to verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/SingleSceneSkillHostTest.gd'
```

Expected: FAIL because provider injection is missing and Host still scans the group.

- [ ] **Step 3: Add the provider and remove the global scan**

Delete `SKILL_TARGET_CANDIDATE_GROUP` and `_collect_candidate_targets()`.

Add:

```gdscript
var _target_candidate_provider: Node

func set_target_candidate_provider(provider: Node) -> void:
    _target_candidate_provider = provider

func get_target_candidate_provider() -> Node:
    return (
        _target_candidate_provider
        if is_instance_valid(_target_candidate_provider)
        else null
    )

func _get_candidate_snapshot() -> Array[Node3D]:
    if (
        not is_instance_valid(_target_candidate_provider)
        or not _target_candidate_provider.has_method(
            &"get_perceived_candidates"
        )
    ):
        return []
    var value: Variant = _target_candidate_provider.call(
        &"get_perceived_candidates",
        -1.0
    )
    var candidates: Array[Node3D] = []
    if not value is Array:
        return candidates
    for candidate_value: Variant in value:
        if (
            is_instance_valid(candidate_value)
            and candidate_value is Node3D
        ):
            candidates.append(candidate_value as Node3D)
    return candidates
```

`request_best_skill(current_combat_target)` reads `_get_candidate_snapshot()` once, then reuses it for all registered skills in that decision.

- [ ] **Step 4: Mark explicit and automatic contexts**

Extend `_create_context()`:

```gdscript
func _create_context(
    target: Node3D,
    candidate_targets: Array[Node3D],
    target_position: Vector3,
    source: int,
    explicit_target_requested: bool
) -> SkillContext:
    var context := SkillContext.new()
    # Existing assignments remain unchanged.
    context.explicit_target_requested = explicit_target_requested
    return context
```

Call it with `true` from `request_skill()` and `false` from `request_best_skill()`.

- [ ] **Step 5: Run Host and core regressions**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/SingleSceneSkillHostTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/SingleSceneCoreContractsTest.gd'
```

Expected: both tests print `PASS`.

- [ ] **Step 6: Record checkpoint**

Record that automatic selection no longer uses a hidden global group and explicit requests remain provider-independent.

---

### Task 5: Inject AI Perception and Remove Obsolete Unit Registration

**Files:**

- Modify: `UnitSystem/AI/Ally/AllyBase2.gd`
- Modify: `UnitSystem/Base/00_UnitBase.gd`
- Modify: `UnitSystem/Tests/AllyTargetingIntegrationTest.gd`
- Modify: `UnitSystem/Tests/UnitBaseSkillHostAssemblyTest.gd`

**Interfaces:**

- Consumes:

```gdscript
SkillHostComponent.set_target_candidate_provider(provider: Node)
```

- Produces: Ally scene assembly automatically wires its targeting component into its SkillHost with no exported NodePath.

- [ ] **Step 1: Add failing assembly assertions**

In `AllyTargetingIntegrationTest.gd` or `UnitBaseSkillHostAssemblyTest.gd`, instantiate an `AllyBase2`-derived scene with `SkillHost` and assert:

```gdscript
_expect(
    host.get_target_candidate_provider() == ally.get_targeting_component(),
    "AllyBase2 injects its existing perception component into SkillHost"
)
```

Add an isolated `UnitBase` assertion:

```gdscript
_expect(
    not unit.is_in_group(&"skill_target_candidates"),
    "UnitBase no longer registers the obsolete global skill candidate group"
)
```

- [ ] **Step 2: Run the assembly tests to verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/AllyTargetingIntegrationTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/UnitBaseSkillHostAssemblyTest.gd'
```

Expected: at least the provider/group assertions fail.

- [ ] **Step 3: Inject the provider during AllyBase2 assembly**

After targeting configuration succeeds and before behavior-state-machine configuration, add:

```gdscript
if is_instance_valid(_skill_host):
    _skill_host.set_target_candidate_provider(_targeting_component)
```

Do not export a NodePath and do not make `AllyBehaviorStateMachine` discover or own the provider.

- [ ] **Step 4: Remove obsolete UnitBase group registration**

Delete:

```gdscript
const SKILL_TARGET_CANDIDATE_GROUP
func _enter_tree() -> void:
    add_to_group(SKILL_TARGET_CANDIDATE_GROUP)
```

Keep all health, team, faction, and targetable methods unchanged.

- [ ] **Step 5: Run assembly and targeting regressions**

Run the two Task 5 tests plus:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/AITargetingComponentTest.gd'
```

Expected: all tests print `PASS`.

- [ ] **Step 6: Record checkpoint**

Record that candidate-provider wiring is automatic for allies and no hidden unit group remains.

---

### Task 6: Migrate Firebolt and HolyLight Scene Configuration

**Files:**

- Modify: `SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn`
- Modify: `SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn`
- Modify: `SkillSystem/05-Tests/SingleSceneFireboltTest.gd`
- Modify: `SkillSystem/05-Tests/SingleSceneHolyLightTest.gd`
- Modify: `UnitSystem/Tests/PriestHolyLightAutomaticRuntimeTest.gd`

**Interfaces:**

- Consumes: new `SkillBase.target_relations` and `SkillBase.target_selection_mode`.
- Produces:

```text
Firebolt:
  target_relations = HOSTILE (4)
  target_selection_mode = CURRENT_COMBAT_TARGET (0)

HolyLight:
  target_relations = FRIENDLY (2)
  target_selection_mode = NEAREST (1)
```

- [ ] **Step 1: Update scene-contract tests first**

Replace old `target_source`/`target_relation` expectations:

```gdscript
_expect(
    skill.target_relations == TargetResolver.TargetRelationFlag.HOSTILE,
    "Firebolt targets hostiles"
)
_expect(
    skill.target_selection_mode
        == TargetResolver.TargetSelectionMode.CURRENT_COMBAT_TARGET,
    "Firebolt uses the persistent combat target"
)
```

For HolyLight:

```gdscript
_expect(
    skill.target_relations == TargetResolver.TargetRelationFlag.FRIENDLY,
    "HolyLight targets other friendly units"
)
_expect(
    skill.target_selection_mode == TargetResolver.TargetSelectionMode.NEAREST,
    "HolyLight selects the nearest eligible friendly"
)
```

Update the runtime-test comment from `AUTO_NEAREST + FRIENDLY` to `FRIENDLY + NEAREST`.

- [ ] **Step 2: Run scene tests to verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/SingleSceneFireboltTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/SingleSceneHolyLightTest.gd'
```

Expected: FAIL until the scene properties are migrated.

- [ ] **Step 3: Update the two skill scenes**

In `FireboltSkill.tscn`, remove the old `target_relation = 3` line and save:

```text
target_relations = 4
target_selection_mode = 0
```

In `HolyLightSkill.tscn`, remove `target_source = 2` and `target_relation = 2`, then save:

```text
target_relations = 2
target_selection_mode = 1
```

Because these are scene properties rather than new external Resources, no ResourceSaver/UID creation step is required.

- [ ] **Step 4: Run scene and automatic-runtime tests**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/SingleSceneFireboltTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://SkillSystem/05-Tests/SingleSceneHolyLightTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/PriestHolyLightAutomaticRuntimeTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/CasterFireboltRuntimeTest.gd'
```

Expected: all four tests print `PASS`; HolyLight targets a nearby friendly without changing hostile lock, and Firebolt still uses the locked enemy.

- [ ] **Step 5: Record checkpoint**

Record that existing skills are migrated with no extra skill Resource or per-skill script.

---

### Task 7: Full Lifecycle, Failure, and Editor Verification

**Files:**

- Modify only if a regression test exposes a defect:
  - `UnitSystem/Tests/RepeatedSkillCastingLifecycleTest.gd`
  - `UnitSystem/Tests/SkillApproachRecoveryTest.gd`
  - `UnitSystem/Tests/AllySkillCombatPolicyTest.gd`
- Update: `Docs/Superpowers/Specs/2026-07-28-unified-ai-target-query-design.md`
  - Append final verified paths and test results; do not change approved behavior.

**Interfaces:**

- Consumes all previous task interfaces.
- Produces a verified migration with no stale serialized property names or hidden candidate-group dependency.

- [ ] **Step 1: Search for stale configuration and group references**

Run:

```powershell
rg -n `
  "target_source|target_relation\b|AUTO_NEAREST|SKILL_TARGET_CANDIDATE_GROUP|skill_target_candidates" `
  'G:\Godot\SipSip\SkillSystem'
```

Expected: no SkillSystem runtime, scene, test, or comment references remain. Then search `UnitSystem` separately: only the persistent `AITargetingComponent` Policy's singular `target_relation` and its own tests/resources may remain; `SKILL_TARGET_CANDIDATE_GROUP`, `skill_target_candidates`, `target_source`, and `AUTO_NEAREST` must be absent everywhere.

- [ ] **Step 2: Run lifecycle and failure regressions**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/RepeatedSkillCastingLifecycleTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/SkillApproachRecoveryTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/AllySkillCombatPolicyTest.gd'
```

Expected:

- Caster and Priest complete 20 repeated casts.
- Invalid/freed targets release `active_skill`.
- `approach_stalled` still returns to normal decision flow.
- Skill-only units do not fall back to unwanted melee while skills are enabled.

- [ ] **Step 3: Run all directly affected tests**

Run every test touched or introduced in Tasks 1–6. Each must print `PASS` and exit `0`.

- [ ] **Step 4: Run a complete Godot 4.7 editor scan**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --editor --path 'G:\Godot\SipSip' --quit
```

Expected: exit code `0`, no parser error, invalid serialized property warning, or missing script/resource error.

- [ ] **Step 5: Validate with Godot MCP Pro**

After the headless scan, refresh the connected Godot editor and inspect:

- Script validation for `TargetResolver.gd`, `SkillBase.gd`, `SkillHostComponent.gd`, `AITargetingComponent.gd`, and `AllyBase2.gd`.
- Output and debugger panels contain no new errors or warnings.
- Firebolt and HolyLight Inspector show only the approved target fields.

Do not treat MCP dynamic class-cache false positives as project failures when the Godot 4.7 full editor scan and runtime tests are clean; record both pieces of evidence.

- [ ] **Step 6: Update the design record with verification evidence**

Append a short `Implementation Verification` section containing:

- Created/modified paths.
- Exact passing test names.
- Godot editor scan exit code.
- Confirmation that no `TestScene.tscn` unit instance was modified.

- [ ] **Step 7: Final checkpoint**

Report the completed migration, the Inspector configuration for Firebolt and HolyLight, and any intentionally retained legacy component (`AITargetingComponent.selection_policy`) so the user can distinguish persistent combat locking from per-skill target selection.
