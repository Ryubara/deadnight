extends SceneTree
## Fits the hit zones to the bodies: for each zombie model and each pose it can be in (the clips
## it plays), the model is skinned at several moments of its clips and a sphere or capsule is fitted
## to each piece of the body (head, torso, upper and fore arms, thighs and shins) over all of them.
## The shapes are the envelope of the bones' travel through the pose, since the server does not
## know which moment of a clip a client has drawn. Writes `hit_pose_data.tres` (`HitPoseSets`).
##
## Run after a model or a clip changes (`tests/zombies/test_hit_zones_follow_bodies.gd` fails when
## the zones stop following the mesh):
##   godot --headless --path game -s res://tools/hit_fit/fit_hit_shapes.gd [-- --check]
## `--check` prints the ray grid stats of each set and writes nothing.

const EXTRA := "extra/"
## Moments sampled in each clip.
const SAMPLES := 32
## The share of a piece's vertices a shape must reach round its axis (the rest are hair spikes,
## fingers and the tongue), per piece.
const COVER := {
	ZombieMeshProbe.Piece.HEAD: 0.85,
	ZombieMeshProbe.Piece.TONGUE: 1.0,
	ZombieMeshProbe.Piece.TORSO: 0.9,
	ZombieMeshProbe.Piece.UPPER_ARM_L: 0.9,
	ZombieMeshProbe.Piece.FOREARM_L: 0.88,
	ZombieMeshProbe.Piece.UPPER_ARM_R: 0.9,
	ZombieMeshProbe.Piece.FOREARM_R: 0.88,
	ZombieMeshProbe.Piece.THIGH_L: 0.9,
	ZombieMeshProbe.Piece.SHIN_L: 0.88,
	ZombieMeshProbe.Piece.THIGH_R: 0.9,
	ZombieMeshProbe.Piece.SHIN_R: 0.88,
}
## How many shapes follow each piece through its travel (`_cluster`).
const PARTS := {
	ZombieMeshProbe.Piece.HEAD: 3,
	ZombieMeshProbe.Piece.TONGUE: 1,
	ZombieMeshProbe.Piece.TORSO: 2,
	ZombieMeshProbe.Piece.UPPER_ARM_L: 4,
	ZombieMeshProbe.Piece.FOREARM_L: 4,
	ZombieMeshProbe.Piece.UPPER_ARM_R: 4,
	ZombieMeshProbe.Piece.FOREARM_R: 4,
	ZombieMeshProbe.Piece.THIGH_L: 3,
	ZombieMeshProbe.Piece.SHIN_L: 3,
	ZombieMeshProbe.Piece.THIGH_R: 3,
	ZombieMeshProbe.Piece.SHIN_R: 3,
}
## A climb moves the body a metre and more round its origin: this many times `PARTS` for its sets.
const CLIMB_PARTS := 2
## The clips of each pose of a body; every look has the walker's poses but the crawler, which lies
## on the ground, and the headliner, which has clips of its own. `extra/` ones are from
## `ZombieRig.EXTRA_CLIPS_FILE`.
const WALKER_POSES := {
	&"move": ["Idle", "Walk"],
	&"run": ["Run"],
	&"sprint": ["extra/Sprint"],
	&"strike": ["Punch"],
	&"stagger": ["HitReact"],
	&"tear": ["extra/Tear_Boards"],
	&"climb": ["extra/Climb_Sill"],
}
const CRAWLER_POSES := {
	&"move": ["Crawl"],
	&"strike": ["extra/Crawl_Attack"],
	&"stagger": ["extra/Crawl_Stagger"],
	&"climb": ["extra/Crawl_Climb"],
}
const HEADLINER_POSES := {
	&"move": ["Idle", "Boss_Walk"],
	&"strike": ["Boss_Attack"],
	&"roar": ["Boss_Roar"],
	&"stagger": ["Boss_Stagger"],
	&"tear": ["extra/Tear_Boards"],
}

var _check := false
## `--cover=X` replaces the cover of every piece but the head's, `--only=a,b` fits only those sets,
## and `--spacing=M` sets the check grid's spacing: for trying values.
var _cover_override := 0.0
var _only: Array[String] = []
var _parts_override := 0
var _samples := SAMPLES
var _spacing := 0.08


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--check":
			_check = true
		elif arg.begins_with("--cover="):
			_cover_override = float(arg.get_slice("=", 1))
		elif arg.begins_with("--samples="):
			_samples = int(arg.get_slice("=", 1))
		elif arg.begins_with("--parts="):
			_parts_override = int(arg.get_slice("=", 1))
		elif arg.begins_with("--only="):
			_only.assign(arg.get_slice("=", 1).split(","))
		elif arg.begins_with("--spacing="):
			_spacing = float(arg.get_slice("=", 1))
	await process_frame
	var sets := {}
	for body in ZombieModels.VARIANTS:
		var poses := WALKER_POSES
		if body == &"crawler":
			poses = CRAWLER_POSES
		elif body == &"headliner":
			poses = HEADLINER_POSES
		if (
			not _only.is_empty()
			and not _only.any(func(id: String) -> bool: return id.begins_with("%s." % body))
		):
			continue
		var probe := ZombieMeshProbe.make(root, body)
		probe.use_extra_clips()
		var unit := ZombieModels.height_of(body)
		for pose: StringName in poses:
			var id := StringName("%s.%s" % [body, pose])
			if not _only.is_empty() and not _only.has(String(id)):
				continue
			var parts := CLIMB_PARTS if pose == ZombiePose.CLIMB else 1
			sets[id] = _fit(probe, poses[pose], unit, body == &"headliner", parts)
			if _check:
				print(id, ": ", _stats(probe, poses[pose], sets[id], unit))
		probe.free_model()
	if not _check:
		_write(sets)
	quit()


## The shapes of one pose, in units of the look's height: `{shapes: [{zone, a, b, r}], bound}`.
func _fit(
	probe: ZombieMeshProbe, clips: Array, unit: float, weak: bool, parts_times: int = 1
) -> Dictionary:
	# One cloud per piece per sampled moment.
	var moments := {}
	for piece in ZombieMeshProbe.Piece.values():
		moments[piece] = []
	for clip: String in clips:
		var length := probe.length_of(clip)
		for i in _samples:
			probe.pose(clip, length * float(i) / float(_samples))
			for piece in moments:
				(moments[piece] as Array).append(probe.points(piece))
	var shapes: Array[Dictionary] = []
	for piece in ZombieMeshProbe.Piece.values():
		if piece == ZombieMeshProbe.Piece.TONGUE:
			continue  # it swings out of every shape; a shot at it is a shot at the head
		var zone := Hitbox.LIMB
		if piece == ZombieMeshProbe.Piece.HEAD:
			zone = Hitbox.HEAD
		elif piece == ZombieMeshProbe.Piece.TORSO:
			zone = Hitbox.BODY
		var parts: int = PARTS[piece] * parts_times
		if _parts_override > 0 and piece != ZombieMeshProbe.Piece.HEAD:
			parts = _parts_override
		for group in _cluster(moments[piece], parts):
			var cloud := PackedVector3Array()
			for moment: int in group:
				cloud.append_array((moments[piece] as Array)[moment])
			if cloud.size() < 8:
				continue
			var cover: float = COVER[piece]
			if _cover_override > 0.0 and piece != ZombieMeshProbe.Piece.HEAD:
				cover = _cover_override
			var shape := _capsule_around(cloud, cover, piece == ZombieMeshProbe.Piece.HEAD)
			(
				shapes
				. append(
					{
						"zone": zone,
						"a": (shape["a"] as Vector3) / unit,
						"b": (shape["b"] as Vector3) / unit,
						"r": float(shape["r"]) / unit,
					}
				)
			)
	var bounded := shapes.duplicate()
	if weak:
		bounded.append(Hitbox.WEAK_ZONE)
	return {"shapes": shapes, "bound": _bound(bounded)}


## Groups the moments (indexes into `clouds`) into at most `count` sets whose clouds sit together
## (k-means on the clouds' centres, first centres picked far apart): one shape each follows the
## piece through its travel more tightly than one shape round all of it.
func _cluster(clouds: Array, count: int) -> Array:
	var centres: Array[Vector3] = []
	for cloud: PackedVector3Array in clouds:
		var sum := Vector3.ZERO
		for p in cloud:
			sum += p
		centres.append(sum / float(maxi(cloud.size(), 1)))
	var seeds: Array[Vector3] = [centres[0]]
	while seeds.size() < mini(count, centres.size()):
		var far := 0
		var far_distance := -1.0
		for i in centres.size():
			var nearest := INF
			for seed in seeds:
				nearest = minf(nearest, centres[i].distance_to(seed))
			if nearest > far_distance:
				far_distance = nearest
				far = i
		seeds.append(centres[far])
	var groups: Array = []
	for _round in 12:
		groups = []
		for _k in seeds.size():
			groups.append([])
		for i in centres.size():
			var best := 0
			for k in seeds.size():
				if centres[i].distance_to(seeds[k]) < centres[i].distance_to(seeds[best]):
					best = k
			groups[best].append(i)
		for k in seeds.size():
			if (groups[k] as Array).is_empty():
				continue
			var sum := Vector3.ZERO
			for i: int in groups[k]:
				sum += centres[i]
			seeds[k] = sum / float((groups[k] as Array).size())
	return groups.filter(func(g: Array) -> bool: return not g.is_empty())


## A capsule (a sphere when `sphere`) that holds `cover` of the points round their long axis.
func _capsule_around(points: PackedVector3Array, cover: float, sphere: bool) -> Dictionary:
	var centre := Vector3.ZERO
	for p in points:
		centre += p
	centre /= float(points.size())
	if sphere:
		var box := AABB(points[0], Vector3.ZERO)
		for p in points:
			box = box.expand(p)
		centre = box.get_center()
		var distances := PackedFloat32Array()
		for p in points:
			distances.append(p.distance_to(centre))
		distances.sort()
		var r := distances[int(float(distances.size() - 1) * cover)]
		return {"a": centre, "b": centre, "r": r}
	var axis := _principal_axis(points, centre)
	var along := PackedFloat32Array()
	for p in points:
		along.append((p - centre).dot(axis))
	var perpendicular := PackedFloat32Array()
	for i in points.size():
		perpendicular.append(((points[i] - centre) - axis * along[i]).length())
	var sorted_perpendicular := perpendicular.duplicate()
	sorted_perpendicular.sort()
	var radius := sorted_perpendicular[int(float(points.size() - 1) * cover)]
	var sorted_along := along.duplicate()
	sorted_along.sort()
	var low := sorted_along[int(float(points.size() - 1) * (1.0 - cover) * 0.5)]
	var high := sorted_along[int(float(points.size() - 1) * (1.0 - (1.0 - cover) * 0.5))]
	var middle := (low + high) * 0.5
	var from := minf(low + radius, middle)
	var to := maxf(high - radius, middle)
	return {"a": centre + axis * from, "b": centre + axis * to, "r": radius}


func _principal_axis(points: PackedVector3Array, centre: Vector3) -> Vector3:
	var xx := 0.0
	var xy := 0.0
	var xz := 0.0
	var yy := 0.0
	var yz := 0.0
	var zz := 0.0
	for p in points:
		var d := p - centre
		xx += d.x * d.x
		xy += d.x * d.y
		xz += d.x * d.z
		yy += d.y * d.y
		yz += d.y * d.z
		zz += d.z * d.z
	var axis := Vector3(1, 0.7, 0.3).normalized()
	for _i in 40:
		axis = Vector3(
			xx * axis.x + xy * axis.y + xz * axis.z,
			xy * axis.x + yy * axis.y + yz * axis.z,
			xz * axis.x + yz * axis.y + zz * axis.z
		)
		if axis.length() < 1e-9:
			return Vector3.UP
		axis = axis.normalized()
	return axis


## A sphere round every shape: `{c, r}`.
func _bound(shapes: Array) -> Dictionary:
	var box := AABB(shapes[0]["a"], Vector3.ZERO)
	for shape in shapes:
		box = box.expand(shape["a"]).expand(shape["b"])
	var centre := box.get_center()
	var radius := 0.0
	for shape in shapes:
		for end: Vector3 in [shape["a"], shape["b"]]:
			radius = maxf(radius, end.distance_to(centre) + float(shape["r"]))
	return {"c": centre, "r": radius}


func _stats(probe: ZombieMeshProbe, clips: Array, fit: Dictionary, unit: float) -> String:
	var fitted := {
		"shapes": fit["shapes"],
		"bound_centre": fit["bound"]["c"],
		"bound_radius": fit["bound"]["r"],
	}
	var shooter := func(origin: Vector3, dir: Vector3) -> StringName:
		return Hitbox.ray_in(fitted, origin, dir, 40.0, Vector3.ZERO, 0.0, 0.0, unit).get(
			"zone", &""
		)
	var any := 0.0
	var head := 0.0
	var spurious := 0.0
	var own := 0.0
	var low := 2.0
	var count := 0
	for clip: String in clips:
		var length := probe.length_of(clip)
		for i in 3:
			probe.pose(clip, length * float(i) / 3.0)
			var grid := ZombieRayGrid.new()
			grid.run(probe, shooter, _spacing)
			any += grid.registered_rate()
			head += grid.registered_rate(ZombieMeshProbe.Part.HEAD)
			own += grid.matched_rate()
			spurious += grid.spurious_rate()
			low = minf(low, grid.registered_rate())
			count += 1
	return (
		(
			"any mean %.1f%% worst %.1f%% | head any %.1f%% | own zone %.1f%%"
			+ " | off the mesh %.1f%% | %d shapes"
		)
		% [
			any / count * 100.0,
			low * 100.0,
			head / count * 100.0,
			own / count * 100.0,
			spurious / count * 100.0,
			(fit["shapes"] as Array).size()
		]
	)


func _write(sets: Dictionary) -> void:
	var resource := HitPoseSets.new()
	for id: StringName in sets:
		var shapes: Array[Dictionary] = []
		for shape: Dictionary in sets[id]["shapes"]:
			(
				shapes
				. append(
					{
						"zone": shape["zone"],
						"a": _v(shape["a"]),
						"b": _v(shape["b"]),
						"r": snappedf(shape["r"], 0.001),
					}
				)
			)
		var bound: Dictionary = sets[id]["bound"]
		resource.sets[id] = {
			"shapes": shapes,
			"bound_centre": _v(bound["c"]),
			"bound_radius": snappedf(bound["r"], 0.001),
		}
	var error := ResourceSaver.save(resource, HitPoseData.FILE)
	print("wrote ", HitPoseData.FILE, " (", error_string(error), ")")


func _v(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001))
