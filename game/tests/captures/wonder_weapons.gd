extends Node
## The two wonder weapons in the night (#788), from the player's own camera: the fire button goes in
## as a real mouse event. Not part of the game. Run with Movie Maker, 20 frames a second:
## `godot --path game res://tests/captures/wonder_weapons.tscn --fixed-fps 20 --write-movie out.png
## --quit-after 520`. Three zombies stand in a row ahead of the player. The ray gun fires at them
## (the bolt, the burst and the blast on the two beside the one it hit), then the freeze gun
## freezes the three in its bloom, they stand a moment in their ice, and a shot of the revolver
## (aimed, over the sights) shatters the middle one. `MODE` picks the sequence: `ray`, `freeze` or
## `both`.

const SECOND := 60
const MODE := "both"
## Where the row stands, metres ahead of the player along the lane the view looks down.
const AHEAD := 6.5
const SPREAD := 1.4
## Metres of open lane wanted from the shoulder camera on.
const LANE := 16.0

var _night: Night
var _ids: Array[int] = []
## The way the player looks (radians of view yaw): along the open lane found on the lot.
var _yaw := 0.0


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 1.0
	tuning.rounds.health_base = 900.0
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	await get_tree().physics_frame
	var player := _night.player()
	player.local_input = false
	player.capture_mouse = false
	_yaw = _find_the_lane()
	player.camera_rig.yaw = _yaw
	player.camera_rig.snap_to(player.global_position)
	_night.server.rules.apply(RulesAction.skip_break())
	while _night.server.sim.zombies.size() < 3:
		await get_tree().physics_frame
	await _wait(SECOND * 3)
	_stand_the_row()
	await _wait(SECOND)
	if MODE != "freeze":
		await _ray_gun()
	if MODE != "ray":
		await _freeze_gun()
	get_tree().quit()


## Somewhere on the lot with open ground in front, found by looking down: a spot is open when a ray
## dropped on it from above meets only the ground (no car, no post, no wall). The lane is the strip
## `LANE` metres long and three wide in front of the player, all open. The player is stood at the
## start of the first such lane (the grid is walked from the middle out) and the view turned
## along it. Returns the yaw.
func _find_the_lane() -> float:
	var space := _night.world.get_world_3d().direct_space_state
	var best_spot := Vector3.ZERO
	var best_yaw := 0.0
	var found := false
	var spots: Array[Vector3] = []
	for gx in range(-44, 45, 2):
		for gz in range(-44, 45, 2):
			spots.append(Vector3(gx, 0.0, gz))
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.length() < b.length())
	for spot in spots:
		for step in 16:
			var yaw := TAU * float(step) / 16.0
			if _lane_is_open(space, spot, yaw):
				best_spot = spot
				best_yaw = yaw
				found = true
				break
		if found:
			break
	print("lane found: %s yaw %.2f (%s)" % [best_spot, best_yaw, found])
	_night.player().global_position = best_spot
	return best_yaw


func _lane_is_open(space: PhysicsDirectSpaceState3D, spot: Vector3, yaw: float) -> bool:
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var across := Vector3(forward.z, 0.0, -forward.x)
	for along in range(-3, int(LANE) + 1, 2):
		for side in [-1.5, 0.0, 1.5]:
			var at: Vector3 = spot + forward * along + across * side
			var query := PhysicsRayQueryParameters3D.create(
				at + Vector3(0.0, 4.0, 0.0), at + Vector3(0.0, -1.0, 0.0)
			)
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and (hit["position"] as Vector3).y > 0.2:
				return false
	return true


func _wait(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame


## The first three zombies stand still in a row across the view, facing the player.
func _stand_the_row() -> void:
	var from := _night.player().global_position
	_ids.assign(_night.server.sim.zombies.keys().slice(0, 3))
	for i in _ids.size():
		var body: ZombieBody = _night.server.sim.zombies[_ids[i]]
		var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var across := Vector3(forward.z, 0.0, -forward.x)
		body.position = from + forward * AHEAD + across * (i - 1) * SPREAD
		body.yaw = atan2(-forward.x, -forward.z)
		body.speed = 0.0
		# Not at the fence's boards (a zombie that came for a breach is pushed back to it).
		body.gate_id = &""


## Turns the view so the crosshair is on the chest of the middle zombie.
func _aim_at_the_middle() -> void:
	var rig := _night.player().camera_rig
	var body: ZombieBody = _night.server.sim.zombies.get(_ids[1])
	if body == null:
		return
	var camera := rig.camera()
	var want := body.position + Vector3(0.0, 1.2, 0.0) - camera.global_position
	rig.yaw = atan2(-want.x, -want.z)
	rig.pitch = asin(clampf(want.normalized().y, -1.0, 1.0))


func _hold_the_row() -> void:
	for id in _ids:
		if _night.server.sim.zombies.has(id):
			_night.server.sim.zombies[id].speed = 0.0


func _give(weapon: StringName) -> void:
	_night.server.combat.apply(CombatAction.give_weapon(_night.PLAYER_ID, weapon))
	_night.server.combat.apply(CombatAction.equip(_night.PLAYER_ID, weapon))


func _ray_gun() -> void:
	_give(&"ray_gun")
	await _wait(SECOND)
	_aim_at_the_middle()
	await _wait(SECOND / 2)
	_button(MOUSE_BUTTON_LEFT, true)
	await _wait(3)
	_button(MOUSE_BUTTON_LEFT, false)
	await _wait(SECOND * 3)
	_hold_the_row()


func _freeze_gun() -> void:
	_stand_the_row()
	_give(&"freeze_gun")
	await _wait(SECOND)
	_aim_at_the_middle()
	await _wait(SECOND / 2)
	_button(MOUSE_BUTTON_LEFT, true)
	await _wait(3)
	_button(MOUSE_BUTTON_LEFT, false)
	# It stands in its ice a moment (the shell, the held pose), then the second shot, from the
	# revolver (the freeze gun's own bolt does not break it) over the sights, well inside the three
	# seconds.
	await _wait(SECOND + 10)
	_night.server.combat.apply(CombatAction.equip(_night.PLAYER_ID, &"pistol"))
	_button(MOUSE_BUTTON_RIGHT, true)
	_aim_at_the_middle()
	await _wait(SECOND / 2)
	_button(MOUSE_BUTTON_LEFT, true)
	await _wait(3)
	_button(MOUSE_BUTTON_LEFT, false)
	await _wait(SECOND * 3)
	_button(MOUSE_BUTTON_RIGHT, false)


func _button(index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
