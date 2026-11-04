class_name PlatePalettes
extends RefCounted
## The colours a calling card or an emblem is painted in: a ground, a base colour, a light and a
## dark (`PlateShapes.Role`). Each is one family of colours, so a piece made of any part reads as
## one thing. The names are what `plate_pieces.json` uses.

const SETS := {
	&"brass": ["#c8943a", "#f1d58a", "#1c1208", "#3a2a14"],
	&"sunset": ["#f08a2c", "#ffd9a0", "#1f0f06", "#4a2412"],
	&"chrome": ["#9aa6b2", "#e8eef4", "#12161a", "#2b3138"],
	&"teal": ["#2fb5a8", "#bff5ea", "#07191a", "#0f3b3d"],
	&"violet": ["#8f5be0", "#d9c4ff", "#120a24", "#2a1c4a"],
	&"moss": ["#68b04a", "#d6f2b0", "#0d1a0e", "#1f3820"],
	&"cherry": ["#c8323c", "#ffb0a8", "#240810", "#5a1420"],
	&"ice": ["#4fc3f7", "#d6f3ff", "#08141f", "#123048"],
	&"neon": ["#ff4fb4", "#ffd0ee", "#1a0618", "#3a0f35"],
	&"gold": ["#f2c230", "#fff0a8", "#1f1804", "#4a3a0c"],
	&"ivory": ["#e8e0cc", "#ffffff", "#2a2622", "#4a423a"],
}
const FALLBACK := &"chrome"


static func names() -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(SETS.keys())
	return found


static func has(palette: StringName) -> bool:
	return SETS.has(palette)


## The colour of `role` in `palette` (the chrome set for a name nobody knows).
static func colour(palette: StringName, role: int) -> Color:
	var colours: Array = SETS.get(palette, SETS[FALLBACK])
	return Color(String(colours[role]))
