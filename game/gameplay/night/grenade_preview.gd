class_name GrenadePreview
extends Node3D
## Where the grenade in the hand would go if the button came up now (#357): a line along its flight,
## and a ring on the ground the size of the blast's core where it would go off. It runs the same
## `GrenadeArc` stepping the server and the flying copies use, from the same hand and aim
## (`GrenadeThrower.launch`), so what it shows is what the throw does. It decides nothing and sends
## nothing; the server throws when the button comes up, a swing later.

const LINE_COLOUR := Color(1.0, 0.85, 0.4, 0.9)
const RING_COLOUR := Color(1.0, 0.45, 0.25, 0.9)
const RING_SEGMENTS := 36
## The ring is drawn this high above the point, so it does not sink into the ground.
const RING_LIFT := 0.05
## The longest flight the line shows (s), if the fuse would allow more.
const MAX_FLIGHT := 6.0

## The hand's reach out in front of the player, as the server throws (`NightTuning`).
var hand_reach := 0.35
## Seconds the throw takes from the button coming up to the grenade leaving, as the server's.
var release_over := 0.0
var release_under := 0.0
## What the client was told it carries (-1 until it is told): none left, no preview.
var grenades_left := -1

var _def: GrenadeDef
var _cast: Callable
var _cooked := 0.0
var _line: MeshInstance3D
var _ring: MeshInstance3D
var _mesh_line := ImmediateMesh.new()
var _mesh_ring := ImmediateMesh.new()
var _landing := Vector3.ZERO
var _points := PackedVector3Array()


func _ready() -> void:
	_line = _drawn(_mesh_line, LINE_COLOUR)
	_ring = _drawn(_mesh_ring, RING_COLOUR)
	visible = false


## The grenade this previews and the world it flies through.
func setup(def: GrenadeDef, cast: Callable) -> void:
	_def = def
	_cast = cast


## Where it would go off if thrown now, or the zero vector while nothing is shown.
func landing() -> Vector3:
	return _landing if visible else Vector3.ZERO


## The points of the flight line, for tests.
func points() -> PackedVector3Array:
	return _points if visible else PackedVector3Array()


## One tick of `delta` seconds: shows the flight of the throw `command` is holding for the body
## `body` (the local player), or hides it when no grenade button is held, none are left or the
## player is down.
func follow(command: NightCommand, body: Player, delta: float, downed: bool = false) -> void:
	var over := command.motion.throw_over
	var under := command.motion.throw_under
	if _def == null or body == null or downed or grenades_left == 0 or not (over or under):
		_cooked = 0.0
		_hide()
		return
	_cooked += delta
	var launch := GrenadeThrower.launch(
		_def, hand_reach, body.global_position, body.state.facing, command.dir
	)
	var underarm := under and not over
	var release := release_under if underarm else release_over
	var flight := clampf(_def.fuse - _cooked - release, 0.05, MAX_FLIGHT)
	var result := GrenadeArc.predict(
		_def, launch["hand"], launch["aim"], body.state.velocity, underarm, _cast, delta, flight
	)
	_points = result["points"]
	_landing = result["landing"]
	_draw()
	visible = true


func _hide() -> void:
	visible = false
	_points = PackedVector3Array()


func _draw() -> void:
	_mesh_line.clear_surfaces()
	_mesh_line.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in _points:
		_mesh_line.surface_add_vertex(point)
	_mesh_line.surface_end()
	_mesh_ring.clear_surfaces()
	_mesh_ring.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for index in RING_SEGMENTS + 1:
		var angle := TAU * index / RING_SEGMENTS
		_mesh_ring.surface_add_vertex(
			(
				_landing
				+ Vector3(cos(angle), 0.0, sin(angle)) * _def.core_radius
				+ Vector3.UP * RING_LIFT
			)
		)
	_mesh_ring.surface_end()


func _drawn(mesh: ImmediateMesh, colour: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.top_level = true
	add_child(instance)
	return instance
