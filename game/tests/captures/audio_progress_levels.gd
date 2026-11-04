extends Node
## The progression sounds (#1062) through the real service, the rules of `UiSounds` and the buses
## at the default settings, so `tools/audio/progress_levels.py` can read their levels, put them
## under and over the night's sounds and write the numbers the test pins. In order, with `PLAY
## <seconds> <kind> <detail>` lines for the tool (a section starts with `SECTION <seconds>
## <name>`):
## - `cues`: each cue alone, every variant file of its sound, `GAP` seconds apart;
## - `stack`: eight unlocks and cards in two seconds, then eight at the popups' own 0.15 s;
## - `moments`: a scratch and a level up on top of each other, a level up and a tier up in both
##   orders, a level up asked for while a tier up still sounds (it is not played);
## - `refs`: the sounds a cue must not hide, alone, as the player hears them: a pistol shot at
##   the muzzle, a groan 6 m off and 2 m off, a shriek, a grenade's beep, two of the soldier's
##   urgent lines, a footstep and the till; then the automatic rifle, the heavy gun and the
##   submachine gun in a burst. The mix has no effects on any bus, so a sum of two recordings is
##   the recording of both together. Not part of the game. Run with Movie Maker at a fixed rate:
##   `gds godot -- --path game res://tests/captures/audio_progress_levels.tscn --write-movie
##   <abs>/m.avi --fixed-fps 60 --resolution 160x90`, then `ffmpeg -i m.avi -vn -c:a pcm_s32le
##   m.wav`.

const FPS := 60.0
const GAP := 3.0
const LISTENER := Vector3(0.6, 1.6, 2.3)
const MUZZLE := Vector3(0.3, 1.45, -0.4)
const BURST_SECONDS := 1.5
const BED_SECONDS := 12.0
## The cues, in the order of the issue.
const CUES: Array[StringName] = [
	&"challenge_done", &"level_up", &"tier_up", &"unlock", &"card_earned"
]
## What each reference is: id, where it is (null for a flat sound), and the gap after it.
const REFERENCES: Array[Array] = [
	[&"shot_pistol", MUZZLE, 1.6],
	[&"zombie_groan", Vector3(0.6, 1.6, -3.7), 2.4],
	[&"zombie_groan", Vector3(0.6, 1.6, 0.3), 2.4],
	[&"zombie_shriek", Vector3(0.6, 1.6, 0.3), 3.0],
	[&"grenade_beep", Vector3(2.0, 0.5, -1.7), 1.2],
	[&"vox_boss_arrive_1", null, 4.0],
	[&"vox_low_ammo_1", null, 3.0],
	[&"step_own_asphalt", null, 1.2],
	[&"till_ring", null, 2.0],
]
## The bursts: the catalog's shot and tail of the weapon, and the shots a second.
const BURSTS: Array[Array] = [
	[&"shot_m4a1", &"tail_m4a1", 12.5],
	[&"shot_m249", &"tail_m249", 13.3],
	[&"shot_smg", &"tail_smg", 15.0],
]

var _frame_start := 0


func _ready() -> void:
	get_window().size = Vector2i(160, 90)
	Settings.path = "user://audio_progress_levels.cfg"
	Settings.reset_defaults()
	Audio.seed_random(5)
	var listener := Camera3D.new()
	add_child(listener)
	listener.position = LISTENER
	listener.make_current()
	Audio.listener = listener
	_frame_start = Engine.get_frames_drawn()
	print("SECTION %.3f cues" % _seconds())
	for cue in CUES:
		await _cue_every_variant(cue)
	print("SECTION %.3f stack" % _seconds())
	await _stack(0.25)
	await _wait(GAP)
	await _stack(0.15)
	await _wait(GAP)
	print("SECTION %.3f moments" % _seconds())
	await _moments()
	print("SECTION %.3f refs" % _seconds())
	for reference: Array in REFERENCES:
		var where: Variant = reference[1]
		print("REF %.3f %s %s" % [_seconds(), reference[0], where if where != null else "flat"])
		Audio.play(reference[0], where)
		await _wait(reference[2])
	print("SECTION %.3f beds" % _seconds())
	await _beds()
	for burst: Array in BURSTS:
		await _burst(burst)
	print("SECTION %.3f end" % _seconds())
	Audio.stop_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
	await get_tree().process_frame
	get_tree().quit()


## Each variant file of a cue's sound in turn: the definition is pointed at one file for the play
## (the files of a sound differ in shape) and put back. The cue goes through the rules, as in a
## night.
func _cue_every_variant(cue: StringName) -> void:
	var id: StringName = UiSoundTable.row(&"any", cue)["sound"]
	var def := SoundCatalog.get_def(id)
	var format := def.path_format
	var variants := def.variants
	for variant in range(1, variants + 1):
		def.path_format = def.path_for(variant)
		def.variants = 1
		print("PLAY %.3f cue %s %s %d" % [_seconds(), cue, id, variant])
		Audio.ui.handle(cue)
		def.path_format = format
		def.variants = variants
		await _wait(GAP)


## Eight unlock sounds (the cards and the plain unlocks alternate) `every` seconds apart.
func _stack(every: float) -> void:
	for i in 8:
		var cue: StringName = &"unlock" if i % 2 == 0 else &"card_earned"
		print("PLAY %.3f stack_%.2f %s %d" % [_seconds(), every, cue, i])
		Audio.ui.handle(cue)
		await _wait(every)


## Moments close together: the scratch and the level up at once, the level up then the tier up 0.3 s
## later, the tier up then a level up (which is not played), and a tier up over a scratch.
func _moments() -> void:
	var cases: Array[Array] = [
		["scratch_level", [[&"challenge_done", 0.0], [&"level_up", 0.0]]],
		["level_tier", [[&"level_up", 0.0], [&"tier_up", 0.3]]],
		["tier_level", [[&"tier_up", 0.0], [&"level_up", 0.3]]],
		["tier_scratch", [[&"tier_up", 0.0], [&"challenge_done", 0.5]]],
	]
	for case: Array in cases:
		var at := 0.0
		for step: Array in case[1]:
			await _wait(step[1] - at)
			at = step[1]
			var before := Audio.ui.started.size()
			Audio.ui.handle(step[0])
			print(
				(
					"PLAY %.3f moment_%s %s %d"
					% [_seconds(), case[0], step[0], Audio.ui.started.size() - before]
				)
			)
		await _wait(GAP + 1.0)


## The night's beds alone for `BED_SECONDS` (the crickets, the highway, the score, the wind's
## base), the quiet of a night that a cue lands on.
func _beds() -> void:
	var ids: Array[StringName] = [NightSounds.SCORE, WindSounds.BASE]
	ids.append_array(NightSounds.NIGHT_BEDS)
	print("BEDS %.3f %d" % [_seconds(), ids.size()])
	for id in ids:
		Audio.start_bed(id)
	await _wait(BED_SECONDS)
	for id in ids:
		Audio.stop_bed(id)
	await _wait(2.5)


## A burst of an automatic weapon as the player hears it (the shot and its tail at the muzzle),
## alone.
func _burst(burst: Array) -> void:
	print("BURST %.3f %s %.1f" % [_seconds(), burst[0], BURST_SECONDS])
	var interval := 1.0 / float(burst[2])
	var next := 0.0
	var elapsed := 0.0
	while elapsed < BURST_SECONDS:
		if elapsed >= next:
			Audio.play(burst[0], MUZZLE)
			Audio.play(burst[1], MUZZLE + Vector3(0.0, 0.0, -0.05))
			next += interval
		await get_tree().process_frame
		elapsed += 1.0 / FPS
	await _wait(1.5)


func _seconds() -> float:
	return (Engine.get_frames_drawn() - _frame_start) / FPS


func _wait(seconds: float) -> void:
	for _i in int(round(seconds * FPS)):
		await get_tree().process_frame
