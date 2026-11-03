extends Node
## Does a player standing still on a place the dead cannot walk to get struck? (#833)
## Puts the player at `--at=x,y,z` in a real night of a map (`--scene`), starts a round, puts
## `--dead` of the dead in the open, chasing, and runs `--seconds` of the night by hand. Prints
## the blows that landed (`player_hurt`), the nearest any zombie got, and where the player stood.
##
##   godot --headless --path game res://tools/world/roost_probe.tscn -- \
##     --scene=res://world/smallmap/smallmap_greybox.tscn --at=8,1.25,6.25 --dead=10 --seconds=40
##
## `--speed` is the dead's walking pace in m/s (2.4, a mid-night walker; the first version put them
## down with no pace at all, so they never closed in). `--doors=all` sells every door first (the
## lot's plaza and yard are behind doors), or name the door ids, separated by commas.

var _hurts := 0


func _ready() -> void:
	var scene_path := ""
	var at := Vector3.ZERO
	var dead := 10
	var seconds := 40.0
	var speed := 2.4
	var doors := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--at="):
			var parts := argument.trim_prefix("--at=").split(",")
			at = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		elif argument.begins_with("--dead="):
			dead = int(argument.trim_prefix("--dead="))
		elif argument.begins_with("--seconds="):
			seconds = float(argument.trim_prefix("--seconds="))
		elif argument.begins_with("--speed="):
			speed = float(argument.trim_prefix("--speed="))
		elif argument.begins_with("--doors="):
			doors = argument.trim_prefix("--doors=")
	var seated := await SeatedNight.start(self, 1, null, 7, false, load(scene_path) as PackedScene)
	seated.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"player_hurt":
			_hurts += 1
	if doors != "":
		_open_doors(seated, doors)
		for _i in 30:
			seated.tick()
			await get_tree().physics_frame
	seated.start_round()
	for _i in 4:
		await get_tree().physics_frame
	var body := seated.server.body_of(1)
	body.teleport(at)
	for _i in 30:
		seated.tick()
		await get_tree().physics_frame
	var stood := body.global_position
	var floor_at := _hall_ring(at, dead)
	var zombies: Array = []
	for i in floor_at.size():
		var zombie := seated.server.sim.spawn(7000 + i, speed, floor_at[i])
		zombie.enter(ZombieBody.Mode.CHASE)
		zombies.append(zombie)
	var nearest := INF
	var ticks := int(seconds * 60.0)
	for tick in ticks:
		seated.tick()
		if tick % 4 == 0:
			await get_tree().physics_frame
		for zombie in zombies:
			var apart := (
				Vector2(
					zombie.position.x - body.global_position.x,
					zombie.position.z - body.global_position.z
				)
				. length()
			)
			nearest = minf(nearest, apart)
	print(
		"ROOST at ",
		at,
		" stood ",
		stood,
		" ended ",
		body.global_position,
		" blows ",
		_hurts,
		" nearest zombie (flat) ",
		snappedf(nearest, 0.01),
		" dead ",
		zombies.size(),
		" speed ",
		speed,
		" health ",
		seated.server.rules.players[1].health
	)
	seated.dispose()
	get_tree().quit()


## Places for the dead: a ring about the player's spot, at 4 to 7 m, kept where the floor is.
func _hall_ring(centre: Vector3, count: int) -> Array[Vector3]:
	var places: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tries := 0
	while places.size() < count and tries < 2000:
		tries += 1
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(3.0, 7.0)
		var point := Vector3(centre.x + cos(angle) * radius, 0.0, centre.z + sin(angle) * radius)
		var map := get_viewport().find_world_3d().navigation_map
		var snapped := NavigationServer3D.map_get_closest_point(map, point)
		if Vector2(snapped.x - point.x, snapped.z - point.z).length() < 0.3 and snapped.y < 0.5:
			places.append(snapped)
	return places


## Sells the doors asked for (`all`, or ids), each after the one it needs.
func _open_doors(seated: SeatedNight, doors: String) -> void:
	var rules := seated.server.rules
	rules.apply(RulesAction.grant_points(1, 100000))
	for _pass in 4:
		for item: ShopItem in rules.tuning.economy.items:
			var wanted := doors == "all" or doors.split(",").has(String(item.id))
			if wanted and item.kind == ShopItem.Kind.DOOR and not rules.is_door_open(item.id):
				rules.apply(RulesAction.buy(1, item.id))
