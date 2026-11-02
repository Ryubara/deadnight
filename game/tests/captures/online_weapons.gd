extends Node
## Player B's screen in a night on a game server (a real WebSocket on this machine), with player A,
## who is driven by hand from another client, standing in B's view and doing what A can do with a
## weapon: hold the pistol, aim it, fire it, swap to the crowbar, swing it, put the pistol back and
## reload it, and cook and throw a grenade. One png per beat shows what B sees of A (#518). Not part
## of the game.
##
##     gds godot -- --path game res://tests/captures/online_weapons.tscn --resolution 1280x720
##         -- --out=<abs folder>
##
## Options after `--`: `--out=<folder>` (the folder the pngs are written to, then quit).

## Where A stands from B, metres: ahead and to the side, in the shoulder camera's view.
const AHEAD := 3.6
const ASIDE := 0.9
## B's distance south of the lamp post.
const BACK := 7.5
## A faces this far round from away from B's camera (PI faces it), so B sees the weapon side on
## and the front of A: three quarters.
const A_FACING := 2.4
## B joins first, so B is player 1 and A player 2.
const B_ID := 1
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
	await _frames(40)
	await _beat("1_hold_pistol")
	_command.motion.aim = true
	await _frames(40)
	await _beat("2_aim")
	_command.fire = true
	await _until_clip("Fire_")
	await _beat("3_fire")
	_command.fire = false
	_command.motion.aim = false
	await _frames(30)
	await _swap_to(&"crowbar")
	await _frames(30)
	await _beat("4_swap_crowbar")
	_command.fire = true
	await _until_clip("Swing_")
	await _frames(3)
	await _beat("5_swing")
	_command.fire = false
	await _frames(40)
	await _swap_to(&"pistol")
	await _frames(40)
	await _tap_reload()
	await _frames(14)
	await _beat("6_reload")
	await _frames(60)
	_host.server.rules.apply(RulesAction.skip_break())
	await _frames(30)
	_command.motion.throw_over = true
	await _frames(20)
	await _beat("7_grenade_cook")
	_command.motion.throw_over = false
	await _until_clip("Grenade_Throw")
	await _frames(8)
	await _beat("8_grenade_throw")
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
	_command.motion.yaw = A_FACING


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


func _pose() -> PlayerAnimation:
	var body := _b.avatars.avatar(A_ID)
	return body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body != null else null


func _swap_to(weapon: StringName) -> void:
	for _i in 4:
		if _host.server.combat.weapon_of(A_ID).def.id == weapon:
			return
		_command.swap = true
		await _a.ticked
		_command.swap = false
		await _frames(4)


func _tap_reload() -> void:
	_command.reload = true
	await _a.ticked
	_command.reload = false


func _beat(label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _out == "":
		return
	DirAccess.make_dir_recursive_absolute(_out)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, label])
