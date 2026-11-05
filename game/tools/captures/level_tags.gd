extends Control
## The level icons as the game will show them (#1060), through `LevelIcons`: the whole ladder at
## 128 px, the sizes beside the name tags' font, and what eight tags cost to draw. Counts, not
## times. Not part of the game. Windowed, the pictures are written to the folder given:
##
##     gds godot -- --path game res://tools/captures/level_tags.tscn --resolution 1760x960
##         -- --out=<folder> [--no-mipmaps]
##
## In the web build `tools/web_smoke/level_tags_cost.py` reads `window.__level_tags`, and the same
## counts print as `LEVELTAGS {json}`.

const COUNT_FRAMES := 4
const SETTLE_FRAMES := 3

const PAGES: Array[StringName] = [&"ladder", &"sizes"]
## Eight tags, each way of drawing them. `empty` is what the frame costs with nothing on it.
const CASES: Array[StringName] = [
	&"empty",
	&"icons_one_atlas",
	&"icons_eight_textures",
	&"icon_rects",
	&"tags_icons_first",
	&"tags_interleaved",
]

const NAMES: Array[String] = ["VERA", "RUBY", "THE DUKE", "SAL", "MARGE", "OTTO", "DOT", "HANK"]
const LEVELS: Array[int] = [1, 9, 17, 24, 33, 38, 46, 55]
const TAG_ICON := 24.0
const TAG_GAP := 42
const SIZES: Array[int] = [24, 32, 64]
const LOT := Color("5a5d66")

var _page: StringName = &"empty"
var _tokens: UITokens
var _font: Font
var _manifest: Array = []
var _separate: Array[Texture2D] = []
var _rects: Array[TextureRect] = []


func _ready() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	texture_filter = LevelIcons.FILTER
	if "--no-mipmaps" in OS.get_cmdline_user_args():
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_tokens = load("res://ui/skin/deadnight_tokens.tres") as UITokens
	_font = _tokens.text_font(_tokens.embolden_display * 0.3, 1.0)
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(LevelIcons.MANIFEST_PATH)
	)
	_manifest = manifest["levels"]
	var whole := LevelIcons.atlas().get_image()
	whole.clear_mipmaps()
	whole.convert(Image.FORMAT_RGBA8)
	for i in LEVELS.size():
		var cut := whole.get_region(Rect2i(LevelIcons.region(LEVELS[i])))
		_separate.append(ImageTexture.create_from_image(cut))
		var rect := TextureRect.new()
		rect.texture = LevelIcons.texture(LEVELS[i])
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.position = _tag_at(i)
		rect.size = Vector2.ONE * TAG_ICON
		rect.visible = false
		add_child(rect)
		_rects.append(rect)
	await _run()


func _run() -> void:
	var out := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	for page in PAGES:
		await _show(page)
		_save(out, page)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__level_tags = {page: '%s'};" % page)
			await get_tree().create_timer(1.0).timeout
	var counts := {}
	for case in CASES:
		counts[case] = await _count(case)
	await _show(&"tags_icons_first")
	_save(out, "tags")
	counts["web"] = OS.has_feature("web")
	counts["renderer"] = RenderingServer.get_current_rendering_method()
	var text := JSON.stringify(counts)
	print("LEVELTAGS ", text)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__level_tags = {done: true, counts: %s};" % text)
	else:
		get_tree().quit()


func _show(page: StringName) -> void:
	_page = page
	queue_redraw()
	for _i in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw


func _save(out: String, page: String) -> void:
	if not out.is_empty():
		var picture := get_viewport().get_texture().get_image()
		picture.save_png(out.path_join("level_%s.png" % page))


func _count(case: StringName) -> int:
	for rect in _rects:
		rect.visible = case == &"icon_rects"
	await _show(case)
	var total := 0
	for _i in COUNT_FRAMES:
		await get_tree().process_frame
		total += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return total / COUNT_FRAMES


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LOT if _page != &"ladder" else _tokens.bg)
	match _page:
		&"ladder":
			_draw_ladder()
		&"sizes":
			_draw_sizes()
		&"icons_one_atlas":
			_draw_icons()
		&"icons_eight_textures":
			for i in LEVELS.size():
				draw_texture_rect(_separate[i], Rect2(_tag_at(i), Vector2.ONE * TAG_ICON), false)
		&"tags_icons_first":
			_draw_icons()
			for i in LEVELS.size():
				_draw_words_outline(i)
			for i in LEVELS.size():
				_draw_words(i)
		&"tags_interleaved":
			for i in LEVELS.size():
				_draw_icon(i)
				_draw_words_outline(i)
				_draw_words(i)


func _draw_ladder() -> void:
	const COLUMN := 156.0
	const ROW := 172.0
	var atlas := LevelIcons.atlas(LevelIcons.CELL_LARGE)
	var cell := float(LevelIcons.CELL_LARGE)
	for entry: Dictionary in _manifest:
		var level := int(entry["level"])
		var at := Vector2(LevelIcons.row(level) * COLUMN, LevelIcons.column(level) * ROW)
		at += Vector2(20.0, 56.0)
		if LevelIcons.column(level) == 0:
			var title := str(entry["tier_name"]).to_upper()
			_label(title, at + Vector2(0.0, -24.0), 22, _tokens.hot, COLUMN)
		var place := Rect2(at, Vector2.ONE * cell)
		draw_texture_rect_region(atlas, place, LevelIcons.region(level, LevelIcons.CELL_LARGE))
		_label(str(level), at + Vector2(0.0, cell + 16.0), 22, Color.WHITE, cell)
		_label(str(entry["name"]), at + Vector2(0.0, cell + 36.0), 18, Color("b9b3c9"), COLUMN)


## The ladder at each size a player meets it, a number beside each in the tags' font: on the dark
## of the menus at left, on the lot's asphalt at right.
func _draw_sizes() -> void:
	draw_rect(Rect2(0.0, 0.0, 850.0, size.y), _tokens.bg)
	var y := 16.0
	for pixels in SIZES:
		var cell := pixels + 8.0
		var pitch := Vector2(pixels + 38.0, cell)
		for side in 2:
			if side == 1 and pixels == SIZES[2]:
				continue
			for level in range(1, LevelIcons.LEVELS + 1):
				var at := Vector2(16.0 + side * 860.0, y)
				at += Vector2(LevelIcons.row(level), LevelIcons.column(level)) * pitch
				var place := Rect2(at, Vector2.ONE * pixels)
				draw_texture_rect_region(LevelIcons.atlas(), place, LevelIcons.region(level))
				var baseline := at + Vector2(pixels + 3.0, pixels * 0.5 + 7.0)
				_tag_text(baseline, str(level), Color.WHITE)
		y += 5 * cell + 20.0


func _label(text: String, at: Vector2, font_size: int, colour: Color, width: float) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, colour)


## Text as `HudMarkers` draws it: an outline in the shadow's colour, then the letters.
func _tag_text(at: Vector2, text: String, colour: Color) -> void:
	_tag_outline(at, text)
	_tag_letters(at, text, colour)


func _tag_outline(at: Vector2, text: String) -> void:
	draw_string_outline(
		_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.MIN_TEXT, 7, _tokens.shadow
	)


func _tag_letters(at: Vector2, text: String, colour: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.MIN_TEXT, colour)


func _tag_at(i: int) -> Vector2:
	return Vector2(40.0, 40.0 + i * TAG_GAP)


func _draw_icons() -> void:
	for i in LEVELS.size():
		_draw_icon(i)


func _draw_icon(i: int) -> void:
	var place := Rect2(_tag_at(i), Vector2.ONE * TAG_ICON)
	draw_texture_rect_region(LevelIcons.atlas(), place, LevelIcons.region(LEVELS[i]))


func _words(i: int) -> String:
	return "%s  %d" % [NAMES[i], LEVELS[i]]


func _draw_words_outline(i: int) -> void:
	_tag_outline(_tag_at(i) + Vector2(30.0, 19.0), _words(i))


func _draw_words(i: int) -> void:
	_tag_letters(_tag_at(i) + Vector2(30.0, 19.0), _words(i), _tokens.accent_bright)
