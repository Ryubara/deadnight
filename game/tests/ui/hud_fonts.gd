class_name HudFonts
extends RefCounted
## The faces a HUD test runs under: the engine fallback (no file), a synthetic wide face made of
## the fallback font (so a pipeline without font files still tests a wide typeface), and the Marquee
## pairing from the workspace's `refs/fonts` when the folder exists. Fonts are read at run time and
## never committed. The HUD reads the tokens as its parts are made, so apply a face, build the HUD,
## then `reset()`.

const FALLBACK := &"fallback"
const WIDE := &"wide"
const MARQUEE := &"marquee"
## Stretch of the synthetic face; Bungee Inline sets about this much wider than the fallback.
const WIDE_STRETCH := 1.4
const WIDE_TRACKING := 2


## Every face to test with; Marquee only when its files are present.
static func available() -> Array[StringName]:
	var found: Array[StringName] = [FALLBACK, WIDE]
	if fonts_dir() != "":
		found.append(MARQUEE)
	return found


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
	match kind:
		FALLBACK:
			tokens.font_display = null
			tokens.font_text = null
		WIDE:
			tokens.font_display = _wide()
			tokens.font_text = _wide()
		MARQUEE:
			if fonts_dir() == "":
				return false
			var pairing: Dictionary = TypographyPairings.ALL[0]
			tokens.font_display = TypographyPairings.load_face(pairing["display"], fonts_dir())
			tokens.font_text = TypographyPairings.load_face(pairing["text"], fonts_dir())
			return tokens.font_display != null and tokens.font_text != null
	return true


static func reset() -> void:
	apply(FALLBACK)


static func _wide() -> FontVariation:
	var face := FontVariation.new()
	face.base_font = ThemeDB.fallback_font
	face.variation_transform = Transform2D(
		Vector2(WIDE_STRETCH, 0.0), Vector2(0.0, 1.0), Vector2.ZERO
	)
	face.spacing_glyph = WIDE_TRACKING
	return face
