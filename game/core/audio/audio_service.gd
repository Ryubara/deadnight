# gdlint: disable=max-public-methods
class_name AudioService
extends Node
## The game's sound player, registered as the autoload `Audio`.
##
## Ask for a sound by id (`SoundCatalog`): `Audio.play(&"shot_rifle", muzzle_position)` for a
## sound in the world, `Audio.play(&"round_start")` for one without a place. Behind that:
## - pooled players (no node is created while playing), one `VoiceBudget` per pool deciding who
##   gets a slot, so a night with 28 zombies and four guns stays readable: each group has a
##   limit, and the nearest, most important voices win;
## - a random variant (never the same one twice in a row) and a small random pitch for every
##   play, from a seedable generator (`seed_random`);
## - distance (sounds past their `max_distance` are not started; the engine attenuates the rest)
##   and occlusion (a muffled, quieter sound when `occlusion_probe` says a wall is between);
## - ducking: a sting lowers the `Duck` bus, which the Effects and Ambience buses send to, for a
##   moment, so the player's own volume settings (which own those buses' volumes) are never touched.
##   It is bus volume and nothing else, so it sounds the same in the web build, where players are
##   samples that ignore bus effects;
## - beds: a few players for the looping ambience and score, which fade in and out in dB per second
##   of the service's own clock (`start_bed`, `stop_bed`);
## - the hook for the UI: `UIAudio.handler` is pointed at `play_ui` when the service is ready.
##
## Time is the service's own: `_process` calls `advance(delta)`, and tests call it directly.

## A sound started: `id` and its position (null when flat). For tests and a debug overlay.
signal played(id: StringName, position: Variant)

## A sound that cannot start this frame (`starts_per_frame`) waits at most this long, then is
## dropped: a step or a hurt cry that late would be heard as a mistake.
const DEFER_MAX_SECONDS := 0.12
## Sounds that may wait at once; past it the quietest waiting one is dropped.
const DEFER_MAX := 16
## Pooled players for sounds with a place, and for sounds without one.
## The background load of the sounds (`start_background_preload`): the wait before it starts (s),
## its share of a frame, and the least and most it takes of one (ms).
const BACKGROUND_WAIT_S := 1.0
const BACKGROUND_SHARE := 0.25
const BACKGROUND_MIN_MSEC := 3.0
const BACKGROUND_MAX_MSEC := 40.0
## The decode of the deferred sounds (`preload_sound_for_night`) while a night runs: a tenth of a
## frame, between these (ms). It is slower than the menu's load because a night is being played.
const DEFERRED_SHARE := 0.1
const DEFERRED_MIN_MSEC := 2.0
const DEFERRED_MAX_MSEC := 6.0
## `AudioStreamPlayer3D.max_db` by default: how far over its file a sound may be boosted close up.
const ENGINE_MAX_DB := 3.0
const POOL_3D := 32
const POOL_2D := 12
## Players for beds (looping ambience and score), which are outside the voice budget. A night
## holds up to seven (crickets, highway, score, wind, the world's bed and the small map's two) and
## each takes two seconds to fade out after the night; the menu's two (`MenuAmbience`) start the
## moment the menu is back, so they need a place while the night's beds are still going.
const POOL_BEDS := 10
## A bed fades between this and its own level, at these rates (dB per second), so it comes in over
## about three seconds and goes out over about two.
const BED_SILENT_DB := -60.0
const BED_FADE_IN_DB_PER_S := 20.0
const BED_FADE_OUT_DB_PER_S := 30.0
## What a fully occluded sound loses, and the low-pass it gets (the engine's per-player distance
## filter).
const OCCLUSION_DB := -9.0
const OCCLUDED_CUTOFF_HZ := 1100.0
const OPEN_CUTOFF_HZ := 5000.0
## A `rear_cue` sound directly behind the listener is low-passed here (fading in from the side), so
## the dead heard behind the player sound muffled against those in front.
const REAR_CUTOFF_HZ := 1800.0
## The rear cue starts here: the cosine of the angle from straight ahead (negative is behind).
const REAR_FROM_COS := 0.15
## The budget treats a fully occluded sound as this much quieter.
const OCCLUSION_LOUDNESS := 0.5
## Ducking: how fast the `Duck` bus drops and recovers, in dB per second.
const DUCK_ATTACK_DB_PER_S := 80.0
const DUCK_RELEASE_DB_PER_S := 14.0
## Mix steps the audio thread must take after voices are stopped before it has let go of their
## playbacks (the first fades them out, a later one removes them), and the most polls (with a short
## sleep each) `wait_for_mixer` makes before it gives up.
const DRAIN_MIX_STEPS := 4
const DRAIN_MAX_POLLS := 4000
const DRAIN_POLL_MS := 2
## The buses a sting ducks (the guns and the dead, and the ambience under them). The voice of the
## player, the music and the interface are left alone.
const DUCK_BUSES: Array[StringName] = [&"Effects", &"Ambience"]
## The bus the ducked buses send to (`default_bus_layout.tres`); the duck is its volume.
const DUCK_BUS := &"Duck"
## The value of the project setting `audio/general/default_playback_type.web` that plays players as
## samples (0 is streams). It is not the engine's `AudioServer.PlaybackType`, whose numbers differ.
const PLAYBACK_SETTING_SAMPLE := 1
## Where a player's filter does not apply (the web build plays players as samples, which ignore it),
## a wall and the rear cue are also told by volume: this much more than the usual occlusion drop for
## a fully blocked sound, and this much for one straight behind the listener (dB, both quieter).
const NO_FILTER_OCCLUSION_DB := -4.0
const NO_FILTER_REAR_DB := -3.0

## Where the listener is when no camera exists (and what tests set).
var listener: Node3D
## `Callable(from: Vector3, to: Vector3) -> float`: 0 open, 1 fully blocked. Used when valid.
var occlusion_probe := Callable()
## Whether the low-pass of occlusion and the rear cue is heard (`players_apply_filters`). When it is
## not, they are told by volume as well (`NO_FILTER_OCCLUSION_DB`, `NO_FILTER_REAR_DB`). A test
## sets it.
var filters_apply := AudioService.players_apply_filters()
## Physics layers that block sound. 0 turns the built-in ray test off (the default until the map
## has walls on a layer of their own); `occlusion_probe` overrides it.
var occluder_mask := 0
## The Effects bus's current ducking in dB (0 or negative).
var duck_db := 0.0
## How many sounds may start in one frame; 0 is no limit. Starting a sound costs about a millisecond
## in the web build, and a kill starts six: the rest start in the next frames (the highest priority
## first), a frame or two late, which no one hears. The night turns it on.
var starts_per_frame := 0
## Counters for tests and the debug overlay.
var started := 0
var culled := 0
## Whether the deferred sounds wait, because the night's loading bar is up and every frame of it is
## already paid for (`NightWarmup`): the line is made once the bar is gone.
var decode_held := false
## The menu's sound rules; `play_ui` is its way in.
var ui: UiSounds = UiSounds.new(self)

## While the player is in a menu the service loads the sounds a night uses, a slice of each frame
## (`start_background_preload`), so the night's loading screen has less to do.
var _background_ids: Array = []
var _background_at := 0
var _background_wait := 0.0
## Files of deferred sounds waiting to be decoded to samples: the ones played already first.
var _decode_queue: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _now := 0.0
var _streams := {}
## Loops and beds ready to play, by file path: a copy of the Ogg that loops (made when the sound is
## preloaded, not when a bed starts, where copying a minute of music took 40 ms of the frame).
var _looped := {}
## Short sounds decoded to samples (`PcmStream`) by file path, played instead of the Ogg.
var _pcm := {}
var _starts_frame := -1
var _starts_now := 0
var _deferred: Array[Dictionary] = []
var _last_variant := {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _bed_players: Array[AudioStreamPlayer] = []
## Each running bed by id: {"player", "def", "fade_db" (now), "target_db"}.
var _beds := {}
## Beds that come and go (`keep_bed`): at silence their player is paused, not freed.
var _kept := {}
## The looping players `start_loop` made, so `stop_all` can stop those too.
var _loops: Array[AudioStreamPlayer3D] = []
var _budget_3d: VoiceBudget
var _budget_2d: VoiceBudget
var _duck_until := 0.0
var _duck_target := 0.0
## The amplify effect this service put on each ducked bus.
var _duck_bus := -1
## The duck last written to the `Duck` bus, so a second service (a test beside the game's) that has
## nothing to duck leaves the bus alone.
var _duck_written := 0.0
var _warned := {}
var _rules: GameRules


func _init() -> void:
	_budget_3d = VoiceBudget.new(POOL_3D, SoundCatalog.group_limits())
	_budget_2d = VoiceBudget.new(POOL_2D, SoundCatalog.group_limits())
	_rng.randomize()


func _ready() -> void:
	for i in POOL_3D:
		var player := AudioStreamPlayer3D.new()
		player.name = "Voice3D%d" % i
		add_child(player)
		_players_3d.append(player)
	for i in POOL_2D:
		var player := AudioStreamPlayer.new()
		player.name = "Voice2D%d" % i
		add_child(player)
		_players_2d.append(player)
	for i in POOL_BEDS:
		var player := AudioStreamPlayer.new()
		player.name = "Bed%d" % i
		add_child(player)
		_bed_players.append(player)
	_duck_bus = AudioServer.get_bus_index(DUCK_BUS)
	if _duck_bus < 0:
		push_warning("Audio: the bus layout has no %s bus, so a sting cannot duck" % DUCK_BUS)
	install_ui_hook()


func _exit_tree() -> void:
	# A stream still held by a playing voice when the engine shuts down is reported as a leaked
	# resource: stop every voice and let go of every stream (the players' and the cache's).
	stop_all()
	for player in _players_3d:
		player.stream = null
	for player in _players_2d:
		player.stream = null
	_streams.clear()
	_pcm.clear()
	_looped.clear()
	_kept.clear()
	_set_duck_volume(0.0)
	if UIAudio.handler == play_ui:
		UIAudio.handler = Callable()
	# The engine frees what the audio server still holds only once its mixer has taken a few steps,
	# and a process that quits at once (a test run, a capture) leaves it held: reported at exit as
	# `ObjectDB instances were leaked` and `resources still in use`, at random under load. Only the
	# autoload waits: it leaves the tree last, and a service a test frees mid-run would add a wait
	# to every test.
	if is_inside_tree() and get_parent() == get_tree().root:
		drain_mixer_blocking()


func _process(delta: float) -> void:
	advance(delta)
	_background_preload(delta)
	_decode_queued(delta)


## Starts loading every sound into the cache in the background, a slice of each frame, after a
## short wait (the menu draws first). The night's warm-up loads what is left. Starting again does
## nothing. The slice is a quarter of the last frame, between `BACKGROUND_MIN_MSEC` and
## `BACKGROUND_MAX_MSEC`: a machine that draws slowly has the time, a fast one is not stuttered.
func start_background_preload() -> void:
	if not _background_ids.is_empty() or _background_at > 0:
		return
	_background_ids = SoundCatalog.ids()
	_background_wait = BACKGROUND_WAIT_S


## Ends the menu's background load where it is: a night is loading, and its bar takes over (what
## is not in the cache yet is loaded or queued by `preload_sound_for_night`).
func stop_background_preload() -> void:
	_background_at = _background_ids.size()


## Whether the background load has been asked for and has not finished.
func background_preloading() -> bool:
	return _background_at < _background_ids.size()


func _background_preload(delta: float) -> void:
	if not background_preloading():
		return
	_background_wait -= delta
	if _background_wait > 0.0:
		return
	var slice := clampf(delta * 1000.0 * BACKGROUND_SHARE, BACKGROUND_MIN_MSEC, BACKGROUND_MAX_MSEC)
	var until := Time.get_ticks_msec() + int(slice)
	while background_preloading() and Time.get_ticks_msec() < until:
		preload_sound(_background_ids[_background_at])
		_background_at += 1


func _decode_queued(delta: float) -> void:
	if _decode_queue.is_empty() or decode_held:
		return
	var slice := clampf(delta * 1000.0 * DEFERRED_SHARE, DEFERRED_MIN_MSEC, DEFERRED_MAX_MSEC)
	var until := Time.get_ticks_msec() + int(slice)
	while not _decode_queue.is_empty() and Time.get_ticks_msec() < until:
		var path: String = _decode_queue.pop_front()
		if not _streams.has(path):
			_streams[path] = load(path) if ResourceLoader.exists(path) else null
		if not _pcm.has(path) and PcmStream.fits(_streams[path]):
			_pcm[path] = PcmStream.decode(_streams[path], int(AudioServer.get_mix_rate()))


## Moves the service's clock: frees finished voices and steps the ducking.
func advance(delta: float) -> void:
	_now += delta
	_start_deferred()
	_budget_3d.expire(_now)
	_budget_2d.expire(_now)
	_duck_target = _duck_target if _now < _duck_until else 0.0
	var rate := DUCK_ATTACK_DB_PER_S if _duck_target < duck_db else DUCK_RELEASE_DB_PER_S
	duck_db = move_toward(duck_db, _duck_target, rate * delta)
	_set_duck_volume(duck_db)
	_step_beds(delta)


## Makes every gds_ui control, the menu's own controls and the router sound through the menu's
## table (`UiSounds`, `UiSoundTable`).
func install_ui_hook() -> void:
	UIAudio.handler = play_ui


## One cue of the `UIAudio` vocabulary from `source`: the table and its rules decide the sound.
func play_ui(cue: StringName, source: Object = null) -> void:
	ui.handle(cue, source)


## The service's own clock in seconds (what `advance` moves), for rules that need a gap.
func clock() -> float:
	return _now


## A random number from the service's generator (seedable), so a test or a capture repeats.
func random_range(low: float, high: float) -> float:
	return _rng.randf_range(low, high)


## Plays a round's sting when the rules say a round began or ended. Pass null to stop listening.
func connect_rules(rules: GameRules) -> void:
	if _rules != null and _rules.event_emitted.is_connected(_on_rules_event):
		_rules.event_emitted.disconnect(_on_rules_event)
	_rules = rules
	if _rules != null:
		_rules.event_emitted.connect(_on_rules_event)


## Makes the random choices repeatable (variants and pitch).
func seed_random(value: int) -> void:
	_rng.seed = value
	_last_variant.clear()


## Starts a sound. With a Vector3 `position` it is a 3D sound; without one it plays flat. Returns
## the player it started on, or null when the sound was dropped (too far, over its limit, too
## soon, missing).
func play(id: StringName, position: Variant = null, extra_db := 0.0, pitch_st := 0.0) -> Node:
	var began := PerfProbe.begin()
	var player: Node = null
	if _may_start_now():
		player = _start(id, position, extra_db, pitch_st)
	else:
		_defer(id, position, extra_db, pitch_st)
	PerfProbe.end(&"audio.play", began)
	if PerfProbe.enabled:
		PerfProbe.end(StringName("snd.%s" % id), began)
		PerfProbe.count(&"sounds")
	return player


## Whether another sound may start in this frame; counts it if so.
func _may_start_now() -> bool:
	if starts_per_frame <= 0:
		return true
	var frame := Engine.get_process_frames()
	if frame != _starts_frame:
		_starts_frame = frame
		_starts_now = 0
	if _starts_now >= starts_per_frame:
		return false
	_starts_now += 1
	return true


func _defer(id: StringName, position: Variant, extra_db: float, pitch_st := 0.0) -> void:
	var def := SoundCatalog.get_def(id)
	if def == null:
		return
	(
		_deferred
		. append(
			{
				"id": id,
				"position": position,
				"extra_db": extra_db,
				"pitch_st": pitch_st,
				"at": _now,
				"priority": def.priority,
			}
		)
	)
	if _deferred.size() > DEFER_MAX:
		var quietest := 0
		for i in _deferred.size():
			if _deferred[i]["priority"] < _deferred[quietest]["priority"]:
				quietest = i
		_deferred.remove_at(quietest)
	PerfProbe.count(&"sounds_deferred")


## Starts the waiting sounds the frame has room for, highest priority first (the oldest of equals).
func _start_deferred() -> void:
	if _deferred.is_empty():
		return
	var waiting: Array[Dictionary] = []
	for sound in _deferred:
		if _now - float(sound["at"]) <= DEFER_MAX_SECONDS:
			waiting.append(sound)
	_deferred = waiting
	_deferred.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				a["priority"] > b["priority"]
				or (a["priority"] == b["priority"] and a["at"] < b["at"])
			)
	)
	while not _deferred.is_empty() and _may_start_now():
		var sound: Dictionary = _deferred.pop_front()
		_start(sound["id"], sound["position"], sound["extra_db"], sound.get("pitch_st", 0.0))


func _start(id: StringName, position: Variant, extra_db: float, pitch_st := 0.0) -> Node:
	var def := SoundCatalog.get_def(id)
	if def == null:
		_warn_once("unknown sound '%s'" % id)
		return null
	var stream := _pick_stream(def, true)
	if stream == null:
		return null
	var pitch := _random_pitch(def)
	if pitch_st != 0.0:
		pitch *= exp(pitch_st / 12.0 * log(2.0))
	var duration := stream.get_length() / pitch
	if position is Vector3:
		return _play_3d(def, stream, position, pitch, duration, extra_db)
	return _play_2d(def, stream, pitch, duration, extra_db)


## What the night's loading bar does for a sound: loads its files and decodes them to samples,
## unless the sound is `deferred` (its bank says so): then it only queues the files, and the
## background makes them while the night runs (`_decode_queued`, a few milliseconds a frame), or at
## once for a sound that is played first (`_pick_stream`). Reading a file of the pack and decoding
## it to samples cost about the same, and both grew with every weapon's and every voice's
## sounds (`docs/research/web-export.md`, "Loading a night"). Returns how many files it loaded.
func preload_sound_for_night(id: StringName) -> int:
	var def := SoundCatalog.get_def(id)
	if def == null:
		return 0
	if not def.deferred:
		return preload_sound(id)
	for variant in range(1, def.variants + 1):
		var path := def.path_for(variant)
		if not _pcm.has(path) and not _decode_queue.has(path):
			_decode_queue.append(path)
	return 0


## Sounds whose samples are still to be made (the deferred ones), for tests and the loading bar.
func decode_pending() -> int:
	return _decode_queue.size()


## Loads every variant of a sound into the cache, so its first play has nothing to read. Returns
## how many files it loaded (0 for an unknown sound or one already cached).
func preload_sound(id: StringName) -> int:
	var def := SoundCatalog.get_def(id)
	if def == null:
		return 0
	var loaded := 0
	for variant in range(1, def.variants + 1):
		var path := def.path_for(variant)
		if not _streams.has(path):
			_streams[path] = load(path) if ResourceLoader.exists(path) else null
			loaded += 1
		if not def.loop and not _pcm.has(path) and PcmStream.fits(_streams[path]):
			_pcm[path] = PcmStream.decode(_streams[path], int(AudioServer.get_mix_rate()))
		if def.loop and not _looped.has(path) and _streams[path] is AudioStreamOggVorbis:
			_looped[path] = _loop_of(_streams[path])
	return loaded


## A looping sound that lives on `parent` (the generator's hum). The caller frees it with the
## parent.
func start_loop(id: StringName, parent: Node3D) -> AudioStreamPlayer3D:
	var def := SoundCatalog.get_def(id)
	var stream := _pick_stream(def) if def != null else null
	if stream == null:
		return null
	var looped := _loop_for(stream)
	var player := AudioStreamPlayer3D.new()
	player.stream = looped
	player.bus = def.bus
	player.volume_db = def.volume_db
	cap_near_level(player, def)
	player.unit_size = def.unit_size
	player.max_distance = def.max_distance
	parent.add_child(player)
	player.play()
	_loops = _loops.filter(is_instance_valid)
	_loops.append(player)
	return player


## Starts a looping flat sound (a bed: the night's ambience, the score) that fades in from
## silence. Starting one that already runs only turns it back up. Returns its player, or null when
## the sound is unknown or every bed player is busy.
func start_bed(id: StringName, keep := false) -> AudioStreamPlayer:
	var whole := PerfProbe.begin()
	var bed := _start_bed(id)
	PerfProbe.end(&"audio.start_bed", whole)
	if keep and bed != null:
		_keep(id)
	return bed


## Marks a bed that comes and goes with the night's rounds (the score between them, the tension in
## them), and puts it away silent and paused: from here on it is only paused when it fades to
## silence, and starting it again is a fade up. Starting a minute of music takes 40 ms in the
## browser, which is a frame of the night when it is done at the end of a round.
func _keep(id: StringName) -> void:
	_kept[id] = true
	stop_bed(id)
	_beds[id]["fade_db"] = BED_SILENT_DB
	advance(0.0)


func _start_bed(id: StringName) -> AudioStreamPlayer:
	if _beds.has(id):
		var bed: Dictionary = _beds[id]
		if bed.get("parked", false):
			bed["parked"] = false
			(bed["player"] as AudioStreamPlayer).stream_paused = false
		bed["target_db"] = 0.0
		return bed["player"]
	var def := SoundCatalog.get_def(id)
	var stream := _pick_stream(def) if def != null else null
	var player := _free_bed_player()
	if stream == null or player == null:
		return null
	var looped := _loop_for(stream)
	player.stream = looped
	player.bus = def.bus
	player.volume_db = def.volume_db + BED_SILENT_DB
	var began := PerfProbe.begin()
	player.play()
	PerfProbe.end(&"audio.bed_play", began)
	_beds[id] = {"player": player, "def": def, "fade_db": BED_SILENT_DB, "target_db": 0.0}
	return player


## Fades a bed out and frees its player when it is silent. Nothing happens for a bed not running.
func stop_bed(id: StringName) -> void:
	if _beds.has(id) and not _beds[id].get("parked", false):
		_beds[id]["target_db"] = BED_SILENT_DB


## Fades every bed out (`immediately` stops them now: a scene change or a test reset).
func stop_beds(immediately := false) -> void:
	for id: StringName in _beds.keys():
		if immediately:
			_release_bed(id)
		else:
			stop_bed(id)


func is_bed_running(id: StringName) -> bool:
	return _beds.has(id) and not _beds[id].get("parked", false)


## Moves a bed to `db` under its own level (0 is its own level, `BED_SILENT_DB` or less is silence),
## fading at the bed's usual rates: a room's tone follows the room the listener stands in. A silent
## target fades the bed out like `stop_bed`; a level on a bed not running starts it (from silence).
func set_bed_level(id: StringName, db: float) -> void:
	if db <= BED_SILENT_DB + 0.5:
		stop_bed(id)
		return
	if _start_bed(id) != null:
		_beds[id]["target_db"] = minf(db, 0.0)


## A bed's fade in dB: -60 is silent, 0 is its own level.
func bed_fade_db(id: StringName) -> float:
	return _beds[id]["fade_db"] if _beds.has(id) else BED_SILENT_DB


## Sets the player's `max_db` for the sound: its level plus `near_cap_db`, or the engine's own
## ceiling for a sound with no cap. It always sets it, so a pooled player never keeps the cap of the
## sound it played before. Re-call after changing its `volume_db`.
static func cap_near_level(player: AudioStreamPlayer3D, def: SoundDef) -> void:
	if def.near_cap_db < INF:
		player.max_db = player.volume_db + def.near_cap_db
	else:
		player.max_db = ENGINE_MAX_DB


func listener_position() -> Vector3:
	if listener != null and listener.is_inside_tree():
		return listener.global_position
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera != null else Vector3.ZERO


## How far behind the listener a point is, 0 (in front or beside) to 1 (straight behind). Without a
## listener node or camera there is no facing, so 0.
func rear_amount(at: Vector3) -> float:
	var node: Node3D = listener if listener != null and listener.is_inside_tree() else null
	if node == null and is_inside_tree():
		node = get_viewport().get_camera_3d()
	if node == null:
		return 0.0
	var to := at - node.global_position
	to.y = 0.0
	var forward := -node.global_transform.basis.z
	forward.y = 0.0
	if to.length_squared() < 0.01 or forward.length_squared() < 0.0001:
		return 0.0
	var cosine := forward.normalized().dot(to.normalized())
	return clampf((REAR_FROM_COS - cosine) / (REAR_FROM_COS + 1.0), 0.0, 1.0)


## How blocked the path from the listener to a point is, 0 to 1.
func occlusion_between(from: Vector3, to: Vector3) -> float:
	if occlusion_probe.is_valid():
		return clampf(float(occlusion_probe.call(from, to)), 0.0, 1.0)
	if occluder_mask == 0 or not is_inside_tree():
		return 0.0
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, occluder_mask)
	return 1.0 if not space.intersect_ray(query).is_empty() else 0.0


## Voices in use right now, for tests and a debug overlay.
func active_voices() -> int:
	return _budget_3d.active_count() + _budget_2d.active_count()


func budget_3d() -> VoiceBudget:
	return _budget_3d


func budget_2d() -> VoiceBudget:
	return _budget_2d


## Stops everything (a scene change or a test reset).
func stop_all() -> void:
	for player in _players_3d:
		player.stop()
	for player in _players_2d:
		player.stop()
	_budget_3d.release_all()
	_budget_2d.release_all()
	stop_beds(true)
	for loop in _loops:
		if is_instance_valid(loop):
			loop.stop()
			loop.stream = null
	_loops.clear()
	_duck_until = 0.0
	_duck_target = 0.0


## Waits until the audio thread has taken the stopped voices off, so that quitting leaves no stream
## held by the audio server (reported at exit as `ObjectDB instances were leaked` and `resources
## still in use`). A voice stopped on the main thread stays in the server until its mixer takes a
## few steps, which a loaded machine delays by any amount of real time, so this counts the steps
## themselves (`get_time_since_last_mix` falls when one lands) instead of waiting a set time. Call
## it after `stop_all`, from a coroutine, before quitting.
func wait_for_mixer() -> void:
	var steps := 0
	var last := AudioServer.get_time_since_last_mix()
	for _i in DRAIN_MAX_POLLS:
		if steps >= DRAIN_MIX_STEPS:
			return
		OS.delay_msec(DRAIN_POLL_MS)
		await get_tree().process_frame
		var now := AudioServer.get_time_since_last_mix()
		if now < last:
			steps += 1
		last = now
	push_warning("Audio: the mixer took %d of %d steps in time" % [steps, DRAIN_MIX_STEPS])


## `wait_for_mixer` for a place that cannot await, the end of the process: blocks this thread (the
## mixer runs on its own) until the mixer has taken the steps or the polls run out. Returns whether
## it did.
func drain_mixer_blocking() -> bool:
	var steps := 0
	var last := AudioServer.get_time_since_last_mix()
	for _i in DRAIN_MAX_POLLS:
		if steps >= DRAIN_MIX_STEPS:
			return true
		OS.delay_msec(DRAIN_POLL_MS)
		var now := AudioServer.get_time_since_last_mix()
		if now < last:
			steps += 1
		last = now
	return false


func _play_3d(
	def: SoundDef, stream: AudioStream, at: Vector3, pitch: float, duration: float, extra_db: float
) -> Node:
	var from := listener_position()
	var distance := from.distance_to(at)
	if distance > def.max_distance:
		culled += 1
		return null
	var began := PerfProbe.begin()
	var occlusion := occlusion_between(from, at) * def.occlusion_scale
	PerfProbe.end(&"audio.occlusion", began)
	var loudness := def.linear_gain() * def.unit_size / (def.unit_size + distance)
	loudness *= 1.0 - OCCLUSION_LOUDNESS * occlusion
	var slot := _budget_3d.acquire(def, loudness, _now, duration)
	if slot < 0:
		return null
	var player := _players_3d[slot]
	began = PerfProbe.begin()
	player.stop()
	player.stream = stream
	player.bus = def.bus
	player.volume_db = def.volume_db + extra_db + OCCLUSION_DB * occlusion
	if not filters_apply:
		player.volume_db += NO_FILTER_OCCLUSION_DB * occlusion
		if def.rear_cue:
			player.volume_db += NO_FILTER_REAR_DB * rear_amount(at)
	cap_near_level(player, def)
	player.pitch_scale = pitch
	player.unit_size = def.unit_size
	player.max_distance = def.max_distance
	var cutoff := lerpf(OPEN_CUTOFF_HZ, OCCLUDED_CUTOFF_HZ, occlusion)
	if def.rear_cue:
		cutoff = minf(cutoff, lerpf(OPEN_CUTOFF_HZ, REAR_CUTOFF_HZ, rear_amount(at)))
	player.attenuation_filter_cutoff_hz = cutoff
	player.global_position = at
	PerfProbe.end(&"audio.setup3d", began)
	began = PerfProbe.begin()
	player.play()
	PerfProbe.end(&"audio.player_play", began)
	_after_start(def, at)
	return player


func _play_2d(
	def: SoundDef, stream: AudioStream, pitch: float, duration: float, extra_db: float
) -> Node:
	var slot := _budget_2d.acquire(def, def.linear_gain(), _now, duration)
	if slot < 0:
		return null
	var player := _players_2d[slot]
	var began := PerfProbe.begin()
	player.stop()
	player.stream = stream
	player.bus = def.bus
	player.volume_db = def.volume_db + extra_db
	player.pitch_scale = pitch
	player.play()
	PerfProbe.end(&"audio.player_play", began)
	_after_start(def, null)
	return player


func _step_beds(delta: float) -> void:
	for id: StringName in _beds.keys():
		var bed: Dictionary = _beds[id]
		if bed.get("parked", false):
			continue
		var rate := (
			BED_FADE_IN_DB_PER_S if bed["target_db"] > bed["fade_db"] else BED_FADE_OUT_DB_PER_S
		)
		bed["fade_db"] = move_toward(bed["fade_db"], bed["target_db"], rate * delta)
		(bed["player"] as AudioStreamPlayer).volume_db = (
			(bed["def"] as SoundDef).volume_db + bed["fade_db"]
		)
		if bed["target_db"] <= BED_SILENT_DB and bed["fade_db"] <= BED_SILENT_DB:
			if _kept.has(id):
				bed["parked"] = true
				(bed["player"] as AudioStreamPlayer).stream_paused = true
			else:
				_release_bed(id)


func _release_bed(id: StringName) -> void:
	var player := _beds[id]["player"] as AudioStreamPlayer
	player.stop()
	player.stream_paused = false
	player.stream = null
	_beds.erase(id)


func _free_bed_player() -> AudioStreamPlayer:
	var taken := _beds.values().map(func(bed: Dictionary) -> Node: return bed["player"])
	for player in _bed_players:
		if not taken.has(player):
			return player
	return null


func _after_start(def: SoundDef, position: Variant) -> void:
	started += 1
	played.emit(def.id, position)
	if def.duck_db < 0.0:
		_duck_target = minf(_duck_target if _now < _duck_until else 0.0, def.duck_db)
		_duck_until = maxf(_duck_until, _now + def.duck_hold)


## One variant of the sound (never the one played last). `samples` asks for its decoded copy when it
## has one (`PcmStream`): a loop or a bed needs the Ogg, which it can loop.
## The copy of `stream` that loops: the one made at preload, or one made now.
func _loop_for(stream: AudioStream) -> AudioStreamOggVorbis:
	if _looped.has(stream.resource_path):
		return _looped[stream.resource_path]
	return _loop_of(stream)


func _loop_of(stream: AudioStream) -> AudioStreamOggVorbis:
	var looped := stream.duplicate() as AudioStreamOggVorbis
	looped.loop = true
	return looped


func _pick_stream(def: SoundDef, samples := false) -> AudioStream:
	var variant := 1
	if def.variants > 1:
		var last: int = _last_variant.get(def.id, 0)
		variant = _rng.randi_range(1, def.variants - 1 if last > 0 else def.variants)
		if last > 0 and variant >= last:
			variant += 1
		_last_variant[def.id] = variant
	var path := def.path_for(variant)
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	if _streams[path] == null:
		_warn_once("missing file %s" % path)
	if samples and _pcm.has(path):
		return _pcm[path]
	if samples and def.deferred and _decode_queue.has(path):
		# Played before its turn: this play is the Ogg, and the next ones are samples; the sound's
		# other takes follow it to the front of the line.
		for take in range(def.variants, 0, -1):
			var queued := def.path_for(take)
			if _decode_queue.has(queued):
				_decode_queue.erase(queued)
				_decode_queue.push_front(queued)
	return _streams[path]


func _random_pitch(def: SoundDef) -> float:
	if def.pitch_semitones <= 0.0:
		return 1.0
	return exp((_rng.randf_range(-1.0, 1.0) * def.pitch_semitones / 12.0) * log(2.0))


func _warn_once(message: String) -> void:
	if not _warned.has(message):
		_warned[message] = true
		push_warning("Audio: " + message)


func _on_rules_event(event: Dictionary) -> void:
	match event.get("type"):
		&"round_started":
			play(&"round_start")
		&"round_ended":
			play(&"round_end")
		&"special_round_announced":
			play(&"special_round")


## Writes the duck to the `Duck` bus when it has changed.
func _set_duck_volume(db: float) -> void:
	if _duck_bus < 0 or is_equal_approx(db, _duck_written):
		return
	_duck_written = db
	AudioServer.set_bus_volume_db(_duck_bus, db)


## Whether a 3D player's distance filter (the low-pass of occlusion and the rear cue) reaches the
## speakers: not for a player played as a sample, which is the web build's default.
static func players_apply_filters() -> bool:
	if not OS.has_feature("web"):
		return true
	var setting := int(
		ProjectSettings.get_setting(
			"audio/general/default_playback_type.web", PLAYBACK_SETTING_SAMPLE
		)
	)
	return setting != PLAYBACK_SETTING_SAMPLE
