extends Node
## The seat of a player who left (#904), over a real socket on this machine: one person carries a
## re-cut M249 and MP5 and leaves, the next person takes the same seat. The window is that
## newcomer's screen with the real HUD; the line printed says what the server carries and what the
## frame told the newcomer. Before the fix the strip shows the leaver's guns beside the pistol;
## after it, the pistol alone.
##
## `gds godot -- --path game res://tests/captures/weapon_seat_tour.tscn --resolution 1280x720 --
## --out=<folder> --tag=after`.

const LEAVER := 2
const WAIT_SECONDS := 20.0

var _out := ""
var _tag := "seat"
var _host: NightHost


func _ready() -> void:
	var args := _args()
	_out = String(args.get("out", "user://"))
	_tag = String(args.get("tag", "seat"))
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()
	get_tree().quit()


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _until(condition: Callable) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > WAIT_SECONDS:
			return false
		await get_tree().physics_frame
	return true


func _run() -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.resume_within = 0.0
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving)
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	var first := Night.new()
	_world().add_child(first)
	await first.start_remote(url, Night.Mode.MANUAL, 30.0)
	var leaver := Night.new()
	var leaver_world := _world()
	leaver_world.add_child(leaver)
	await leaver.start_remote(url, Night.Mode.MANUAL, 30.0)
	await _until(func() -> bool: return leaver.state.me().has("arms"))
	var server := _host.server
	for id: StringName in [&"m249", &"mp5"]:
		server.combat.apply(CombatAction.give_weapon(LEAVER, id))
		server.rules.players[LEAVER].weapons.append(
			StringName(WeaponCatalog.SHOP_PREFIX + String(id))
		)
		server.combat.apply(CombatAction.upgrade_weapon(LEAVER, id))
	leaver_world.queue_free()
	await _until(func() -> bool: return not server.rules.players.has(LEAVER))
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var newcomer := Night.new()
	newcomer.hud = hud
	add_child(newcomer)
	await newcomer.start_remote(url, Night.Mode.MANUAL, 30.0)
	await _until(func() -> bool: return newcomer.state.me().has("arms"))
	for _i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var me := newcomer.state.me()
	print(
		(
			"SEAT %s: seat %d, server carries %s, rules say %s, the newcomer was told %s, HUD slots %s"
			% [
				_tag,
				newcomer.state.player_id,
				server.combat.carried(newcomer.state.player_id),
				server.rules.players[newcomer.state.player_id].weapons,
				me["arms"].keys(),
				hud.state.slot_ids,
			]
		)
	)
	get_viewport().get_texture().get_image().save_png("%s/%s_seat.png" % [_out, _tag])
