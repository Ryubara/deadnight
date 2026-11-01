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
	super._ready()


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
		_material.emission_energy_multiplier = level * amber_energy * shimmer(phase)
