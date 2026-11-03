class_name SmallMapWalkers
extends Node3D
## Real player bodies (`Player`, `PlayerSimulation`) walking the second map's greybox with every
## link open, each from goal to goal along the zombies' mesh: the ring, both stairs, the door, the
## opening upstairs, round the counter and the racks. What it shows is that the walking mesh and
## the collision agree (a body follows every path the mesh offers, on the stairs too) and that
## nobody leaves the building. Used by `test_smallmap_walk.gd` (a short run) and
## `res://tests/captures/smallmap_move_soak.tscn` (a long one, and its numbers).

const SCENE := SmallMapMeasure.SCENE
const PLAYER_SCENE := preload("res://gameplay/player/player.tscn")
## A goal is reached this close (metres, on the ground plane, on its floor).
const REACHED := 0.8
## Ticks between two path queries of a body.
const REPATH_TICKS := 30
## A body that walked less than `STUCK_METRES` in this many ticks (half a second) is stuck: it
## walks 3.5 to 5 m a second.
const STUCK_TICKS := 30
const STUCK_METRES := 0.5
## A leg that takes longer than this many ticks is given up.
const LEG_TICKS := 60 * 40
## The bodies' physics layer: no wall's and no body's mask has it.
const WALKER_LAYER := 1 << 9

var lot: Node3D
var nav: SmallMapNavigation
## Per body: {body, goal, path, next, ticks, best, best_tick, legs, reached, failed, stuck_ticks,
## episodes, longest_stuck, outside}.
var walkers: Array[Dictionary] = []
var goals: Array[Vector3] = []
var ticks := 0

var _rng := RandomNumberGenerator.new()
var _rects: Array[Rect2] = []
var _floors: Array[float] = []


## Builds the map with every link open, its mesh, and `count` bodies at the players' spawns.
func setup(count: int, seed_value: int) -> void:
	_rng.seed = seed_value
	lot = (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(lot)
	for _i in 4:
		await get_tree().physics_frame
	var doors := lot.get_node("Doors") as LotDoors
	for door in doors.get_children():
		doors.open(StringName(door.get_meta(&"shop_id")))
	for _i in 4:
		await get_tree().physics_frame
	nav = SmallMapNavigation.new(lot, SmallMapNavigation.zombie_mesh())
	await nav.settle(get_tree())
	for group: String in SmallMapMeasure.GROUPS:
		var room := lot.get_node(group)
		_rects.append(room.get_meta(&"rect"))
		_floors.append(float(room.get_meta(&"floor")))
	_collect_goals()
	var spawns := lot.get_node("PlayerSpawns").get_children()
	for i in count:
		var body := PLAYER_SCENE.instantiate() as Player
		body.local_input = false
		body.capture_mouse = false
		body.strip_model()
		# On a layer of their own, out of each other's way: what is measured is the map against
		# one body (the walls, the stairs, the doorways), not how two steer round each other on a
		# stair, which is the bots' business (in a first soak two bodies stood on each other for
		# 36 s halfway up a stair).
		body.collision_layer = WALKER_LAYER
		add_child(body)
		body.teleport((spawns[i % spawns.size()] as Node3D).global_position + Vector3.UP * 0.1)
		body.set_physics_process(false)
		var walker := {
			"body": body,
			"path": PackedVector3Array(),
			"next": 0,
			"ticks": 0,
			"legs": 0,
			"reached": 0,
			"failed": 0,
			"stuck_ticks": 0,
			"episodes": 0,
			"longest_stuck": 0,
			"outside": 0,
			"metres": 0.0,
			"last": body.global_position,
			"failures": [],
			"stuck_at": [],
		}
		walkers.append(walker)
		_new_goal(walker)


## Goals: each room's middle, the ring's markers and the loops' corners, so every leg crosses the
## map's narrow places.
func _collect_goals() -> void:
	for group_path: String in [
		"Measure/Middles", "Measure/Ring", "Measure/LoopStart", "Measure/LoopSide"
	]:
		for marker: Node3D in lot.get_node(group_path).get_children():
			goals.append(marker.global_position)


func _new_goal(walker: Dictionary) -> void:
	var body := walker["body"] as Player
	var goal := goals[_rng.randi_range(0, goals.size() - 1)]
	while SmallMapNavigation.flat(goal, body.global_position) < 4.0:
		goal = goals[_rng.randi_range(0, goals.size() - 1)]
	walker["goal"] = goal
	walker["ticks"] = 0
	walker["mark"] = body.global_position
	walker["stuck"] = false
	walker["legs"] += 1
	_repath(walker)


func _repath(walker: Dictionary) -> void:
	walker["path"] = nav.path((walker["body"] as Player).global_position, walker["goal"])
	walker["next"] = 1


## One tick of every body.
func step() -> void:
	ticks += 1
	for walker in walkers:
		_step(walker)


func _step(walker: Dictionary) -> void:
	var body := walker["body"] as Player
	var at := body.global_position
	var goal: Vector3 = walker["goal"]
	walker["ticks"] += 1
	walker["metres"] += SmallMapNavigation.flat(at, walker["last"])
	walker["last"] = at
	if not _inside(at):
		walker["outside"] += 1
	if SmallMapNavigation.flat(at, goal) < REACHED and absf(at.y - goal.y) < 1.0:
		walker["reached"] += 1
		_end_stuck(walker)
		_new_goal(walker)
		return
	if walker["ticks"] > LEG_TICKS:
		walker["failed"] += 1
		walker["failures"].append("%s to %s" % [at.snapped(Vector3.ONE * 0.1), goal])
		_end_stuck(walker)
		_new_goal(walker)
		return
	# Stuck: less than `STUCK_METRES` walked in the last `STUCK_TICKS` (a body walking round the
	# ring may be no nearer its goal for a long time, and is not stuck).
	if walker["ticks"] % STUCK_TICKS == 0:
		if SmallMapNavigation.flat(at, walker["mark"]) < STUCK_METRES:
			walker["stuck_ticks"] += STUCK_TICKS
			if not walker["stuck"]:
				walker["stuck"] = true
				walker["episodes"] += 1
				walker["stuck_from"] = walker["ticks"] - STUCK_TICKS
				walker["stuck_at"].append(
					"%s on the way to %s" % [at.snapped(Vector3.ONE * 0.1), goal]
				)
		else:
			_end_stuck(walker)
		walker["mark"] = at
	if walker["ticks"] % REPATH_TICKS == 0:
		_repath(walker)
	var path: PackedVector3Array = walker["path"]
	var target := goal
	while walker["next"] < path.size():
		var corner := path[walker["next"]]
		if SmallMapNavigation.flat(corner, at) > 0.35:
			target = corner
			break
		walker["next"] += 1
	var command := PlayerCommand.new()
	var dx := target.x - at.x
	var dz := target.z - at.z
	command.yaw = atan2(-dx, -dz)
	command.move = Vector2(0.0, -1.0)
	body.tick(command)


func _end_stuck(walker: Dictionary) -> void:
	if walker.get("stuck", false):
		walker["stuck"] = false
		var length: int = walker["ticks"] - int(walker["stuck_from"])
		walker["longest_stuck"] = maxi(walker["longest_stuck"], length)


## Whether `at` is inside a room of the building, or in a doorway or on a stair between them.
func _inside(at: Vector3) -> bool:
	var flat := Vector2(at.x, at.z)
	for i in _rects.size():
		if _rects[i].grow(0.35).has_point(flat) and at.y > _floors[i] - 0.5:
			return true
	return false


## The walkers' numbers: per body, and for all.
func report() -> Dictionary:
	var bodies := []
	var total := {"legs": 0, "reached": 0, "failed": 0, "episodes": 0, "outside": 0, "metres": 0.0}
	var longest := 0
	for walker in walkers:
		_end_stuck(walker)
		(
			bodies
			. append(
				{
					"legs": walker["legs"] - 1,
					"reached": walker["reached"],
					"failed": walker["failed"],
					"stuck_episodes": walker["episodes"],
					"stuck_seconds": walker["stuck_ticks"] / 60.0,
					"longest_stuck_seconds": walker["longest_stuck"] / 60.0,
					"outside_ticks": walker["outside"],
					"metres": snappedf(walker["metres"], 0.1),
					"failures": walker["failures"],
					"stuck_at": walker["stuck_at"],
				}
			)
		)
		for key: String in ["reached", "failed", "episodes", "outside"]:
			total[key] += walker[key]
		total["legs"] += walker["legs"] - 1
		total["metres"] += walker["metres"]
		longest = maxi(longest, walker["longest_stuck"])
	total["longest_stuck_seconds"] = longest / 60.0
	total["ticks"] = ticks
	total["metres"] = snappedf(total["metres"], 0.1)
	return {"bodies": bodies, "all": total}


func _exit_tree() -> void:
	if nav != null:
		nav.free_map()
		nav = null
