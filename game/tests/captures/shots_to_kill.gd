extends Node
## Shots to kill a round-one walker (#898), from the player's own camera, through the real
## night: one walker stands still `AHEAD` metres in front of the player and every shot is a real
## fire command from the eye to the zone, straight to the server (its events reach the HUD as the
## link would deliver them). Not part of the game. Run with Movie Maker, 20 frames a second:
## `gds godot -- --path game res://tests/captures/shots_to_kill.tscn --fixed-fps 20
## --write-movie out.png --quit-after 900 -- --weapon=house_pistol --zone=head`.
## `--weapon=` is the catalogue id in hand (the House Pistol, or `pistol`, the revolver), `--zone=`
## is `head` or `body` (`--y=` the height aimed at, metres). Every shot is printed (`SHOT n zone
## damage health`); the run ends a moment after the kill.

const SECOND := 60
const AHEAD := 4.5
const LANE := 16.0
## Ticks between two shots: past every start weapon's fire interval.
const GAP := 40
## Where on a standing walker the zone is aimed at, metres above its feet.
var _aim_y := {"head": 1.55, "body": 0.95}

var _night: Night
var _id := 0
var _yaw := 0.0
var _weapon := &"house_pistol"
var _zone := "head"
var _shots := 0
var _seq := 0
var _dead := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weapon="):
			_weapon = StringName(arg.trim_prefix("--weapon="))
		if arg.begins_with("--zone="):
			_zone = arg.trim_prefix("--zone=")
		if arg.begins_with("--y="):
			_aim_y[_zone] = float(arg.trim_prefix("--y="))
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
	_yaw = _find_the_lane()
	player.camera_rig.yaw = _yaw
	player.camera_rig.snap_to(player.global_position)
	_night.state.event_received.connect(_on_event)
	_night.server.rules.apply(RulesAction.skip_break())
	while _night.server.sim.zombies.size() < 1:
		await get_tree().physics_frame
	_night.server.combat.apply(CombatAction.give_weapon(_night.PLAYER_ID, _weapon))
	_night.server.combat.apply(CombatAction.equip(_night.PLAYER_ID, _weapon))
	_id = _night.server.sim.zombies.keys()[0]
	_stand()
	_aim_at(_target(1.1))
	await _wait(SECOND * 2)
	while not _dead and _shots < 40:
		_stand()
		_fire()
		await _wait(GAP)
	await _wait(SECOND)
	print("KILLED in %d shots (%s, %s)" % [_shots, _weapon, _zone])
	get_tree().quit()


func _on_event(event: Dictionary) -> void:
	if event.get("type") == &"damage_dealt" and event.get("shooter_id") == _night.PLAYER_ID:
		_shots += 1
		print(
			(
				"SHOT %d %s %.1f health %.1f"
				% [_shots, event["zone"], event["damage"], event["health"]]
			)
		)
		if float(event["health"]) <= 0.0:
			_dead = true


func _stand() -> void:
	var body: ZombieBody = _night.server.sim.zombies.get(_id)
	if body == null:
		return
	var from := _night.player().global_position
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	body.position = from + forward * AHEAD
	body.yaw = atan2(-forward.x, -forward.z)
	body.speed = 0.0
	body.gate_id = &""


func _target(height: float = -1.0) -> Vector3:
	var body: ZombieBody = _night.server.sim.zombies.get(_id)
	var at := body.position if body != null else Vector3.ZERO
	return at + Vector3(0.0, _aim_y[_zone] if height < 0.0 else height, 0.0)


## The real fire command from the eye to the zone, straight to the server: its events reach the
## client as the link would deliver them (the view stays on the walker, set once).
func _fire() -> void:
	var eye := _night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	var dir := (_target() - eye).normalized()
	_seq += 1
	var action := CombatAction.fire(1, _seq, eye, dir, eye, _night.server.combat.now)
	_night.state.apply_events(_night.server.combat.apply(action))


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


## Turns the view so the crosshair is on `point`.
func _aim_at(point: Vector3) -> void:
	var rig := _night.player().camera_rig
	var camera := rig.camera()
	var want := point - camera.global_position
	rig.yaw = atan2(-want.x, -want.z)
	rig.pitch = asin(clampf(want.normalized().y, -1.0, 1.0))
