class_name SmallMapYard
extends Node3D
## The cold yard outside the second map, as loops in the world: wind in the bare trees at the
## yard's corners, the two fires, the power lines and the drive-in's road far off. Each is a
## 3D loop at its place in the backdrop (read off the scene, so it follows the picture), and each
## moves with the listener: inside, it is played from the window it comes in at, at the level
## `SmallMapWays` says (the way round, a boarded or open window, or a wall); outside it is where
## it is. A loop out of reach is stopped, and fades up when the listener comes back.

## The loops: sound id, the backdrop node it sits at (a path under the backdrop) and a height.
const FIRE_NODES: Array[String] = ["Fires/Wreck", "Fires/Barrel"]
const FIRE_LIFT := 1.6
const WIND_LIFT := 3.0
const WIRE_LIFT := 6.5
const WIND := &"yard_wind"
const FIRE := &"yard_fire"
const WIRE := &"yard_wire"
const ROAD := &"yard_road"
## The wind in each corner of the yard starts this far (seconds) into its loop, and at its own
## pitch, so the four are not one sound four times.
const WIND_OFFSETS: Array[float] = [0.0, 6.5, 13.0, 18.5]
const WIND_PITCHES: Array[float] = [1.0, 0.94, 1.06, 0.97]
## At most this many poles are given a hum (the nearest to the building on each line).
const WIRE_POLES := 2
## ... and this far (metres) from each other.
const WIRE_APART := 20.0

## The loops, in the order they were made (tests and the report read them).
var sources: Array[Source] = []

var _ways: SmallMapWays
var _t: SmallMapSoundTuning
var _over := false


## One loop in the yard.
class Source:
	extends RefCounted
	var id: StringName
	var def: SoundDef
	var anchor: Node3D
	var player: AudioStreamPlayer3D
	var offset := 0.0
	## Where the sound is played from now, and how it gets in (`SmallMapWays.Way`).
	var way: SmallMapWays.Way
	## The level it is at now (it moves toward its target at the slew rate), -INF before the first.
	var db := -INF


## `backdrop` is the `Backdrop` scene (null: no yard, only the building's own sound).
func setup(ways: SmallMapWays, tuning: SmallMapSoundTuning, backdrop: Node3D) -> void:
	_ways = ways
	_t = tuning
	if backdrop == null:
		return
	var half: Vector2 = backdrop.get_meta(&"yard_half", Vector2(31.0, 27.0))
	var corners: Array[Vector2] = [
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	]
	for i in corners.size():
		var at := backdrop.global_position + Vector3(corners[i].x, WIND_LIFT, corners[i].y)
		_add(WIND, at, WIND_OFFSETS[i], WIND_PITCHES[i])
	for path in FIRE_NODES:
		var fire := backdrop.get_node_or_null(path) as Node3D
		if fire != null:
			_add(FIRE, fire.global_position + Vector3(0.0, FIRE_LIFT, 0.0))
	for pole in _poles(backdrop):
		_add(WIRE, pole + Vector3(0.0, WIRE_LIFT, 0.0))
	var asphalt := backdrop.get_node_or_null("Lot/Asphalt") as Node3D
	if asphalt != null:
		_add(ROAD, asphalt.global_position + Vector3(0.0, 1.0, 0.0))


## Moves every loop for a listener at `ear`: where it plays from, how loud and how dull, and
## whether it plays at all. `delta` is the time since the last call (the level's slew). `wind_db`
## is what the blowing gust adds to each wind loop now (0: no gust).
func update(ear: Vector3, delta: float, wind_db := 0.0) -> void:
	for source in sources:
		_follow(source, ear, delta, wind_db if source.id == WIND else 0.0)


## Fades the yard out and stops it (the night is over).
func finish() -> void:
	_over = true


func source_of(id: StringName) -> Array[Source]:
	var found: Array[Source] = []
	for source in sources:
		if source.id == id:
			found.append(source)
	return found


func _add(id: StringName, at: Vector3, offset := 0.0, pitch := 1.0) -> void:
	var def := SoundCatalog.get_def(id)
	var source := Source.new()
	source.id = id
	source.def = def
	source.offset = offset
	source.anchor = Node3D.new()
	source.anchor.name = "%s%d" % [id, sources.size()]
	add_child(source.anchor)
	source.anchor.global_position = at
	source.player = Audio.start_loop(id, source.anchor)
	if source.player != null:
		source.player.stop()
		source.player.pitch_scale = pitch
		source.player.volume_db = SmallMapSoundTuning.SILENT_DB
	sources.append(source)


func _follow(source: Source, ear: Vector3, delta: float, gust_db := 0.0) -> void:
	var player := source.player
	if player == null:
		return
	var true_at := source.anchor.global_position
	if _over or ear.distance_to(true_at) > source.def.max_distance:
		source.way = null
		source.db = -INF
		if player.playing:
			player.stop()
		return
	var way := _ways.route(ear, true_at, source.def.unit_size)
	source.way = way
	var target := source.def.volume_db + way.extra_db + gust_db
	if not Audio.filters_apply and way.kind != &"outside":
		target += _t.no_filter_db
	source.db = (
		target if source.db == -INF else move_toward(source.db, target, _t.slew_db_per_s * delta)
	)
	player.global_position = way.at
	player.volume_db = source.db
	player.attenuation_filter_cutoff_hz = way.cutoff_hz
	if not player.playing:
		player.play(source.offset)


## The poles of the backdrop's near lines nearest the building, from the poles' multimesh.
func _poles(backdrop: Node3D) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var poles := backdrop.get_node_or_null("Lines/Poles") as MultiMeshInstance3D
	if poles == null:
		return found
	var all := copies_of(poles)
	all.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			return a.distance_to(backdrop.global_position) < b.distance_to(backdrop.global_position)
	)
	for pole in all:
		if found.size() >= WIRE_POLES:
			break
		# The next pole is on another stretch of the lines, not its neighbour.
		var flat := Vector3(pole.x, 0.0, pole.z)
		if found.all(func(other: Vector3) -> bool: return other.distance_to(flat) >= WIRE_APART):
			found.append(flat)
	return found


## Where every copy of a multimesh stands in the world. Read from the `buffer` (12 floats a copy:
## each basis row followed by its origin's coordinate, then the colour and custom data if it has
## them): a headless run draws with the dummy renderer, which keeps no instance data, so
## `get_instance_transform` reads zero there (`docs/godot/headless-renderer.md` in the kit).
static func copies_of(multi: MultiMeshInstance3D) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var mesh := multi.multimesh
	var stride := 12 + (4 if mesh.use_colors else 0) + (4 if mesh.use_custom_data else 0)
	var buffer := mesh.buffer
	for i in mini(mesh.instance_count, buffer.size() / stride):
		var at := i * stride
		var local := Vector3(buffer[at + 3], buffer[at + 7], buffer[at + 11])
		found.append(multi.global_transform * local)
	return found
