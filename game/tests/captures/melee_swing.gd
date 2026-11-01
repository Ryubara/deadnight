extends Node
## A person swings the crowbar at a zombie in the night (#285), from the player's own camera: the
## attack button goes in as a real mouse event, held for a few blows; a zombie stands in reach.
## Not part of the game. Run with Movie Maker (a swing is under a second, so 20 frames a second):
## `godot --path game res://tests/captures/melee_swing.tscn --fixed-fps 20 --write-movie out.png
## --quit-after 600`. It prints the blows, the hurt and the swing it saw.

const SECOND := 60
const REACH_AHEAD := 1.1

var _night: Night
var _heard: Array[StringName] = []


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
	player.camera_rig.yaw = PI
	player.camera_rig.snap_to(player.global_position)
	_night.state.event_received.connect(func(e: Dictionary) -> void: _heard.append(e["type"]))
	# The revolver first, at the hip and aimed, then the crowbar.
	await _wait(SECOND * 2)
	Input.action_press("aim")
	await _wait(SECOND * 2)
	Input.action_release("aim")
	_night.server.combat.apply(CombatAction.equip(_night.PLAYER_ID, &"crowbar"))
	var zombie := await _first_zombie()
	var animation := player.get_node("AnimationTree") as PlayerAnimation
	var look := -player.camera_rig.camera().global_basis.z
	var ahead := Vector3(look.x, 0.0, look.z).normalized()
	var spot := player.global_position + ahead * REACH_AHEAD
	_button(true)
	var swung := false
	for _i in SECOND * 5:
		zombie.position = spot
		zombie.velocity = Vector3.ZERO
		await get_tree().physics_frame
		swung = swung or animation.action_clip == &"Swing_Melee"
	_button(false)
	print(
		(
			"blows %d, hurt %d, swing seen %s"
			% [_heard.count(&"shot_fired"), _heard.count(&"damage_dealt"), swung]
		)
	)
	get_tree().quit()


func _wait(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame


func _first_zombie() -> ZombieBody:
	for _i in 900:
		await get_tree().physics_frame
		if not _night.server.sim.zombies.is_empty():
			return _night.server.sim.zombies.values()[0]
	return null


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
