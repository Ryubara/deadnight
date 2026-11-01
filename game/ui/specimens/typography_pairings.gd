class_name TypographyPairings
extends RefCounted
## The typeface pairings under review (issue #24), and the loading of their font files.
##
## The font files are third-party and stay outside the repository: they are read at run time by
## absolute path from a fonts folder (`<workspace>/refs/fonts/<family>/`), so nothing licensed
## enters the project. Nothing here is the game's choice yet; the maintainer picks.

const WGHT := "wght"
const WDTH := "wdth"

## Each pairing: a display face (title, marquee, big numbers) and a text face (menus, captions).
## `file` is relative to the fonts folder; `axes` are OpenType variation axes for variable fonts;
## `track` is extra pixels between letters. `hud` names the face for the big numbers ("display" by
## default) and `hud_size` their size in pixels (default 150).
const ALL: Array[Dictionary] = [
	{
		"id": "marquee",
		"name": "Marquee",
		"title": "DEADNIGHT",
		"display": {"file": "bungeeinline/BungeeInline-Regular.ttf", "track": 2, "size": 150},
		"text": {"file": "barlowcondensed/BarlowCondensed-SemiBold.ttf", "track": 3, "size": 46},
		"upper_menu": true,
		"neon": false,
	},
	{
		"id": "neon-script",
		"name": "Neon script",
		"title": "Deadnight",
		"display": {"file": "yellowtail/Yellowtail-Regular.ttf", "track": 0, "size": 200},
		"text": {"file": "jost/Jost[wght].ttf", "axes": {WGHT: 500}, "track": 2, "size": 40},
		"upper_menu": false,
		"neon": true,
		"hud": "text",
		"hud_size": 120,
	},
	{
		"id": "ticket",
		"hud_size": 180,
		"name": "Ticket stub",
		"title": "DEADNIGHT",
		"display":
		{
			"file": "bigshouldersdisplay/BigShouldersDisplay[wght].ttf",
			"axes": {WGHT: 900},
			"track": 4,
			"size": 190
		},
		"text": {"file": "courierprime/CourierPrime-Bold.ttf", "track": 2, "size": 38},
		"upper_menu": true,
		"neon": false,
	},
	{
		"id": "b-movie",
		"name": "B-movie poster",
		"title": "DEADNIGHT",
		"display": {"file": "bowlbyone/BowlbyOne-Regular.ttf", "track": 0, "size": 140},
		"text":
		{
			"file": "archivo/Archivo[wdth,wght].ttf",
			"axes": {WGHT: 600, WDTH: 75},
			"track": 3,
			"size": 46
		},
		"upper_menu": true,
		"neon": false,
	},
	{
		"id": "atomic",
		"name": "Atomic age",
		"title": "DEADNIGHT",
		"display": {"file": "atomicage/AtomicAge-Regular.ttf", "track": 2, "size": 120},
		"text":
		{"file": "josefinsans/JosefinSans[wght].ttf", "axes": {WGHT: 600}, "track": 3, "size": 40},
		"upper_menu": true,
		"neon": false,
	},
	{
		"id": "diner",
		"name": "Diner",
		"title": "Deadnight",
		"display": {"file": "fontdinerswanky/FontdinerSwanky-Regular.ttf", "track": 2, "size": 150},
		"text":
		{
			"file": "librefranklin/LibreFranklin[wght].ttf",
			"axes": {WGHT: 600},
			"track": 1,
			"size": 36
		},
		"upper_menu": false,
		"neon": false,
	},
	{
		"id": "gothic",
		"hud_size": 210,
		"name": "Poster gothic",
		"title": "DEADNIGHT",
		"display":
		{
			"file": "leaguegothic/LeagueGothic[wdth].ttf",
			"axes": {WDTH: 100},
			"track": 6,
			"size": 230
		},
		"text": {"file": "specialelite/SpecialElite-Regular.ttf", "track": 1, "size": 36},
		"upper_menu": true,
		"neon": false,
	},
	{
		"id": "tube",
		"name": "Neon tube",
		"title": "DEADNIGHT",
		"display": {"file": "monoton/Monoton-Regular.ttf", "track": 2, "size": 120},
		"text": {"file": "barlowcondensed/BarlowCondensed-Medium.ttf", "track": 3, "size": 46},
		"upper_menu": true,
		"neon": true,
	},
	{
		"id": "deco",
		"name": "Deco palace",
		"title": "DEADNIGHT",
		"display": {"file": "limelight/Limelight-Regular.ttf", "track": 4, "size": 140},
		"text":
		{"file": "josefinsans/JosefinSans[wght].ttf", "axes": {WGHT: 500}, "track": 4, "size": 40},
		"upper_menu": true,
		"neon": false,
	},
	{
		"id": "slab",
		"name": "Slab",
		"title": "DEADNIGHT",
		"display": {"file": "alfaslabone/AlfaSlabOne-Regular.ttf", "track": 2, "size": 140},
		"text": {"file": "courierprime/CourierPrime-Bold.ttf", "track": 2, "size": 38},
		"upper_menu": true,
		"neon": false,
	},
]


## Load one face of a pairing (`pairing["display"]` or `pairing["text"]`) from `fonts_dir`.
## Returns null (and prints a warning) when the file is missing.
static func load_face(face: Dictionary, fonts_dir: String) -> FontVariation:
	var path := fonts_dir.path_join(str(face["file"]))
	var file := FontFile.new()
	if file.load_dynamic_font(path) != OK:
		push_warning("Font file not found: " + path)
		return null
	var variation := FontVariation.new()
	variation.base_font = file
	variation.spacing_glyph = int(face.get("track", 0))
	var axes: Dictionary = face.get("axes", {})
	var coordinates := {}
	for axis: String in axes:
		coordinates[TextServerManager.get_primary_interface().name_to_tag(axis)] = axes[axis]
	variation.variation_opentype = coordinates
	return variation
