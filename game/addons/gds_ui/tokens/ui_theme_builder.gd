class_name UIThemeBuilder
extends RefCounted
## Builds the Godot Theme from UITokens, so no theme is ever hand-edited.
##
## Components are drawn in code (UIButton, UIPanel); the theme only supplies type, colour and
## content margins through type variations, and a usable look for plain controls.

const LABEL_STYLES: Array[StringName] = [
	&"UILabelDisplay",
	&"UILabelTitle",
	&"UILabelHeading",
	&"UILabelBody",
	&"UILabelCaption",
	&"UILabelOverline",
	&"UILabelMono",
]
const BUTTON_STYLES: Array[StringName] = [
	&"UIButtonPrimary", &"UIButtonSecondary", &"UIButtonGhost"
]
const PANEL_STYLES: Array[StringName] = [&"UIPanelFlat", &"UIPanelRaised", &"UIPanelMarquee"]

const TOGGLE_STYLE := &"UIToggle"
const SLIDER_STYLE := &"UISlider"
const OPTION_TYPE := &"UIOptionSelector"
const CHECK_STYLE := &"UICheckBox"
const LINE_EDIT_STYLE := &"UILineEdit"
const ITEM_LIST_TYPE := &"UIItemList"

const BUTTON_STATES: Array[StringName] = [
	&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"
]


static func build(tokens: UITokens = null) -> Theme:
	var t := tokens if tokens != null else UITokens.active()
	var theme := Theme.new()
	theme.default_font = t.text_font()
	theme.default_font_size = t.size_body
	_add_labels(theme, t)
	_add_buttons(theme, t)
	_add_panels(theme, t)
	_add_controls(theme, t)
	_add_plain_controls(theme, t)
	return theme


static func _add_labels(theme: Theme, t: UITokens) -> void:
	# name, face, size, colour, embolden, tracking, drop shadow. Display and title type take the
	# display face; everything that is read at a smaller size takes the text face (an inline or
	# decorative display face fills in there), and mono is for tabular figures and code.
	var display := t.display_font
	var text := t.text_font
	var mono := t.mono_font
	var rows := [
		[LABEL_STYLES[0], display, t.size_display, t.accent_bright, t.embolden_display, 0.0, true],
		[LABEL_STYLES[1], display, t.size_title, t.ink, t.embolden_display, 0.0, true],
		[
			LABEL_STYLES[2],
			text,
			t.size_heading,
			t.ink,
			t.embolden_display * t.embolden_heading_ratio,
			0.0,
			false
		],
		[LABEL_STYLES[3], text, t.size_body, t.ink, 0.0, 0.0, false],
		[LABEL_STYLES[4], text, t.size_caption, t.ink_muted, 0.0, 0.0, false],
		[LABEL_STYLES[5], text, t.size_overline, t.accent, 0.0, t.tracking_wide, false],
		[LABEL_STYLES[6], mono, t.size_body, t.ink, 0.0, 0.0, false],
	]
	for row in rows:
		var type: StringName = row[0]
		var make: Callable = row[1]
		theme.set_type_variation(type, &"Label")
		theme.set_font(&"font", type, make.call(row[4], row[5]))
		theme.set_font_size(&"font_size", type, row[2])
		theme.set_color(&"font_color", type, row[3])
		if row[6]:
			theme.set_color(&"font_shadow_color", type, t.shadow)
			theme.set_constant(&"shadow_offset_x", type, 0)
			theme.set_constant(&"shadow_offset_y", type, maxi(2, int(row[2] * 0.04)))


static func _add_buttons(theme: Theme, t: UITokens) -> void:
	# name, text colour. The hover and pressed text colours equal the rest colour: a variant's
	# fill moves on hover, its text does not.
	var rows := [
		[BUTTON_STYLES[0], t.ink_on_accent],
		[BUTTON_STYLES[1], t.ink],
		[BUTTON_STYLES[2], t.accent_bright],
	]
	for row in rows:
		var type: StringName = row[0]
		var ink: Color = row[1]
		theme.set_type_variation(type, &"Button")
		theme.set_font(
			&"font",
			type,
			t.text_font(t.embolden_display * t.embolden_button_ratio, t.tracking_wide)
		)
		theme.set_font_size(&"font_size", type, t.size_button)
		for color_name in [
			&"font_color",
			&"font_hover_color",
			&"font_pressed_color",
			&"font_hover_pressed_color",
			&"font_focus_color",
		]:
			theme.set_color(color_name, type, ink)
		theme.set_color(&"font_disabled_color", type, t.ink_disabled)
		for state in BUTTON_STATES:
			theme.set_stylebox(state, type, _margins(StyleBoxEmpty.new(), t.space_md, t.space_xl))


static func _add_panels(theme: Theme, t: UITokens) -> void:
	for type in PANEL_STYLES:
		theme.set_type_variation(type, &"PanelContainer")
		theme.set_stylebox(&"panel", type, _margins(StyleBoxEmpty.new(), t.space_lg, t.space_xl))


## The settings controls draw themselves; the theme gives them type, and the slider an invisible
## grabber of the thumb's size so the engine's hit-testing matches the drawing.
static func _add_controls(theme: Theme, t: UITokens) -> void:
	theme.set_type_variation(TOGGLE_STYLE, &"Button")
	for state in BUTTON_STATES:
		theme.set_stylebox(state, TOGGLE_STYLE, StyleBoxEmpty.new())
	theme.set_type_variation(SLIDER_STYLE, &"HSlider")
	for part in [&"slider", &"grabber_area", &"grabber_area_highlight"]:
		theme.set_stylebox(part, SLIDER_STYLE, StyleBoxEmpty.new())
	var blank := Image.create_empty(t.control_height, t.control_height, false, Image.FORMAT_RGBA8)
	var thumb := ImageTexture.create_from_image(blank)
	for icon in [&"grabber", &"grabber_highlight", &"grabber_disabled"]:
		theme.set_icon(icon, SLIDER_STYLE, thumb)
	theme.set_font(
		&"font", OPTION_TYPE, t.text_font(t.embolden_display * t.embolden_option_ratio, 0.0)
	)
	theme.set_font_size(&"font_size", OPTION_TYPE, t.size_body)
	theme.set_font(
		&"font", ITEM_LIST_TYPE, t.text_font(t.embolden_display * t.embolden_option_ratio, 0.0)
	)
	theme.set_font_size(&"font_size", ITEM_LIST_TYPE, t.size_body)
	_add_check_box(theme, t)
	_add_line_edit(theme, t)
	_add_scroll_bars(theme, t)
	_add_scroll_room(theme, t)


## The check box draws its box; the theme gives its label the body face and leaves room for the box.
static func _add_check_box(theme: Theme, t: UITokens) -> void:
	theme.set_type_variation(CHECK_STYLE, &"Button")
	theme.set_font(
		&"font", CHECK_STYLE, t.text_font(t.embolden_display * t.embolden_option_ratio, 0.0)
	)
	theme.set_font_size(&"font_size", CHECK_STYLE, t.size_body)
	for color_name in [
		&"font_color",
		&"font_hover_color",
		&"font_pressed_color",
		&"font_hover_pressed_color",
		&"font_focus_color",
	]:
		theme.set_color(color_name, CHECK_STYLE, t.ink)
	theme.set_color(&"font_disabled_color", CHECK_STYLE, t.ink_disabled)
	var left := t.space_sm + UICheckBox.box_size(t) + t.space_md
	for state in BUTTON_STATES:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = left
		box.content_margin_right = t.space_md
		theme.set_stylebox(state, CHECK_STYLE, box)


## The text field: a raised fill with the outline, the accent border while it has focus.
static func _add_line_edit(theme: Theme, t: UITokens) -> void:
	theme.set_type_variation(LINE_EDIT_STYLE, &"LineEdit")
	theme.set_font(
		&"font", LINE_EDIT_STYLE, t.text_font(t.embolden_display * t.embolden_option_ratio, 0.0)
	)
	theme.set_font_size(&"font_size", LINE_EDIT_STYLE, t.size_body)
	theme.set_color(&"font_color", LINE_EDIT_STYLE, t.ink)
	theme.set_color(&"font_uneditable_color", LINE_EDIT_STYLE, t.ink_muted)
	theme.set_color(&"font_placeholder_color", LINE_EDIT_STYLE, t.ink_disabled)
	theme.set_color(&"font_selected_color", LINE_EDIT_STYLE, t.ink_on_accent)
	theme.set_color(&"caret_color", LINE_EDIT_STYLE, t.accent_bright)
	theme.set_color(&"selection_color", LINE_EDIT_STYLE, Color(t.accent, 0.85))
	var rows := {
		&"normal": [t.surface_raised, t.outline],
		&"focus": [t.surface_raised, t.accent],
		&"read_only": [t.surface, t.outline],
	}
	for state in rows:
		var box := _flat(rows[state][0], rows[state][1], t, t.space_md)
		box.content_margin_left = t.space_lg
		box.content_margin_right = t.space_lg
		theme.set_stylebox(state, LINE_EDIT_STYLE, box)


## Scroll bars (any ScrollContainer, and the plain engine ones): a thin track and a rounded thumb
## that warms on hover and press.
static func _add_scroll_bars(theme: Theme, t: UITokens) -> void:
	var thickness := t.border * 3
	var track := _pill(Color(t.surface, 0.0), thickness)
	var thumbs := {
		&"grabber": t.ink_disabled,
		&"grabber_highlight": t.accent,
		&"grabber_pressed": t.accent_bright,
	}
	for kind in [&"VScrollBar", &"HScrollBar"]:
		theme.set_stylebox(&"scroll", kind, track)
		theme.set_stylebox(&"scroll_focus", kind, track)
		for part in thumbs:
			theme.set_stylebox(part, kind, _pill(thumbs[part], thickness))


## Every ScrollContainer keeps `hover_room` free at its left and right and `scroll_room` above and
## below: a scroll area cuts off what sticks out of it, and a hovered button grows past its slot
## (#628) while the focus ring is drawn outside the button (#644). The margin is empty space at the
## ends of the content only; a screen that sizes the area from its content adds
## `UIScroll.margins` to it.
static func _add_scroll_room(theme: Theme, t: UITokens) -> void:
	var room := StyleBoxEmpty.new()
	room.content_margin_left = t.hover_room
	room.content_margin_right = t.hover_room
	room.content_margin_top = t.scroll_room
	room.content_margin_bottom = t.scroll_room
	theme.set_stylebox(&"panel", &"ScrollContainer", room)


static func _pill(fill: Color, thickness: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.anti_aliasing = true
	box.set_corner_radius_all(thickness)
	box.set_content_margin_all(thickness * 0.5)
	return box


static func _add_plain_controls(theme: Theme, t: UITokens) -> void:
	theme.set_color(&"font_color", &"Label", t.ink)
	theme.set_stylebox(&"panel", &"PanelContainer", _flat(t.surface, t.outline, t, t.space_lg))
	var fills := {
		&"normal": t.surface_raised,
		&"hover": t.surface_raised.lightened(t.tint_hover),
		&"pressed": t.surface.darkened(t.tint_press),
		&"hover_pressed": t.surface.darkened(t.tint_press),
		&"disabled": t.surface,
		&"focus": Color.TRANSPARENT,
	}
	for state in fills:
		var box := _flat(fills[state], t.outline, t, t.space_md)
		if state == &"focus":
			box.draw_center = false
			box.border_color = t.accent_bright
		theme.set_stylebox(state, &"Button", box)
	theme.set_color(&"font_color", &"Button", t.ink)
	theme.set_color(&"font_hover_color", &"Button", t.ink)
	theme.set_color(&"font_disabled_color", &"Button", t.ink_disabled)


static func _margins(box: StyleBox, vertical: int, horizontal: int) -> StyleBox:
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	return box


static func _flat(fill: Color, edge: Color, t: UITokens, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(t.border)
	box.set_corner_radius_all(t.radius_md)
	box.set_content_margin_all(pad)
	return box
