class_name WorldSounds
extends Node
## What the lot's machines and its shop sound like, from the server's events: the generator's hum
## (louder and higher under load, coughing when the tank is low, winding down when it is dry and
## roaring back on a refuel), the breaker posts, every purchase, the deny buzzer, the points tick
## and a tense bed that lives under each round. It holds no game state and asks the server
## nothing. The design is `docs/design/audio.md`.

const HUM := &"generator_hum"
const ENGINE := &"generator_engine"
const BED := &"bed_tension"
## The hum's level in dB: the synthesised layer and the generated engine, idle to full load.
const HUM_DB := Vector2(-15.0, -7.0)
const ENGINE_DB := Vector2(-22.0, -9.0)
## The hum's pitch scale at idle and at full load, and how far a starving engine wobbles.
const HUM_PITCH := Vector2(0.94, 1.05)
const STARVE_WOBBLE := 0.035
const STARVE_WOBBLE_HZ := 6.0
## How fast a level moves toward its target, in dB per second, and the level that counts as off.
const SLEW_DB_PER_S := 24.0
const OFF_DB := -60.0
## Seconds between sputters: barely low, and nearly dry.
const SPUTTER_GAP := Vector2(4.0, 1.0)
## The tense bed starts this long after a round does, when the sting's front is over, and fades
## in and out like the other beds (`Audio.start_bed`).
const BED_DELAY := 2.4
const HEAD_LIFT := Vector3(0.0, 1.6, 0.0)
## The points reasons that ring the bell (a kill) instead of ticking (a hit).
const KILL_REASONS: Array[StringName] = [
	&"kill", &"headshot_kill", &"melee_kill", &"explosion_kill"
]
## The sounds of each kind of purchase, besides the till: the first at once, the others 0.2 s
## apart. The crane has none: its play is the spin (`crane_spin_started`).
const BUYS := {
	ShopItem.Kind.WEAPON: [&"buy_weapon"],
	ShopItem.Kind.AMMO: [&"buy_ammo"],
	ShopItem.Kind.GRENADES: [&"buy_ammo"],
	ShopItem.Kind.FUEL: [&"buy_fuel"],
	ShopItem.Kind.TONIC: [&"buy_tonic"],
	ShopItem.Kind.UPGRADE: [&"buy_recut"],
	ShopItem.Kind.DOOR: [&"door_unlock", &"door_buy"],
}
const BUY_GAP := 0.2
## The prize ding comes this long after the claw starts up with it.
const PRIZE_DING_DELAY := 0.35

## `Callable(id: StringName, at: Variant, extra_db: float)`; the audio service unless a test
## listens instead.
var play := Callable()
var schedule := SoundSchedule.new()
var generator := GeneratorLoad.new()

var _state: ClientState
var _economy: EconomyTuning
var _anchor: Node3D
var _post_point := Callable()
var _crane_point := Callable()
var _rng := RandomNumberGenerator.new()
var _hum: AudioStreamPlayer3D
var _engine: AudioStreamPlayer3D
var _hum_db := HUM_DB.x
var _engine_db := ENGINE_DB.x
var _running := true
var _clock := 0.0
var _sputter_left := 0.0


## `anchor` is the generator (the hum plays from it); `post_point` is a
## `Callable(circuit_id) -> Variant` giving the world position of a breaker post (or null);
## `crane_point` a `Callable(spot: int) -> Variant` giving where the prize crane stands at a spot.
func setup(
	state: ClientState,
	fuel: FuelTuning,
	economy: EconomyTuning,
	anchor: Node3D,
	post_point := Callable(),
	crane_point := Callable(),
	seed_value := 1958
) -> void:
	_state = state
	_economy = economy
	_anchor = anchor
	_post_point = post_point
	_crane_point = crane_point
	_rng.seed = seed_value
	generator.configure(fuel)
	_running = not generator.empty
	_start_hum()
	Audio.start_bed(BED, true)
	if state.is_active():
		Audio.start_bed(BED)
	state.event_received.connect(_on_event)


func _exit_tree() -> void:
	Audio.stop_bed(BED)


func _process(delta: float) -> void:
	advance(delta)


## Moves the clock: the hum follows the load and the engine coughs when starving.
func advance(delta: float) -> void:
	_clock += delta
	schedule.advance(delta)
	_follow_hum(delta)
	_follow_sputter(delta)


func hum_player() -> AudioStreamPlayer3D:
	return _hum


func engine_player() -> AudioStreamPlayer3D:
	return _engine


func _on_event(event: Dictionary) -> void:
	generator.apply(event)
	match event["type"]:
		&"fuel_low":
			_sputter_left = 0.0
		&"fuel_empty":
			_running = false
			_play_at_generator(&"generator_down")
			_play_at_generator(&"generator_down_air")
		&"fuel_restored":
			_running = true
			_play_at_generator(&"generator_start")
			_play_at_generator(&"generator_up")
		&"circuit_changed":
			_on_breaker(event)
		&"purchase_made":
			_on_purchase(event)
		&"purchase_denied":
			if event["player_id"] == _state.player_id:
				_play(&"deny", null)
		&"points_changed":
			_on_points(event)
		&"crane_spin_started":
			_at_crane(&"crane_claw_drop", event["spot"], event["player_id"])
			_at_crane(&"crane_spin", event["spot"], event["player_id"])
		&"crane_prize_ready":
			_at_crane(&"crane_claw_lift", event["spot"], event["player_id"])
			schedule.add(
				PRIZE_DING_DELAY,
				func() -> void: _at_crane(&"crane_prize", event["spot"], event["player_id"])
			)
		&"crane_prize_taken":
			_at_player(&"buy_weapon", event["player_id"])
		&"crane_take_denied":
			if event["player_id"] == _state.player_id:
				_play(&"deny", null)
		&"crane_breakdown":
			_at_crane(&"crane_break", event["spot"], event["player_id"])
		&"crane_moved":
			_at_crane(&"crane_move", event["from_spot"], -1)
		&"round_started":
			schedule.cancel(&"bed")
			schedule.add(BED_DELAY, func() -> void: Audio.start_bed(BED), &"bed")
		&"round_ended", &"game_over":
			schedule.cancel(&"bed")
			Audio.stop_bed(BED)


# --- The generator ---


func _start_hum() -> void:
	if _anchor == null:
		return
	_hum = Audio.start_loop(HUM, _anchor)
	_engine = Audio.start_loop(ENGINE, _anchor)
	_follow_hum(0.0, true)


## Level and pitch follow the load; a dry tank (`_running` false) fades the hum away and stops it.
func _follow_hum(delta: float, snap := false) -> void:
	var load_fraction := generator.load_fraction()
	var hum_target := lerpf(HUM_DB.x, HUM_DB.y, load_fraction) if _running else OFF_DB
	var engine_target := lerpf(ENGINE_DB.x, ENGINE_DB.y, load_fraction) if _running else OFF_DB
	var step := SLEW_DB_PER_S * delta
	_hum_db = hum_target if snap else move_toward(_hum_db, hum_target, step)
	_engine_db = engine_target if snap else move_toward(_engine_db, engine_target, step)
	var pitch := lerpf(HUM_PITCH.x, HUM_PITCH.y, load_fraction)
	if generator.is_low():
		pitch *= 1.0 + STARVE_WOBBLE * generator.starving() * sin(_clock * TAU * STARVE_WOBBLE_HZ)
	_set_loop(_hum, _hum_db, pitch)
	_set_loop(_engine, _engine_db, pitch)


func _set_loop(player: AudioStreamPlayer3D, db: float, pitch: float) -> void:
	if player == null:
		return
	player.volume_db = db
	# Near the generator the engine would boost the loop to its own ceiling: hold it at its level.
	player.max_db = db
	player.pitch_scale = pitch
	if db <= OFF_DB + 1.0 and player.playing:
		player.stop()
	elif db > OFF_DB + 1.0 and not player.playing and _anchor.is_inside_tree():
		player.play()


func _follow_sputter(delta: float) -> void:
	if not generator.is_low():
		return
	_sputter_left -= delta
	if _sputter_left <= 0.0:
		_play_at_generator(&"generator_sputter")
		var gap := lerpf(SPUTTER_GAP.x, SPUTTER_GAP.y, generator.starving())
		_sputter_left = gap * _rng.randf_range(0.7, 1.3)


func _play_at_generator(sound: StringName) -> void:
	var at: Variant = _anchor.global_position + Vector3.UP if _anchor != null else null
	_play(sound, at)


func _on_breaker(event: Dictionary) -> void:
	var at: Variant = _post_point.call(event["circuit_id"]) if _post_point.is_valid() else null
	if at == null and _anchor != null:
		at = _anchor.global_position
	_play(&"breaker_on" if event["on"] else &"breaker_off", at)


# --- The shop and the points ---


func _on_purchase(event: Dictionary) -> void:
	var item := _economy.item(event["item_id"])
	if item == null:
		return
	var sounds: Array = BUYS.get(item.kind, [])
	var buyer: int = event["player_id"]
	for i in sounds.size():
		var sound: StringName = sounds[i]
		if i == 0:
			_at_player(sound, buyer)
		else:
			schedule.add(BUY_GAP * i, func() -> void: _at_player(sound, buyer))


func _on_points(event: Dictionary) -> void:
	if event["player_id"] != _state.player_id or event["delta"] <= 0 or event["reason"] == &"start":
		return
	_play(&"points_kill" if event["reason"] in KILL_REASONS else &"points_tick", null)


## A sound where the crane stands at `spot`; where `player_id` (its buyer) stands when the lot
## cannot say, and nothing when neither is known.
func _at_crane(sound: StringName, spot: int, player_id: int) -> void:
	var at: Variant = _crane_point.call(spot) if _crane_point.is_valid() else null
	if at is Vector3:
		_play(sound, at + Vector3.UP)
	elif player_id >= 0:
		_at_player(sound, player_id)


## A sound where `player_id` stands, or flat when it is this screen's own player and nothing says
## where; nothing for a stranger who is not in the frame.
func _at_player(sound: StringName, player_id: int) -> void:
	var player: Dictionary = _state.frame.get("players", {}).get(player_id, {})
	if player.has("pos"):
		_play(sound, player["pos"] + HEAD_LIFT)
	elif player_id == _state.player_id:
		_play(sound, null)


func _play(sound: StringName, at: Variant, extra_db := 0.0) -> void:
	if play.is_valid():
		play.call(sound, at, extra_db)
	else:
		Audio.play(sound, at, extra_db)
