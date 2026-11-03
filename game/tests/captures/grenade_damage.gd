extends Node
## A grenade hurts the players it reaches (#805), from the player's own shoulder camera with the
## HUD: 1. the player holds the pin until it goes off in the hand (all of the health, the feed says
## so); 2. a teammate throws a grenade and the player stands 3 m from where it lands (a close
## blast); 3. the same throw with the player 6 m from where it lands (a far blast). Each stage
## starts the player at full health. The throw is the teammate's real command (the server throws for
## every player on the command's grenade button), the blast the server's. Not part of the game. Run
## with Movie Maker through the kit's `gds godot`: `gds godot -- --path game
## res://tests/captures/grenade_damage.tscn --fixed-fps 10 --write-movie out.png --quit-after 420`.
## Each stage prints its name and the movie frame it began on.

const PLAYER_NAME := "Ruby"
const TEAMMATE_NAME := "Moe"
const LEAD_IN := 1.0
## Seconds the pin is held in the hand before it goes off there (the fuse is 3 s).
const HELD_FOR := 3.4
const AFTER_BLAST := 2.4
const FLIGHT_LIMIT := 600
const CLOSE := 3.0
const FAR := 6.0
## Where the player stands for the film, on open ground; the teammate throws from this far behind
## and to the side, along the view.
const MATE_BEHIND := 9.0

var _night: Night
var _hud: Hud
var _throw_over := false
var _thrown := {}
var _start := Vector3.ZERO
var _log: Array[Dictionary] = []


func _ready() -> void:
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(_hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = _hud
	add_child(_night)
	var tuning := (load("res://gameplay/rules/default_tuning.tres") as RulesTuning).duplicate(true)
	tuning.rounds.first_spawn_delay = 600.0
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.ticked.connect(_send)
	_night.state.event_received.connect(_on_event)
	var player := _night.player()
	player.capture_mouse = false
	player.local_input = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_night.link.send({"type": NightServer.JOIN, "player_id": 2, "local": false})
	await _ticks(2)
	player.camera_rig.camera().make_current()
	_hud.state.set_player_name(1, PLAYER_NAME)
	_hud.state.set_player_name(2, TEAMMATE_NAME)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	var door: Vector3 = _night.world.door_points(_night.world.door_ids()[0])[0]
	_start = Vector3(door.x, 0.1, door.z - 18.0)
	player.camera_rig.yaw = 0.0
	player.camera_rig.pitch = -0.18
	_place()
	await _seconds(LEAD_IN)
	_stage("in the hand: the pin is held")
	_throw_over = true
	await _seconds(HELD_FOR)
	_throw_over = false
	_report("hand")
	await _seconds(AFTER_BLAST)
	await _get_up()
	_stage("a close blast: the teammate's grenade lands %.0f m from the player" % CLOSE)
	await _teammate_throws(CLOSE)
	_report("close")
	await _seconds(AFTER_BLAST)
	await _get_up()
	_stage("a far blast: the teammate's grenade lands %.0f m from the player" % FAR)
	await _teammate_throws(FAR)
	_report("far")
	await _seconds(AFTER_BLAST)
	get_tree().quit()


## Both stand where the film is made, at full health, the teammate behind the player.
func _place() -> void:
	_put_player(_start)
	_night.server.body_of(2).teleport(_start + Vector3(4.0, 0.0, MATE_BEHIND))


## The player's body, the server's and the one on the screen, put somewhere facing the film's way.
func _put_player(at: Vector3) -> void:
	_night.server.body_of(1).teleport(at)
	_night.player().teleport(at)
	_night.player().camera_rig.snap_to(at)


## The player is on their feet again with all their health, for the next stage.
func _get_up() -> void:
	var rules := _night.server.rules
	var state := rules.players[1]
	if state.downed:
		_night.state.apply_events(rules.apply(RulesAction.set_downed(1, false)))
	state.health = state.max_health
	_place()
	_night.state.apply_events(
		[
			{
				"type": &"player_healed",
				"player_id": 1,
				"health": state.max_health,
				"max_health": state.max_health,
				"reason": &"regen"
			}
		]
	)
	await _seconds(0.6)


## The teammate throws overarm along the view; the grenade's landing is found from its flight, and
## the player is put `apart` metres short of it, facing it, before it goes off.
func _teammate_throws(apart: float) -> void:
	_thrown = {}
	var command := NightCommand.new()
	command.look_along(0.0, 0.1)
	command.motion.throw_over = true
	_night.server.submit(2, command)
	await _seconds(0.4)
	var release := NightCommand.new()
	release.look_along(0.0, 0.1)
	_night.server.submit(2, release)
	for _i in FLIGHT_LIMIT:
		if not _thrown.is_empty():
			break
		await get_tree().physics_frame
	var landing := _landing_of(_thrown)
	# The grenade lies where it landed (a body in its way would stop it): the player steps up to it
	# for the last moments of the fuse.
	await _seconds(_thrown["fuse_left"] - 0.5)
	_put_player(Vector3(landing.x, 0.1, landing.z + apart))
	for _i in FLIGHT_LIMIT:
		if _heard("grenade_exploded", _thrown["grenade_id"]):
			break
		await get_tree().physics_frame


func _heard(type: String, grenade_id: int) -> bool:
	for event in _log:
		if event["type"] == StringName(type) and event.get("grenade_id", -1) == grenade_id:
			return true
	return false


func _on_event(event: Dictionary) -> void:
	_log.append(event)
	if event["type"] == &"grenade_thrown" and event["thrower_id"] == 2:
		_thrown = event


## Where a grenade thrown as the event says lies when its fuse runs out, by flying a copy of it.
func _landing_of(thrown: Dictionary) -> Vector3:
	var cast := WorldCast.new(_night.get_world_3d().direct_space_state)
	var copy := GrenadeState.new(
		0,
		2,
		load("res://gameplay/grenades/defs/frag.tres"),
		thrown["position"],
		thrown["velocity"],
		thrown["fuse_left"]
	)
	for _i in FLIGHT_LIMIT:
		copy.step(Night.STEP, cast.callable())
		if copy.is_spent():
			break
	return copy.position


func _report(label: String) -> void:
	var rules := _night.server.rules
	var hurt := {}
	for event in _log:
		if event["type"] == &"grenade_exploded":
			print("exploded at %s in_hand %s" % [event["point"], event["in_hand"]])
		if event["type"] == &"player_blasted" and event["player_id"] == 1:
			hurt = event
	print(
		(
			"%s: grenades left %d, player health %.0f of %.0f, downed %s, blast on the player %s"
			% [
				label,
				rules.grenades_of(1),
				rules.health_of(1),
				rules.players[1].max_health,
				rules.players[1].downed,
				(
					(
						"share %.2f at %.1f m, damage %.0f"
						% [hurt["share"], hurt["distance"], hurt["damage"]]
					)
					if not hurt.is_empty()
					else "none"
				)
			]
		)
	)
	_log.clear()


func _send() -> void:
	var command := NightCommand.new()
	command.player_id = Night.PLAYER_ID
	var rig := _night.player().camera_rig
	command.motion.yaw = rig.yaw
	command.motion.pitch = rig.pitch
	command.motion.throw_over = _throw_over
	var aim := rig.aim_transform()
	command.origin = aim.origin
	command.dir = -aim.basis.z
	_night.link.send(command.to_dict())


func _stage(stage: String) -> void:
	print("%s at frame %d" % [stage, Engine.get_frames_drawn()])


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _ticks(int(seconds * 60.0))
