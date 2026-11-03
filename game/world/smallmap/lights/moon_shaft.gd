class_name MoonShaft
extends LightFollower
## Cool moonlight through a window or a barred opening, as the Compatibility renderer cannot draw
## it: the moon casts no shadows there (`docs/research/night-environment.md`), so the light that
## comes in and the bars' shadows on the floor are additive cards (`LightCards`).
##
## - `Opening`: a faint cool card in the opening, so the window reads lit from inside.
## - `Shaft`: two sheets of haze from the opening down along the moon's direction, cut into rays by
##   the bars.
## - `Patch`: where the light lands, the opening projected along the moon's direction onto the floor
##   (or onto a wall `land_wall` ahead, where it reaches that first), cut by the shadows of the bars
##   and rails. Built in rows, so a patch that runs up a wall bends at the corner.
##
## Local space is a wall module's: the origin in the middle of the wall on the floor, the room side
## +Z, the opening's room face at `wall_face`. `light_path` is the moon, so the shaft dims with it
## as the rounds darken the night (`NightLight`); with none it burns steady.

## Rows the patch is cut into along the opening's height.
const PATCH_ROWS := 12
## The two shaft sheets, as shares of the opening's height from its top.
const SHEETS: Array[float] = [0.3, 0.75]

## The opening's clear width and height, and its sill above the floor.
@export var opening := Vector2(1.2, 1.3)
@export_range(0.0, 3.0, 0.05, "suffix:m") var sill := 0.9
## Where the opening's room face is: half the wall's thickness.
@export_range(0.0, 0.5, 0.01, "suffix:m") var wall_face := 0.15
## The moon's direction into the room: degrees down from level, and turned sideways.
@export_range(5.0, 85.0, 0.5, "suffix:deg") var pitch := 38.0
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var yaw := 0.0
## A wall facing the window this far into the room, where the light lands first (0: the floor only).
@export_range(0.0, 20.0, 0.05, "suffix:m") var land_wall := 0.0
## The shadows: bars across the opening (vertical), rails along it (horizontal: boards, mullions),
## and the share of each gap a bar's shadow takes.
@export_range(0, 24) var bars := 0
@export_range(0, 12) var rails := 0
@export_range(0.0, 0.95, 0.01) var shadow := 0.3

@export_group("Look")
## The moon's colour (`#9db4e8`, the lot's).
@export var colour := Color(0.616, 0.706, 0.91)
@export_range(0.0, 2.0, 0.01) var opening_energy := 0.12
@export_range(0.0, 2.0, 0.01) var shaft_energy := 0.18
@export_range(0.0, 2.0, 0.01) var patch_energy := 0.3

var _materials: Dictionary[StringName, ShaderMaterial] = {}
var _steady := false


func _ready() -> void:
	_build()
	_steady = get_node_or_null(light_path) == null
	super._ready()
	if _steady:
		level = 1.0
		_apply()


## The moon's direction in local space (into the room, downward).
func direction() -> Vector3:
	var down := deg_to_rad(pitch)
	var side := deg_to_rad(yaw)
	return Vector3(sin(side) * cos(down), -sin(down), cos(side) * cos(down)).normalized()


## A point of the opening (`u` 0 left to 1 right, `v` 0 top to 1 sill) on its room face.
func opening_point(u: float, v: float) -> Vector3:
	return Vector3((u - 0.5) * opening.x, sill + opening.y * (1.0 - v), wall_face)


## Where the moonlight through `from` lands: the floor, or the wall ahead if it gets there first.
func land(from: Vector3) -> Vector3:
	var d := direction()
	var t := -from.y / d.y
	if land_wall > 0.0 and d.z > 0.0:
		t = minf(t, (wall_face + land_wall - 0.01 - from.z) / d.z)
	var at := from + d * t
	# A hair off the surface it lands on, so the card never fights it for depth (the wall's is in
	# `t` above).
	return at + (Vector3.UP * 0.015 if at.y < 0.001 else Vector3.ZERO)


func _build() -> void:
	var settings := {"bars": float(bars), "shadow": shadow}
	var face := Vector3.BACK * 0.01
	var opening_card := LightCards.card(
		opening_point(0, 0) + face,
		opening_point(1, 0) + face,
		opening_point(1, 1) + face,
		opening_point(0, 1) + face
	)
	_add(
		&"opening",
		opening_card,
		settings.merged({"rails": float(rails), "edge": Vector2(0.06, 0.06), "fade": 0.3})
	)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in PATCH_ROWS + 1:
		var v := float(i) / PATCH_ROWS
		left.append(land(opening_point(0, v)))
		right.append(land(opening_point(1, v)))
	_add(
		&"patch",
		LightCards.strip(left, right),
		settings.merged({"rails": float(rails), "edge": Vector2(0.08, 0.06)})
	)
	var shaft := Node3D.new()
	shaft.name = "Shaft"
	add_child(shaft)
	for share in SHEETS:
		var a := opening_point(0, share)
		var b := opening_point(1, share)
		var sheet := LightCards.card(a, b, land(b), land(a))
		var material := _material(
			&"shaft", settings.merged({"edge": Vector2(0.25, 0.2), "fade": 0.75})
		)
		shaft.add_child(LightCards.node("Sheet", sheet, material))


func _add(key: StringName, mesh: Mesh, settings: Dictionary) -> void:
	add_child(LightCards.node(String(key).capitalize(), mesh, _material(key, settings)))


func _material(key: StringName, settings: Dictionary) -> ShaderMaterial:
	if not _materials.has(key):
		_materials[key] = LightCards.glow(colour, true, settings)
	return _materials[key]


func _apply() -> void:
	var energies := {&"opening": opening_energy, &"shaft": shaft_energy, &"patch": patch_energy}
	for key: StringName in _materials:
		_materials[key].set_shader_parameter(&"energy", level * float(energies[key]))
	for child in get_children():
		(child as Node3D).visible = level > 0.0
