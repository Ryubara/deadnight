extends Node
## A person fires the flare gun in the night (#257), from the player's own camera: the fire button
## goes in as a real mouse event. Not part of the game. Run with Movie Maker (a flare is in the
## air for about two seconds, so 20 frames a second):
## `godot --path game res://tests/captures/flare_flight.tscn --fixed-fps 20 --write-movie out.png
## --quit-after 420`. It prints the most flares the view drew at once.

const SECOND := 60
## How long to watch after the trigger.
const WATCH_TICKS := SECOND * 4

var _night: Night


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
	_night.server.combat.apply(CombatAction.give_weapon(_night.PLAYER_ID, &"flare_gun"))
	_night.server.combat.apply(CombatAction.equip(_night.PLAYER_ID, &"flare_gun"))
	await _wait(SECOND)
	_button(true)
	await _wait(3)
	_button(false)
	var drawn := 0
	for _i in WATCH_TICKS:
		await get_tree().physics_frame
		drawn = maxi(drawn, _night.view.projectiles_in_flight())
	print("most flares drawn at once: %d" % drawn)
	get_tree().quit()


func _wait(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
