class_name StatusLook
extends RefCounted
## How a status effect looks on a zombie in a client: one shell material for each status, shared by
## every zombie under it, laid over the model (`GeometryInstance3D.material_overlay`) so the body
## keeps its own animation, skin and outline. One material each (not one per zombie) so the renderer
## builds its shader once, in the warm-up, and a freeze in the middle of a night builds none.

## How far the shell stands off the body, in metres: the model grows along its normals by this.
const SHELL_GROW := 0.03

static var _shells: Dictionary[int, StandardMaterial3D] = {}


## The shell of the status with this wire id, or null for none (0) or one no build knows.
static func shell_for(wire: int) -> StandardMaterial3D:
	var def := StatusCatalog.by_wire(wire)
	if def == null:
		return null
	if not _shells.has(wire):
		_shells[wire] = _make(def)
	return _shells[wire]


static func _make(def: StatusDef) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# Unshaded: a lit material of its own setting is another program on the lot (`test_load_cost`
	# holds the lit ones to a budget), and a shell that reads blue on the dark lot needs no light.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = def.tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.grow = true
	material.grow_amount = SHELL_GROW
	return material
