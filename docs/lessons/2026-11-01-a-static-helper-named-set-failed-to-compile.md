# A static helper named `_set` stopped a whole suite from compiling

2026-11-01

- **Symptom:** `Parse Error: The function signature doesn't match the parent. Parent signature is
  "_set(StringName, Variant) -> bool"`, then "Failed to compile depended scripts" for the night, the HUD
  binding and every suite that loads them.
- **Cause:** `_set` is Object's virtual property setter; a helper called `_set(state, kind, label, cost,
  detail)` overrode it.
- **Fix:** rename the helper (`_put`). A name that reads naturally (`_get`, `_set`, `_init`, `_ready`,
  `_process`, `_notification`, `_to_string`) can be a virtual method, in a `RefCounted` as well.
- **Documented:** nowhere else; the Godot class reference lists the virtuals.
