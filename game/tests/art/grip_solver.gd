class_name GripSolver
extends RefCounted
## Solves how the Soldier's hands hold a weapon model (Deadnight #460), from the model's hand
## sockets: the right hand's `Grip` (and `Trigger`), the left hand's `Support`. Run by
## `solve_grips.gd`, which writes the result as a `HandGrip` file. The steps, all in the hand bone's
## space (`Index1`), so the result holds in every pose:
##
## 1. The hand's handle line: across the knuckles (pinky to index) at the middle finger, with the
##    straight fingers' direction and the palm's normal square to it.
## 2. The model is turned so its socket's up runs along that line and its front the fingers' way (a
##    melee weapon keeps its old hold's turn about the handle, so its blade still leads), and moved
##    so the socket is on the line; a gun slides along it until its trigger is level with the
##    index finger's knuckle.
## 3. It is pushed along the palm's normal until the palm is `PALM_TARGET` from it.
## 4. A gun is turned up to 30 degrees about the line and slid up to 2 cm along the fingers, to
##    where the index finger reaches the trigger best (the kit's fingers are short and thick).
## 5. Each finger is bent, knuckle and middle joint (the thumb at its root and tip, the trigger
##    finger sideways too), within `LIMITS`, to the bend that brings its tip `TARGET` from the
##    surface without any part of it going in more than `MAX_DEPTH`; the index finger goes for the
##    trigger's face, and lies along the frame when it cannot reach it.
##
## Docs: docs/design/animation.md, "Grips".

## The pose the hands are solved in: any clip with the hand bones at rest relative to the forearm.
const BASE_CLIP := &"Aim_Rifle"
## Where the skin should sit from the weapon's surface, metres: in contact, not in it.
const TARGET := 0.001
## The palm and the root of the thumb are seated this far off: their skin is partly the forearm's,
## and the arms' IK bends the wrist in the game, which moves it by up to about 2 mm.
const PALM_TARGET := 0.003
## The deepest any part may go in while solving (the test allows 2 mm).
const MAX_DEPTH := 0.0012
## A tip farther than this from the surface does not touch (the test allows 5 mm for a contact).
const MAX_FLOAT := 0.004
## The Player's Model node: the Soldier at 0.8, turned to face -Z.
const MODEL := Transform3D(
	Basis(Vector3(-0.8, 0, 0), Vector3(0, 0.8, 0), Vector3(0, 0, -0.8)), Vector3.ZERO
)

## How far each finger bone may bend, in degrees about its bend axis from straight (the kit's rest):
## a finger joint from a little past straight to a full curl; the thumb's root swings across the
## palm. The kit's own curl (the clips) is inside these.
const LIMITS := {
	"Index2": Vector2(-10, 95),
	"Index3": Vector2(-5, 105),
	"Middle2": Vector2(-10, 95),
	"Middle3": Vector2(-5, 105),
	"Pinky2": Vector2(-10, 95),
	"Pinky3": Vector2(-5, 105),
	"Thumb1": Vector2(-30, 60),
	"Thumb2": Vector2(-10, 110),
}
## How far the trigger finger may swing sideways at its knuckle, degrees.
const SPREAD := 25.0
## Each finger: the bones the search bends, and which parts it is measured by.
const FINGERS := {
	"index":
	{"bones": ["Index2", "Index3"], "tip": "index_tip", "parts": ["index_tip", "index_mid"]},
	"middle":
	{"bones": ["Middle2", "Middle3"], "tip": "middle_tip", "parts": ["middle_tip", "middle_mid"]},
	"pinky":
	{"bones": ["Pinky2", "Pinky3"], "tip": "pinky_tip", "parts": ["pinky_tip", "pinky_mid"]},
	"thumb":
	{
		# The thumb's root bends palm skin too, so the palm is checked with it.
		"bones": ["Thumb1", "Thumb2"],
		"tip": "thumb_tip",
		"parts": ["thumb_tip", "thumb_base", "palm"]
	},
}

## Where the solver writes OBJ files of each solved hand (empty: none).
var dump_dir := ""
var root: Node
var skeleton: Skeleton3D
var contact: HandContact
var log_lines := PackedStringArray()
var _model: Node3D
## Each finger bone's bend axis in its own space: the axis the kit's own curl turns about.
var _axes := {}
## Each finger bone's rotation in the clip, read once before the search bends it.
var _clip := {}


func _init(tree_root: Node) -> void:
	root = tree_root
	_model = Node3D.new()
	_model.transform = MODEL
	root.add_child(_model)
	var soldier: Node3D = (
		(load("res://assets/characters/soldier_parts/soldier_parts.glb") as PackedScene)
		. instantiate()
	)
	_model.add_child(soldier)
	skeleton = soldier.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := soldier.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.play(BASE_CLIP)
	player.seek(0.0, true)
	player.get_parent().remove_child(player)
	player.free()
	for side in ["R", "L"]:
		for finger: String in FINGERS:
			for bone: String in FINGERS[finger].bones:
				_axes[bone + "." + side] = _bend_axis(bone + "." + side)
	contact = HandContact.new(skeleton)


## The axis the kit's curl turns a finger bone about (in its own space); the thumb's root, which
## the kit never turns, bends about the axis of the thumb's second bone.
func _bend_axis(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	var turn := (
		skeleton.get_bone_rest(i).basis.get_rotation_quaternion().inverse()
		* skeleton.get_bone_pose_rotation(i)
	)
	if turn.get_angle() < 0.05:
		var other := skeleton.find_bone(bone.replace("1", "2"))
		var t2 := (
			skeleton.get_bone_rest(other).basis.get_rotation_quaternion().inverse()
			* skeleton.get_bone_pose_rotation(other)
		)
		return t2.get_axis().normalized()
	return turn.get_axis().normalized()


## The clip's curl of a finger bone: degrees about its bend axis from its rest.
func _curl(bone: int) -> float:
	var turn := (
		skeleton.get_bone_rest(bone).basis.get_rotation_quaternion().inverse()
		* _clip_rotation(bone)
	)
	var axis: Vector3 = _axes[skeleton.get_bone_name(bone)]
	var angle := turn.get_angle()
	return rad_to_deg(angle) * signf(turn.get_axis().dot(axis)) if angle > 0.001 else 0.0


func _bone(name: String) -> int:
	return skeleton.find_bone(name)


## A bone's place in the hand bone's space (unscaled skeleton units).
func _in_hand(side: String, bone: String) -> Vector3:
	var hand := skeleton.get_bone_global_pose(_bone("Index1." + side))
	return hand.affine_inverse() * skeleton.get_bone_global_pose(_bone(bone + "." + side)).origin


## The world transform of the hand bone of `side`.
func hand_world(side: String) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_bone("Index1." + side))


## Step 1: the handle line in the hand bone's space. Origin on the line at the middle finger, basis
## Y along it (pinky to index), -Z the way the straight fingers point, X the rest (the palm's
## normal, palm to fingertips, or its opposite).
## `index_offset` is how far up the line the index finger's knuckle sits from the middle's.
func handle_frame(side: String) -> Dictionary:
	var index := _in_hand(side, "Index2")
	var middle := _in_hand(side, "Middle2")
	var pinky := _in_hand(side, "Pinky2")
	var along := (index - pinky).normalized()
	var to_knuckles := (index + middle + pinky) / 3.0
	var fingers := (to_knuckles - along * to_knuckles.dot(along)).normalized()
	var normal := along.cross(fingers).normalized()
	# The fingers curl toward the palm's normal: the middle finger's tip is on its side.
	var tip := _part_centre(side, "middle_tip")
	if normal.dot(tip - middle) < 0.0:
		normal = -normal
	# The handle's centre: under the middle knuckle, half a finger's bend toward the palm's
	# normal; the seat (step 3) moves it to the palm.
	var centre := middle + normal * 0.06 - fingers * 0.02
	# The model's front (the barrel's way) is the way the straight fingers point; the palm's normal
	# runs across the handle (on a pistol grip, from the palm on its right to the fingertips on its
	# left).
	var basis := Basis(along.cross(-fingers), along, -fingers).orthonormalized()
	return {
		"frame": Transform3D(basis, centre),
		"along": along,
		"normal": normal,
		"fingers": fingers,
		"index_offset": (index - middle).dot(along),
	}


## The centre of a hand part's skin, in the hand bone's space.
func _part_centre(side: String, part: String) -> Vector3:
	var points: PackedVector3Array = contact.skin_points(side)[part]
	var sum := Vector3.ZERO
	for p in points:
		sum += p
	var inverse := hand_world(side).affine_inverse()
	return inverse * (sum / maxf(points.size(), 1))


## A node's transform in the model's own space (under the model's root).
static func socket(model: Node3D, name: String) -> Variant:
	var node := model.find_child(name, true, false) as Node3D
	if node == null:
		return null
	return model.global_transform.affine_inverse() * node.global_transform


## Solves one model in the hand of `side`. `spec`: {scene or node, model_scale, kind ("gun",
## "melee", "ball"), reference (the old hold, for a melee weapon's turn), grip ("Grip" or
## "Support")}. Returns {hold (model under the hand bone, before scale), fingers {bone: Quaternion},
## contacts, table {part: mm}, trigger_finger}.
func solve(side: String, model: Node3D, spec: Dictionary) -> Dictionary:
	_reset_fingers(side)
	var mount := Node3D.new()
	root.add_child(mount)
	mount.global_transform = hand_world(side)
	mount.add_child(model)
	var scale: float = spec.model_scale
	var frame := handle_frame(side)
	var hand: Transform3D = frame.frame
	var grip_name: String = spec.get("grip", "Grip")
	model.transform = Transform3D.IDENTITY
	var grip_socket: Variant = socket(model, grip_name)
	if grip_socket == null:
		grip_socket = Transform3D.IDENTITY
	var gs: Transform3D = grip_socket
	gs = Transform3D(gs.basis.orthonormalized(), gs.origin)
	var basis: Basis
	if spec.kind == "gun" or not spec.has("reference"):
		basis = hand.basis * gs.basis.inverse()
	else:
		# Keep the old hold's turn about the handle: the least turn that lays its handle on the line.
		var reference: Basis = (spec.reference as Transform3D).basis.orthonormalized()
		var handle: Vector3 = reference * (gs.basis.y)
		basis = (Basis(Quaternion(handle.normalized(), frame.along)) * reference).orthonormalized()
	var trigger_socket: Variant = socket(model, "Trigger") if grip_name == "Grip" else null
	model.transform = Transform3D(basis, hand.origin).scaled_local(Vector3.ONE * scale)
	contact.set_weapon(model)
	# Steps 2 and 3, and for a gun the turn about the handle and the slide along the fingers that let
	# the index finger reach the trigger best (a chibi finger is short: the hand turns the gun).
	var place := _place(side, model, basis, gs, scale, frame, trigger_socket, 0.0, 0.0)
	if spec.has("keep_hold"):
		# Only the fingers: the model stays where the written grip holds it (Deadnight #716).
		place = _kept(model, spec.keep_hold, scale, trigger_socket)
	elif trigger_socket != null:
		var best_score := INF
		for roll in range(-30, 31, 10):
			for shift in [-0.02, -0.01, 0.0, 0.01, 0.02]:
				var p := _place(side, model, basis, gs, scale, frame, trigger_socket, roll, shift)
				_reset_fingers(side)
				var reach := _close_finger(side, "index", true, p.trigger_world, true)
				# Prefer the hold as drawn when two reach alike (a centimetre is worth 15 degrees).
				var score: float = reach.score + absf(roll) * 0.0007 + absf(shift) * 0.3
				if score < best_score:
					best_score = score
					place = p
		log_lines.append(
			(
				"PLACE %s roll=%.0f shift=%.3f score=%.4f"
				% [spec.get("name", ""), place.roll, place.shift, best_score]
			)
		)
		_reset_fingers(side)
	basis = place.basis
	var origin: Vector3 = place.origin
	model.transform = Transform3D(basis, origin).scaled_local(Vector3.ONE * scale)
	# Step 4: the fingers.
	var fingers := {}
	var contacts := PackedStringArray()
	var trigger_finger := ""
	var trigger_world: Vector3 = place.trigger_world
	for finger: String in ["index", "middle", "pinky", "thumb"]:
		var want_trigger := finger == "index" and trigger_socket != null
		var result := _close_finger(side, finger, want_trigger, trigger_world, false)
		for bone: String in result.rotations:
			fingers[bone] = result.rotations[bone]
		if result.touches:
			contacts.append(FINGERS[finger].tip)
		if want_trigger:
			trigger_finger = result.mode
	var table := {}
	var measured := contact.measure(side)
	for part: String in measured:
		table[part] = snappedf(measured[part].distance * 1000.0, 0.1)
	if table.get("palm", 99.0) <= MAX_FLOAT * 1000.0:
		contacts.append("palm")
	var row := {}
	if dump_dir != "":
		var tag := "%s_%s" % [spec.get("name", "model"), side]
		contact.dump_obj(dump_dir.path_join(tag + ".obj"))
		var b := model.global_basis.orthonormalized()
		var centre := hand_world(side) * _part_centre(side, "palm")
		row = {
			"tag": tag,
			side: table,
			"weapon_basis": [_v(b.x), _v(b.y), _v(b.z)],
			"centre_" + side: _v(centre),
			"contacts": {side: contacts},
		}
	mount.remove_child(model)
	mount.queue_free()
	return {
		"hold": Transform3D(basis, origin),
		"fingers": fingers,
		"contacts": contacts,
		"table": table,
		"trigger_finger": trigger_finger,
		"row": row,
	}


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)]


## The model turned `roll` degrees about the handle line and slid `shift` (skeleton units) the way
## the fingers point, its socket on the line (a gun's trigger level with the index finger), then
## seated against the palm. Returns {basis, origin, trigger_world, roll, shift}; leaves the model
## there.
func _place(
	side: String,
	model: Node3D,
	basis0: Basis,
	gs: Transform3D,
	scale: float,
	frame: Dictionary,
	trigger_socket: Variant,
	roll: float,
	shift: float
) -> Dictionary:
	var hand: Transform3D = frame.frame
	var basis := (Basis(frame.along, deg_to_rad(roll)) * basis0).orthonormalized()
	var origin: Vector3 = (
		hand.origin - basis * (gs.origin * scale) + (frame.fingers as Vector3) * shift
	)
	if trigger_socket != null:
		var at: Vector3 = origin + basis * ((trigger_socket as Transform3D).origin * scale)
		var level: float = (at - hand.origin).dot(frame.along)
		origin += frame.along * (frame.index_offset - level)
	origin = _seat(side, model, basis, origin, scale, frame.normal)
	model.transform = Transform3D(basis, origin).scaled_local(Vector3.ONE * scale)
	var trigger_world := Vector3.ZERO
	if trigger_socket != null:
		trigger_world = model.global_transform * (trigger_socket as Transform3D).origin
	return {
		"basis": basis,
		"origin": origin,
		"trigger_world": trigger_world,
		"roll": roll,
		"shift": shift
	}


## The model at a hold that is kept (`HandGrip.hold`, before scale): {basis, origin, trigger_world,
## roll, shift} as `_place` returns them; leaves the model there.
func _kept(model: Node3D, hold: Transform3D, scale: float, trigger_socket: Variant) -> Dictionary:
	model.transform = hold.scaled_local(Vector3.ONE * scale)
	var trigger_world := Vector3.ZERO
	if trigger_socket != null:
		trigger_world = model.global_transform * (trigger_socket as Transform3D).origin
	return {
		"basis": hold.basis,
		"origin": hold.origin,
		"trigger_world": trigger_world,
		"roll": 0.0,
		"shift": 0.0
	}


## Puts every finger bone of `side` back to the clip's curl.
func _reset_fingers(side: String) -> void:
	for finger: String in FINGERS:
		for bone: String in FINGERS[finger].bones:
			var i := _bone(bone + "." + side)
			skeleton.set_bone_pose_rotation(i, _clip_rotation(i))


func _clip_rotation(bone: int) -> Quaternion:
	if not _clip.has(bone):
		_clip[bone] = skeleton.get_bone_pose_rotation(bone)
	return _clip[bone]


## The handle moved along the palm's normal until the palm (and the root of the thumb) is
## `TARGET` from it. Returns the hold's origin.
func _seat(
	side: String, model: Node3D, basis: Basis, origin: Vector3, scale: float, normal: Vector3
) -> Vector3:
	var low := -0.15
	var high := 0.15
	var f := func(t: float) -> float:
		model.transform = Transform3D(basis, origin + normal * t).scaled_local(Vector3.ONE * scale)
		var m := contact.measure_parts(side, ["palm", "thumb_base"])
		return minf(m["palm"].distance, m["thumb_base"].distance) - PALM_TARGET
	# Toward the palm (negative t) the distance falls: find where it crosses zero.
	if f.call(high) < 0.0:
		return origin + normal * high
	if f.call(low) > 0.0:
		return origin + normal * low
	for _i in 30:
		var mid := (low + high) * 0.5
		if f.call(mid) > 0.0:
			high = mid
		else:
			low = mid
	return origin + normal * high


## Bends one finger: knuckle and middle joint (for the thumb its root and its tip bone), and for the
## trigger finger its knuckle sideways too, over a grid of degrees and then finer around the best,
## keeping the bend whose tip is nearest `TARGET` without any part of the finger going in. With
## `want_trigger` the index finger's tip must also be at the trigger; when no bend brings it there
## it lies along the frame instead. A finger that can touch nothing is only kept out of the weapon.
func _close_finger(
	side: String, finger: String, want_trigger: bool, trigger_world: Vector3, coarse: bool
) -> Dictionary:
	var spec: Dictionary = FINGERS[finger]
	var bones: Array = spec.bones
	var a := _bone(bones[0] + "." + side)
	var b := _bone(bones[1] + "." + side)
	var axis_a: Vector3 = _axes[bones[0] + "." + side]
	var axis_b: Vector3 = _axes[bones[1] + "." + side]
	# Sideways: square to the bend and to the bone (toward its child).
	var along_a := skeleton.get_bone_rest(b).origin.normalized()
	var spread_axis := axis_a.cross(along_a).normalized()
	var base_a := _clip_rotation(a)
	var base_b := _clip_rotation(b)
	var parts: Array = spec.parts
	var tip: String = spec.tip
	# The bend allowed on top of the clip's curl.
	var limit_a: Vector2 = LIMITS[bones[0]] - Vector2.ONE * _curl(a)
	var limit_b: Vector2 = LIMITS[bones[1]] - Vector2.ONE * _curl(b)
	var evaluate := func(da: float, db: float, ds: float, mode: String) -> Dictionary:
		da = clampf(da, limit_a.x, limit_a.y)
		db = clampf(db, limit_b.x, limit_b.y)
		ds = clampf(ds, -SPREAD, SPREAD)
		var turn_a := Quaternion(spread_axis, deg_to_rad(ds)) * Quaternion(axis_a, deg_to_rad(da))
		skeleton.set_bone_pose_rotation(a, base_a * turn_a)
		skeleton.set_bone_pose_rotation(b, base_b * Quaternion(axis_b, deg_to_rad(db)))
		var m := contact.measure_parts(side, parts)
		var deepest := INF
		for part: String in m:
			deepest = minf(deepest, m[part].distance)
		var tip_d: float = m[tip].distance
		var from_trigger := (m[tip].point as Vector3).distance_to(trigger_world)
		var cost := absf(tip_d - TARGET)
		match mode:
			"trigger":
				cost += from_trigger * 0.5
			"frame":
				# Straight along the frame: the middle of the finger on it as well, bent little.
				cost += absf(m[parts[1]].distance - TARGET) + absf(db) * 0.0002
			"wrap":
				# A finger that wraps: its middle should touch too.
				cost += maxf(m[parts[1]].distance - 0.003, 0.0) * 0.3
			"clear":
				cost = absf(da) * 0.00001 + absf(db) * 0.00001
		if deepest < -MAX_DEPTH:
			cost += 10.0 - deepest
		return {
			"cost": cost,
			"tip": tip_d,
			"deepest": deepest,
			"from_trigger": from_trigger,
			"da": da,
			"db": db,
			"ds": ds,
		}
	var modes := ["trigger", "frame", "clear"] if want_trigger else ["wrap", "clear"]
	var spreads := range(-20, 21, 10) if want_trigger else [0]
	if coarse:
		# Only how near the trigger the finger can come without going in: a quick score.
		var score := INF
		for ds in [-20, 0, 20]:
			for da in range(floori(limit_a.x), ceili(limit_a.y) + 1, 15):
				for db in range(floori(limit_b.x), ceili(limit_b.y) + 1, 15):
					var r: Dictionary = evaluate.call(float(da), float(db), float(ds), "trigger")
					var s: float = (
						r.from_trigger
						+ absf(r.tip - TARGET) * 2.0
						+ maxf(-MAX_DEPTH - r.deepest, 0.0) * 20.0
					)
					score = minf(score, s)
		return {"score": score}
	var chosen := {}
	for mode: String in modes:
		var best := {"cost": INF}
		for ds in spreads if mode == "trigger" else [0]:
			for da in range(floori(limit_a.x), ceili(limit_a.y) + 1, 10):
				for db in range(floori(limit_b.x), ceili(limit_b.y) + 1, 10):
					var r: Dictionary = evaluate.call(float(da), float(db), float(ds), mode)
					if r.cost < best.cost:
						best = r
		for step: float in [5.0, 2.0, 1.0, 0.5, 0.25]:
			var centre := best.duplicate()
			for i in range(-2, 3):
				for j in range(-2, 3):
					for k in [-1, 0, 1] if mode == "trigger" else [0]:
						var r: Dictionary = evaluate.call(
							centre.da + i * step, centre.db + j * step, centre.ds + k * step, mode
						)
						if r.cost < best.cost:
							best = r
		best["mode"] = mode
		var ok: bool = best.deepest >= -MAX_DEPTH and absf(best.tip - TARGET) <= MAX_FLOAT
		if mode == "trigger":
			ok = ok and best.from_trigger < 0.02
			(
				log_lines
				. append(
					(
						"TRIGGER %s best bend=(%.1f, %.1f, spread %.1f) tip=%.1fmm deepest=%.1fmm from trigger=%.1fmm"
						% [
							side,
							best.da,
							best.db,
							best.ds,
							best.tip * 1000.0,
							best.deepest * 1000.0,
							best.from_trigger * 1000.0
						]
					)
				)
			)
		if mode == "clear":
			ok = false
		if ok or mode == modes[-1]:
			chosen = best
			chosen["ok"] = ok
			break
	evaluate.call(chosen.da, chosen.db, chosen.ds, chosen.mode)
	log_lines.append(
		(
			"FINGER %s %s mode=%s bend=(%.2f, %.2f, spread %.2f) tip=%.1fmm deepest=%.1fmm ok=%s"
			% [
				side,
				finger,
				chosen.mode,
				chosen.da,
				chosen.db,
				chosen.ds,
				chosen.tip * 1000.0,
				chosen.deepest * 1000.0,
				chosen.ok
			]
		)
	)
	return {
		"rotations":
		{
			bones[0] + "." + side: skeleton.get_bone_pose_rotation(a),
			bones[1] + "." + side: skeleton.get_bone_pose_rotation(b),
		},
		"touches": chosen.ok,
		"mode": chosen.mode if chosen.ok else "",
	}
