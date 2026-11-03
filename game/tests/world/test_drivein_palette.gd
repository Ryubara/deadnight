# The drive-in props' palette atlas (tools/blender/build_drivein_props.py, issue #651) holds each
# swatch as its sRGB value, the one the builder's PALETTE names: the atlas once held the linear
# value instead, so every prop drew far darker than its colour (Concrete #9a968c as #524e43).
extends GdUnitTestSuite

const ATLAS := "res://assets/drivein/drivein_palette.png"
const GRID := 5
const SWATCH_PX := 16
## A few swatches of the builder's PALETTE: [index, hex], dark to light.
const SWATCHES := [
	[0, "#818491"],  # Grey
	[3, "#252525"],  # Black
	[5, "#d1ab46"],  # Yellow
	[9, "#3b4b8c"],  # Blue
	[12, "#95703d"],  # Wood
	[18, "#9a968c"],  # Concrete
]


func _cell(image: Image, index: int) -> Color:
	return image.get_pixel(
		(index % GRID) * SWATCH_PX + SWATCH_PX / 2, (index / GRID) * SWATCH_PX + SWATCH_PX / 2
	)


func _assert_cell(image: Image, index: int, hex: String) -> void:
	var got := _cell(image, index)
	var want := Color(hex)
	var message := "cell %d is #%s, the palette says %s" % [index, got.to_html(false), hex]
	for channel in 3:
		var byte := roundi(want[channel] * 255.0)
		var cell := assert_int(roundi(got[channel] * 255.0)).override_failure_message(message)
		cell.is_between(byte - 1, byte + 1)


func test_the_atlas_cells_hold_the_palette_swatches_as_srgb() -> void:
	var image := (load(ATLAS) as Texture2D).get_image()
	assert_int(image.get_width()).is_equal(GRID * SWATCH_PX)
	for swatch in SWATCHES:
		_assert_cell(image, swatch[0], swatch[1])


func test_the_glowing_swatches_match_the_glow_colours() -> void:
	var image := (load(ATLAS) as Texture2D).get_image()
	_assert_cell(image, ModelGlow.AMBER_INDEX, "#" + ModelGlow.AMBER.to_html(false))
	_assert_cell(image, ModelGlow.CREAM_INDEX, "#" + ModelGlow.CREAM.to_html(false))
