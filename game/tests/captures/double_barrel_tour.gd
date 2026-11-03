extends Node
## The double-barrel in a person's hands (#684), from the player's own camera: two pulls of the real
## fire button, the third on an empty gun (it breaks open by itself), then the reload to its end.
## A zombie stands ahead for the shells to hit. Each stage prints `STAGE <name> <ammo> <reserve>`.
## Not part of the game. Run it with Movie Maker (10 frames a second, 6 physics ticks a frame):
## `godot --path game res://tests/captures/double_barrel_tour.tscn --fixed-fps 10
## --write-movie out.png --quit-after 140`.

const SECOND := 60
const AHEAD := 3.5
const PULL_TICKS := 3
## Ticks between the pulls: past the 0.3 s between barrels, with room to see the flash fade.
const GAP := 40

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
	_night.server.combat.apply(CombatAction.give_weapon(_night.PLAYER_ID, &"shotgun"))
	_night.server.combat.apply(CombatAction.equip(_night.PLAYER_ID, &"shotgun"))
	var zombie := await _first_zombie()
	await _wait(SECOND)
	_stage("ready")
	await _pull()
	await _wait(GAP)
	_stage("one barrel fired")
	await _pull()
	await _wait(GAP)
	_stage("both barrels fired")
	await _pull()
	await _wait(SECOND / 2)
	_stage("empty trigger: it breaks open")
	await _wait(SECOND * 2)
	_stage("reloaded")
	await _wait(SECOND)
	if zombie != null:
		zombie.velocity = Vector3.ZERO
	get_tree().quit()


func _stage(name: String) -> void:
	var state := _night.server.combat.state_of(_night.PLAYER_ID, &"shotgun")
	print("STAGE %s %d %d" % [name, state.ammo, state.reserve])


func _wait(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame


## A zombie of round one, brought in front of the player and held there.
func _first_zombie() -> ZombieBody:
	var player := _night.player()
	for _i in 900:
		await get_tree().physics_frame
		if not _night.server.sim.zombies.is_empty():
			var zombie: ZombieBody = _night.server.sim.zombies.values()[0]
			var look := -player.camera_rig.camera().global_basis.z
			var ahead := Vector3(look.x, 0.0, look.z).normalized()
			zombie.position = player.global_position + ahead * AHEAD
			zombie.velocity = Vector3.ZERO
			return zombie
	return null


func _pull() -> void:
	_button(true)
	await _wait(PULL_TICKS)
	_button(false)


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
