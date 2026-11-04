extends Node
## The quick melee on a round-two walker (#897), from the player's own camera: the real V key goes
## in twice, a cooldown apart, with the walker standing in reach. It takes two blows now (one before
## the change). Not part of the game. Run with Movie Maker (20 frames a second):
## `gds godot -- --path game res://tests/captures/quick_melee_hits.tscn --fixed-fps 20
## --write-movie <folder>/hits.png --quit-after 1500`. It prints the frame each key went down on
## (`BLOW <n> <frame>`) and the health the walker had left after it (`LEFT <n> <health>`).

const SECOND := 60
const REACH_AHEAD := 1.3
const BLOWS := 3

var _night: Night
var _first_frame := 0
var _left := -1.0


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
	# The round that starts after the intro is round 2.
	_night.server.rules.round_number = 1
	_night.state.event_received.connect(_heard)
	await get_tree().physics_frame
	var player := _night.player()
	player.local_input = false
	player.capture_mouse = false
	player.camera_rig.yaw = 0.0
	player.camera_rig.snap_to(player.global_position)
	player.state.facing = 0.0
	player.rotation.y = 0.0
	await _wait(SECOND * 3)
	_first_frame = Engine.get_process_frames()
	var zombie := await _first_zombie()
	await _hold_zombie(zombie, SECOND / 2)
	for blow in BLOWS:
		if not is_instance_valid(zombie) or not zombie.is_alive():
			break
		print("BLOW %d %d" % [blow + 1, Engine.get_process_frames() - _first_frame])
		_key(true)
		await _hold_zombie(zombie, 2)
		_key(false)
		await _hold_zombie(zombie, SECOND)
		print("LEFT %d %.0f" % [blow + 1, _left])
	await _wait(SECOND)
	get_tree().quit()


func _heard(event: Dictionary) -> void:
	if event["type"] == &"damage_dealt":
		_left = event["health"]


func _hold_zombie(zombie: ZombieBody, ticks: int) -> void:
	var player := _night.player()
	var look := -player.camera_rig.camera().global_basis.z
	var spot := player.global_position + Vector3(look.x, 0.0, look.z).normalized() * REACH_AHEAD
	for _i in ticks:
		if is_instance_valid(zombie) and zombie.is_alive():
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
