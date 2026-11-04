extends Node
## Every sound of the menu's table (`UiSoundTable`), alone, through the real service and the
## buses at the default settings, so each one's level can be read off the recording (#894): one
## play of each variant file of each distinct (sound, trim) of the table, `GAP` seconds apart,
## then a few sounds of the night for scale (a pistol, a footstep, a till, a groan) and the
## same sounds again. Prints `PLAY <seconds> <sound> <variant> <trim dB>` and `REF <seconds>
## <sound>`. Not part of the game. Run with Movie Maker at a fixed rate;
## `tools/audio/menu_levels.py` reads the mix: `gds godot -- --path game
## res://tests/captures/audio_menu_levels.tscn --write-movie <abs>/m.avi --fixed-fps 60
## --resolution 160x90`, then `ffmpeg -i m.avi -vn -c:a pcm_s32le m.wav`.

const FPS := 60.0
const GAP := 0.7
const LONG_GAP := 3.2
const REFERENCES: Array[Array] = [
	[&"shot_pistol", Vector3(0.4, 1.4, -1.0)],
	[&"step_own_asphalt", null],
	[&"till_ring", null],
	[&"zombie_groan", Vector3(0.0, 1.0, -6.0)],
]

var _frame_start := 0


func _ready() -> void:
	get_window().size = Vector2i(160, 90)
	Settings.path = "user://audio_menu_levels.cfg"
	Settings.reset_defaults()
	Audio.seed_random(5)
	var listener := Camera3D.new()
	add_child(listener)
	listener.make_current()
	Audio.listener = listener
	_frame_start = Engine.get_frames_drawn()
	var done := {}
	for role: StringName in UiSoundTable.ROLES:
		for cue: StringName in UiSoundTable.ROLES[role]:
			var row: Dictionary = UiSoundTable.ROLES[role][cue]
			if UiSoundTable.is_silent(row):
				continue
			var key := "%s|%s" % [row["sound"], row.get("db", 0.0)]
			if done.has(key):
				continue
			done[key] = true
			await _play_every_variant(row["sound"], float(row.get("db", 0.0)))
	for _round in 2:
		for reference: Array in REFERENCES:
			print("REF %.3f %s" % [_seconds(), reference[0]])
			Audio.play(reference[0], reference[1])
			await _wait(1.6)
	Audio.stop_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
	await get_tree().process_frame
	get_tree().quit()


## Each variant file in turn: the definition is pointed at one file for the play (the files of a
## sound differ in shape) and put back.
func _play_every_variant(id: StringName, trim_db: float) -> void:
	var def := SoundCatalog.get_def(id)
	var format := def.path_format
	var variants := def.variants
	for variant in range(1, variants + 1):
		def.path_format = def.path_for(variant)
		def.variants = 1
		print("PLAY %.3f %s %d %.1f" % [_seconds(), id, variant, trim_db])
		Audio.play(id, null, trim_db)
		def.path_format = format
		def.variants = variants
		await _wait(LONG_GAP if id == &"ui_sign_on" else GAP)


func _seconds() -> float:
	return (Engine.get_frames_drawn() - _frame_start) / FPS


func _wait(seconds: float) -> void:
	for _i in int(round(seconds * FPS)):
		await get_tree().process_frame
