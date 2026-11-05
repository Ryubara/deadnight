extends SceneTree
## Which button a touch presses, over a whole phone page (#1217): one transparent image per rule, a
## pixel of the window coloured by the button `TouchLayout.button_at` gives a finger there, and
## clear where it gives none (the stick or the look). Not part of the game. Run headless:
## `godot --headless --path game -s res://tests/captures/touch_hit_map.gd -- <folder> [ui size]`
## writes `<folder>/map_before.png` (the hit areas as they were, no fingertip rule) and
## `<folder>/map_after.png` (the rule on) for the phone's 1688 x 780 window at the interface size,
## and prints each hit area's width in CSS pixels at the page's pixel ratio of 2.

const WINDOW := Vector2i(1688, 780)
const RATIO := 2.0
const COLOURS := {
	&"pause": Color(0.95, 0.35, 0.35),
	&"ping": Color(0.95, 0.75, 0.2),
	&"scoreboard": Color(0.4, 0.85, 0.4),
	&"quick_melee": Color(0.3, 0.7, 0.95),
	&"bot_wheel": Color(0.75, 0.45, 0.95),
	&"fire": Color(0.95, 0.5, 0.15),
	&"aim": Color(0.2, 0.85, 0.8),
	&"interact": Color(0.9, 0.9, 0.9),
	&"reload": Color(0.55, 0.55, 0.95),
	&"swap_weapon": Color(0.85, 0.45, 0.6),
	&"jump": Color(0.6, 0.8, 0.3),
	&"throw_grenade": Color(0.8, 0.6, 0.4),
	&"swap_shoulder": Color(0.5, 0.7, 0.7),
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if args.size() > 0 else "."
	var ui_scale := float(args[1]) if args.size() > 1 else 0.8
	var per_unit := MenuScale.pixels_per_unit(WINDOW, ui_scale)
	var canvas := Vector2(WINDOW) / per_unit
	var safe := Rect2(Vector2.ZERO, canvas)
	# The unit's size in CSS pixels, and the finger the night asks for (44 CSS px).
	var finger := ceilf(MenuScale.TAP_PIXELS * RATIO / per_unit)
	var css := per_unit / RATIO
	print(
		(
			"interface size %s: one unit is %.3f CSS px, a fingertip is %d units"
			% [ui_scale, css, finger]
		)
	)
	var before := TouchLayout.buttons(safe, 1.0, false, 0.0)
	var after := TouchLayout.buttons(safe, 1.0, false, finger)
	for id: StringName in after:
		print(
			(
				"%s: hit area %.1f CSS px (was %.1f)"
				% [id, after[id][&"hit"] * 2.0 * css, before[id][&"hit"] * 2.0 * css]
			)
		)
	_paint(folder + "/map_before.png", before, per_unit)
	_paint(folder + "/map_after.png", after, per_unit)
	quit()


func _paint(path: String, circles: Dictionary, per_unit: float) -> void:
	var image := Image.create(WINDOW.x, WINDOW.y, false, Image.FORMAT_RGBA8)
	for y in WINDOW.y:
		for x in WINDOW.x:
			var winner := TouchLayout.button_at(
				Vector2(x + 0.5, y + 0.5) / per_unit, circles, [TouchLayout.INTERACT]
			)
			if winner != &"":
				image.set_pixel(x, y, Color(COLOURS.get(winner, Color.WHITE), 0.5))
	image.save_png(path)
