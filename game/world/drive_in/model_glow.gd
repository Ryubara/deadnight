class_name ModelGlow
extends LightFollower
## Makes the amber swatches of a drive-in prop glow (the marquee's bulbs and arrow, a ticket booth's
## lamp, the counter's prices) with the lamp it follows. The props share one palette atlas
## (`assets/drivein/drivein_palette.png`, `tools/blender/build_drivein_props.py`), so one emission
## texture of the same layout lights exactly the swatches asked for and nothing else of the model.
## The texture is painted here, not a file: 80 x 80 pixels, black but for the swatches.

## The atlas: 5 swatches a row, 16 px each; the colours' places in `PALETTE`.
const GRID := 5
const SWATCH_PX := 16
const AMBER_INDEX := 6
const AMBER := Color("#e8a33a")
const CREAM_INDEX := 4
const CREAM := Color("#e6d8b0")

## The prop (an instance of a fixture scene) to light.
@export var model_path: NodePath
## How brightly the amber swatches burn at level 1.
@export var amber_energy := 2.5
## How much of the cream swatch glows, a lit board (0 for none). Every cream face of the model does.
@export_range(0.0, 1.0) var cream_glow := 0.0
## A single lamp (the generator's running light), not a bulb string: no shimmer of its own, so it
## changes only when the lamp it follows does (steady, the brown-out's flicker, dark).
@export var steady := false
## A halo round one lamp of the model (`glow.gdshader`, billboarded): its size in metres (0 for
## none), where it sits in the model's frame and how bright it burns at level 1. Keep it clear of
## every wall by its half-size (#703, #832): the generator's sits over the cage's walls.
@export var halo_size := 0.0
@export var halo_at := Vector3.ZERO
@export var halo_energy := 0.8
@export var halo_tint := Color(1, 0.62, 0.22, 1)

var _halo: MeshInstance3D
var _halo_material: ShaderMaterial

var _material: StandardMaterial3D


func _ready() -> void:
	var model := get_node_or_null(model_path)
	var mesh := _first_mesh(model) if model != null else null
	if mesh != null:
		_material = (mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
		_material.emission_enabled = true
		_material.emission_texture = _texture(cream_glow)
		_material.emission_energy_multiplier = 0.0
		mesh.set_surface_override_material(0, _material)
	if model != null and halo_size > 0.0:
		_halo = _make_halo(model as Node3D)
	super._ready()


func _make_halo(model: Node3D) -> MeshInstance3D:
	_halo_material = ShaderMaterial.new()
	_halo_material.shader = load("res://world/drive_in/glow.gdshader")
	_halo_material.render_priority = 1
	_halo_material.set_shader_parameter(&"tint", halo_tint)
	_halo_material.set_shader_parameter(&"falloff", 2.5)
	_halo_material.set_shader_parameter(&"billboard", true)
	var quad := QuadMesh.new()
	quad.size = Vector2(halo_size, halo_size)
	var halo := MeshInstance3D.new()
	halo.name = &"Halo"
	halo.mesh = quad
	halo.material_override = _halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = halo_at
	model.add_child.call_deferred(halo)
	return halo


## A sparse bulb string: every so often one drops out for an instant, a function of the phase.
static func shimmer(at: float) -> float:
	return (
		1.0
		- 0.06 * (0.5 + 0.5 * sin(at * 1.7))
		- (0.25 if sin(at * 0.9) * sin(at * 2.9) > 0.97 else 0.0)
	)


## The emission atlas with the amber swatch (and `cream` of the cream one) lit.
static func _texture(cream: float) -> ImageTexture:
	var size := GRID * SWATCH_PX
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	_paint(image, AMBER_INDEX, AMBER)
	if cream > 0.0:
		_paint(image, CREAM_INDEX, CREAM * cream)
	return ImageTexture.create_from_image(image)


static func _paint(image: Image, index: int, colour: Color) -> void:
	var swatch := Rect2i(
		(index % GRID) * SWATCH_PX, (index / GRID) * SWATCH_PX, SWATCH_PX, SWATCH_PX
	)
	image.fill_rect(swatch, Color(colour.r, colour.g, colour.b))


static func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _apply() -> void:
	if _material != null:
		_material.emission_energy_multiplier = (
			level * amber_energy * (1.0 if steady else shimmer(phase))
		)
	if _halo != null:
		_halo_material.set_shader_parameter(&"energy", level * halo_energy)
		_halo.visible = level > 0.0
