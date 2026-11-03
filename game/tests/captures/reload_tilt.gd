extends Node
## A gun reloading in a real night, from the shoulder camera with the body seen side-on, with the
## numbers of the weapon's pitch and the sounds it makes. One shot at `SHOT_AT`, the reload
## pressed at `RELOAD_AT`, the whole thing on a timeline of physics seconds. Not part of the
## game. Two ways to run it (`--weapon=rifle` or any catalogue gun, `--aim` to hold the aim):
##
## Frames and the mix (Movie Maker, fixed time step; the audio lands in the movie's .wav):
##     gds godot -- --path game res://tests/captures/reload_tilt.tscn --write-movie <abs>/r.png \
##         --fixed-fps 20 --resolution 1920x1080 -- --weapon=rifle
## Numbers (headless, `SAMPLE t pitch_deg dip` per tick on stdout):
##     godot --headless --path game res://tests/captures/reload_tilt.tscn
##         --fixed-fps 60 -- --weapon=rifle

const TICKS_PER_SECOND := 60.0
const LOOK_AWAY := 70.0
const START := Vector3(0.0, 0.05, -28.0)
const START_YAW := 180.0
const SHOT_AT := 0.3
const RELOAD_AT := 1.8
const END_AT := 6.0

var _ticks := 0
var _night: Night
var _weapon := &"rifle"
var _aim := false
var _hands: WeaponHandsIK
var _animation: PlayerAnimation
var _shot := false
var _reloaded := false
var _looked := false


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--weapon="):
			_weapon = StringName(argument.trim_prefix("--weapon="))
		elif argument == "--aim":
			_aim = true
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	_night.server.combat.apply(CombatAction.give_weapon(1, _weapon))
	_night.server.combat.apply(CombatAction.equip(1, _weapon))
	# One round left, so the shot at SHOT_AT empties the magazine and the reload has work to do.
	_night.server.combat.state_of(1, _weapon).ammo = 1
	var player := _night.player()
	player.capture_mouse = false
	player.local_input = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.teleport(START)
	player.state.facing = deg_to_rad(START_YAW)
	player.rotation.y = player.state.facing
	player.camera_rig.yaw = player.state.facing
	_ticks = 0


func _physics_process(_delta: float) -> void:
	if _night == null or not _night.running:
		return
	var player := _night.player()
	if _hands == null:
		_hands = _find_hands(player)
		_animation = player.get_node_or_null(^"AnimationTree") as PlayerAnimation
		if _hands == null or _animation == null:
			return
	var now := _ticks / TICKS_PER_SECOND
	_ticks += 1
	# The view turns away after the shot's hold is over, so the body is seen side-on, in the hip pose.
	if now >= RELOAD_AT - 0.1 and not _looked:
		_looked = true
		player.camera_rig.apply_look(deg_to_rad(LOOK_AWAY), 0.0)
		if _aim:
			Input.action_press("aim")
	if now >= SHOT_AT and not _shot:
		_shot = true
		_stage("shot", now)
		Input.action_press("fire")
	if _shot and now >= SHOT_AT + 0.1:
		Input.action_release("fire")
	if now >= RELOAD_AT and not _reloaded:
		_reloaded = true
		_stage("reload", now)
		Input.action_press("reload")
	if _reloaded and now >= RELOAD_AT + 0.1:
		Input.action_release("reload")
	_sample(now)
	if now >= END_AT:
		Input.action_release("aim")
		get_tree().quit()


func _stage(stage_name: String, now: float) -> void:
	print("STAGE %s %.3f frame=%d" % [stage_name, now, Engine.get_frames_drawn()])


func _sample(now: float) -> void:
	var barrel := -_hands.weapon_target().basis.x
	print(
		(
			"SAMPLE %.4f pitch=%.3f reload=%.4f aim=%.4f"
			% [
				now,
				rad_to_deg(asin(clampf(barrel.y, -1.0, 1.0))),
				_animation.reload_weight(),
				_night.player().camera_rig.aim_amount()
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
