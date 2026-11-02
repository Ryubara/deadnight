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
