class_name PosterSetView
extends Button
## One poster set on the Challenges tab, read from an entry of `ChallengeBoard.poster_sets()`.
## Two sizes: the **teaser** (the All view): a small poster, the title, how many panels are
## uncovered as a punch card; and the **full set** (the Poster sets view): the poster at the left
## with a panel for each challenge done, and at the right the title, how far the set is, the six
## challenges as numbered rows and what finishing it wins (a calling card and an emblem). On a
## phone the poster is smaller and the rows go under it. It is a button so a pad walks the list
## and the scroll follows; pressing it opens the full set from the teaser, and does nothing in it.

const PAD := 18.0
const POSTER_WIDTH := 250.0
const POSTER_WIDTH_COMPACT := 150.0
const TEASER_POSTER := 56.0
const ROW_HEIGHT := 46.0
const PRIZE_CARD_WIDTH := 150.0
const PRIZE_EMBLEM := 46.0
const DISC := 30.0
## Above and below the full set.
const MARGIN := 10.0

var entry: Dictionary = {}
var poster: PosterArt

var _teaser := false


## The full set for `data`, `width` units wide.
static func make_full(data: Dictionary, width: float, compact: bool) -> PosterSetView:
	var view := PosterSetView.new()
	view.entry = data
	view._build_full(width, compact)
	return view


## The teaser for `data`, `width` units wide.
static func make_teaser(data: Dictionary, width: float) -> PosterSetView:
	var view := PosterSetView.new()
	view.entry = data
	view._teaser = true
	view._build_teaser(width)
	return view


## "4 of 6 panels uncovered", or "Finished" for a whole set.
static func progress_text(data: Dictionary) -> String:
	if data.get("done", false):
		return "All 6 panels uncovered"
	return "%d of %d panels uncovered" % [int(data["count"]), int(data["total"])]


func _init() -> void:
	UiSounds.wire(self)
	flat = true
	focus_mode = Control.FOCUS_ALL
	# Inside a scroll area a drag that starts here reaches it (`UIScroll`); anywhere else the button
	# stops the pointer, as a button does.
	UIScroll.pass_touch_in_scroll(self)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(queue_redraw)


func ui_sound_role() -> StringName:
	return &"sheet_row_swap" if _teaser else &"sheet_row"


## The words the title says.
func title_text() -> String:
	return String(entry.get("title", ""))


## How many numbered rows the full set shows, for tests.
func row_count() -> int:
	var found := 0
	for node in find_children("SetRow*", "Control", true, false):
		found += 1
	return found


func _build_teaser(width: float) -> void:
	custom_minimum_size = Vector2(width, 110.0)
	accessibility_name = "%s, %s" % [title_text(), progress_text(entry)]
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = PAD
	line.offset_right = -PAD
	line.offset_top = 8.0
	line.offset_bottom = -8.0
	line.add_theme_constant_override(&"separation", 18)
	add_child(line)
	poster = _poster(TEASER_POSTER, false)
	poster.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(poster)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 2)
	line.add_child(column)
	var title := MenuLook.label(title_text(), MenuLook.SIZE_BODY, MenuLook.PAPER_INK)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	var low := HBoxContainer.new()
	low.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(low)
	var note := MenuLook.label(
		progress_text(entry).to_upper(),
		MenuLook.SIZE_CAPTION,
		MenuLook.RED,
		&"wide",
		HORIZONTAL_ALIGNMENT_LEFT
	)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	low.add_child(note)
	low.add_child(MenuLook.Punches.new(PosterSet.PANELS, int(entry["count"])))


func _build_full(width: float, compact: bool) -> void:
	accessibility_name = "%s, %s" % [title_text(), progress_text(entry)]
	var wide := POSTER_WIDTH_COMPACT if compact else POSTER_WIDTH
	var inner := width - 2.0 * PAD
	var body := MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override(&"margin_left", int(PAD))
	body.add_theme_constant_override(&"margin_right", int(PAD))
	body.add_theme_constant_override(&"margin_top", int(MARGIN))
	body.add_theme_constant_override(&"margin_bottom", int(MARGIN))
	add_child(body)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 10)
	body.add_child(column)
	poster = _poster(wide, true)
	poster.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var head := VBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override(&"separation", 6)
	# The title is broken into lines here, by the room beside the poster: a label that wraps by itself
	# does not know how tall it is until it is laid out, and the height of the set depends on it.
	var broken := _broken(title_text(), maxf(inner - wide - 40.0, 1.0))
	var head_lines := broken.count("\n") + 1
	var title := MenuLook.label(broken, MenuLook.SIZE_TITLE, MenuLook.PAPER_INK, &"display")
	head.add_child(title)
	head.add_child(
		MenuLook.label(
			progress_text(entry).to_upper(), MenuLook.SIZE_CAPTION, MenuLook.RED, &"wide"
		)
	)
	head.add_child(MenuLook.Punches.new(PosterSet.PANELS, int(entry["count"])))
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", 0)
	for panel: Dictionary in entry["panels"]:
		rows.add_child(_row(panel))
	if compact:
		# A phone: the poster beside the title and how far it is, the rows and the prize under.
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override(&"separation", 18)
		top.add_child(poster)
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_child(head)
		column.add_child(top)
		column.add_child(rows)
		column.add_child(_prize(inner))
		custom_minimum_size = Vector2(width, _height(true, head_lines))
		return
	var side := VBoxContainer.new()
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override(&"separation", 12)
	side.add_child(head)
	side.add_child(rows)
	side.add_child(_prize(inner - wide - 22.0))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", 22)
	line.add_child(poster)
	line.add_child(side)
	column.add_child(line)
	custom_minimum_size = Vector2(width, _height(false, head_lines))


## How tall the full set is: laid out by hand, because a button does not ask what is in it, and a
## container only knows its children's sizes once it is in the tree (the list that holds the set
## sorts before that). A few units over, never under.
func _height(compact: bool, title_lines: int) -> float:
	var caption := MenuLook.wide_font().get_height(MenuLook.SIZE_CAPTION)
	var title := UITokens.active().font_display.get_height(MenuLook.SIZE_TITLE) * title_lines
	var head := title + caption + 12.0 + 22.0
	var card := PRIZE_CARD_WIDTH * 120.0 / 440.0
	var prize := caption + 6.0 + maxf(card, PRIZE_EMBLEM)
	var rows := PosterSet.PANELS * (ROW_HEIGHT + 1.0)
	var poster_height := poster.custom_minimum_size.y
	var body := 0.0
	if compact:
		body = maxf(poster_height, head) + 10.0 + rows + 10.0 + prize
	else:
		body = maxf(poster_height, head + 12.0 + rows + 12.0 + prize)
	return body + 2.0 * MARGIN + 8.0


## `text` with line breaks where the display face would run past `room`.
func _broken(text: String, room: float) -> String:
	var face := UITokens.active().font_display
	var lines: Array[String] = []
	var line := ""
	for word in text.split(" "):
		var tried := word if line == "" else line + " " + word
		var span := face.get_string_size(tried, HORIZONTAL_ALIGNMENT_LEFT, -1, MenuLook.SIZE_TITLE)
		if line != "" and span.x > room:
			lines.append(line)
			line = word
		else:
			line = tried
	lines.append(line)
	return "\n".join(lines)


func _poster(width: float, print_title: bool) -> PosterArt:
	var poster_set := PosterSets.shipped().get_set(StringName(entry["id"]))
	var found: Array[int] = []
	found.assign(entry.get("uncovered", []))
	return PosterArt.make(poster_set, width, found, print_title)


## A numbered row: a disc with the panel's number (filled and ticked when done), the words of the
## challenge and whether it is done.
func _row(panel: Dictionary) -> Control:
	var done: bool = panel["done"]
	var box := HBoxContainer.new()
	box.name = "SetRow%d" % int(panel["n"])
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.y = ROW_HEIGHT
	box.add_theme_constant_override(&"separation", 14)
	var disc := NumberDisc.new(int(panel["n"]), done)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(disc)
	var words := MenuLook.label(
		String(panel["text"]),
		MenuLook.SIZE_BODY,
		MenuLook.PAPER_MUTED if done else MenuLook.PAPER_INK
	)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(words)
	var status := (
		"Done" if done else MenuNav.fraction_text(int(panel["progress"]), int(panel["target"]))
	)
	var state := MenuLook.label(
		status.to_upper(),
		MenuLook.SIZE_CAPTION,
		MenuLook.RED if done else MenuLook.PAPER_MUTED,
		&"wide",
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(state)
	var wrapper := VBoxContainer.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_theme_constant_override(&"separation", 0)
	wrapper.add_child(box)
	wrapper.add_child(MenuLook.hairline(MenuLook.PAPER_RULE))
	return wrapper


## "Finish the set": the calling card and the emblem it wins.
func _prize(width: float) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	var done: bool = entry.get("done", false)
	box.add_child(
		MenuLook.label(
			"WON FOR THE SET" if done else "FINISH THE SET",
			MenuLook.SIZE_CAPTION,
			MenuLook.RED,
			&"wide"
		)
	)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", 18)
	box.add_child(line)
	var plates := PlateCatalog.shipped()
	var card := CardArt.new()
	card.card_id = StringName(entry["card"])
	card.custom_minimum_size = Vector2(PRIZE_CARD_WIDTH, PRIZE_CARD_WIDTH * 120.0 / 440.0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.titled = true
	line.add_child(card)
	var emblem := EmblemArt.make(StringName(entry["emblem"]), PRIZE_EMBLEM)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(emblem)
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(
		MenuLook.label(
			"%s card" % plates.title(PlateCatalog.CARD, StringName(entry["card"])),
			MenuLook.SIZE_CAPTION,
			MenuLook.PAPER_INK
		)
	)
	names.add_child(
		MenuLook.label(
			"%s emblem" % plates.title(PlateCatalog.EMBLEM, StringName(entry["emblem"])),
			MenuLook.SIZE_CAPTION,
			MenuLook.PAPER_INK
		)
	)
	line.add_child(names)
	box.custom_minimum_size.x = minf(width, 640.0)
	return box


func _on_hover() -> void:
	grab_focus()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0.0, size.y - 1.0, size.x, 1.0), MenuLook.PAPER_RULE)
	if has_focus() or is_hovered():
		draw_rect(Rect2(Vector2.ZERO, size), Color(MenuLook.RED, 0.10))
		draw_rect(Rect2(0.0, 0.0, 4.0, size.y), MenuLook.RED)


## The number of a panel in a disc: ink on paper while to do, red with a tick once done.
class NumberDisc:
	extends Control
	var number := 1
	var done := false

	func _init(n: int, is_done: bool) -> void:
		number = n
		done = is_done
		custom_minimum_size = Vector2.ONE * PosterSetView.DISC
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var centre := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 1.5
		if done:
			draw_circle(centre, radius, MenuLook.RED)
			var tick := PackedVector2Array(
				[
					centre + Vector2(-radius * 0.45, 0.0),
					centre + Vector2(-radius * 0.1, radius * 0.38),
					centre + Vector2(radius * 0.5, -radius * 0.38),
				]
			)
			draw_polyline(tick, MenuLook.PAPER, 3.0, true)
			return
		draw_circle(centre, radius, MenuLook.PAPER_SHADE)
		draw_arc(centre, radius, 0.0, TAU, 24, MenuLook.PAPER_MUTED, 1.5, true)
		var font := MenuLook.wide_font()
		var px := 20
		var text := str(number)
		var span := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		draw_string(
			font,
			Vector2(
				centre.x - span.x * 0.5,
				centre.y + (font.get_ascent(px) - font.get_descent(px)) * 0.5
			),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			px,
			MenuLook.PAPER_INK
		)
