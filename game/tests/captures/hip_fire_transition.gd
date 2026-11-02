extends Node
## The shoulder camera and the held weapon through a hip-fire burst and through an aim press, in a
## real night (HUD over it), with the numbers that say how smooth it is. Real input actions on a
## timeline of physics seconds, so the same script films the game before and after a change. Not
## part of the game. Two ways to run it:
##
## Frames (Movie Maker, fixed time step):
##     gds godot -- --path game res://tests/captures/hip_fire_transition.tscn \
##         --write-movie <abs>/hip.png --fixed-fps 20 --resolution 1280x720 -- --scenario=fire
## Numbers (headless, one CSV line per physics tick on stdout, `SAMPLE ...`):
##     godot --headless --path game res://tests/captures/hip_fire_transition.tscn --fixed-fps 60 \
##         -- --scenario=fire
##
## `--scenario=fire` holds the trigger without aiming, `--scenario=aim` holds the aim button.
## `STAGE <name> <seconds> frame=<n>` lines mark the stages (the movie's frame number, which starts
## before the night does); the view is turned `LOOK_AWAY` degrees from the
## body just before, so the body has to turn to it (the old weapon pose jumped by that much).

const TICKS_PER_SECOND := 60.0
## The view is turned this far to the right of the body, in degrees.
const LOOK_AWAY := 75.0
## Where the player stands in the avenue and which way the body and view face, degrees (180 is
## down the lot, toward the road).
const START := Vector3(0.0, 0.05, -28.0)
const START_YAW := 180.0
const WEAPON := &"rifle"
const PRESS_AT := 1.8
const RELEASE_AT := 3.0
const END_AT := 6.0

var _ticks := 0
var _night: Night
var _scenario := "fire"
var _hands: WeaponHandsIK
var _pressed := false
var _released := false
var _looked := false
var _staged := {}


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="):
			_scenario = argument.trim_prefix("--scenario=")
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	# The starting pistol has no shouldered hold yet: the lever rifle is the gun that shows the pose.
	_night.server.combat.apply(CombatAction.give_weapon(1, WEAPON))
	_night.server.combat.apply(CombatAction.equip(1, WEAPON))
	var player := _night.player()
	player.capture_mouse = false
	# The machine's real mouse must not turn the camera between two runs.
	player.local_input = false
	# The player node captured the mouse when it came into the tree (before the two flags above
	# could be set): give the cursor back at once, and never take it again.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.teleport(START)
	player.state.facing = deg_to_rad(START_YAW)
	player.rotation.y = player.state.facing
	player.camera_rig.yaw = player.state.facing
	_ticks = 0


func _physics_process(_delta: float) -> void:
	if _night == null or not _night.running:
		return
	if _hands == null:
		_hands = _find_hands(_night.player())
		if _hands == null:
			return
	var now := _ticks / TICKS_PER_SECOND
	_ticks += 1
	var player := _night.player()
	if now >= 1.0 and not _looked:
		_looked = true
		_stage("look_away", now)
		player.camera_rig.apply_look(deg_to_rad(LOOK_AWAY), 0.0)
	if now >= PRESS_AT and not _pressed:
		_pressed = true
		_stage("press_" + _scenario, now)
		Input.action_press("fire" if _scenario == "fire" else "aim")
	if now >= RELEASE_AT and not _released:
		_released = true
		_stage("release", now)
		Input.action_release("fire")
		Input.action_release("aim")
	_sample(player, now)
	if now >= END_AT:
		get_tree().quit()


func _stage(stage_name: String, now: float) -> void:
	if not _staged.has(stage_name):
		_staged[stage_name] = true
		print("STAGE %s %.3f frame=%d" % [stage_name, now, Engine.get_frames_drawn()])


func _sample(player: Player, now: float) -> void:
	var rig := player.camera_rig
	# The recoil kick is one frame by design: measure the pose without it.
	var kick := _hands.recoil
	_hands.recoil = 0.0
	var target := _hands.weapon_target()
	_hands.recoil = kick
	var barrel := -target.basis.x
	print(
		(
			"SAMPLE %.4f fov=%.4f lens=%.4f hand=%.5f,%.5f,%.5f barrel=%.5f,%.5f,%.5f body=%.4f view=%.4f"
			% [
				now,
				rig.camera().fov,
				rig.lens_distance(),
				target.origin.x,
				target.origin.y,
				target.origin.z,
				barrel.x,
				barrel.y,
				barrel.z,
				player.rotation.y,
				rig.yaw,
			]
		)
	)


func _find_hands(node: Node) -> WeaponHandsIK:
	if node is WeaponHandsIK:
		return node
	for child in node.get_children():
		var found := _find_hands(child)
		if found != null:
			return found
	return null
