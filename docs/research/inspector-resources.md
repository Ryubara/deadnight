# Resources you edit in the inspector

What moving constants into resources (#415) taught us about Godot 4.7.2. The guide for the person tuning is
[Tuning in the editor](../design/tuning.md).

## Writing the files

- **Generate the `.tres` from the script's own defaults, every value explicit.** A throwaway `SceneTree` script walks
  `get_property_list()` (usage `SCRIPT_VARIABLE` and `STORAGE`) and writes `name = var_to_str(value)`. `ResourceSaver`
  would leave out the defaults. The editor does the same when someone saves a file later (a value equal to the script's
  default disappears from the file), which is fine: the script default is then the fallback and the inspector shows no
  revert arrow.
- **A family of sub-resources in one file** (`SoundBank`): write the `.tres` as text. The typed array of a script class
  is `sounds = Array[ExtResource("2_def")]([SubResource("a"), SubResource("b")])`, each `[sub_resource
  type="Resource" id="a"]` carrying `script = ExtResource("2_def")` and its values. It loads and opens in the
  inspector as a list of expandable items.
- **A typed dictionary export** (`Dictionary[StringName, int]`) is written
  `Dictionary[StringName, int]({&"gun": 12, ...})`, and the inspector edits it.
- **`inf` is a valid value** in a `.tres` (`near_cap_db = inf`), for "no cap".

## Annotations

- `@export_enum` refuses a `StringName` variable. `@export_custom(PROPERTY_HINT_ENUM, "Music,Effects,UI")` gives the
  same dropdown on a `StringName`.
- A unit goes in `@export_range(min, max, step, "suffix:m/s")`. Keep it ASCII: a degree sign or a superscript written
  by a script that saved the file as Windows-1252 makes Godot refuse the whole script ("invalid unicode").
- Scene exports need no resource: `@export` on the root script of a scene (the range cameras) shows in that node's
  inspector. A member initialiser must not copy an export (`var _aim := demo_aim` reads the script default, not the
  scene's override): copy it in `_ready`.

## Running a throwaway script

- A script error in `_init` of a `-s` script leaves headless Godot waiting for ever with no output: always run it
  under `timeout`, and run it once with the output piped to `head` to see the error.
- A new `class_name` is unknown to `-s` and to GdUnit4 until `--headless --import` has run once.
- Python on Windows writes `\r\n` and Windows-1252 with `open(path, "w")`: pass `newline="\n"` and `encoding="utf-8"`
  (or write bytes) when it edits a GDScript file.

## Pinning the shipped values

`tests/tuning/default_values.gd` holds one table per resource and a `differences` helper that also flags an exported
property missing from the table, so a new number cannot ship unpinned. The 97 sounds are `sound_defaults.json`,
dumped from the code that built them before it was deleted.

## Reading a shared resource from many places (2026-11-02, the rest of #415)

- **`Resource.current()`**: a static `_shipped` loaded once (`NightSoundTuning`, `LightTuning`, `HudTuning`,
  `TouchLook.tuning`) serves a class whose users are many small nodes and static helpers; `shipped()` (a private copy)
  serves a class a test or a variant mutates (`ZombieTuning`, `AimAssistTuning`). A test that needs another value makes
  a copy with `duplicate()`; it never edits the shared one.
- **A `const` cannot hold a resource number**, so a test's `const TOTAL := Hud.A + Hud.B` becomes a function, and a
  default argument (`hold := HudBanner.HOLD_TIME`) becomes a sentinel (`-1.0`) resolved in the body. One parse error in
  a suite stops that whole folder with exit code 105 and no failed test: read the log for `Parse Error` and compare the
  executed-suite count.
- **A table keyed by name** (`SoldierVoiceCatalog.EVENTS`) becomes a resource with an array of small resources
  (`SoldierMoments` of `SoldierMoment`); a static accessor rebuilds the old dictionary shape once, so nothing else
  changes. The inspector shows each as a named item.
- **Ranges and units in bulk**: a script that reads `@export var name := number` lines and writes
  `@export_range(min, max, step, "or_greater", "suffix:unit")` from the name (`*_speed` m/s, `*_seconds` s, `*_degrees`
  deg, `*_frequency` Hz) and a reviewed override table did 246 properties. `or_greater` keeps the slider's end from being
  a wall; a share from 0 to 1 is bounded. Keep each annotation on one line under 100 characters or gdformat joins it and
  gdlint fails.
- **gdformat on Windows writes CRLF**: a script that edits files after a pre-commit run must strip carriage returns
  first, and assert that its replacement matched.
- **F6 on a scene the router starts** does nothing visible: the scene's `_ready` can start itself when
  `get_tree().current_scene == self` (deferred, because the root is not set yet in `_ready`).
