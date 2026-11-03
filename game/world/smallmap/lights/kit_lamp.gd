class_name KitLamp
extends LightFollower
## A lamp of the small-map kit, lit: its model's bulb glows, and around it the cards that make the
## light read in the Compatibility renderer: a halo round the bulb, a pool on the floor, a cone of
## haze under a pendant's shade, a wash on the wall behind a lantern. All are additive quads on the
## lot's shaders and take no light slot (`LightCards`).
##
## A room has one or two real lamps (`own_light`, an `OmniLight3D` that lights the dead and the
## player); a row of lamps down a corridor has none and follows a lamp of its circuit instead
## (`light_path`), or burns steady. The bulb is the model's Popcorn swatch, lit by an emission
## texture of the atlas's layout (the drive-in's `ModelGlow` manner), so the lamp stays one mesh
## with one material.

## The atlas (`tools/blender/smallmap_kit.py`): 5 swatches a row, 16 px each; the bulb's swatch
## (Popcorn) and the inside of the shade (Cream).
const GRID := 5
const SWATCH_PX := 16
const BULB_INDEX := 16
const BULB := Color("#f2dc8c")
const SHADE_INDEX := 4
const SHADE := Color("#e6d8b0")

## The fixture's model, whose bulb glows.
@export var model_path: NodePath = ^"Lamp/Model"
## A real light of its own (`Light`): the one or two a room has. Off, the `Light` node is removed
## and the lamp follows `light_path`, or burns steady when that is empty.
@export var own_light := true

@export_group("Look")
## The colour of the glow: the bulb's halo, the pool, the haze, the wash.
@export var colour := Color(1.0, 0.72, 0.42)
## How brightly the bulb's swatch burns, and how much of the shade's cream inside glows with it.
@export_range(0.0, 10.0, 0.05) var bulb_energy := 3.0
@export_range(0.0, 1.0, 0.01) var shade_glow := 0.12
## The halo round the bulb (`Halo`), the pool on the floor (`Pool`), the cone of haze (`Haze`, none
## at 0) and the wash on the wall (`Wash`); each is drawn only when its node is in the scene.
@export_range(0.0, 10.0, 0.05) var halo_energy := 1.2
@export_range(0.0, 10.0, 0.05) var pool_energy := 0.45
@export_range(0.0, 2.0, 0.01) var haze_energy := 0.3
@export_range(0.0, 10.0, 0.05) var wash_energy := 0.3
## The cone of haze: its radius at the shade's rim, on the floor, and how far down it reaches.
@export_range(0.05, 3.0, 0.01, "suffix:m") var haze_top_radius := 0.27
@export_range(0.1, 5.0, 0.01, "suffix:m") var haze_bottom_radius := 1.3
@export_range(0.1, 5.0, 0.01, "suffix:m") var haze_length := 2.14
## Haze nearer the camera than this fades out: players walk under these lamps, and from inside the
## cone it would wash over the screen.
@export_range(0.0, 5.0, 0.05, "suffix:m") var haze_near_fade := 2.0

var _bulb_material: StandardMaterial3D
var _cards: Dictionary[StringName, ShaderMaterial] = {}
var _steady := false


func _ready() -> void:
	var light := get_node_or_null(^"Light") as Light3D
	if own_light and light != null and light_path.is_empty():
		light_path = get_path_to(light)
	elif not own_light and light != null:
		remove_child(light)
		light.free()
	_steady = get_node_or_null(light_path) == null
	_light_up_the_bulb()
	_make_cards()
	super._ready()
	if _steady:
		level = 1.0
		_apply()


func _light_up_the_bulb() -> void:
	var model := get_node_or_null(model_path)
	var found := model.find_children("*", "MeshInstance3D", true, false) if model != null else []
	var mesh := found[0] as MeshInstance3D if not found.is_empty() else null
	if mesh == null:
		return
	_bulb_material = (mesh.get_active_material(0) as StandardMaterial3D).duplicate()
	_bulb_material.emission_enabled = true
	_bulb_material.emission_texture = emission_texture(shade_glow)
	_bulb_material.emission_energy_multiplier = 0.0
	mesh.set_surface_override_material(0, _bulb_material)


## The atlas's layout, black but for the bulb's swatch and `shade` of the cream one.
static func emission_texture(shade: float) -> ImageTexture:
	var size := GRID * SWATCH_PX
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	_paint(image, BULB_INDEX, BULB)
	if shade > 0.0:
		_paint(image, SHADE_INDEX, SHADE * shade)
	return ImageTexture.create_from_image(image)


static func _paint(image: Image, index: int, colour: Color) -> void:
	var swatch := Rect2i(
		(index % GRID) * SWATCH_PX, (index / GRID) * SWATCH_PX, SWATCH_PX, SWATCH_PX
	)
	image.fill_rect(swatch, Color(colour.r, colour.g, colour.b))


func _make_cards() -> void:
	var halo := get_node_or_null(^"Halo") as MeshInstance3D
	if halo != null:
		_cards[&"halo"] = LightCards.glow(colour, false, {"falloff": 2.5, "billboard": true})
		halo.material_override = _cards[&"halo"]
	var pool := get_node_or_null(^"Pool") as MeshInstance3D
	if pool != null:
		_cards[&"pool"] = LightCards.glow(colour, false, {"falloff": 1.5})
		pool.material_override = _cards[&"pool"]
	var wash := get_node_or_null(^"Wash") as MeshInstance3D
	if wash != null:
		_cards[&"wash"] = LightCards.glow(colour, false, {"falloff": 1.8})
		wash.material_override = _cards[&"wash"]
	var haze_at := get_node_or_null(^"Haze") as Node3D
	if haze_at != null and haze_energy > 0.0:
		var material := LightCards.haze(colour)
		material.set_shader_parameter(&"near_fade", haze_near_fade)
		_cards[&"haze"] = material
		var cone := LightCards.cone(haze_top_radius, haze_bottom_radius, haze_length, 1.0, 0.15)
		haze_at.add_child(LightCards.node("Cone", cone, material))


func _apply() -> void:
	if _bulb_material != null:
		_bulb_material.emission_energy_multiplier = level * bulb_energy
	_set_card(&"halo", ^"Halo", halo_energy)
	_set_card(&"pool", ^"Pool", pool_energy)
	_set_card(&"wash", ^"Wash", wash_energy)
	_set_card(&"haze", ^"Haze", haze_energy)


func _set_card(key: StringName, path: NodePath, energy: float) -> void:
	if not _cards.has(key):
		return
	_cards[key].set_shader_parameter(&"energy", level * energy)
	(get_node(path) as Node3D).visible = level > 0.0
