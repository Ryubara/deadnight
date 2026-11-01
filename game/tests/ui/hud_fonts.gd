class_name HudFonts
extends RefCounted
## The faces a HUD test runs under: the engine fallback (no file), a synthetic wide face made of
## the fallback font (a typeface wider than the one we ship), and Marquee, the pairing the game
## ships (Bungee Inline and Barlow Condensed, committed under `assets/fonts`). Any other pairing of
## the type review (`TypographyPairings`) can be read from the workspace's `refs/fonts` for a
## capture, as `pair:<id>`. The HUD reads the tokens as its parts are made, so apply a face, build
## the HUD, then `reset()`.

const FALLBACK := &"fallback"
const WIDE := &"wide"
const MARQUEE := &"marquee"
## The faces the game ships. They are read from the files, not from the game's tokens: a test
## changes the tokens in force (the one resource the project setting names), and `reset()` must
## put the files' faces back.
const SHIPPED_DISPLAY := preload("res://assets/fonts/bungee_inline/BungeeInline-Regular.ttf")
const SHIPPED_TEXT := preload("res://assets/fonts/barlow_condensed/BarlowCondensed-SemiBold.ttf")
## Stretch of the synthetic face; Bungee Inline sets about this much wider than the fallback.
const WIDE_STRETCH := 1.4
const WIDE_TRACKING := 2


## Every face to test with.
static func available() -> Array[StringName]:
	return [FALLBACK, WIDE, MARQUEE]


## The folder of font files (`DEADNIGHT_FONTS`, else `refs/fonts` found by walking up from the
## project), or "" when there is none.
static func fonts_dir() -> String:
	var from_env := OS.get_environment("DEADNIGHT_FONTS")
	if from_env != "" and DirAccess.dir_exists_absolute(from_env):
		return from_env
	var folder := ProjectSettings.globalize_path("res://").simplify_path()
	for _step in 8:
		var candidate := folder.path_join("refs/fonts")
		if DirAccess.dir_exists_absolute(candidate):
			return candidate
		folder = folder.get_base_dir()
	return ""


## Sets the active tokens' two faces for `kind`; false when that face is not available here.
static func apply(kind: StringName) -> bool:
	var tokens := UITokens.active()
	if String(kind).begins_with("pair:"):
		return _pairing(tokens, String(kind).trim_prefix("pair:"))
	match kind:
		FALLBACK:
			tokens.font_display = null
			tokens.font_text = null
			tokens.font_mono = null
		WIDE:
			tokens.font_display = _wide()
			tokens.font_text = _wide()
		MARQUEE:
			tokens.font_display = SHIPPED_DISPLAY
			tokens.font_text = SHIPPED_TEXT
			tokens.font_mono = null
	return true


## Back to the faces the game ships.
static func reset() -> void:
	apply(MARQUEE)


static func _wide() -> FontVariation:
	var face := FontVariation.new()
	face.base_font = ThemeDB.fallback_font
	face.variation_transform = Transform2D(
		Vector2(WIDE_STRETCH, 0.0), Vector2(0.0, 1.0), Vector2.ZERO
	)
	face.spacing_glyph = WIDE_TRACKING
	return face


## Any pairing of the type review (`TypographyPairings`) from the workspace's font folder, for
## captures that compare candidates: `pair:ticket`.
static func _pairing(tokens: UITokens, id: String) -> bool:
	if fonts_dir() == "":
		return false
	for pairing: Dictionary in TypographyPairings.ALL:
		if pairing["id"] == id:
			tokens.font_display = TypographyPairings.load_face(pairing["display"], fonts_dir())
			tokens.font_text = TypographyPairings.load_face(pairing["text"], fonts_dir())
			return tokens.font_display != null and tokens.font_text != null
	return false
