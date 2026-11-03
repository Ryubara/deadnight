extends Node
## Player B's screen in a night on a game server (a real WebSocket on this machine), with player A,
## who is driven by hand from another client, standing in B's view with the dual pistols (#789):
## holding them, aiming, firing (a beat for each hand's shot), reloading, sprinting and the quick
## melee. One png per beat shows what B sees of A. Not part of the game.
##
##     gds godot -- --path game res://tests/captures/online_dual_pistols.tscn --resolution 1280x720
##         -- --out=<abs folder>
##
## Options after `--`: `--out=<folder>` (the folder the pngs are written to, then quit).

## Where A stands from B, metres: ahead and to the side, in the shoulder camera's view.
const AHEAD := 2.7
const ASIDE := 0.9
## B's distance south of the lamp post.
const BACK := 7.5
## A faces this far round from away from B's camera (PI faces it), so B sees the weapon side on
## and the front of A: three quarters.
const A_FACING := 2.4
## B joins first, so B is player 1 and A player 2.
const B_ID := 1
const WEAPON := &"dual_pistols"
const A_ID := 2

var _host: NightHost
var _a: Night
var _b: Night
var _command := NightCommand.new()
var _out := ""


func _ready() -> void:
	var args := NetArgs.new()
	_out = args.get_string("out")
	var server_world := _world()
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 5
	server_world.add_child(_host)
	while not _host.serving:
		await get_tree().physics_frame
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	# B is this window: a human's body and camera.
	_b = Night.new()
	_b.own_look = CharacterLook.from_preset(5)
	add_child(_b)
	await _b.start_remote(url, Night.Mode.HUMAN, 30.0)
	# A is hand driven, in a world of its own that is never drawn.
	_a = Night.new()
	_a.own_look = CharacterLook.from_preset(2)
	_world().add_child(_a)
	await _a.start_remote(url, Night.Mode.MANUAL, 30.0)
	_a.ticked.connect(func() -> void: _a.link.send(_command.to_dict()))
	_stand()
	_host.server.combat.apply(CombatAction.give_weapon(A_ID, WEAPON))
	_host.server.combat.apply(CombatAction.equip(A_ID, WEAPON))
	await _frames(60)
	await _beat("1_hold")
	_command.motion.aim = true
	await _frames(40)
	await _beat("2_aim")
	# The hands alternate: one frame of each is the point, so each beat waits for the next shot.
	_command.fire = true
	await _until_shot(0)
	await _beat("3_fire_right", false)
	await _until_shot(1)
	await _beat("4_fire_left", false)
	_command.fire = false
	_command.motion.aim = false
	await _frames(30)
	_host.server.combat.state_of(A_ID, WEAPON).ammo = 8
	await _tap_reload()
	await _frames(14)
	await _beat("5_reload_start")
	await _frames(14)
	await _beat("6_reload_open")
	await _frames(90)
	_command.motion.move = Vector2(0.0, -1.0)
	_command.motion.sprint = true
	await _frames(14)
	await _beat("7_sprint")
	_command.motion.move = Vector2.ZERO
	_command.motion.sprint = false
	await _frames(20)
	_stand()
	await _frames(40)
	_command.motion.melee = true
	await _until_clip("Strike_")
	await _frames(4)
	await _beat("8_strike")
	_command.motion.melee = false
	await _frames(30)
	if _out != "":
		print("SAVED ", _out)
	get_tree().quit()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


## B stands a few metres south of the first lamp post, looking at it; A is put ahead and to B's
## right, turned to show its gun.
func _stand() -> void:
	var lamp: Node3D = _host.world.greybox.get_node("Field/Lamps/Lamp1")
	var here := Vector3(lamp.global_position.x - ASIDE, 0.0, lamp.global_position.z + BACK)
	_host.server.body_of(B_ID).teleport(here)
	var spot := Vector3(here.x + 2.0 * ASIDE, here.y, here.z - AHEAD)
	var body: Player = _host.server.body_of(A_ID)
	body.teleport(spot)
	body.state.facing = A_FACING
	body.rotation.y = A_FACING
	# The shot goes where A's view points (the server refuses one that does not).
	_command.aim_along(NightServer.view_dir(A_FACING, 0.0))
	_command.origin = body.global_position + Vector3(0.0, 1.4, 0.0)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


## Waits until the clip of A's upper body on B's screen starts with `prefix` (about two seconds).
func _until_clip(prefix: String) -> void:
	for _i in 120:
		var pose := _pose()
		if pose != null and String(pose.action_clip).begins_with(prefix):
			return
		await get_tree().physics_frame


## Waits until the shot of A's `hand` is the one on B's screen: the flash of that gun is up.
func _until_shot(hand: int) -> void:
	for _i in 120:
		var pose := _pose()
		var muzzle := pose.muzzle_point(hand) if pose != null else null
		var flash := muzzle.get_node_or_null(NodePath(MuzzleFlash.NODE_NAME)) if muzzle else null
		if flash != null and (flash as MuzzleFlash).is_up():
			print("SHOT hand %d after %d frames" % [hand, _i])
			return
		await get_tree().physics_frame
	print(
		(
			"NO SHOT for hand %d: clip %s ammo %d"
			% [
				hand,
				_pose().action_clip if _pose() else "-",
				_host.server.combat.weapon_of(A_ID).ammo
			]
		)
	)


func _pose() -> PlayerAnimation:
	var body := _b.avatars.avatar(A_ID)
	return body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body != null else null


func _tap_reload() -> void:
	_command.reload = true
	await _a.ticked
	_command.reload = false


func _beat(label: String, settle := true) -> void:
	if settle:
		await get_tree().process_frame
		await get_tree().process_frame
	else:
		# A flash lives a few frames: take the frame it was drawn in.
		await RenderingServer.frame_post_draw
	if _out == "":
		return
	DirAccess.make_dir_recursive_absolute(_out)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, label])
