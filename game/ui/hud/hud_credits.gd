class_name HudCredits
extends HudTicket
## The film credits under the players' ticket on the end board (docs/design/progression.md#the-
## night-report-and-credits): one line for every player, the crew title they earned, what it was
## for, their name and the XP the night paid them (nothing where the server told none: a bot, or
## a night nobody keeps). `NightCredits` decides the titles; this only draws them. The rows get less
## height on a short screen (`show_credits`'s `row`), to a floor.

const ROW := 30.0
const MIN_ROW := 26.0
## What the ticket takes besides its rows (the heading's row, the padding and the shadow), for the
## board's sums.
const CHROME := 70.0
const TITLE_WIDTH := 290.0
const NAME_WIDTH := 220.0
const XP_WIDTH := 110.0
const CHIP := Vector2(8.0, 20.0)
## The local player's line is laid on a faint wash of the accent, as on the players' ticket.
const LOCAL_WASH := 0.14
const HEADING := "THAT'S A WRAP: THE CREDITS"

## What the ticket says, for tests and tools: a row is `[title, reason, name, xp]` (xp `+12 XP`, or
## empty), in the order they are drawn, and the player each belongs to.
var rows_text: Array[Array] = []
var row_ids: Array[int] = []
## The height of a row now.
var row_height := ROW

var _tokens := UITokens.active()
var _signature := ""


func _init() -> void:
	super()
	accent = _tokens.accent
	visible = false


## The height of the ticket for `players` rows of `row` canvas units.
static func height_for(players: int, row: float) -> float:
	return CHROME + float(players) * row


## Shows the credits of the players in `members` (`{player_id: {name, seat, bot, ...}}`, the board's
## own) from what the night counted (`ReportTracker.credits_input`), rows `row` tall. `local_id`
## is the viewer's line.
func show_credits(
	members: Dictionary, input: Dictionary, local_id: int, row: float = ROW, crew: CrewTitles = null
) -> void:
	var counts: Dictionary = input.get("counts", {})
	var xp: Dictionary = input.get("xp", {})
	var seats := {}
	for id: int in members:
		seats[id] = int(members[id].get("seat", id))
	var credits := NightCredits.award(counts, seats, crew)
	var heights := clampf(row, MIN_ROW, ROW)
	var signature := (
		"%s|%s|%s|%s|%s" % [heights, local_id, JSON.stringify(credits), xp, _names(members)]
	)
	if signature == _signature:
		return
	_signature = signature
	row_height = heights
	_rebuild(credits, members, xp, local_id)
	visible = not credits.is_empty()


func _rebuild(
	credits: Array[Dictionary], members: Dictionary, xp: Dictionary, local_id: int
) -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	rows_text.clear()
	row_ids.clear()
	var heading := HudStyle.clip(
		HudStyle.label(HEADING, HudStyle.SMALL, _tokens.ink_muted, false, 2.0)
	)
	heading.custom_minimum_size.y = row_height
	heading.clip_text = true
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(heading)
	for credit in credits:
		var id: int = credit["player_id"]
		if not members.has(id):
			continue
		var member: Dictionary = members[id]
		var told := int(xp.get(id, -1))
		var cells: Array[String] = [
			str(credit["title"]).to_upper(),
			str(credit["reason"]).to_upper(),
			HudState.name_of(member),
			"" if told < 0 else "%+d XP" % told,
		]
		rows_text.append(cells)
		row_ids.append(id)
		body.add_child(_row(cells, member, id == local_id))
	update_minimum_size()


func _row(cells: Array[String], member: Dictionary, local: bool) -> Control:
	var wash := PanelContainer.new()
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(_tokens.accent, LOCAL_WASH) if local else Color.TRANSPARENT
	wash.add_theme_stylebox_override(&"panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", HudStyle.SM)
	row.custom_minimum_size.y = row_height
	wash.add_child(row)
	var chip_slot := CenterContainer.new()
	chip_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := ColorRect.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.color = LookCatalog.armband_colour(int(member.get("seat", 0)))
	chip.custom_minimum_size = Vector2(CHIP.x, minf(CHIP.y, row_height - 6.0))
	chip_slot.add_child(chip)
	row.add_child(chip_slot)
	row.add_child(_cell(cells[0], HudStyle.TEXT, _tokens.accent, TITLE_WIDTH, false, true))
	var reason := _cell(cells[1], HudStyle.SMALL, _tokens.ink_muted, 0.0, false)
	reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reason)
	row.add_child(_cell(cells[2], HudStyle.TEXT, _tokens.ink, NAME_WIDTH, false))
	row.add_child(_cell(cells[3], HudStyle.TEXT, _tokens.ink, XP_WIDTH, true))
	return wash


func _cell(
	text: String, size: int, ink: Color, width: float, right: bool, display := false
) -> Label:
	var label := HudStyle.clip(HudStyle.label("", size, ink, display))
	# A line of type is never taller than its row (a label's height is its font's), so a short
	# screen gets smaller type before it gets a taller ticket.
	var font := label.get_theme_font(&"font")
	while size > HudStyle.MIN_TEXT and font.get_height(size) > row_height:
		size -= 2
	label.add_theme_font_size_override(&"font_size", size)
	label.custom_minimum_size = Vector2(width, row_height)
	# A title or a name wider than its column gets smaller type first, and an ellipsis last.
	HudStyle.set_fitted(
		label, text, size, maxf(width - float(HudStyle.SM), 1.0) if width > 0.0 else INF
	)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _names(members: Dictionary) -> String:
	var out := []
	for id: int in members:
		out.append([id, HudState.name_of(members[id]), members[id].get("seat", 0)])
	return JSON.stringify(out)
