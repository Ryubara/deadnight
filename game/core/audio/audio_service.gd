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
## - ducking: a sting lowers the Effects bus for a moment, in an `AudioEffectAmplify` this node
##   adds, so the player's own volume settings (which own the buses' volumes) are never touched;
## - beds: a few players for the looping ambience and score, which fade in and out in dB per second
##   of the service's own clock (`start_bed`, `stop_bed`);
## - the hook for the UI: `UIAudio.handler` is pointed at `play_ui` when the service is ready.
##
## Time is the service's own: `_process` calls `advance(delta)`, and tests call it directly.

## A sound started: `id` and its position (null when flat). For tests and a debug overlay.
signal played(id: StringName, position: Variant)

## Pooled players for sounds with a place, and for sounds without one.
const POOL_3D := 32
const POOL_2D := 12
## Players for beds (looping ambience and score), which are outside the voice budget.
const POOL_BEDS := 4
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
## Ducking: how fast the Effects bus drops and recovers, in dB per second.
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

## Where the listener is when no camera exists (and what tests set).
var listener: Node3D
## `Callable(from: Vector3, to: Vector3) -> float`: 0 open, 1 fully blocked. Used when valid.
var occlusion_probe := Callable()
## Physics layers that block sound. 0 turns the built-in ray test off (the default until the map
## has walls on a layer of their own); `occlusion_probe` overrides it.
var occluder_mask := 0
## The Effects bus's current ducking in dB (0 or negative).
var duck_db := 0.0
## Counters for tests and the debug overlay.
var started := 0
var culled := 0

var _rng := RandomNumberGenerator.new()
var _now := 0.0
var _streams := {}
var _last_variant := {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _bed_players: Array[AudioStreamPlayer] = []
## Each running bed by id: {"player", "def", "fade_db" (now), "target_db"}.
var _beds := {}
## The looping players `start_loop` made, so `stop_all` can stop those too.
var _loops: Array[AudioStreamPlayer3D] = []
var _budget_3d: VoiceBudget
var _budget_2d: VoiceBudget
var _duck_until := 0.0
var _duck_target := 0.0
## The amplify effect this service put on each ducked bus.
var _duck_effects: Dictionary[StringName, AudioEffectAmplify] = {}
var _warned := {}
var _rules: GameRules


func _init() -> void:
	_budget_3d = VoiceBudget.new(POOL_3D, SoundCatalog.GROUP_LIMITS)
	_budget_2d = VoiceBudget.new(POOL_2D, SoundCatalog.GROUP_LIMITS)
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
	_add_duck_effect()
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
	_remove_duck_effect()
	if UIAudio.handler == play_ui:
		UIAudio.handler = Callable()


func _process(delta: float) -> void:
	advance(delta)


## Moves the service's clock: frees finished voices and steps the ducking.
func advance(delta: float) -> void:
	_now += delta
	_budget_3d.expire(_now)
	_budget_2d.expire(_now)
	_duck_target = _duck_target if _now < _duck_until else 0.0
	var rate := DUCK_ATTACK_DB_PER_S if _duck_target < duck_db else DUCK_RELEASE_DB_PER_S
	duck_db = move_toward(duck_db, _duck_target, rate * delta)
	for effect in _duck_effects.values():
		effect.volume_db = duck_db
	_step_beds(delta)


## Makes every gds_ui control and the router sound through the catalog's `ui_*` sounds.
func install_ui_hook() -> void:
	UIAudio.handler = play_ui


func play_ui(cue: StringName) -> void:
	var id: StringName = SoundCatalog.UI_CUES.get(cue, &"")
	if id != &"":
		play(id)


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
func play(id: StringName, position: Variant = null, extra_db := 0.0) -> Node:
	var def := SoundCatalog.get_def(id)
	if def == null:
		_warn_once("unknown sound '%s'" % id)
		return null
	var stream := _pick_stream(def)
	if stream == null:
		return null
	var pitch := _random_pitch(def)
	var duration := stream.get_length() / pitch
	if position is Vector3:
		return _play_3d(def, stream, position, pitch, duration, extra_db)
	return _play_2d(def, stream, pitch, duration, extra_db)


## A looping sound that lives on `parent` (the generator's hum). The caller frees it with the
## parent.
func start_loop(id: StringName, parent: Node3D) -> AudioStreamPlayer3D:
	var def := SoundCatalog.get_def(id)
	var stream := _pick_stream(def) if def != null else null
	if stream == null:
		return null
	var looped := stream.duplicate() as AudioStreamOggVorbis
	looped.loop = true
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
func start_bed(id: StringName) -> AudioStreamPlayer:
	if _beds.has(id):
		_beds[id]["target_db"] = 0.0
		return _beds[id]["player"]
	var def := SoundCatalog.get_def(id)
	var stream := _pick_stream(def) if def != null else null
	var player := _free_bed_player()
	if stream == null or player == null:
		return null
	var looped := stream.duplicate() as AudioStreamOggVorbis
	looped.loop = true
	player.stream = looped
	player.bus = def.bus
	player.volume_db = def.volume_db + BED_SILENT_DB
	player.play()
	_beds[id] = {"player": player, "def": def, "fade_db": BED_SILENT_DB, "target_db": 0.0}
	return player


## Fades a bed out and frees its player when it is silent. Nothing happens for a bed not running.
func stop_bed(id: StringName) -> void:
	if _beds.has(id):
		_beds[id]["target_db"] = BED_SILENT_DB


## Fades every bed out (`immediately` stops them now: a scene change or a test reset).
func stop_beds(immediately := false) -> void:
	for id: StringName in _beds.keys():
		if immediately:
			_release_bed(id)
		else:
			stop_bed(id)


func is_bed_running(id: StringName) -> bool:
	return _beds.has(id)


## A bed's fade in dB: -60 is silent, 0 is its own level.
func bed_fade_db(id: StringName) -> float:
	return _beds[id]["fade_db"] if _beds.has(id) else BED_SILENT_DB


## Applies the sound's `near_cap_db` to `player`: re-call after changing its `volume_db`.
static func cap_near_level(player: AudioStreamPlayer3D, def: SoundDef) -> void:
	if def.near_cap_db < INF:
		player.max_db = player.volume_db + def.near_cap_db


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


func _play_3d(
	def: SoundDef, stream: AudioStream, at: Vector3, pitch: float, duration: float, extra_db: float
) -> Node:
	var from := listener_position()
	var distance := from.distance_to(at)
	if distance > def.max_distance:
		culled += 1
		return null
	var occlusion := occlusion_between(from, at)
	var loudness := def.linear_gain() * def.unit_size / (def.unit_size + distance)
	loudness *= 1.0 - OCCLUSION_LOUDNESS * occlusion
	var slot := _budget_3d.acquire(def, loudness, _now, duration)
	if slot < 0:
		return null
	var player := _players_3d[slot]
	player.stop()
	player.stream = stream
	player.bus = def.bus
	player.volume_db = def.volume_db + extra_db + OCCLUSION_DB * occlusion
	cap_near_level(player, def)
	player.pitch_scale = pitch
	player.unit_size = def.unit_size
	player.max_distance = def.max_distance
	var cutoff := lerpf(OPEN_CUTOFF_HZ, OCCLUDED_CUTOFF_HZ, occlusion)
	if def.rear_cue:
		cutoff = minf(cutoff, lerpf(OPEN_CUTOFF_HZ, REAR_CUTOFF_HZ, rear_amount(at)))
	player.attenuation_filter_cutoff_hz = cutoff
	player.global_position = at
	player.play()
	_after_start(def, at)
	return player


func _play_2d(
	def: SoundDef, stream: AudioStream, pitch: float, duration: float, extra_db: float
) -> Node:
	var slot := _budget_2d.acquire(def, def.linear_gain(), _now, duration)
	if slot < 0:
		return null
	var player := _players_2d[slot]
	player.stop()
	player.stream = stream
	player.bus = def.bus
	player.volume_db = def.volume_db + extra_db
	player.pitch_scale = pitch
	player.play()
	_after_start(def, null)
	return player


func _step_beds(delta: float) -> void:
	for id: StringName in _beds.keys():
		var bed: Dictionary = _beds[id]
		var rate := (
			BED_FADE_IN_DB_PER_S if bed["target_db"] > bed["fade_db"] else BED_FADE_OUT_DB_PER_S
		)
		bed["fade_db"] = move_toward(bed["fade_db"], bed["target_db"], rate * delta)
		(bed["player"] as AudioStreamPlayer).volume_db = (
			(bed["def"] as SoundDef).volume_db + bed["fade_db"]
		)
		if bed["target_db"] <= BED_SILENT_DB and bed["fade_db"] <= BED_SILENT_DB:
			_release_bed(id)


func _release_bed(id: StringName) -> void:
	var player := _beds[id]["player"] as AudioStreamPlayer
	player.stop()
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


func _pick_stream(def: SoundDef) -> AudioStream:
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


func _add_duck_effect() -> void:
	for bus_name in DUCK_BUSES:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var effect := AudioEffectAmplify.new()
		AudioServer.add_bus_effect(bus, effect)
		_duck_effects[bus_name] = effect


func _remove_duck_effect() -> void:
	for bus_name in _duck_effects:
		var bus := AudioServer.get_bus_index(bus_name)
		for i in AudioServer.get_bus_effect_count(bus) if bus >= 0 else 0:
			if AudioServer.get_bus_effect(bus, i) == _duck_effects[bus_name]:
				AudioServer.remove_bus_effect(bus, i)
				break
	_duck_effects.clear()
