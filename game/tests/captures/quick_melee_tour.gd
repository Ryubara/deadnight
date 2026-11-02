extends Node
## The quick melee with every kind of weapon in hand (#411), from the player's own camera: the real
## V key goes in as an input event, once for each weapon, with a zombie standing in reach. Not part
## of the game. Run with Movie Maker (a blow is half a second, so 20 frames a second):
## `gds godot -- --path game res://tests/captures/quick_melee_tour.tscn --fixed-fps 20
## --write-movie <folder>/tour.png --quit-after 4000`. It prints the frame each blow's key went down
## on (`BLOW <weapon> <frame>`), so the frames to look at are easy to find.

const SECOND := 60
const REACH_AHEAD := 1.3
const WEAPONS: Array[StringName] = [&"pistol", &"rifle", &"shotgun", &"baseball_bat", &"fire_axe"]
## Frames a second the movie is made at (`--fixed-fps`), to say which frame a tick is.
const MOVIE_FPS := 20

var _night: Night
var _first_frame := 0


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 1.0
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	await get_tree().physics_frame
	var player := _night.player()
	player.local_input = false
	player.capture_mouse = false
	player.camera_rig.yaw = PI
	player.camera_rig.snap_to(player.global_position)
	# The body faces the view, as a person's does after a moment of standing there.
	player.state.facing = PI
	player.rotation.y = PI
	await _wait(SECOND * 3)
	_first_frame = Engine.get_process_frames()
	for id in WEAPONS:
		_night.server.combat.apply(CombatAction.give_weapon(_night.PLAYER_ID, id, id))
		await _wait(SECOND)
		var zombie := await _first_zombie()
		await _hold_zombie(zombie, SECOND / 2)
		var frame := Engine.get_process_frames() - _first_frame
		print("BLOW %s %d" % [id, frame])
		_key(true)
		await _hold_zombie(zombie, 2)
		_key(false)
		await _hold_zombie(zombie, SECOND)
	get_tree().quit()


## Keeps a zombie in reach of the blow, `ticks` ticks.
func _hold_zombie(zombie: ZombieBody, ticks: int) -> void:
	var player := _night.player()
	var look := -player.camera_rig.camera().global_basis.z
	var spot := player.global_position + Vector3(look.x, 0.0, look.z).normalized() * REACH_AHEAD
	for _i in ticks:
		if is_instance_valid(zombie):
			zombie.position = spot
			zombie.velocity = Vector3.ZERO
		await get_tree().physics_frame


func _wait(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame


func _first_zombie() -> ZombieBody:
	for _i in 1800:
		await get_tree().physics_frame
		for zombie: ZombieBody in _night.server.sim.zombies.values():
			if zombie.is_alive():
				return zombie
	return null


func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_V
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
