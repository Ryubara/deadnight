class_name Barricade
extends Node3D
## The boards across one breach of the field's fence (`Field/Breach*`, written by
## tools/world/build_greybox.py). The node sits in the middle of the gap on the fence line, turned
## so its local +Z points into the field: a zombie outside stands at a negative depth, a player
## putting a board back at a positive one.
##
## The boards are `Board` children, bottom to top. They are drawn and solid for players while they
## are up, and never part of the navigation mesh (they are not CSG): the dead's way in is the gap,
## and what holds them is the zombie simulation's gate, not physics. The shots go through them: they
## sit on a physics layer of their own that only players' bodies collide with.
##
## `NightWorld.bind` sets the count from the rules' events; nothing else changes it.
##
## A board that is not up leaves its outline (`BoardOutline`): a faint ghost of the plank where it
## was, drawn by the barricade itself, so every repairable entry reads the same whatever light its
## window has. It goes when the board is back.
##
## How a change looks (docs/design/map.md, Breaches): what is solid follows the count at once (the
## rules are the authority), and only the drawing moves. A torn board's body goes and a drawn copy
## of it (a pooled `MeshInstance3D` on the same mesh, no physics) is flung out of the field on a
## short arc, tumbling, lands flat and sinks into the ground. A mended board's body is in its slot
## at once; its `Mesh` child slides in from the field side, swung up about one end, and knocks home
## with a small overshoot. One Tween a motion, no `_process`, no material copies. A jump of several
## boards (a late join, a catch-up) moves only the last board that changed; the others snap.

## The physics layer (as a mask bit) of boards: players collide with it, shots and grenades do not.
## `player.tscn` has it in its mask.
const BOARD_LAYER := 2
## Most torn boards in the air at once at one breach; a further tear takes the oldest copy.
const FLYING_MAX := 5
## A torn board: how far out of the field it lands (m), how high it rises above where it was (m),
## and the gravity of its fall (m/s², heavier than the world's so a top board is down in under a
## second: 0.5 s from the lowest slot, 0.78 s from the highest).
const FLING_OUT := 1.2
const FLING_RISE := 0.55
const FLING_GRAVITY := 20.0
## Once down: how long it takes to sink out of sight (s) and how far it sinks (m); the height of
## its middle lying flat on the ground (half its thickness).
const SINK_SECONDS := 0.22
const SINK_DEPTH := 0.12
const LIE_HEIGHT := 0.07
## A mended board: where it starts (m into the field, degrees swung up about one end) and how long
## it takes to knock home.
const MEND_IN := 0.5
const MEND_SWING := 55.0
const MEND_SECONDS := 0.28
## Half a board's length: the ends it swings about. The fence breaches' boards are 4.1 m long; a
## barricade of shorter boards (the second map's windows, 1.5 m) names its own in
## `metadata/board_half`.
const BOARD_HALF := 2.05

## The breach's id, the one the rules' tuning lists (`metadata/barricade_id`).
var barricade_id: StringName = &""
## Half the length of this barricade's boards (`BOARD_HALF` unless the scene says otherwise).
var board_half := BOARD_HALF

var _boards: Array[StaticBody3D] = []
var _up: int = 0
## Each board's `Mesh` child and its transform in the slot.
var _meshes: Array[MeshInstance3D] = []
var _mesh_rest: Array[Transform3D] = []
## The running mend of each board's own mesh, by board index.
var _mending: Dictionary[int, Tween] = {}
## Drawn copies of torn boards (at most `FLYING_MAX`); the busy ones in the order they flew.
var _copies: Array[MeshInstance3D] = []
var _flying: Array[MeshInstance3D] = []
var _flights: Dictionary[MeshInstance3D, Tween] = {}
var _outline: BoardOutline


func _ready() -> void:
	# The boards' motions are tweens on the drawn frame, and the pooled copies jump when reused:
	# the engine's physics interpolation would blend them a tick late
	# (docs/research/physics-interpolation.md).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	barricade_id = StringName(get_meta(&"barricade_id", ""))
	board_half = float(get_meta(&"board_half", BOARD_HALF))
	for child in get_children():
		if child is StaticBody3D:
			_boards.append(child)
			var mesh := child.get_node_or_null(^"Mesh") as MeshInstance3D
			_meshes.append(mesh)
			_mesh_rest.append(mesh.transform if mesh != null else Transform3D.IDENTITY)
	_up = _boards.size()
	var in_barricade: Array[Transform3D] = []
	for i in _boards.size():
		in_barricade.append(_boards[i].transform * _mesh_rest[i])
	_outline = BoardOutline.new()
	_outline.set_boards(_meshes, in_barricade)
	add_child(_outline)
	_outline.show_missing(_up)


## The ghost of the missing boards.
func outline() -> BoardOutline:
	return _outline


## The most boards it holds.
func capacity() -> int:
	return _boards.size()


## Boards up now.
func boards() -> int:
	return _up


## Puts the lowest `count` boards up and the rest down, clamped to what it holds. With `animate`,
## the board that changed last is drawn torn off or mended (the others of a jump snap); without,
## everything snaps (binding to the rules). Bodies and collision follow at once either way.
func set_boards(count: int, animate: bool = true) -> void:
	var before := _up
	_up = clampi(count, 0, _boards.size())
	for i in _boards.size():
		var up := i < _up
		_boards[i].visible = up
		_boards[i].collision_layer = BOARD_LAYER if up else 0
		if not up:
			_rest_mesh(i)
	if _outline != null:
		_outline.show_missing(_up)
	if not animate or not is_inside_tree() or _up == before:
		return
	if _up < before:
		_fling(_up)  # the lowest board that went: the last one pulled off
	else:
		_mend(_up - 1)


## The motions running now (tests step them with `Tween.custom_step`).
func motions() -> Array[Tween]:
	var out: Array[Tween] = []
	for tween: Tween in _mending.values() + _flights.values():
		if tween.is_valid():
			out.append(tween)
	return out


## Drawn copies of torn boards in the air or sinking now.
func flying() -> Array[MeshInstance3D]:
	return _flying.duplicate()


## The mesh of board `index` (its drawing; the body stays in the slot).
func board_mesh(index: int) -> MeshInstance3D:
	return _meshes[index]


## Where board `index`'s mesh sits in its slot, in the board's space.
func board_mesh_rest(index: int) -> Transform3D:
	return _mesh_rest[index]


## Ends every motion at once: copies gone, meshes in their slots.
func finish_motion() -> void:
	for i: int in _mending.keys():
		_rest_mesh(i)
	for copy in _flying.duplicate():
		_land(copy)


## The mesh of board `index` back in its slot, its mend (if any) stopped.
func _rest_mesh(index: int) -> void:
	var tween: Tween = _mending.get(index)
	if tween != null:
		tween.kill()
		_mending.erase(index)
	if _meshes[index] != null:
		_meshes[index].transform = _mesh_rest[index]


## Board `index` was torn off: a copy of it flies out of the field, tumbling, and sinks away.
func _fling(index: int) -> void:
	var mesh := _meshes[index]
	if mesh == null:
		return
	var copy := _take_copy(mesh)
	var start := _boards[index].transform * _mesh_rest[index]
	# Deterministic per breach and board: no two breaches throw alike, and a replay is the same.
	var roll := hash(String(barricade_id) + str(index))
	var spin := (1.5 * PI) * (1.0 if roll & 1 else -1.0)  # a turn and a half: it lands flat
	# One end swings out ahead of the other, so a torn board shows past the gap's edge from inside too.
	var yaw := deg_to_rad(20.0 + 2.0 * float(roll >> 1 & 7)) * (1.0 if roll & 16 else -1.0)
	var drift := (float(roll >> 5 & 7) / 7.0 - 0.5) * 0.6
	var rise := sqrt(2.0 * FLING_GRAVITY * FLING_RISE)
	var drop := maxf(start.origin.y - LIE_HEIGHT, 0.0)
	var seconds := (rise + sqrt(rise * rise + 2.0 * FLING_GRAVITY * drop)) / FLING_GRAVITY
	var flight := {
		"from": start,
		"to": Vector3(start.origin.x + drift, LIE_HEIGHT, start.origin.z - FLING_OUT),
		"rise": rise,
		"seconds": seconds,
		"spin": spin,
		"yaw": yaw,
	}
	_fly(0.0, copy, flight)
	copy.visible = true
	var tween := create_tween()
	tween.tween_method(_fly.bind(copy, flight), 0.0, 1.0, seconds)
	tween.tween_property(copy, ^"position:y", LIE_HEIGHT - SINK_DEPTH, SINK_SECONDS)
	tween.parallel().tween_property(copy, ^"scale", Vector3(1.0, 0.05, 0.05), SINK_SECONDS)
	tween.tween_callback(_land.bind(copy))
	_flights[copy] = tween


## One point of a flight, `t` from 0 (in the slot) to 1 (lying on the ground outside).
func _fly(t: float, copy: MeshInstance3D, flight: Dictionary) -> void:
	var from: Transform3D = flight["from"]
	var to: Vector3 = flight["to"]
	var time: float = t * flight["seconds"]
	var at := from.origin.lerp(to, t)
	at.y = maxf(from.origin.y + flight["rise"] * time - 0.5 * FLING_GRAVITY * time * time, to.y)
	var turn := Basis(Vector3.UP, flight["yaw"] * t) * Basis(Vector3.RIGHT, flight["spin"] * t)
	copy.transform = Transform3D(turn * from.basis, at)


## A copy is done: hidden, back in the pool.
func _land(copy: MeshInstance3D) -> void:
	var tween: Tween = _flights.get(copy)
	if tween != null:
		tween.kill()
		_flights.erase(copy)
	copy.visible = false
	copy.scale = Vector3.ONE
	_flying.erase(copy)


## A free copy from the pool (made the first time, at most `FLYING_MAX`), or the oldest in the air.
func _take_copy(mesh: MeshInstance3D) -> MeshInstance3D:
	var copy: MeshInstance3D = null
	for candidate in _copies:
		if not candidate in _flying:
			copy = candidate
			break
	if copy == null and _copies.size() < FLYING_MAX:
		copy = MeshInstance3D.new()
		copy.name = "Torn%d" % _copies.size()
		copy.cast_shadow = mesh.cast_shadow
		add_child(copy)
		_copies.append(copy)
	if copy == null:
		copy = _flying[0]
		_land(copy)
	copy.mesh = mesh.mesh
	copy.material_override = mesh.material_override
	_flying.append(copy)
	return copy


## Board `index` was put back: its body is in the slot already; its mesh slides in from the field
## side swung up about one end, and knocks home with a small overshoot.
func _mend(index: int) -> void:
	if _meshes[index] == null:
		return
	_rest_mesh(index)
	var held := board_half if index % 2 == 0 else -board_half  # alternate ends, as nailed by hand
	_swing(0.0, index, held)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(_swing.bind(index, held), 0.0, 1.0, MEND_SECONDS)
	tween.tween_callback(_rest_mesh.bind(index))
	_mending[index] = tween


## A mended board's mesh at `t` from 0 (held up in the field) to 1 (in its slot); past 1 on the
## overshoot it swings a little the other way, as a board knocked home does. `held` is the end
## that is lifted (x in the board's space); it swings about the other.
func _swing(t: float, index: int, held: float) -> void:
	var angle := deg_to_rad(MEND_SWING) * (1.0 - t) * signf(held)
	var pivot := Vector3(-held, 0.0, 0.0)
	var about := (
		Transform3D(Basis.IDENTITY, pivot)
		* Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO)
		* Transform3D(Basis.IDENTITY, -pivot)
	)
	var slide := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, MEND_IN * (1.0 - t)))
	_meshes[index].transform = slide * about * _mesh_rest[index]


## Where the boards stand, on the ground in the middle of the gap.
func centre() -> Vector3:
	return global_position


## The way into the field, flat and unit length.
func inward() -> Vector3:
	var direction := global_basis.z
	direction.y = 0.0
	return direction.normalized()


## How far `point` is past the boards into the field, in metres: negative outside the fence.
func depth_of(point: Vector3) -> float:
	var offset := point - global_position
	offset.y = 0.0
	return offset.dot(inward())


## A place on the field side to stand at to put boards back, `distance` metres in.
func standing_point(distance: float) -> Vector3:
	return global_position + inward() * distance
