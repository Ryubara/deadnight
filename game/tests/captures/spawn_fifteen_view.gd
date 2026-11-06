extends Node
## Where the 15 bodies of a full room stand at the start of a night (#1193): 8 people and 7 bots
## on the map, drawn, seen from above with each seat's number over its head, one picture. Not part
## of the game.
##
##     gds godot -- --path game res://tests/captures/spawn_fifteen_view.tscn --resolution 1280x720
##         -- --out=<abs>/spawn.png [--map=drive_in] [--height=24] [--back=1.5] [--people=8]
##            [--bots=7]
##
## Two bodies on one spot show as one soldier with two numbers over it (the numbers are drawn a
## little apart in height so both can be read).

const SETTLE_FRAMES := 20
const SEED := 1193

var _args := NetArgs.new()


func _ready() -> void:
	var map_id := _args.get_string("map", MapRegistry.DEFAULT)
	var people := clampi(_args.get_int("people", NightHost.MAX_PLAYERS), 1, NightHost.MAX_PLAYERS)
	var bots := clampi(_args.get_int("bots", MatchSettings.MAX_BOTS), 0, MatchSettings.MAX_BOTS)
	var world := NightWorld.new()
	add_child(world)
	await world.build(MapRegistry.of(map_id))
	var settings := MatchSettings.new()
	settings.map = map_id
	var tuning := (load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).duplicate(true)
	tuning.rounds.first_spawn_delay = 600.0
	var server := NightServer.new(world, SEED, null, world.rules_for(tuning), settings)
	for id in range(1, people + 1):
		server.apply({"type": NightServer.JOIN, "player_id": id, "local": false})
	server.apply({"type": NightServer.START_NIGHT})
	var seated := NightBots.new(server, world, SEED, func(_events: Array) -> void: pass)
	seated.fill(bots)
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	var ids: Array[int] = []
	for id: int in server.rules.players:
		ids.append(id)
	var centre := Vector3.ZERO
	for id in ids:
		centre += server.body_of(id).global_position
	centre /= ids.size()
	# A roofed map is seen from above with its ceilings and roof taken off.
	for name in ["Ceilings", "Roof"]:
		for node in world.find_children(name, "Node3D", true, false):
			(node as Node3D).visible = false
	_label(server, ids)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 40.0
	camera.global_position = (
		centre + Vector3(0.0, _args.get_float("height", 24.0), _args.get_float("back", 1.5))
	)
	camera.look_at(centre, Vector3.UP)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	var out := _args.get_string("out")
	if not out.is_empty():
		get_viewport().get_texture().get_image().save_png(out)
	for id in ids:
		print("seat ", id, " at ", server.body_of(id).global_position)
	get_tree().quit()


## A number over each body: the seat's id, people 1 to 8 and bots 101 and up shown as B1 to B7.
func _label(server: NightServer, ids: Array[int]) -> void:
	for id in ids:
		var label := Label3D.new()
		label.text = str(id) if id < NightBots.FIRST_ID else "B%d" % NightBots.number_of(id)
		label.font_size = 96
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color.WHITE if id < NightBots.FIRST_ID else Color(1.0, 0.8, 0.2)
		label.outline_size = 24
		var body := server.body_of(id)
		body.add_child(label)
		label.position = Vector3(0.0, 2.3 + (0.35 if id >= NightBots.FIRST_ID else 0.0), 0.0)
