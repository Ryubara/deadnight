extends Node
## The elements of the re-cut in the night (#794), from the player's own camera: the fire button
## goes in as a real mouse event. Not part of the game. Run with Movie Maker, 20 frames a second:
## `godot --path game res://tests/captures/recut_elements.tscn --fixed-fps 20 --write-movie out.png
## --quit-after 420 -- --mode=explosive`. Three zombies (health 900, so they stand to be seen) stand
## in a row ahead of the player. `--mode=` picks the element: `explosive` (the re-cut revolver's
## shot on the middle zombie bursts on the two beside it), `shock` (the same shot arcs to them) or
## `ground` (the re-cut flare gun sets the ground alight under the row), `fire` (the re-cut pump's
## shell sets the zombies it hits burning: flames follow them for the three seconds), `freeze` (the
## plain freeze gun's bolt on the middle zombie of a row three metres apart: only it freezes) and
## `freeze_cut` (the same row, re-cut: the bloom reaches the two beside it). `--spread=` sets the
## metres between the zombies of the row.

const SECOND := 60
## Where the row stands, metres ahead of the player along the lane the view looks down.
const AHEAD := 4.5
const SPREAD := 1.3
## The row's spread for the freeze modes: over the plain bloom's radius, under the re-cut one's.
const FREEZE_SPREAD := 3.0
## Metres of open lane wanted from the shoulder camera on.
const LANE := 16.0

var _night: Night
var _ids: Array[int] = []
## The way the player looks (radians of view yaw): along the open lane found on the lot.
var _yaw := 0.0
var _mode := "explosive"
var _spread := SPREAD


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--spread="):
			_spread = float(arg.trim_prefix("--spread="))
	if _mode.begins_with("freeze") and _spread == SPREAD:
		_spread = FREEZE_SPREAD
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 1.0
	tuning.rounds.health_base = 900.0
	if _mode == "shock":
		# The dual pistols are not in the catalogue yet: the revolver carries the shock.
		var cut := tuning.upgrade.profile_of(&"pistol")
		cut.element = load("res://gameplay/weapons/elements/defs/shock.tres")
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
	match _mode:
		"ground":
			await _flare()
		"fire":
			await _pump()
		"freeze", "freeze_cut":
			await _freezer()
		_:
			await _revolver()
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
		body.position = from + forward * AHEAD + across * (i - 1) * _spread
		body.yaw = atan2(-forward.x, -forward.z)
		body.speed = 0.0
		# Not at the fence's boards (a zombie that came for a breach is pushed back to it).
		body.gate_id = &""


func _hold_the_row() -> void:
	for id in _ids:
		if _night.server.sim.zombies.has(id):
			_night.server.sim.zombies[id].speed = 0.0


func _give_recut(weapon: StringName) -> void:
	_night.server.combat.apply(CombatAction.give_weapon(_night.PLAYER_ID, weapon))
	_night.server.combat.apply(CombatAction.upgrade_weapon(_night.PLAYER_ID, weapon))
	_night.server.combat.apply(CombatAction.equip(_night.PLAYER_ID, weapon))


## Turns the view so the crosshair is on `point`.
func _aim_at(point: Vector3) -> void:
	var rig := _night.player().camera_rig
	var camera := rig.camera()
	var want := point - camera.global_position
	rig.yaw = atan2(-want.x, -want.z)
	rig.pitch = asin(clampf(want.normalized().y, -1.0, 1.0))


func _middle() -> Vector3:
	var body: ZombieBody = _night.server.sim.zombies.get(_ids[1])
	return body.position if body != null else Vector3.ZERO


## Three shots of the re-cut revolver at the middle zombie, a second apart, the row held in place.
func _revolver() -> void:
	_give_recut(&"pistol")
	await _wait(SECOND)
	for _shot in 3:
		_hold_the_row()
		_aim_at(_middle() + Vector3(0.0, 1.2, 0.0))
		await _wait(SECOND / 3)
		_button(MOUSE_BUTTON_LEFT, true)
		await _wait(3)
		_button(MOUSE_BUTTON_LEFT, false)
		await _wait(SECOND)


## One flare at the ground under the middle zombie, then the fire is watched burn.
func _flare() -> void:
	_give_recut(&"flare_gun")
	await _wait(SECOND)
	_aim_at(_middle() + Vector3(0.0, 0.1, 0.0))
	await _wait(SECOND / 3)
	_button(MOUSE_BUTTON_LEFT, true)
	await _wait(3)
	_button(MOUSE_BUTTON_LEFT, false)
	for _second in 6:
		_hold_the_row()
		await _wait(SECOND)


## One shell of the re-cut pump at the middle zombie; the flames are watched for the whole burn.
func _pump() -> void:
	_give_recut(&"pump_870")
	await _wait(SECOND)
	_hold_the_row()
	_aim_at(_middle() + Vector3(0.0, 1.2, 0.0))
	await _wait(SECOND / 3)
	_button(MOUSE_BUTTON_LEFT, true)
	await _wait(3)
	_button(MOUSE_BUTTON_LEFT, false)
	for _second in 5:
		_hold_the_row()
		await _wait(SECOND)


## One bolt of the freeze gun (re-cut in `freeze_cut`) at the middle zombie of a wide row, then the
## ice is watched.
func _freezer() -> void:
	if _mode == "freeze_cut":
		_give_recut(&"freeze_gun")
	else:
		_night.server.combat.apply(CombatAction.give_weapon(_night.PLAYER_ID, &"freeze_gun"))
		_night.server.combat.apply(CombatAction.equip(_night.PLAYER_ID, &"freeze_gun"))
	await _wait(SECOND)
	_hold_the_row()
	_aim_at(_middle() + Vector3(0.0, 1.0, 0.0))
	await _wait(SECOND / 3)
	_button(MOUSE_BUTTON_LEFT, true)
	await _wait(3)
	_button(MOUSE_BUTTON_LEFT, false)
	for _second in 3:
		_hold_the_row()
		await _wait(SECOND)


func _button(index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
