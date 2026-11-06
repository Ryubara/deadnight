class_name NightTrace
extends Node
## A line of hashes for each tick of a night, so two runs of the same commit, seed and command can
## be compared tick by tick and the first tick (and part of the night) that differs named (#1350).
## Not part of the play: `AutopilotRun` adds one with `trace=PATH`.
##
## A line is `tick Z P R N S K` and then a few words for each body. Z hashes the dead (id, mode,
## place, yaw, target), P the bodies (place, health), R the rules (phase, round, the four dice's
## states), N the dead's paths, S the points, K is how many dead stand. The words of a body are its
## id, place, velocity, floor flag and health in full, and the colliders it touched in its last
## slide. Hashes of values, never of the time: the same night gives the same line. A `.meta` file
## beside the trace says which physics frame the first tick was.

var _night: Night
var _file: FileAccess
var _ticks := 0
var _every := 1
var _path := ""


func _init(night: Night, path: String, every: int = 1) -> void:
	_night = night
	_every = maxi(every, 1)
	_path = path
	_file = FileAccess.open(path, FileAccess.WRITE)
	night.ticked.connect(_on_ticked)


func _on_ticked() -> void:
	_ticks += 1
	if _ticks == 1:
		var meta := FileAccess.open(_path + ".meta", FileAccess.WRITE)
		meta.store_line(
			(
				"physics_frames %d process_frames %d ticks_msec %d"
				% [Engine.get_physics_frames(), Engine.get_process_frames(), Time.get_ticks_msec()]
			)
		)
		meta.close()
	if _ticks % _every != 0:
		return
	var server := _night.server
	var zombies := PackedFloat64Array()
	var paths := PackedFloat64Array()
	var ids: Array = server.sim.zombies.keys()
	ids.sort()
	for id: int in ids:
		var z: ZombieBody = server.sim.zombies[id]
		zombies.append_array(
			PackedFloat64Array(
				[id, z.mode, z.position.x, z.position.y, z.position.z, z.yaw, z.target_id]
			)
		)
		paths.append(z.path.size())
		for p in z.path:
			paths.append_array(PackedFloat64Array([p.x, p.y, p.z]))
	var bodies := PackedFloat64Array()
	var raw := ""
	var body_ids: Array = server.rules.players.keys()
	body_ids.sort()
	for id: int in body_ids:
		var body := server.body_of(id)
		if body != null:
			var at := body.global_position
			bodies.append_array(PackedFloat64Array([id, at.x, at.y, at.z, server.health_of(id)]))
			raw += (
				" "
				+ (
					(
						"%d:%s:%s:%s:%s"
						% [
							id,
							var_to_str(at),
							var_to_str(body.velocity),
							body.is_on_floor(),
							var_to_str(server.health_of(id))
						]
					)
					. replace(" ", "")
				)
			)
			raw += " " + _contact_text(body)
	var rules := server.rules
	var dice := [
		rules.phase,
		rules.round_number,
		rules._spawn_rng.state,
		rules._shop_rng.state,
		rules._cripple_rng.state,
		rules._crane_rng.state,
	]
	var points := PackedInt64Array()
	for id: int in body_ids:
		points.append((rules.players[id] as PlayerState).points)
	var line := (
		"%d %d %d %d %d %d %d"
		% [
			_ticks,
			hash(zombies),
			hash(bodies),
			hash(dice),
			hash(paths),
			hash(points),
			ids.size(),
		]
	)
	_file.store_line(line + raw)


func _exit_tree() -> void:
	if _file != null:
		_file.close()


## What a body touches after its last slide, for the trace of a body that stands still: the floor
## normal and each contact's collider and place (#1350).
static func _contact_text(body: CharacterBody3D) -> String:
	var text := "c:%d:%s" % [body.get_slide_collision_count(), var_to_str(body.get_floor_normal())]
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		text += (
			":%s@%s@%s"
			% [
				(hit.get_collider() as Node).get_path() if hit.get_collider() is Node else "?",
				var_to_str(hit.get_position()),
				var_to_str(hit.get_depth()),
			]
		)
	return text.replace(" ", "")
