class_name ChalkMessage
extends LightFollower
## A line of chalk on a wall: one of our own messages (`assets/smallmap/chalk_messages.png`, written
## by `tools/world/build_chalk_messages.py`), drawn additively in the Chalk swatch's colour on the
## lot's glow shader. Additive chalk shows only as much as the light it is given, so place it where
## a moon shaft lands or under a lamp (the reference writes where the light falls) and give it that
## light to follow (`light_path`: the moon, or the lamp); with none it burns steady.
##
## Local space: the card stands in the XY plane facing +Z, its middle at the origin. Put the node a
## centimetre off the wall.

const LAYOUT := preload("res://assets/smallmap/chalk_messages.json")
const LETTERING := preload("res://assets/smallmap/chalk_messages.png")

## Which line, as `chalk_messages.json` lists them.
@export_enum(
	"KEEP THE LIGHTS ON",
	"STAY IN THE LIGHT",
	"THEY COME AT DARK",
	"NOT THIS WAY",
	"HOLD THE WINDOWS",
	"UP THERE ->"
)
var message := 0
## How wide the line is on the wall; its height follows from the lettering.
@export_range(0.3, 3.0, 0.05, "suffix:m") var width := 1.2
## The Chalk swatch (`#ece6d2`) and how bright the chalk is at the followed light's full level.
@export var colour := Color("#ece6d2")
@export_range(0.0, 2.0, 0.01) var energy := 0.5

var _material: ShaderMaterial
var _steady := false


## The row of `message` in the lettering, as (offset, size) in UV.
static func rect_of(index: int) -> Rect2:
	var data: Dictionary = LAYOUT.data
	var size := float(data["size"])
	var row: Dictionary = data["messages"][index]
	return Rect2(
		float(row["x"]) / size,
		float(row["y"]) / size,
		float(row["w"]) / size,
		float(row["h"]) / size
	)


func _ready() -> void:
	var rect := rect_of(message)
	var height := width * rect.size.y / rect.size.x
	_material = (
		LightCards
		. glow(
			colour,
			true,
			{
				"edge": Vector2(0.001, 0.001),
				"mask": LETTERING,
				"mask_rect": Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y),
			}
		)
	)
	var w := width * 0.5
	var h := height * 0.5
	var card := LightCards.card(
		Vector3(-w, h, 0.0), Vector3(w, h, 0.0), Vector3(w, -h, 0.0), Vector3(-w, -h, 0.0)
	)
	add_child(LightCards.node("Lettering", card, _material))
	_steady = get_node_or_null(light_path) == null
	super._ready()
	if _steady:
		level = 1.0
		_apply()


func _apply() -> void:
	if _material != null:
		_material.set_shader_parameter(&"energy", level * energy)
