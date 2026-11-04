extends Node
## A melee weapon on a walker of a chosen round (#924), from the player's own camera: the real
## attack button goes in, a cooldown apart, with the walker standing in reach. Not part of the
## game. Run with Movie Maker (20 frames a second), the weapon and the round after `--`:
## `gds godot -- --path game res://tests/captures/melee_weapon_hits.tscn --fixed-fps 20
## --write-movie <folder>/hits.png --quit-after 1500 -- crowbar 3`. It prints the frame each blow
## went down on (`BLOW <n> <frame>`) and the health the walker had left after it
## (`LEFT <n> <health>`).

const SECOND := 60
const REACH_AHEAD := 1.3
const BLOWS := 4

var _night: Night
var _first_frame := 0
var _left := -1.0
var _weapon := &"crowbar"
var _round := 3


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
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		_weapon = StringName(args[0])
		_round = int(args[1])
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	# The round that starts after the intro is the one after this number.
	_night.server.rules.round_number = _round - 1
	_night.server.combat.apply(CombatAction.give_weapon(1, _weapon))
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
		_button(true)
		await _hold_zombie(zombie, 2)
		_button(false)
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


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
