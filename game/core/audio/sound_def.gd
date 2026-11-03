class_name SoundDef
extends Resource
## One sound the game can play: where its variants live, which bus carries it, how loud it is and
## how the voice budget treats it. Every sound is a sub-resource of a `SoundBank` file under
## `core/audio/banks/` (open one in the inspector); `SoundCatalog` loads the banks and lists every
## sound by id. The design is `docs/design/audio.md`.

@export_group("File")
## What the game calls this sound (`Audio.play(&"shot_pistol")`). Never two with one id.
@export var id: StringName
## Variant files: this path with `%d` replaced by 1..variants (a path without `%d` is one file).
@export var path_format := ""
## How many variant files there are; each play picks one at random.
@export_range(1, 64, 1) var variants := 1
## Which bus carries it. Bus volumes are in `default_bus_layout.tres`.
@export_custom(PROPERTY_HINT_ENUM, "Music,Effects,UI,Voice,Ambience")
var bus: StringName = &"Effects"
## The sound plays on a loop until stopped (beds, the generator's hum).
@export var loop := false

@export_group("Level")
## Trim on top of the file's own level (files are all normalised, the catalog balances them).
@export_range(-60.0, 24.0, 0.1, "suffix:dB") var volume_db := 0.0
## Each play is shifted by a random amount within plus or minus this many semitones.
@export_range(0.0, 12.0, 0.05, "suffix:st") var pitch_semitones := 0.5

@export_group("Voice budget")
## Voices of one group share a limit (`SoundMix.group_limits`), so 28 zombies cannot fill the pool.
@export var group: StringName = &"misc"
## A higher priority may take a voice from a lower one when the budget is full.
@export_range(0, 100, 1) var priority := 50
## Seconds before this sound can start again (a footstep or a hover that fires twice in a frame).
@export_range(0.0, 10.0, 0.01, "suffix:s") var cooldown := 0.0

@export_group("Distance (3D)")
## Beyond this distance the sound is not started at all.
@export_range(1.0, 300.0, 0.5, "suffix:m") var max_distance := 50.0
## How far the sound carries before it halves (the engine's `unit_size`).
@export_range(0.5, 100.0, 0.5, "suffix:m") var unit_size := 8.0
## How far above its own level (`volume_db`) the engine may boost the sound as it comes close, in
## dB. The engine's inverse-distance attenuation boosts by `unit_size / distance` (a gun 1.7 m away
## with `unit_size` 14 is 18 dB up) and only stops at the player's `max_db`, +3 dB over the file,
## whatever the trim: close sounds all end up equally hot and stack past full scale. A finite
## value here makes `volume_db` the near level (0) or a little above; `inf` leaves the engine's
## default. A negative value holds the near level under the trim: `volume_db + near_cap_db` is the
## most the sound gets however close it comes, and from there out it falls as it always did. A loud
## file takes one so a gun shot landing on it still leaves room under full scale
## (`tests/core/test_close_sound_peaks.gd`).
@export var near_cap_db: float = INF
## How much a wall between the sound and the listener dulls and quiets it: 1 is the service's full
## occlusion (9 dB down and a low-pass at 1.1 kHz), 0 none at all. A warning that must carry through
## cover (a grenade's fuse beep) takes less than 1; every other sound keeps 1.
@export_range(0.0, 1.0, 0.05) var occlusion_scale := 1.0
## A sound behind the listener is darker (a low-pass), the cue by which front and back are told
## apart on two speakers, which panning alone cannot do.
@export var rear_cue := false

@export_group("Duck")
## While it plays the Effects bus is lowered by this many dB (negative) for `duck_hold` seconds.
@export_range(-60.0, 0.0, 0.5, "suffix:dB") var duck_db := 0.0
## How long the duck lasts after the sound starts.
@export_range(0.0, 10.0, 0.05, "suffix:s") var duck_hold := 0.0


static func make(
	sound_id: StringName, path: String, count: int, options: Dictionary = {}
) -> SoundDef:
	var def := SoundDef.new()
	def.id = sound_id
	def.path_format = path
	def.variants = count
	for key: String in options:
		def.set(key, options[key])
	return def


func path_for(variant: int) -> String:
	if not path_format.contains("%d"):
		return path_format
	return path_format % clampi(variant, 1, variants)


## The level the budget compares sounds by at zero distance.
func linear_gain() -> float:
	return db_to_linear(volume_db)
