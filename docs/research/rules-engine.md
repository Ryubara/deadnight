# Rules engine

What building the round, points and fuel rules (`game/gameplay/rules/`) taught us. The design is in
[Rounds, points and fuel](../design/rounds.md).

## Shape that worked

- **Rules as a `RefCounted`, not a node.** Nothing needs the scene tree, so the same object runs in
  GdUnit4 suites without a scene runner, in a server process and in single-player. A lambda connected
  to `event_emitted` is all a test needs to record a whole night.
- **Actions in, events out, both plain dictionaries.** One `match` in `apply` is the entire public
  surface for change; queries are separate and read-only. `var_to_bytes` round trips both, which
  the tests check.
- **A restore must not emit.** `from_dict` rebuilds state silently, and the generator recomputes
  its "already low" flag from the restored fuel, otherwise a restored copy re-fires `fuel_low`.
- **Separate random streams** (spawns, shop) seeded from one seed with different offsets, so a
  crane play never shifts which zombie is a sprinter. Their `state` goes in the snapshot, and a
  restored copy on a different seed still matches the original.
- **Hold a spawn "ready", do not bank it.** When the lot is full the spawn timer clamps at zero, so
  a kill lets in one zombie, not the burst that built up.

## Godot behaviour worth knowing

- `ResourceSaver.save` leaves out every value equal to the script's default, so a tuning `.tres`
  saved from defaults shows almost nothing. `default_tuning.tres` was generated once with every
  value written back (a short editor script), so the numbers live in data, not only in the script.
- `Resource.duplicate(true)` deep-copies sub-resources, including `Array[ShopItem]`: tests copy the
  table and change a number without touching other suites. Typed `Dictionary[StringName, float]`
  exports save and load fine.
- GDScript's `&` binds looser than `==`: write `(usage & FLAG) == 0`.
- `x is Node` on a value whose static type cannot be a `Node` is a parse error; use
  `is_instance_of(x, Node)` for a "this is not a node" assertion.
- GdUnit4 headless: with the `-d` flag a runtime script error stops in the debugger and the run
  hangs; without it the run ends with an exit code. CI uses `-d`, so a failing test that raises a
  script error may hang the job until its timeout.
- `gdlint` limits a function to six `return`s and a line to 100 characters, comments included, and
  `gdformat` runs only on tracked files: `git add` new scripts before `pre-commit run --all-files`.
