class_name DoorGlow
extends LightFollower
## Warm light from the room beyond a purchase door or a debris blocker, so the next area shows
## before it is bought (the reference's lit stair behind a blocker;
## `docs/research/maps/small-map-art.md`). It burns with a lamp of the far room's circuit
## (`light_path`), as a lit window of the stand does (`GlowPane`), and with the same faint tremble.
## Two additive cards, no light slot:
##
## - `Beyond`: a card filling the opening on the far side, brightest at the floor, seen through the
##   cracks of the planks, round the leaf and over a blocker.
## - `Spill`: a card on the near floor at the door's foot, the light under the door, fading into the
##   room.
##
## Local space is a doorway module's: the origin in the middle of the wall on the floor, the near
## (room) side +Z, the far side -Z. With no `light_path` it burns steady.

## The opening's clear width and height.
@export var opening := Vector2(1.4, 2.4)
## Where the wall's faces are (half its thickness), and how far behind the far face `Beyond` hangs.
@export_range(0.0, 0.5, 0.01, "suffix:m") var wall_face := 0.15
@export_range(0.0, 2.0, 0.01, "suffix:m") var behind := 0.3
## How far into the near room the light under the door reaches, and how much wider than the door.
@export_range(0.1, 4.0, 0.05, "suffix:m") var spill_depth := 1.6
@export_range(0.0, 2.0, 0.05, "suffix:m") var spill_flare := 0.6
## True once the door is bought: the light no longer comes under it (`Spill` goes), `Beyond` stays
## as the far room's glow in the open doorway.
@export var opened := false:
	set(value):
		opened = value
		if is_node_ready():
			_apply()

@export_group("Look")
## The far room's lamps (sodium, the lot's `#ffb866` side).
@export var colour := Color(1.0, 0.66, 0.32)
@export_range(0.0, 3.0, 0.01) var beyond_energy := 1.0
@export_range(0.0, 3.0, 0.01) var spill_energy := 0.9

var _beyond: ShaderMaterial
var _spill: ShaderMaterial
var _steady := false


func _ready() -> void:
	var w := opening.x * 0.5
	var far := -wall_face - behind
	# V = 0 at the floor, so the far room's glow is brightest low, where the gap under a door is.
	_beyond = LightCards.glow(colour, true, {"edge": Vector2(0.12, 0.1), "fade": 0.75})
	var beyond := LightCards.card(
		Vector3(-w, 0.0, far),
		Vector3(w, 0.0, far),
		Vector3(w, opening.y, far),
		Vector3(-w, opening.y, far)
	)
	add_child(LightCards.node("Beyond", beyond, _beyond))
	_spill = LightCards.glow(colour, true, {"edge": Vector2(0.3, 0.05), "fade": 1.0})
	var y := 0.015
	var spill := LightCards.card(
		Vector3(-w, y, wall_face),
		Vector3(w, y, wall_face),
		Vector3(w + spill_flare, y, wall_face + spill_depth),
		Vector3(-w - spill_flare, y, wall_face + spill_depth)
	)
	add_child(LightCards.node("Spill", spill, _spill))
	_steady = get_node_or_null(light_path) == null
	super._ready()
	if _steady:
		level = 1.0
		_apply()


func _apply() -> void:
	if _beyond == null:
		return
	var tremble := 1.0 + 0.06 * sin(phase * 9.0) * sin(phase * 2.3)
	_beyond.set_shader_parameter(&"energy", level * tremble * beyond_energy)
	_spill.set_shader_parameter(&"energy", level * tremble * spill_energy)
	($Beyond as Node3D).visible = level > 0.0
	($Spill as Node3D).visible = level > 0.0 and not opened
