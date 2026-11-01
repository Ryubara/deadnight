class_name ReticleStyle
extends Resource
## How the centre reticle looks: four short ticks round a gap, and a small dot. Lengths are canvas
## units (the HUD's 1920 x 1080 canvas, which the window and the UI scale stretch), so the reticle
## grows and shrinks with the rest of the HUD. Edit `reticle_style.tres` or the `Hud` node's
## "Reticle Style" property in the editor; the reasoning is in docs/design/hud.md ("The reticle").

## Length of each of the four ticks, from the gap outwards.
@export_range(0.0, 40.0, 0.5, "suffix:units") var arm_length := 9.0
## Distance from the centre to where each tick starts.
@export_range(0.0, 40.0, 0.5, "suffix:units") var gap := 7.0
## Width of a tick.
@export_range(1.0, 10.0, 0.5, "suffix:units") var thickness := 3.0
## Dark edge round every shape, per side, so the reticle holds on lit ground. 0 draws none.
@export_range(0.0, 6.0, 0.5, "suffix:units") var outline := 1.5
## Side of the centre dot. 0 draws none.
@export_range(0.0, 12.0, 0.5, "suffix:units") var dot := 3.0
## Multiplies the HUD's light ink; white keeps the token.
@export var tint := Color.WHITE
@export_range(0.0, 1.0, 0.05) var opacity := 0.92


## The distance from the centre to the farthest edge of the reticle, outline included.
func radius() -> float:
	return gap + arm_length + outline
