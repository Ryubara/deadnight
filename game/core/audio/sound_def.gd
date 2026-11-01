class_name SoundDef
extends RefCounted
## One sound the game can play: where its variants live, which bus carries it, how loud it is and
## how the voice budget treats it. Plain data; `SoundCatalog` lists every one.

var id: StringName
## Variant files: this path with `%d` replaced by 1..variants.
var path_format := ""
var variants := 1
var bus: StringName = &"Effects"
## Trim on top of the file's own level (files are all normalised, the catalog balances them).
var volume_db := 0.0
## Each play is shifted by a random amount within plus or minus this many semitones.
var pitch_semitones := 0.5
## Voices of one group share a limit (`SoundCatalog.GROUP_LIMITS`), so 28 zombies cannot fill the
## pool.
var group: StringName = &"misc"
## A higher priority may take a voice from a lower one when the budget is full.
var priority := 50
## Seconds before this sound can start again (a footstep or a hover that fires twice in a frame).
var cooldown := 0.0
## 3D only: beyond this distance the sound is not started at all.
var max_distance := 50.0
## 3D only: how far the sound carries before it halves (the engine's `unit_size`).
var unit_size := 8.0
var loop := false
## 3D only: a sound behind the listener is darker (a low-pass), the cue by which front and back are
## told apart on two speakers, which panning alone cannot do.
var rear_cue := false
## While it plays the Effects bus is lowered by this many dB (negative) for `duck_hold` seconds.
var duck_db := 0.0
var duck_hold := 0.0


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
	return path_format % clampi(variant, 1, variants)


## The level the budget compares sounds by at zero distance.
func linear_gain() -> float:
	return db_to_linear(volume_db)
