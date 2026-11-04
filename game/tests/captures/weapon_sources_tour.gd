extends Node
## Every weapon taken the way a player takes it (#904): the crane's prize with `use` at the crane
## spot and a wall weapon with `use` at its wall, in the real night with the real HUD. After each
## take the window is saved (`<out>/<tag>_<weapon>.png`) and the line printed says what the server,
## the frame the client reads and the HUD's slots hold.
##
## `gds godot -- --path game res://tests/captures/weapon_sources_tour.tscn --resolution 1280x720 --
## --out=<folder> --tag=after [--only=mp5,ppsh]`.

const SETTLE_FRAMES := 24
const SPIN_TICKS := 300
const PLAYER := 1

var _out := ""
var _tag := "tour"
var _night: Night
var _hud: Hud


func _ready() -> void:
	var args := _args()
	_out = String(args.get("out", "user://"))
	_tag = String(args.get("tag", "tour"))
	DirAccess.make_dir_recursive_absolute(_out)
	var only: PackedStringArray = String(args.get("only", "")).split(",", false)
	await _run(only)
	get_tree().quit()


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found


func _run(only: PackedStringArray) -> void:
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(_hud)
	add_child(layer)
	var tuning := RulesFixture.steady_crane_tuning()
	tuning.crane.spin_seconds = 1.0
	_night = Night.new()
	_night.hud = _hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	_night.player().camera_rig.camera().make_current()
	await _settle()
	var crane := tuning.economy.item(&"crane_play")
	var prizes: Array[StringName] = []
	for prize in crane.pool:
		prizes.append(WeaponCatalog.catalog_id(prize))
	for id in prizes:
		if (
			(not only.is_empty() and not only.has(String(id)))
			or _night.server.combat.carried(PLAYER).has(id)
		):
			continue
		crane.pool.assign([StringName(WeaponCatalog.SHOP_PREFIX + String(id))])
		crane.pool_weights = PackedFloat32Array([1.0])
		_night.server.rules.apply(RulesAction.grant_points(PLAYER, 5000))
		await _stand(_spot(&"crane"))
		_use()
		_night.state.apply_events([])
		for _i in SPIN_TICKS:
			_night.tick()
		await _stand(_spot(&"crane"))
		_use()
		await _settle()
		await _shot("crane_%s" % id)
	for shop_id in [&"weapon_shotgun", &"weapon_rifle"]:
		var id := WeaponCatalog.catalog_id(shop_id)
		if not only.is_empty() and not only.has(String(id)):
			continue
		_night.server.combat.apply(CombatAction.remove_weapons(PLAYER, [id]))
		_night.server.rules.players[PLAYER].weapons.erase(shop_id)
		_night.server.rules.apply(RulesAction.grant_points(PLAYER, 5000))
		await _stand(_spot(&"wall", shop_id))
		_use()
		await _settle()
		await _shot("wall_%s" % id)


func _spot(kind: StringName, shop_id: StringName = &"") -> Dictionary:
	for spot in _night.world.shop_spots():
		if spot["kind"] != kind:
			continue
		if kind == &"crane" and spot["crane_spot"] != _night.server.rules.crane.spot:
			continue
		if shop_id == &"" or spot["shop_id"] == shop_id:
			return spot
	return {}


func _stand(spot: Dictionary) -> void:
	_night.player().teleport(spot["position"] + Vector3(0.0, 0.1, 0.0))
	for _i in 3:
		_night.tick()
	await get_tree().process_frame


func _use() -> void:
	var command := NightCommand.new()
	command.use = true
	_night.link.send(command.to_dict())
	for _i in 4:
		_night.tick()


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		_night.tick()
		await get_tree().process_frame


func _shot(stage: String) -> void:
	await RenderingServer.frame_post_draw
	var me := _night.state.me()
	print(
		(
			"STAGE %s in hand %s, server %s, arms %s, hud slots %s held %d"
			% [
				stage,
				me["weapon"],
				_night.server.combat.carried(PLAYER),
				me["arms"].keys(),
				_hud.state.slot_ids,
				_hud.state.slot_held,
			]
		)
	)
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, stage])
