# A new item in the simulator's shopping list changed nothing, then too much

2026-11-01

- **Symptom:** the first runs with the re-cut in the modelled players' list: the average solo median fell from 10 to
  8, the stampede killed 83% of nights, and a strong player re-cut four weapons a night.
- **Cause:** the list is read again at every break, so a repeatable item was bought again and again and the player
  was always saving for the next one; cheap items later in the list were bought first, so nobody had the points; and
  with the re-cut before the crane the player never had the crowd weapon the stampede needs.
- **Fix:** `SimSkill.re_cuts` (how many a night), `saves_for` (nothing after a saved-for item is bought until it is),
  the crane before the re-cut, and a control run in which the item does nothing (the gate must fail).
- **Documented:** [Weapon upgrades](../research/weapon-upgrade.md#traps-the-model-fell-into-and-the-policy-that-fixed-them).
