class_name NightView
extends Node3D
## What the player sees and hears of the night, made only from what the server sent: the zombies
## from each frame's snapshot, flashes, impacts and damage numbers from the weapons' events, and
## the sounds. It holds no game state and never asks the server anything.

## Lifts a burst of splinters to the middle of the boards.
const BOARD_LIFT := Vector3(0.0, 1.3, 0.0)
## Lifts a damage number off the wound.
const NUMBER_LIFT := Vector3(0.0, 0.3, 0.0)
## A grenade is drawn this many times its real size, with a trail: a hand grenade at real size
## is lost from the shoulder camera by the time it lands.
const GRENADE_SCALE := 2.0
## Lifts a blast's damage number over the zombie's head.
const BLAST_NUMBER_LIFT := Vector3(0.0, 2.0, 0.0)
## Where the gibs of a zombie a blast killed start, and how hard they are thrown up.
const GIB_LIFT := Vector3(0.0, 1.0, 0.0)
const GIB_THROW := 2.0

var horde: ZombieHorde
var effects: ShotEffects
## Where each breach's boards stand (`NightWorld`): a board torn or mended shows a burst there.
var barricade_points: Dictionary[StringName, Vector3] = {}
## The lot's lamps, drawn from the generator's events (`show_lamps`).
var lamps: LotLamps
## The prize crane (`show_crane`).
var crane: CraneView
## The night's sounds besides the guns (`hear`).
var sounds: NightSounds
## The dead's voices and feet, made from the frames (`ZombieVoices`).
var voices: ZombieVoices
## Seconds between frames, for the views' animation.
var step := 1.0 / 60.0
## The drawn body of a player by id (a `Node3D` with a `PlayerAnimation` child named
## `AnimationTree`, or null), for the actions only events tell (the repair). In one process it is
## the server's body; a client on another machine gives its own drawn avatars here.
var bodies: Callable = func(_player_id: int) -> Node3D: return null
## The night's repair interval (s): the pace each player's repair clip is played at.
var repair_interval: Callable = func() -> float: return 1.0

var _state: ClientState
## The grenades in the air, by the server's id: each a copy of the server's grenade, stepped with
## the same code on every frame, so it lands where the server's lands (`show_grenades`).
var _grenade_views: Dictionary[int, GrenadeView] = {}
var _grenade_def: GrenadeDef
## Held here: a Callable does not keep its RefCounted alive.
var _cast: WorldCast


## `telegraphs` maps a look to the seconds its blow takes to land, `board_seconds` to the seconds
## it takes to pull one board off (both from the rules' tuning).
func setup(
	state: ClientState,
	camera: Camera3D,
	telegraphs: Dictionary[StringName, float] = {},
	board_seconds: Dictionary[StringName, float] = {}
) -> void:
	_state = state
	effects = ShotEffects.new()
	add_child(effects)
	horde = ZombieHorde.new()
	add_child(horde)
	horde.setup_client(camera, ZombieTuning.new().emerge_seconds, telegraphs, board_seconds)
	voices = ZombieVoices.new(Audio, 1)
	voices.windups = telegraphs
	state.event_received.connect(_on_event)


## The player who put a board back hammers it home: their repair clip lands on the event, whoever
## they are (every client draws every player's repair from the same event).
func show_repair(player_id: int) -> void:
	var body: Node3D = bodies.call(player_id)
	var animation := body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body else null
	if animation != null:
		animation.board_repaired(repair_interval.call())


## Draws the lamps of `lot` as the rules' events switch them: starting as `fuel` says the night
## begins (the circuits on, the tank full), and following every circuit, the tank and the frames.
func show_lamps(lot: Node, fuel: FuelTuning) -> void:
	lamps = LotLamps.new(lot)
	lamps.configure(fuel)
	lamps.refresh(0)


## Draws the prize crane at the spot the rules say it stands on (`CraneView`).
func show_crane(world: NightWorld, tuning: RulesTuning) -> void:
	crane = CraneView.new()
	add_child(crane)
	var item := tuning.economy.item(&"crane_play")
	crane.setup(_state, world.shop_spots(), tuning.crane, item.pool if item != null else [])


## Draws the grenades the server throws, from its events (`GrenadeView`, `BlastEffect`): a copy of
## each flies through the same world and goes off where the server's does.
func show_grenades(def: GrenadeDef) -> void:
	_grenade_def = def
	_cast = WorldCast.new(get_world_3d().direct_space_state)


## How many grenades are in the air on this client.
func grenades_in_flight() -> int:
	return _grenade_views.size()


## Starts the night's ambience and the sounds of its boards, doors, blows, till and voices, placed
## in `world`.
func hear(world: NightWorld) -> void:
	sounds = NightSounds.new()
	add_child(sounds)
	sounds.setup(_state, world)


## Draws and sounds one event as if the server had sent it (the warm-up replays samples of each
## kind before the night starts, `NightWarmup`).
func draw_event(event: Dictionary) -> void:
	_on_event(event)


func _on_event(event: Dictionary) -> void:
	if lamps != null:
		lamps.apply_event(event)
	voices.on_event(event)
	match event["type"]:
		&"frame":
			horde.apply_snapshot(event["zombies"], step)
			voices.update(_state.zombies, step)
			_step_grenades()
		&"grenade_thrown", &"grenade_dropped":
			_launch_grenade(event)
		&"grenade_exploded":
			_blast(event)
		&"blast_hit":
			_show_blast_hit(event)
		&"zombie_removed":
			_gib(event)
		&"shot_fired":
			effects.shot(WeaponCatalog.get_def(event["weapon_id"]), event["muzzle"], event["ends"])
		&"damage_dealt":
			effects.number(
				event["point"] + NUMBER_LIFT, str(roundi(event["damage"])), event["headshot"]
			)
		&"round_started":
			Audio.play(&"round_start")
		&"round_ended":
			Audio.play(&"round_end")
		&"special_round_announced":
			Audio.play(&"special_round")
		&"projectile_burst":
			effects.spark(event["point"])
		&"board_torn", &"board_repaired":
			if event["type"] == &"board_torn":
				horde.tore(event.get("zombie_id", -1))
			else:
				show_repair(event["player_id"])
			var at: Variant = barricade_points.get(StringName(event["barricade_id"]))
			if at is Vector3:
				effects.spark(at + BOARD_LIFT)


func _launch_grenade(event: Dictionary) -> void:
	if _grenade_def == null:
		return
	var view := GrenadeView.new()
	view.visual_scale = GRENADE_SCALE
	view.trail = true
	view.state = GrenadeState.new(
		event["grenade_id"],
		event["thrower_id"],
		_grenade_def,
		event["position"],
		event["velocity"],
		event["fuse_left"]
	)
	add_child(view)
	view.follow(0.0)
	_grenade_views[event["grenade_id"]] = view


func _step_grenades() -> void:
	for view in _grenade_views.values():
		view.state.step(step, _cast.callable())
		view.follow(step)


func _blast(event: Dictionary) -> void:
	var view: GrenadeView = _grenade_views.get(event["grenade_id"])
	if view != null:
		view.queue_free()
		_grenade_views.erase(event["grenade_id"])
	var blast := BlastEffect.new()
	add_child(blast)
	blast.play(event["point"], _grenade_def)


## What a blast did to one zombie, as a number over it, as a shot's does.
func _show_blast_hit(event: Dictionary) -> void:
	var at := _zombie_position(event["target_id"])
	if at != Vector3.ZERO:
		effects.number(at + BLAST_NUMBER_LIFT, str(roundi(event["damage"])), false)


## A zombie a blast killed bursts into gibs where it stood.
func _gib(event: Dictionary) -> void:
	if event.get("zone", &"") != RulesAction.ZONE_BLAST:
		return
	var at := _zombie_position(event["zombie_id"])
	if at == Vector3.ZERO:
		return
	var gibs := BlastEffect.new()
	add_child(gibs)
	gibs.gibs(at + GIB_LIFT, Vector3.UP * GIB_THROW, event["zombie_id"])


## Where the last frame had a zombie, or the origin when it had none by that id.
func _zombie_position(zombie_id: int) -> Vector3:
	for entry in _state.zombies:
		if entry["id"] == zombie_id:
			return entry["position"]
	return Vector3.ZERO
