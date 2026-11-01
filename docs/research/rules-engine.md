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
- A new `class_name` is invisible to headless runs until `godot --headless --path game --import`
  has rebuilt the global class cache; before that every suite fails with "Failed to compile depended
  scripts".

## Hardening after the review (#59, #60)

- **The rules own the health.** The review found 1000 headshot hits on one zombie paying 8,200
  points because `hit` was a claim, not damage. Now `ZombieState` (health, paid hits) lives in the
  rules, `hit` carries a `zone` and `damage`, the hit that empties the health is the kill, and there
  is no `kill` action. Nothing the client sends can end a zombie any other way.
- **Cap paid hits per zombie, not just health.** Health alone still lets 0.01-damage hits pay
  thousands of times before the zombie dies, so only the first `max_paid_hits` (4) non-lethal hits
  pay. A zombie is then a bounded purse (4 hits and the kill).
- **Validate before dispatch, with one schema.** `RulesAction.REQUIRED`/`OPTIONAL` map each type to
  its fields and types and `validate` also bounds values (tick `0..1`, damage, grant). `apply` runs
  it first, so no handler ever indexes a missing key. Accept `String` for names and `int` for
  floats because JSON has neither `StringName` nor a float/int split. NaN fails a range check
  written as `is_finite(v) and v >= low and v <= high`.
- **Rejections go to the sender.** `action_rejected` carries `reason`, `action` and `field`. A hit on
  a zombie that died a frame earlier is a routine `unknown_zombie`, not a fault.

## Wire form, night end, fuel events (#61, #62, #63)

- **JSON breaks a snapshot in three ways**: integer keys become strings, a float may change in its
  last digits and a 64-bit integer (the random state) is read by many JSON parsers as a double.
  Do not repair the dictionary; carry the `var_to_bytes` bytes, base64 inside JSON
  (`Marshalls.raw_to_base64`). `bytes_to_var` (not `_with_objects`) cannot build objects, so a
  tampered save cannot instantiate scripts.
- **Fingerprint the values, not the file.** `RulesTuning.fingerprint()` walks the stored script
  variables of the resources (key-sorted dictionaries), takes `var_to_bytes` and keeps 16 hex
  characters of its SHA-256. A re-saved `.tres` with the same numbers matches; one changed price does
  not. Validate type and key set before touching state so a refused restore leaves the night intact.
- **Throttle in the rules, not the generator.** `GeneratorState` still signals every change (its tests
  and the lights read them); `GameRules` forwards `fuel_changed` only when `floor(fuel)` moves, and
  recomputes that after a restore so a copy does not repeat an announcement. Low, empty and restored
  are not throttled.
- **"Nobody is left" is a game over too.** Without it a server keeps a match nobody is in. The check
  runs on `remove_player` in a break or a round; `start` with no players is rejected.
- **A snapshot version is one number for one layout.** Two branches that each changed the layout
  both made it 4 (#161 and #166), so a restore could not tell them apart and the old one looked
  `malformed`. Check the version before the keys, bump it in the pull request that changes the layout
  and merge `main` first so a second bump is seen. A restore also checks the insides (each zombie's
  keys and types, the plan's names against the roster, the special round, players, generator) before
  it changes anything: `ZombieState.from_dict` on an entry without `type` used to raise a script error
  and leave the night half restored. The shape checks are `SnapshotCheck` and each state's
  `SNAPSHOT_KEYS`.
- **One builder per event.** `zombie_damaged` is built by `GameRules._emit_damaged` for a shot and a
  blast alike; `test_event_shapes.gd` plays every cause and compares each zombie event with the
  documented fields, so a new emitter that forgets one fails there.

## Player health (#132)

- **Health is the rules'.** A zombie's swing reaches the rules as a `blow` action (`damage`, `bearing`, `source_id`) and
  the answer is `player_hurt`, then `player_downed` at zero; mending is the rules' tick (`player_healed`, one event
  per whole unit, as the fuel does). The numbers are `HealthTuning` in the table (a second `PlayerTuning` already
  names the movement tuning, so a class of that name "hides a global script class" and the import fails with a
  misleading `Invalid access to property or key` everywhere).
- **A bearing, not a position.** The rules know no world, so the blow carries `bearing` (radians clockwise from -z)
  and the client turns it by its own facing; the HUD arc is `bearing + facing`.
- **The 1000-line file lint is real.** `game_rules.gd` crossed it with the health code; the health functions went to
  `PlayerHealth` (static, return the events they caused) and the snapshot to `RulesSnapshot`, leaving the rules room
  for the shop. The HUD state's "no Object" test forbids a helper object held in it: `HudLoadout` is static over its
  fields.
