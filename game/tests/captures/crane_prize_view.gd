extends Node
## Which prize the crane holds out, as the player sees it: one screenshot from the player's own
## shoulder camera for every weapon of the crane's pool, at the moment the prize has come out, plus
## the cycling (mid-spin) and the dud. The player stands where a player stands to play: on the
## crane's marker (`--stand=marker`, the default), at the edge of the use reach (`--stand=back`) or
## off to one side (`--stand=side`), looking level at the machine; `--stand=case` looks down into
## the glass case from close by, for the tiny weapons. `--phone` draws the touch
## controls over the HUD (run it at a phone's size, `--resolution 2340x1080`). Not part of the game.
## Run it windowed through `gds godot`:
## `gds godot -- --path game --resolution 1920x1080 res://tests/captures/crane_prize_view.tscn
## -- --out=<folder> [--stand=back] [--phone]`; it prints `SHOT <file>` for every picture.

## Frames are physics ticks, 60 a second.
const SETTLE := 40
## Ticks into the grab window when the picture is taken: the prize has come out and stopped.
const SHOT_AFTER := 100
## Metres from the marker, along the line to the crane (negative is away from it) and to the side,
## and the camera's pitch (down, radians).
const STANDS := {
	"marker": Vector3(0.0, 0.0, 0.0),
	"back": Vector3(-1.6, 0.0, 0.0),
	"side": Vector3(-0.4, 1.3, 0.0),
	"case": Vector3(0.2, 0.9, -0.5),
}

var _night: Night
var _out := ""
var _stand := "marker"
var _yaw := 0.0
var _args := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		_args[arg.trim_prefix("--").get_slice("=", 0)] = (
			arg.get_slice("=", 1) if "=" in arg else "1"
		)
	_out = String(_args.get("out", OS.get_user_data_dir()))
	_stand = String(_args.get("stand", "marker"))
	DirAccess.make_dir_recursive_absolute(_out)
	var phone := _args.has("phone")
	if phone:
		TouchMode.device_is_touch = true
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	if phone:
		var controls := TouchControls.new()
		controls.state = hud.state
		layer.add_child(controls)
	add_child(layer)
	var tuning := (
		(load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).duplicate(true) as RulesTuning
	)
	tuning.crane.leave_chances = PackedFloat32Array([0.0])
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.ticked.connect(_send)
	var rules := _night.server.rules
	_night.state.apply_events(rules.apply(RulesAction.skip_break()))
	_night.state.apply_events(rules.apply(RulesAction.grant_points(1, 90000)))
	_night.state.apply_events(rules.apply(RulesAction.buy(1, &"door_concession")))
	_night.player().camera_rig.camera().make_current()
	await _hold(5)
	_stand_at_crane()
	await _hold(SETTLE)
	await _shot("rest")
	var pool: Array[StringName] = rules.tuning.economy.item(&"crane_play").pool
	for weapon in pool:
		await _play(weapon)
	await _dud()
	get_tree().quit()


## Stands the player on `_stand` of the crane's marker, looking level at the machine's middle.
func _stand_at_crane() -> void:
	var at := _crane_marker()
	var crane_at: Vector3 = _night.view.crane.crane.global_position
	var standing := at["position"] as Vector3
	var toward := Vector3(crane_at.x - standing.x, 0.0, crane_at.z - standing.z).normalized()
	var across := Vector3(toward.z, 0.0, -toward.x)
	var offset: Vector3 = STANDS.get(_stand, Vector3.ZERO)
	var place := standing + toward * offset.x + across * offset.y
	_night.player().teleport(place + Vector3(0.0, 0.1, 0.0))
	var look := crane_at - place
	_yaw = atan2(-look.x, -look.z)
	_night.player().camera_rig.yaw = _yaw
	_night.player().camera_rig.pitch = offset.z


## One play that gives `weapon`: the spin (a picture of the cycling on the first), then the prize
## out of the machine. The rules draw the prize; the capture names it, so every weapon is filmed.
func _play(weapon: StringName) -> void:
	var rules := _night.server.rules
	_night.state.apply_events(_night.server.buy(1, &"crane_play"))
	var spin := int(rules.tuning.crane.spin_seconds * 60.0)
	await _hold(spin / 2)
	if weapon == rules.tuning.economy.item(&"crane_play").pool[0]:
		await _shot("spin")
	while rules.crane.stage == CraneState.Stage.SPIN:
		await _hold(1)
	rules.crane.weapon = weapon
	await _hold(SHOT_AFTER)
	await _shot(String(weapon).trim_prefix("weapon_"))
	# Let the window run out at once: the next play starts from a ready crane.
	rules.crane.left = 0.01
	await _hold(30)


## A play that breaks the crane down: the dud on show.
func _dud() -> void:
	var rules := _night.server.rules
	_night.state.apply_events(_night.server.buy(1, &"crane_play"))
	rules.crane.breaks = true
	while rules.crane.stage == CraneState.Stage.SPIN:
		await _hold(1)
	await _hold(45)
	await _shot("dud")


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join("%s_%s.png" % [_stand, label])
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s" % path)


func _crane_marker() -> Dictionary:
	for spot in _night.world.shop_spots():
		if spot["kind"] == &"crane" and spot["crane_spot"] == _night.server.rules.crane.spot:
			return spot
	return {}


func _send() -> void:
	var command := NightCommand.new()
	command.motion.yaw = _yaw
	_night.link.send(command.to_dict())
	_night.player().camera_rig.yaw = _yaw


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
