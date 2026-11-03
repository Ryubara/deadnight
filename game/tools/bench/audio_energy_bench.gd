extends Node
## The energy weapons and the re-cut layer as the player hears them, for measurement (#791): like
## `audio_gun_bench.gd`, each slot fires one shot and then a two second burst at the weapon's own
## rate of fire through the night's own `WeaponSounds`, `EnergySounds` and `RecutLayer` and the
## audio service, the listener where the shoulder camera sits behind the shooter. A slot named
## `<weapon>_recut` fires the same weapon with the frame saying it was re-cut. Then the night's
## beds run alone (so the shots can be read against them), and then every variant of the energy
## weapons' close sounds (the burst, the freeze, its creak, the thaw, the shatter) plays one at a
## time 1.2 m ahead, where the player's `max_db` holds them. Run with Movie Maker
## (`--write-movie out.png --fixed-fps 60`). Prints `SLOT`, `SHOT`, `TRIM`, `BED` as the gun bench
## does (`tools/audio/gun_levels.py` reads them) and `CLOSE <seconds> <sound> <variant> <max_db>`
## for each close sound. Arguments after `--`: `slots=ray_gun,smg_recut` for some slots only,
## `other` for a stranger's shots, `close=0` to skip the close sounds, `slots=none beds=0` for the
## close sounds alone.

const SLOT_SECONDS := 7.0
const SINGLE_AT := 0.5
const BURST_AT := 2.5
const BURST_SECONDS := 2.0
const BED_SECONDS := 12.0
const CLOSE_METRES := 1.2
const CLOSE_GAP := 0.25
const CAMERA_AT := Vector3(0.6, 1.6, 2.3)
const MUZZLE := Vector3(0.3, 1.45, -0.4)
const OWN := 1
const OTHER := 2
const RECUT := "_recut"
## The rate of fire of the energy weapons until their definitions are in the catalogue (a wonder
## weapon fires slowly), seconds between two shots.
const INTERVALS := {&"ray_gun": 0.45, &"freeze_gun": 0.8}
## The sounds played close, every variant of each.
const CLOSE_SOUNDS: Array[StringName] = [
	&"burst_ray", &"freeze_hit", &"freeze_creak", &"freeze_thaw", &"freeze_shatter"
]

var _slots: Array[String] = [
	"pistol",
	"pistol_recut",
	"smg",
	"smg_recut",
	"rifle",
	"rifle_recut",
	"shotgun",
	"shotgun_recut",
	"flare_gun",
	"flare_gun_recut",
	"ray_gun",
	"ray_gun_recut",
	"freeze_gun",
	"freeze_gun_recut",
]
var _state := ClientState.new()
var _weapons: WeaponSounds
var _energy: EnergySounds
var _layer: RecutLayer
var _now := 0.0
var _shooter := OWN
var _slot_index := 0
var _next_shot := -1.0
var _single_done := false
var _stage := &"slots"
var _bed_started := false
var _listener: Camera3D
var _bed_end := 0.0
var _close_do_it := true
var _beds_do_it := true
var _close_queue: Array[Array] = []
var _close_next := 0.0
var _close_end := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().size = Vector2i(160, 90)
	Audio.seed_random(791)
	for argument in OS.get_cmdline_user_args():
		if argument == "other":
			_shooter = OTHER
		elif argument.begins_with("slots="):
			_slots.clear()
			for slot in argument.trim_prefix("slots=").split(","):
				if slot != "none":
					_slots.append(slot)
		elif argument == "beds=0":
			_beds_do_it = false
		elif argument == "close=0":
			_close_do_it = false
	_listener = Camera3D.new()
	add_child(_listener)
	_listener.make_current()
	_listener.position = CAMERA_AT
	Audio.listener = _listener
	_state.player_id = OWN
	_weapons = WeaponSounds.new()
	_weapons.play = _play
	add_child(_weapons)
	_weapons.setup(_state, 791)
	_energy = EnergySounds.new()
	_energy.play = _play
	add_child(_energy)
	_energy.setup(_state, 791)
	_layer = RecutLayer.new()
	_layer.play = _play
	add_child(_layer)
	_layer.setup(_state, 791)
	for slot in _slots:
		for id in _voices(slot):
			print("TRIM %s %s %.2f" % [slot, id, SoundCatalog.get_def(id).volume_db])
	if not _slots.is_empty():
		_set_frame(_slot_weapon(), false)


func _process(delta: float) -> void:
	var now := _now
	_now += delta
	if _stage == &"slots":
		_step_slots(now)
	elif _stage == &"bed":
		_step_bed(now)
	elif _stage == &"close":
		_step_close(now)
	elif now > maxf(_bed_end, _close_end) + 1.0:
		Audio.stop_all()
		get_tree().quit()


## The weapon a slot fires, and whether it was re-cut.
static func weapon_of(slot: String) -> StringName:
	return StringName(slot.trim_suffix(RECUT))


static func is_recut(slot: String) -> bool:
	return slot.ends_with(RECUT)


## The sounds a slot's shot starts: the weapon's own voices, and the layer when re-cut.
func _voices(slot: String) -> Array[StringName]:
	var weapon := weapon_of(slot)
	var ids: Array[StringName] = []
	if EnergySounds.FIRE.has(weapon):
		ids.append(EnergySounds.FIRE[weapon])
	else:
		for id: StringName in WeaponSounds.FIRE[weapon].values():
			ids.append(id)
	if is_recut(slot):
		ids.append_array(RecutLayer.layers_for(weapon))
	return ids


func _interval(weapon: StringName) -> float:
	if INTERVALS.has(weapon) and not WeaponCatalog.IDS.has(weapon):
		return float(INTERVALS[weapon])
	return WeaponCatalog.get_def(weapon).fire_interval


func _set_frame(weapon: StringName, recut: bool) -> void:
	var arms := {weapon: [10, 40, 1 if recut else 0]}
	(
		_state
		. apply_events(
			[
				{
					"type": &"frame",
					"players":
					{
						OWN: {"pos": Vector3.ZERO, "arms": arms},
						OTHER: {"pos": Vector3.ZERO, "arms": arms},
					},
					"zombies": []
				}
			]
		)
	)


func _step_slots(now: float) -> void:
	if _slot_index >= _slots.size():
		_stage = &"bed" if _beds_do_it else &"close"
		_close_next = now + 1.0
		return
	var slot := _slots[_slot_index]
	var weapon := weapon_of(slot)
	var start := _slot_index * SLOT_SECONDS
	var local := now - start
	if not _single_done and local >= SINGLE_AT:
		_single_done = true
		_set_frame(weapon, is_recut(slot))
		print(
			(
				"SLOT %s %.3f %.3f %.3f"
				% [slot, start + SINGLE_AT, start + BURST_AT, start + BURST_AT + BURST_SECONDS]
			)
		)
		_fire(weapon)
	if local >= BURST_AT and local < BURST_AT + BURST_SECONDS:
		if _next_shot < 0.0:
			_next_shot = BURST_AT
		while _next_shot <= local:
			_fire(weapon)
			_next_shot += _interval(weapon)
	if local >= SLOT_SECONDS:
		_slot_index += 1
		_next_shot = -1.0
		_single_done = false


func _step_bed(now: float) -> void:
	if not _bed_started:
		_bed_started = true
		_bed_end = now + BED_SECONDS
		print("BED %.3f %.3f" % [now, _bed_end])
		for id in NightSounds.NIGHT_BEDS:
			Audio.start_bed(id)
	if now >= _bed_end:
		for id in NightSounds.NIGHT_BEDS:
			Audio.stop_bed(id)
		_stage = &"close" if _close_do_it else &"end"
		_close_next = now + 2.0


func _step_close(now: float) -> void:
	if _close_queue.is_empty() and _close_end == 0.0:
		for id in CLOSE_SOUNDS:
			var def := SoundCatalog.get_def(id)
			for k in range(1, def.variants + 1):
				_close_queue.append([id, k])
		_close_end = -1.0
	if now < _close_next:
		return
	if _close_queue.is_empty():
		_close_end = now
		_stage = &"end"
		return
	var entry: Array = _close_queue.pop_front()
	var id: StringName = entry[0]
	var def := SoundCatalog.get_def(id)
	# One variant at a time: the definition points at that file for this play.
	var format := def.path_format
	var count := def.variants
	def.path_format = def.path_for(entry[1])
	def.variants = 1
	var at := _listener.global_position + Vector3(0.0, 0.0, -CLOSE_METRES)
	var player: Node = Audio.play(id, at)
	def.path_format = format
	def.variants = count
	var max_db := 0.0
	if player is AudioStreamPlayer3D:
		max_db = (player as AudioStreamPlayer3D).max_db
	print("CLOSE %.3f %s %d %.2f" % [now, id, entry[1], max_db])
	var length := 1.0
	var stream := load(format % entry[1] if format.contains("%d") else format) as AudioStream
	if stream != null:
		length = stream.get_length()
	_close_next = now + length + CLOSE_GAP


func _fire(weapon: StringName) -> void:
	(
		_state
		. apply_events(
			[
				{
					"type": &"shot_fired",
					"shooter_id": _shooter,
					"weapon_id": weapon,
					"muzzle": MUZZLE,
					"ends": [],
				}
			]
		)
	)


func _play(id: StringName, at: Variant, extra_db: float) -> void:
	var player: Node = Audio.play(id, at, extra_db)
	if player == null:
		print("SHOT %.3f %s %s dropped" % [_now, _slot_name(), id])
		return
	var kind := "flat" if at == null else "3d"
	var distance := 0.0 if at == null else _listener.global_position.distance_to(at)
	var level := 0.0
	if player is AudioStreamPlayer3D:
		level = (player as AudioStreamPlayer3D).max_db
	print(
		(
			"SHOT %.3f %s %s %.4f %.2f %s %.2f max_db=%.1f"
			% [_now, _slot_name(), id, player.pitch_scale, player.volume_db, kind, distance, level]
		)
	)


func _slot_name() -> String:
	return _slots[mini(_slot_index, _slots.size() - 1)]


func _slot_weapon() -> StringName:
	return weapon_of(_slot_name())
