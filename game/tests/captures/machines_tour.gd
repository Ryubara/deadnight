extends Node
## The re-cut bench and the soda fountain from the player's shoulder camera, for captures: the
## player stands at the bench with the revolver in hand, the card shows what a re-cut gives and
## costs, the player pays and the press comes down on the weapon; then the same at the fountain
## with the hearty tonic. `--bench`, `--fountain` or `--both` (the default) choose the parts; with
## `--weapon=rifle` another weapon lies on the cradle. Not part of the game.
## Run it with Movie Maker (through `gds godot`): `godot --path game
## res://tests/captures/machines_tour.tscn --fixed-fps 20 --write-movie out.png --quit-after 200
## -- [--bench] [--fountain]`.

## Frames are physics ticks, 60 a second.
const HOLD := 80
const AFTER_BENCH := 200
const AFTER_FOUNTAIN := 110
const SHOULDER_PITCH := 0.2

var _night: Night
var _yaw := 0.0
var _use := false
var _args := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		_args[arg.trim_prefix("--").get_slice("=", 0)] = (
			arg.get_slice("=", 1) if "=" in arg else "1"
		)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7)
	# The real mouse and keys must not turn the camera or move the body in a recording.
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.ticked.connect(_send)
	var rules := _night.server.rules
	_night.state.apply_events(rules.apply(RulesAction.grant_points(1, 6000)))
	for door in [&"door_concession", &"door_booth"]:
		_night.state.apply_events(rules.apply(RulesAction.buy(1, door)))
	# The booth's and the stand's lights on, so both are seen as a player who threw the breakers would.
	for circuit in [&"concession", &"booth"]:
		rules.apply(RulesAction.set_circuit(circuit, true))
	var weapon := StringName(_args.get("weapon", ""))
	if weapon != &"" and weapon != &"pistol":
		_night.server.buy(1, StringName("weapon_" + String(weapon)))
	_night.player().camera_rig.camera().make_current()
	if not _args.has("fountain"):
		await _bench()
	if not _args.has("bench"):
		await _fountain()
	get_tree().quit()


func _bench() -> void:
	await _stand_at(&"upgrade")
	await _hold(HOLD)
	_use = true
	await _hold(1)
	_use = false
	await _hold(AFTER_BENCH)


func _fountain() -> void:
	await _stand_at(&"perk")
	await _hold(HOLD)
	_use = true
	await _hold(1)
	_use = false
	await _hold(AFTER_FOUNTAIN)


## Stands the player a little to the side of the spot, facing the machine, shoulder camera behind.
func _stand_at(kind: StringName) -> void:
	var spot := Vector3.INF
	for candidate in _night.world.shop_spots():
		if candidate["kind"] == kind:
			spot = candidate["position"]
	var machine := _machine_position(kind)
	var toward := machine - spot
	var flat := Vector3(toward.x, 0.0, toward.z).normalized()
	var side := Vector3(flat.z, 0.0, -flat.x) * 1.2
	_night.player().teleport(spot - flat * 0.9 + side + Vector3(0.0, 0.1, 0.0))
	_yaw = atan2(-flat.x, -flat.z)
	_night.player().camera_rig.yaw = _yaw
	_night.player().camera_rig.pitch = SHOULDER_PITCH
	# The body faces the machine, as a person who walked up to it would.
	_night.player().state.facing = _yaw
	_night.server.body_of(1).state.facing = _yaw
	await _hold(5)


func _machine_position(kind: StringName) -> Vector3:
	var group := RecutMachine.GROUP if kind == &"upgrade" else SodaFountain.GROUP
	return (get_tree().get_nodes_in_group(group)[0] as Node3D).global_position


func _send() -> void:
	var command := NightCommand.new()
	command.motion.yaw = _yaw
	command.use = _use
	_night.link.send(command.to_dict())
	_night.player().camera_rig.yaw = _yaw


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
