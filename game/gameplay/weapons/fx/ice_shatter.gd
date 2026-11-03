class_name IceShatter
extends Node3D
## A frozen zombie breaking apart, client only: the body bursts into pieces of ice that fly out,
## tumble, fall to the ground and shrink away. It is drawn from the server's `zombie_shattered`
## event (where it stood, how tall it was), so every client sees it and none decides it. The pieces
## are pooled like the shot effects: made once (`prewarm`, behind the loading screen), lent to a
## burst and taken back, so a kill in the middle of a night builds no mesh and no shader.

## Pieces a body breaks into, and the pool they come from (a few bursts at once).
const PIECES := 16
const POOL := PIECES * 4
## Seconds a piece lives: it flies, lies on the ground and shrinks away over the last share.
const LIFE_SECONDS := 1.7
const SHRINK_SHARE := 0.3
## Metres a piece's side may be, for a walker's height (they scale with the body).
const SIZE_MIN := 0.08
const SIZE_MAX := 0.26
## Metres from the body's axis a piece starts at, and how fast it is thrown out and up.
const START_RADIUS := 0.22
const THROW_OUT := Vector2(1.6, 4.2)
const THROW_UP := Vector2(0.8, 3.6)
const SPIN_MAX := 9.0
const GRAVITY := 14.0
## How tall a walker is, in metres: the pieces start along the whole of it.
const BODY_HEIGHT := 1.75
const ICE_COLOUR := Color(0.6, 0.86, 1.0, 0.78)
const FROST_COLOUR := Color(0.93, 0.98, 1.0, 0.9)

var _free: Array[Piece] = []
var _live: Array[Piece] = []
var _made := 0
var _mesh: PrismMesh
var _ice: StandardMaterial3D
var _frost: StandardMaterial3D


## One piece in the air or on the ground.
class Piece:
	extends RefCounted
	var node: MeshInstance3D
	var velocity := Vector3.ZERO
	var spin := Vector3.ZERO
	var age := 0.0
	var size := 0.1
	var floor_y := 0.0


func _init() -> void:
	# Moved by `_process` on the drawn frame, not interpolated between physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)


## Makes every piece ahead of the night, hidden.
func prewarm() -> void:
	while _made < POOL:
		_free.append(_make())


## A body of `scale` (1 is a walker's height) breaks apart where it stood, at `at` (its feet).
## `seed_value` (the zombie's id) makes the pieces the same on every client.
func burst(at: Vector3, scale: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in PIECES:
		var piece := _lend()
		var height := rng.randf_range(0.1, 0.95) * BODY_HEIGHT * scale
		var angle := rng.randf() * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		piece.size = rng.randf_range(SIZE_MIN, SIZE_MAX) * clampf(scale, 0.5, 1.4)
		piece.floor_y = at.y + piece.size * 0.4
		piece.velocity = (
			out * rng.randf_range(THROW_OUT.x, THROW_OUT.y)
			+ Vector3.UP * rng.randf_range(THROW_UP.x, THROW_UP.y)
		)
		piece.spin = Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * SPIN_MAX * 0.5
		piece.age = 0.0
		var node := piece.node
		node.material_override = _frost if i % 4 == 0 else _ice
		node.position = at + out * START_RADIUS * rng.randf() + Vector3.UP * height
		node.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		node.scale = Vector3.ONE * piece.size
		node.visible = true
	set_process(true)


## Pieces on show now, for tests.
func live_count() -> int:
	return _live.size()


## Pieces made so far, for tests: it stops at `POOL`.
func nodes_made() -> int:
	return _made


## The nodes of the pieces on show, for tests.
func live_nodes() -> Array[MeshInstance3D]:
	var nodes: Array[MeshInstance3D] = []
	for piece in _live:
		nodes.append(piece.node)
	return nodes


## Ends every burst now (the pieces are hidden and kept for the next).
func stop_all() -> void:
	for piece in _live:
		piece.node.visible = false
		_free.append(piece)
	_live.clear()
	set_process(false)


func _process(delta: float) -> void:
	var i := _live.size() - 1
	while i >= 0:
		var piece := _live[i]
		piece.age += delta
		if piece.age >= LIFE_SECONDS:
			piece.node.visible = false
			_free.append(piece)
			_live.remove_at(i)
		else:
			_fly(piece, delta)
		i -= 1
	if _live.is_empty():
		set_process(false)


func _fly(piece: Piece, delta: float) -> void:
	var node := piece.node
	if node.position.y > piece.floor_y or piece.velocity.y > 0.0:
		piece.velocity += Vector3.DOWN * GRAVITY * delta
		node.position += piece.velocity * delta
		node.rotation += piece.spin * delta
		if node.position.y <= piece.floor_y:
			node.position.y = piece.floor_y
			piece.velocity = Vector3.ZERO
	var left := (LIFE_SECONDS - piece.age) / (LIFE_SECONDS * SHRINK_SHARE)
	node.scale = Vector3.ONE * piece.size * clampf(left, 0.0, 1.0)


## An idle piece, or the oldest live one taken over once the pool is out.
func _lend() -> Piece:
	var piece: Piece
	if not _free.is_empty():
		piece = _free.pop_back()
	elif _made < POOL:
		piece = _make()
		_free.erase(piece)
	else:
		piece = _live.pop_front()
	_live.append(piece)
	return piece


func _make() -> Piece:
	if _mesh == null:
		_mesh = PrismMesh.new()
		_ice = _material(ICE_COLOUR)
		_frost = _material(FROST_COLOUR)
	var piece := Piece.new()
	piece.node = MeshInstance3D.new()
	piece.node.mesh = _mesh
	piece.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.node.visible = false
	add_child(piece.node)
	_made += 1
	return piece


static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# Unshaded: a lit material of its own setting is another program on the lot (`test_load_cost`
	# holds the lit ones to a budget), and ice that glows in the dark needs no light.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
