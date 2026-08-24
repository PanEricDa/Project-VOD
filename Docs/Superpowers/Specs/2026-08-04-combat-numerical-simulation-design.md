# Combat Numerical Simulation Design

The simulator is an offline balance tool. It models the current TestCombatRoom party with an ideal, invulnerable Hero and evaluates Pack A, Pack A+B, and Pack A+B+C for 1,000 seeded trials each. It uses current baseline HP, ATK, DEF, attack cadence, damage variance, Guardian threat multipliers, Firebolt, and Holy Light. Navigation, hitbox misses, projectile travel, player input, and spatial avoidance are intentionally excluded.

It produces win rate, mean completion time, ally death rate, OT count, and total healing. It neither instantiates nor edits TestCombatRoom.
