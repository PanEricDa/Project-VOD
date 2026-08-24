# Threat Debug Percentage Display Design

## Goal

Extend the existing debug-only threat label with a readable relative percentage. This helps inspect the 100% to 125% threat-risk window without changing threat calculation, target selection, or gameplay state.

## Display Rule

- The current locked target is the reference and displays `100%` whenever it has positive local threat.
- Every displayed source shows `source threat / locked-target threat`, rounded to an integer percentage. Values above `125%` therefore identify a target-switch challenger directly.
- If the locked target has no positive cached threat, the highest positive local threat is used as a safe `100%` fallback.
- The locked-target summary and the sorted source rows use the same format, for example `Hero 17.0 (100%)` and `Guardian 13.0 (76%)`.
- A debug-only Inspector switch, `show_threat_percentage`, defaults to enabled. When disabled, the existing raw-value display remains and no percentage text is shown.

## Boundaries

- `ThreatDebugDisplay` remains a read-only observer of existing threat and target signals.
- No core threat component, targeting component, health-bar UI, resource, scene instance, or TestScene unit is changed.
- The percentage is relative to the currently locked target, not total threat and not a gameplay balance value.

## Verification

`ThreatDebugDisplayTest` must cover the 100% reference, a lower relative percentage, and disabling the display switch.
