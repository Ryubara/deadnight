class_name OutlineStyle
extends Resource
## How an outline looks, and the materials that draw it. One style is shared by every mesh that
## wears it, so a change to a property here (in the inspector, or in the remote scene tree of a
## running game) reaches every outlined body in the same frame. `chain()` is the material a mesh
## takes as its `material_overlay`: a mask pass, a ring of copies for the line and a wider, fainter
## ring for the glow, each pass a `ShaderMaterial` chained by `next_pass`. A mesh nothing outlines
## has none of it: no draw call, no stencil write.

const MASK_SHADER := preload("res://gameplay/outline/outline_mask.gdshader")
const LINE_SHADER := preload("res://gameplay/outline/outline.gdshader")
## Copies in a ring. The line is a band at least `cos(PI / DIRECTIONS)` of the asked width wide
## between two copies' directions, and the asked width along them.
const DIRECTIONS := 8
## Where the glow's band ends, in line widths beyond the line, and how opaque it is at glow 1.
const GLOW_REACH := 2.5
const GLOW_ALPHA := 0.35
## Draw order among the transparent things (a lower number first): the mask, then the line, then
## the glow, which a stencil keeps off the line.
const PRIORITY_MASK := -100
const PRIORITY_LINE := -99
const PRIORITY_GLOW := -98

## The line's colour (its alpha is the line's opacity).
@export var color := Color(1.0, 0.35, 0.12, 1.0):
	set(value):
		color = value
		_sync()
## The line's width in pixels of a 1080-high screen, the same at any distance (scaled to the real
## screen's height, so it looks the same on a phone and in a big window).
@export_range(0.0, 16.0, 0.25, "suffix:px") var thickness := 3.0:
	set(value):
		thickness = value
		_sync()
## The soft halo outside the line: its opacity (0 draws no halo and costs no more passes).
@export_range(0.0, 2.0, 0.05) var glow := 0.6:
	set(value):
		glow = value
		_sync()

var _mask: ShaderMaterial
var _lines: Array[ShaderMaterial] = []
var _glows: Array[ShaderMaterial] = []


## The material to give a mesh as its `material_overlay` (made on first use, then kept: the shader
## stays built for as long as the style lives).
func chain() -> Material:
	if _mask == null:
		_build()
	return _mask


## How many passes a mesh draws with this style: the mask, the line's copies and, when there is a
## glow, its copies.
func pass_count() -> int:
	return 1 + DIRECTIONS + (DIRECTIONS if glow > 0.0 else 0)


## The materials of the chain in the order they are drawn (for tests and the warm-up).
func materials() -> Array[ShaderMaterial]:
	chain()
	var all: Array[ShaderMaterial] = [_mask]
	all.append_array(_lines)
	all.append_array(_glows)
	return all


func _build() -> void:
	_mask = ShaderMaterial.new()
	_mask.shader = MASK_SHADER
	_mask.render_priority = PRIORITY_MASK
	_ring(_lines, PRIORITY_LINE)
	_ring(_glows, PRIORITY_GLOW)
	_mask.next_pass = _lines[0]
	_sync()


## Fills `into` with DIRECTIONS copies of the line shader chained one after the other.
func _ring(into: Array[ShaderMaterial], priority: int) -> void:
	for i in DIRECTIONS:
		var material := ShaderMaterial.new()
		material.shader = LINE_SHADER
		material.render_priority = priority
		var angle := TAU * float(i) / DIRECTIONS
		material.set_shader_parameter(&"direction", Vector2(cos(angle), sin(angle)))
		if not into.is_empty():
			into[-1].next_pass = material
		into.append(material)


func _sync() -> void:
	if _mask == null:
		return
	# A band of copies reaches `cos(PI / DIRECTIONS)` of its radius between two directions.
	var radius := thickness / cos(PI / DIRECTIONS)
	for material in _lines:
		material.set_shader_parameter(&"color", color)
		material.set_shader_parameter(&"reach", radius)
	var halo := Color(color.r, color.g, color.b, clampf(glow * GLOW_ALPHA, 0.0, 1.0))
	for material in _glows:
		material.set_shader_parameter(&"color", halo)
		material.set_shader_parameter(&"reach", radius * (1.0 + GLOW_REACH))
	# The glow's passes are in the chain only while there is a glow.
	_lines[-1].next_pass = _glows[0] if glow > 0.0 else null
