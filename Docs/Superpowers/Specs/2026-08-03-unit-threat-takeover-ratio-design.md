# Unit Threat Takeover Ratio Design

## Goal

Allow tank units to regain an enemy's target at a lower threat ratio without weakening the normal 125% protection that prevents damage dealers from causing target jitter.

## Rule

- `UnitBase` owns `threat_takeover_ratio`; the default is `1.25`.
- The enemy evaluates the highest-threat challenger using that challenger's ratio: `challenger threat > current target threat × challenger ratio`.
- Guardian overrides the value to `1.05` in its source scene.
- A Guardian currently being attacked does not make other units easier to select; each other challenger still uses its own ratio.
- Exact threshold equality keeps the current target, preserving the existing strict-over behavior.

## Boundaries

- `EnemyThreatComponent` remains the sole target-selection and threat-table authority.
- This does not change threat accumulation, skill multipliers, UI, targeting radius, or TestScene instances.
- The value is intentionally unit-level rather than a hard-coded tank class so bosses or future special units can reuse the rule.
