class_name PhoneRender
extends RefCounted
## How the picture is drawn on a phone (#689). A phone's screen has three times the pixels a page
## asks for (a pixel ratio of 3: 2532 x 1170 for an 844 x 390 page) and a GPU that is slow at
## filling them and shares its power with the rest of the phone. Two things keep the fill cost
## down, neither of which a player can tell from the picture:
##
## - The page reports a pixel ratio of at most `PIXEL_RATIO_CAP` to the engine, which sizes its
##   canvas by it (`html/head_include` in `export_presets.cfg` carries the same number; a test pins
##   them together). A ratio of 2 is 326 pixels to the inch, past what the eye separates at arm's
##   length, and draws 44 % fewer pixels than a ratio of 3. The browser stretches the canvas.
## - No multisample anti-aliasing on the 3D view (`apply`): at that density the stair-steps it
##   smooths are under a pixel of the real screen, and the multisample buffer is the biggest single
##   cost of a frame on a GPU that is limited by the pixels it fills.
##
## A desktop browser and a native build are not touched. Resolution scale in the settings is not
## the tool for this on the web: a scale under 100 made a frame 2.4 times slower in Chrome (see
## `docs/research/phone-frames.md`).

## The most the page reports as its pixel ratio on a touch device.
const PIXEL_RATIO_CAP := 2.0


## Applies the phone's drawing choices to `viewport` (the root's, where the night is drawn).
static func apply(viewport: Viewport) -> void:
	if wanted():
		viewport.msaa_3d = Viewport.MSAA_DISABLED


## Whether this is a phone or a tablet: the same test the touch controls use.
static func wanted() -> bool:
	return TouchMode.detect()
