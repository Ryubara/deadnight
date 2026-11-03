extends Node
## How much headroom the player's own gunfire leaves (#718): the player's own gun fires without a
## break, flat, as a client plays it (`WeaponSounds`, the audio service, the buses), while other
## sounds land on its shots. One cell for each pair of own gun and what lands on it:
## - `alone`: the gun by itself;
## - `reload`: a teammate 4 m ahead reloads each weapon in turn (his steps lifted by
##   `teammate_reload_db`);
## - `mate`: a teammate 4 m ahead fires each weapon, one second at its rate of fire;
## - `zombie`: every zombie voice, a zombie 2 m ahead, and the boss;
## - `world`: a door, a board, a blow, an impact, a grenade blast 4 m off, the till.
## The buses have no effects, so the recorded mix is the plain sum. Not part of the game. Run with
## Movie Maker at a fixed rate, the mix is the movie's .wav, read by `tools/audio/headroom.py`:
## `gds godot -- --path game res://tests/captures/audio_headroom.tscn --write-movie <abs>/m.png
##  --fixed-fps 60 --resolution 160x90 -- [--own=smg,rifle] [--cells=alone,zombie]`.
## `--own=none` is the cell's sounds without any own gun (what each one peaks at by itself).
## `--all-variants` plays every variant file of each sound of the `zombie` and `world` cells (each
## play of a sound otherwise picks one at random, and the files of one sound differ by 15 dB or
## more), one every `VARIANT_GAP` seconds.
## `--close` puts the sounds of those two cells `CLOSE_METRES` from the listener, where every
## sound's near level (the player's `max_db`) is what holds it, not the distance, and leaves the
## whole file of each variant room (its length and `CLOSE_TAIL`) before the next one starts (#753).
## `--wind` runs the night's wind under every cell at its strongest (#782): the base layer at its
## own level and a strongest gust (`+0 dB`, a random file) every `WIND_EVERY` seconds, 11 m off, so
## a sum with the wind can be read against the same run without it. Prints `CELL <own> <cell>
## <start> <end>`, `PLAY <seconds> <own> <cell> <sound>` and, for a 3D sound, `MAXDB <sound> <the
## player's max_db>`.

const OWN := 1
const MATE := 2
## The bench that knows the guns the catalogue does not have yet (#790) and how fast they fire.
const GUN_BENCH := preload("res://tools/bench/audio_gun_bench.gd")
const FPS := 60.0
const OWN_GUNS: Array[StringName] = [
	&"pistol",
	&"smg",
	&"rifle",
	&"shotgun",
	&"flare_gun",
	&"ppsh",
	&"m249",
	&"m4a1",
	&"fifty_cal",
	&"mp5",
	&"pump_870",
	&"dual_pistols",
]
const CELLS: Array[StringName] = [&"alone", &"reload", &"mate", &"zombie", &"world"]
const MATE_GUNS: Array[StringName] = [&"pistol", &"smg", &"rifle", &"shotgun"]
const ZOMBIE_SOUNDS: Array[StringName] = [
	&"zombie_groan",
	&"zombie_attack",
	&"zombie_hurt",
	&"zombie_death",
	&"zombie_alert",
	&"zombie_grunt",
	&"zombie_shriek",
	&"zombie_breath_brute",
	&"zombie_groan_brute",
	&"zombie_groan_crawler",
	&"zombie_roar",
	&"zombie_growl_boss",
]
const WORLD_SOUNDS: Array[StringName] = [
	&"door_open",
	&"board_tear",
	&"board_last",
	&"board_repair",
	&"melee_hit",
	&"impact_head",
	&"impact_flesh",
	&"grenade_blast",
	&"till_ring",
	&"debris_clear",
]
## The shoulder camera from the player's feet (`PlayerTuning`), the muzzle, and where the
## others are.
const LISTENER := Vector3(0.6, 1.6, 2.3)
const MUZZLE := Vector3(0.3, 1.45, -0.4)
const MATE_AT := Vector3(1.4, 0.0, -3.8)
const ZOMBIE_AT := Vector3(0.0, 1.6, -2.0)
const BLAST_AT := Vector3(2.0, 0.5, -4.0)
const WORLD_AT := Vector3(-1.0, 1.0, -3.0)
const LEAD := 0.5
const GAP := 1.0
const VARIANT_GAP := 0.8
const CLOSE_METRES := 1.2
const CLOSE_TAIL := 0.2
const WIND_EVERY := 3.0
const WIND_AT := Vector3(11.0, 0.0, 0.0)
const ALONE_SECONDS := 3.0
const TAIL := 0.7

var _own: Array[StringName] = OWN_GUNS.duplicate()
var _cells: Array[StringName] = CELLS.duplicate()
var _all_variants := false
var _close := false
var _wind := false
var _state := ClientState.new()
var _sounds: WeaponSounds
var _frames := 0
var _label := ""
var _cell := ""


func _ready() -> void:
	get_window().size = Vector2i(160, 90)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--own="):
			_own.clear()
			for gun in argument.trim_prefix("--own=").split(","):
				_own.append(StringName(gun))
		elif argument == "--all-variants":
			_all_variants = true
		elif argument == "--close":
			_close = true
		elif argument == "--wind":
			_wind = true
		elif argument.begins_with("--cells="):
			_cells.clear()
			for cell in argument.trim_prefix("--cells=").split(","):
				_cells.append(StringName(cell))
	Audio.seed_random(718)
	var listener := Camera3D.new()
	add_child(listener)
	listener.position = LISTENER
	listener.make_current()
	Audio.listener = listener
	_state.player_id = OWN
	_sounds = WeaponSounds.new()
	_sounds.play = _play_sound
	add_child(_sounds)
	_sounds.setup(_state, 718)
	(
		_state
		. apply_events(
			[
				{
					"type": &"frame",
					"players": {OWN: {"pos": Vector3.ZERO}, MATE: {"pos": MATE_AT}},
					"zombies": [],
				}
			]
		)
	)
	await get_tree().process_frame
	await _run()
	Audio.stop_all()
	await get_tree().process_frame
	get_tree().quit()


func _run() -> void:
	for own in _own:
		for cell in _cells:
			_label = String(own)
			_cell = String(cell)
			var start := _now()
			var events := _events(cell)
			var interval := 0.1
			if own != &"none":
				interval = GUN_BENCH.interval_of(own)
			# One second more than the last event needs, so a reload's last step and a tail end inside.
			var end := start + LEAD + _span(events) + TAIL
			print("CELL %s %s %.3f %.3f" % [own, cell, start, end])
			var next_shot := start
			var next_event := 0
			var next_gust := start
			if _wind:
				Audio.start_bed(WindSounds.BASE)
				Audio.advance(4.0)
			while _now() < end:
				var now := _now()
				if _wind and now >= next_gust:
					Audio.play(WindSounds.GUST, LISTENER + WIND_AT, 0.0)
					next_gust += WIND_EVERY
				while own != &"none" and next_shot <= now and now < end - TAIL:
					_fire(own, OWN)
					next_shot += interval
				while next_event < events.size() and now - start >= LEAD + events[next_event]["at"]:
					_do(events[next_event])
					next_event += 1
				await get_tree().process_frame
			# Silence between cells so one cell's tails do not reach the next.
			Audio.stop_all()
			_sounds.schedule.clear()
			for _i in int(FPS * 0.4):
				await get_tree().process_frame


## The events of a cell, each `{at, kind, ...}`, spaced so each lands at another phase of the shots.
func _events(cell: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := 0.0
	match cell:
		&"reload":
			for weapon in MATE_GUNS:
				var seconds: float = WeaponCatalog.get_def(weapon).reload_time
				out.append({"at": at, "kind": &"reload", "weapon": weapon, "seconds": seconds})
				at += seconds + 0.3
		&"mate":
			for weapon in MATE_GUNS:
				var def := WeaponCatalog.get_def(weapon)
				var count := maxi(int(1.0 / def.fire_interval), 2)
				for i in count:
					out.append(
						{"at": at + i * def.fire_interval, "kind": &"mate", "weapon": weapon}
					)
				at += GAP + 0.37
		&"zombie":
			at = _sound_events(out, ZOMBIE_SOUNDS, at)
		&"world":
			at = _sound_events(out, WORLD_SOUNDS, at)
	return out


## Appends one event for each sound (each variant of it with `--all-variants`) and returns the
## time after.
func _sound_events(out: Array[Dictionary], ids: Array[StringName], at: float) -> float:
	for id in ids:
		var pos := ZOMBIE_AT if id in ZOMBIE_SOUNDS else WORLD_AT
		if id == &"grenade_blast":
			pos = BLAST_AT
		if _close:
			pos = LISTENER + (pos - LISTENER).normalized() * CLOSE_METRES
		if _all_variants:
			for variant in range(1, SoundCatalog.get_def(id).variants + 1):
				out.append({"at": at, "kind": &"sound", "id": id, "pos": pos, "variant": variant})
				at += _variant_gap(id, variant)
		else:
			out.append({"at": at, "kind": &"sound", "id": id, "pos": pos, "variant": 0})
			at += GAP + 0.037
	return at


## Seconds before the next variant: `VARIANT_GAP`, or with `--close` the length of this one's file.
func _variant_gap(id: StringName, variant: int) -> float:
	if not _close:
		return VARIANT_GAP
	var length := (load(SoundCatalog.get_def(id).path_for(variant)) as AudioStream).get_length()
	return maxf(VARIANT_GAP, length + CLOSE_TAIL)


func _span(events: Array[Dictionary]) -> float:
	var span := ALONE_SECONDS
	if events.is_empty():
		return span
	span = 0.0
	for event in events:
		var length := 1.0
		if event["kind"] == &"reload":
			length = event["seconds"] + 0.3
		span = maxf(span, event["at"] + length)
	return span


func _do(event: Dictionary) -> void:
	match event["kind"]:
		&"reload":
			(
				_state
				. apply_events(
					[
						{
							"type": &"reload_started",
							"shooter_id": MATE,
							"weapon_id": event["weapon"],
							"seconds": event["seconds"],
						}
					]
				)
			)
		&"mate":
			_fire(event["weapon"], MATE)
		&"sound":
			_play_variant(event["id"], event["pos"], event["variant"])


func _fire(weapon: StringName, shooter: int) -> void:
	var from := MATE_AT if shooter == MATE else Vector3.ZERO
	var at := from + MUZZLE
	(
		_state
		. apply_events(
			[
				{
					"type": &"shot_fired",
					"shooter_id": shooter,
					"weapon_id": weapon,
					"muzzle": at,
					"ends": [],
				}
			]
		)
	)


## One sound, and with `variant` above 0 that variant's file: the definition is pointed at the one
## file for the call, then put back.
func _play_variant(id: StringName, at: Variant, variant: int) -> void:
	if variant <= 0:
		_play_sound(id, at, 0.0)
		return
	var def := SoundCatalog.get_def(id)
	var format := def.path_format
	var count := def.variants
	def.path_format = def.path_for(variant)
	def.variants = 1
	_play_sound(id, at, 0.0)
	def.path_format = format
	def.variants = count


func _play_sound(id: StringName, at: Variant, extra_db: float) -> void:
	print("PLAY %.3f %s %s %s" % [_now(), _label, _cell, id])
	var player := Audio.play(id, at, extra_db)
	if player is AudioStreamPlayer3D:
		print("MAXDB %s %.2f" % [id, player.max_db])


func _now() -> float:
	return _frames / FPS


func _process(_delta: float) -> void:
	_frames += 1
