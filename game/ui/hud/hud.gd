class_name Hud
extends Control
## The in-game HUD for a night. It reads a `HudState` and nothing else: feed the state the rules'
## events (`hud.state.apply_event(event)`), a snapshot, and the local player's own readings, and the
## parts draw them. Nothing here touches a game object, so a client runs it from replicated data.
##
## Layout is anchored in canvas units (the project stretches the canvas to at least 1920 x 1080);
## the corners hold the always-on readouts, the centre stays clear for the view.

## The weapon places' boxes are somewhere else now, or came or went (`slots.touch_zones`): what the
## touch layer reads to know where a finger is on a weapon, and the world markers keep clear of.
signal slots_moved

const SCENE := "res://ui/hud/hud.tscn"
## The input action that shows the scoreboard while it is held.
const SCOREBOARD_ACTION := &"scoreboard"
## The gap beside the crosshair where point gains list. The banner sits on the top margin, level
## with the cards at the corners, so it ends above the event list that reaches under it (its rows
## are wider than the column). The prompt sits on the bottom margin between the health and ammo
## cards. Join and leave notices sit under the event list on the right: the left column is full
## with four players on a small screen.
##
## The parts keep to bands so that none overlaps another on a 1536 x 864 canvas (the smallest:
## 720p at UI scale 1.25): the side columns are `HudStyle.COLUMN` wide, the cards in the middle
## `HudStyle.CARD`, the gains `HudGains.WIDTH`; the right column ends above the gains, the gains
## above the prompt. Each part shrinks or ellipsizes its text instead of growing (the prompt wraps
## onto more lines instead). Every card shares the text grid of `HudStyle` (`PAD_LEFT` in, `PAD` in
## from the right) and every column the same `GAP` between its parts.
const GAINS_OFFSET := Vector2(48.0, 4.0)
## Where the challenge prompt starts, as a share of the screen's height: low enough to clear the
## round and objective cards, high enough that a card of three lines ends above the players' column
## on the smallest canvas (four players on 1536 x 864).
const CHALLENGE_TOP := 0.36
## Space kept between the gains and the ammo card they must stay clear of.
const GAINS_GAP := 9.0
## Half the box round the middle of the screen that the popup cards stay out of (the reticle, its
## hit markers and the point gains under it), canvas units.
const CENTRE_CLEAR := 80.0
## The most of the HUD's height a place for a finger takes (a fingertip is 11 percent of a phone's
## night: 122 units of 1080), and the most in units (153 at the smallest interface size, 0.8).
const FINGER_SHARE_MAX := 0.12
const FINGER_UNITS_MAX := 160.0

## Scene-tree names of the parts, by the variable that holds each.
const PART_NAMES := {
	&"round_part": "Round",
	&"objective": "Objective",
	&"fuel": "Fuel",
	&"events_feed": "Events",
	&"notices": "Notices",
	&"points": "Points",
	&"health": "Health",
	&"perks": "Perks",
	&"slots": "Slots",
	&"ammo": "Ammo",
	&"banner": "Banner",
	&"boss_bar": "BossBar",
	&"marquee": "Marquee",
	&"prompt": "Prompt",
	&"gains": "Gains",
	&"challenge": "Challenge",
	&"popups": "Popups",
	&"reticle": "Reticle",
	&"crosshair": "Crosshair",
	&"damage": "Damage",
	&"revive": "Revive",
	&"markers": "Markers",
	&"scoreboard": "Scoreboard",
	&"bot_wheel": "BotWheel",
}

## The look of the centre reticle (`reticle_style.tres`); editable on the Hud node in the editor.
@export var reticle_style: ReticleStyle = preload("res://ui/hud/reticle_style.tres")

var state := HudState.new()
## The corner columns swapped left for right (left-handed touch: Fire and its buttons take the
## left corner and the stick the right, so the cards that stay clear of them move too). The
## columns in the middle stay.
var mirrored := false:
	set(value):
		if value != mirrored:
			mirrored = value
			for column in _columns:
				if column[&"ax"] != 0.5:
					_place(column)
			slots.set_mirrored(value)
			if is_node_ready():
				_fit_gains()
				_queue_perks()
## The touch controls are up: the weapon slots leave the bottom right corner, which the right
## thumb's buttons fill (Fire and Melee sit where the strip would), for the bottom left corner under
## the players' column, each place a fingertip high and wide with the grenades' place after them: it
## is the phone's weapon control (#1280). Set by the night screen from the touch layer; the corner
## columns keep their sides (a left hand flips the column and the strip with it).
var touch_layout := false:
	set(value):
		if value != touch_layout:
			touch_layout = value
			prompt.touch_layout = value
			round_part.compact = value
			health.grenades_shown = not value
			if is_node_ready():
				_home_slots()
				_fit_markers()
var round_part := HudRound.new()
var objective := HudObjective.new()
var fuel := HudFuel.new()
var events_feed := HudFeed.new()
var notices := HudFeed.new()
var points := HudPoints.new()
var health := HudHealth.new()
## The perks had, as badges beside the health card (a left hand flips it to the card's other side).
var perks := HudPerks.new()
## The weapons carried, numbered, above the ammo card.
var slots := HudSlots.new()
var ammo := HudAmmo.new()
var banner := HudBanner.new()
var boss_bar := HudBossBar.new()
var marquee := HudMarquee.new()
var prompt := HudPrompt.new()
var gains := HudGains.new()
var challenge := HudChallenge.new()
## The cards of the progression (a level, a tier, an unlock, a finished challenge), under the
## banner.
var popups := PopupLane.new()
var reticle := HudReticle.new()
var crosshair := HudCrosshair.new()
var damage := HudDamage.new()
var revive := HudRevive.new()
var markers := HudMarkers.new()
var scoreboard := HudScoreboard.new()
## The bot command wheel, over the middle of the screen while it is held open (`BotWheelDriver`).
var bot_wheel := HudBotWheel.new()
## False while a menu or the result is over the night: holding the key then shows nothing.
var scoreboard_enabled := true:
	set(value):
		scoreboard_enabled = value
		if not value:
			scoreboard.set_shown(false)

var _tokens := UITokens.active()
var _slots_queued := false
## The columns the slots move between and the one they push up: `_stack`'s entries.
var _ammo_column: Dictionary = {}
var _players_column: Dictionary = {}
var _slots_column: Dictionary = {}
## Each stacked column: {node, parts, ax, ay, dx, dy}, kept so a mirror can place it again.
var _columns: Array[Dictionary] = []
## The platform's safe area (left, top, right, bottom, canvas units) the cards keep inside.
var _insets := Vector4.ZERO
var _perks_queued := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	notices.kind = HudFeed.Kind.NOTICES
	for part_name in PART_NAMES:
		(get(part_name) as Node).name = PART_NAMES[part_name]
	reticle.style = reticle_style
	for overlay in screen_overlays():
		add_child(overlay)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := float(HudStyle.margin())
	var gap := HudStyle.GAP
	_stack([round_part, objective], 0.0, 0.0, margin, margin, gap)
	_stack([fuel, events_feed, notices], 1.0, 0.0, -margin, margin, gap)
	_players_column = _stack([points, health], 0.0, 1.0, margin, -margin, gap)
	_ammo_column = _stack([slots, ammo], 1.0, 1.0, -margin, -margin, gap)
	_slots_column = _stack([], 0.0, 1.0, margin, -margin, gap)
	_stack([banner, marquee, boss_bar], 0.5, 0.0, 0.0, margin, gap)
	# The lane stands under whichever of the banner, the marquee and the boss bar is up, and eases
	# to its place when one comes or goes.
	popups.above = [banner, marquee, boss_bar]
	add_child(popups)
	_stack([prompt], 0.5, 1.0, 0.0, -margin, gap)
	_home_slots()
	_hold_perks()
	_stack([gains], 0.5, 0.5, GAINS_OFFSET.x, GAINS_OFFSET.y, gap)
	(gains.get_parent() as Control).grow_horizontal = Control.GROW_DIRECTION_END
	_place_challenge(margin)
	popups.mode_changed.connect(_on_popups_mode)
	_on_popups_mode()
	markers.keep_clear = corner_cards() + centre_cards()
	# Last, so it draws over every other part.
	_centre(scoreboard)
	for part in all_parts():
		part.bind(state)
	resized.connect(_fit_gains)
	resized.connect(_fit_popups)
	resized.connect(_fit_markers)
	resized.connect(_fit_slots)
	# The round card is the shorter for a phone (one row), and the column under it has the room.
	round_part.minimum_size_changed.connect(_fit_players)
	for moving: Control in [slots, _ammo_column[&"node"], _slots_column[&"node"]]:
		moving.item_rect_changed.connect(_queue_slots_moved)
	resized.connect(_queue_slots_moved)
	_fit_gains()
	_fit_popups()
	_fit_markers()


## Keeps the cards inside the platform's safe area (a phone's notch, rounded corners and home bar),
## in canvas units: left, top, right, bottom. The overlays that are the screen itself keep all of
## it. The reticle is the centre of the screen, where the camera looks and the shots go (#601): on
## an iPhone held sideways the home bar insets the bottom 29 units and not the top, and a reticle
## in the middle of the inset cards sat 14 units above the dot the shots came to. The same goes for
## the world markers and the damage numbers, which are shares of the screen.
func set_safe_insets(insets: Vector4) -> void:
	_insets = insets
	offset_left = insets.x
	offset_top = insets.y
	offset_right = -insets.z
	offset_bottom = -insets.w
	for overlay: Control in screen_overlays():
		overlay.offset_left = -insets.x
		overlay.offset_top = -insets.y
		overlay.offset_right = insets.z
		overlay.offset_bottom = insets.w
	for entry in _columns:
		_place(entry)
	_fit_popups()


## The overlays that fill the whole screen, whatever the cards keep clear of.
func screen_overlays() -> Array[Control]:
	return [damage, revive, markers, reticle, crosshair, bot_wheel]


func _process(delta: float) -> void:
	state.tick(delta)
	# Polled, not read from events: the key, the pad and the touch button all hold the action.
	scoreboard.set_shown(scoreboard_enabled and Input.is_action_pressed(SCOREBOARD_ACTION))


func _input(event: InputEvent) -> void:
	UIInputMode.track(event)


## The challenge prompt sits on the left edge about a third of the way down, in the band between
## the round column and the players' column, and stays there for a left hand too (the corner
## buttons are at the bottom; the gains and the reticle are at the middle of the screen, a card's
## width away).
func _place_challenge(margin: float) -> void:
	add_child(challenge)
	challenge.anchor_left = 0.0
	challenge.anchor_right = 0.0
	challenge.anchor_top = CHALLENGE_TOP
	challenge.anchor_bottom = CHALLENGE_TOP
	challenge.offset_left = margin
	challenge.offset_right = margin + HudChallengeCard.WIDTH
	challenge.offset_top = 0.0
	challenge.offset_bottom = 0.0
	challenge.grow_vertical = Control.GROW_DIRECTION_END
	# The cards above it change height with their words: it follows them down.
	for above in [round_part, objective]:
		above.item_rect_changed.connect(_fit_challenge)
	resized.connect(_fit_challenge)


## Puts the weapon slots where they belong: over the ammo card, or under the players' column in the
## bottom corner with the touch controls up, where the strip is wider than the column's cards.
func _home_slots() -> void:
	var to := _slots_column if touch_layout else _ammo_column
	var from := _ammo_column if touch_layout else _slots_column
	if slots.get_parent() != to[&"node"]:
		if slots.get_parent() != null:
			from[&"parts"].erase(slots)
			slots.get_parent().remove_child(slots)
		if touch_layout:
			to[&"parts"].append(slots)
			to[&"node"].add_child(slots)
		else:
			to[&"parts"].insert(0, slots)
			to[&"node"].add_child(slots)
			to[&"node"].move_child(slots, 0)
		_place(from)
		_place(to)
	_fit_slots()


## Sizes the weapon places to a fingertip while the touch controls are up (`MenuScale.tap_units`:
## 122 units at the night's factor, 153 at an interface size of 0.8, 98 at 1.25, and the type of
## the number as the markers' words are), and lifts the players' column by the strip's height.
func _fit_slots() -> void:
	if not is_inside_tree():
		return
	var finger := _finger_units() if touch_layout else 0.0
	var number_px := MenuScale.text_units(get_window(), touch_layout, HudStyle.SMALL)
	slots.fit_touch(touch_layout, finger, number_px)
	var lift := slots.custom_minimum_size.y + float(HudStyle.GAP) if touch_layout else 0.0
	var dy := -float(HudStyle.margin()) - lift
	if not is_equal_approx(_players_column[&"dy"], dy):
		_players_column[&"dy"] = dy
		_place(_players_column)
	_fit_players()
	_queue_slots_moved()


## Tells the players' column how much height it has while the touch layout is up (#1301): from a
## gap under the round and the objective at their tallest (two lines of words, so the column does
## not move when the words change) to the health card's top, which stands over the weapon strip.
## A party that does not fit it takes the teammates two to a row (`HudPoints.room`). Without the
## touch layout nothing limits it: a desktop and a pad keep their column as it was.
func _fit_players() -> void:
	var room := INF
	if touch_layout and size.y > 0.0:
		var gap := float(HudStyle.GAP)
		var above := (
			float(HudStyle.margin())
			+ round_part.get_combined_minimum_size().y
			+ gap
			+ objective.max_height()
			+ gap
		)
		var below := size.y + float(_players_column[&"dy"]) - health.get_combined_minimum_size().y
		room = maxf(below - gap - above, 0.0)
	points.room = room


## A fingertip in this HUD's units (`MenuScale.tap_units`), never more than `FINGER_SHARE_MAX` of
## its height or `FINGER_UNITS_MAX`: a window that is no phone's (a test's 64 pixels) would ask for
## places that fill the screen.
func _finger_units() -> float:
	var wanted := minf(MenuScale.tap_units(get_window(), true), FINGER_UNITS_MAX)
	return minf(wanted, size.y * FINGER_SHARE_MAX) if size.y > 0.0 else wanted


func _queue_slots_moved() -> void:
	if not _slots_queued:
		_slots_queued = true
		_emit_slots_moved.call_deferred()


func _emit_slots_moved() -> void:
	_slots_queued = false
	slots_moved.emit()


## Puts the perk badges beside the health card, at its bottom: right of it, or left of it for a left
## hand. The card moves when the touch controls bring the slot strip under it and when the safe area
## or the canvas changes, so the badges follow its rectangle instead of a number.
func _hold_perks() -> void:
	add_child(perks)
	# The card's column is placed after the card is (its own rectangle moves last), so the badges
	# are put once the layout has settled, whichever of them moved.
	for moving: Control in [health, health.get_parent(), perks]:
		moving.item_rect_changed.connect(_queue_perks)
	resized.connect(_queue_perks)


func _queue_perks() -> void:
	if not _perks_queued:
		_perks_queued = true
		_place_perks.call_deferred()


func _place_perks() -> void:
	_perks_queued = false
	if not is_node_ready() or not perks.visible:
		return
	var card := health.get_global_rect()
	var origin := get_global_rect().position
	var gap := float(HudStyle.GAP) + HudStyle.SHADOW.x
	var x := card.end.x + gap if not mirrored else card.position.x - gap - perks.size.x
	var at := Vector2(x, card.end.y - perks.size.y) - origin
	if not perks.position.is_equal_approx(at):
		perks.position = at


## The markers' words read at 14 CSS px where a finger holds the screen (#1218): a phone's night is
## 0.36 CSS px a unit, so that is 39 units and not 20. A desktop keeps its 20.
func _fit_markers() -> void:
	if is_inside_tree():
		markers.label_size = MenuScale.text_units(get_window(), touch_layout, HudStyle.MIN_TEXT)


## The cards of the popup lane stop above the box round the middle of the screen.
func _fit_popups() -> void:
	# The middle of the screen, not of the cards' area: the safe insets move the one from the other.
	var middle := get_global_rect().position.y + size.y * 0.5 - (_insets.y - _insets.w) * 0.5
	popups.limit_y = middle - CENTRE_CLEAR


## The lane shows a finished challenge as a card, so the prompt on the left edge leaves finishes to
## it, unless the player turned the cards off: then the prompt says it.
func _on_popups_mode() -> void:
	challenge.finish_in_lane = popups.mode != PopupLane.Mode.OFF


## Keeps the challenge prompt a gap under the left column's last card when that card reaches past
## the prompt's usual place (the objective's two lines on the smallest canvas).
func _fit_challenge() -> void:
	var bottom := 0.0
	for above in [round_part, objective]:
		if above.is_visible_in_tree():
			bottom = maxf(bottom, above.get_global_rect().end.y - get_global_rect().position.y)
	var usual := CHALLENGE_TOP * size.y
	challenge.offset_top = maxf(0.0, bottom + float(HudStyle.GAP) - usual)
	challenge.offset_bottom = challenge.offset_top


## The gains list takes the width from its start (beside the crosshair) to the left edge of whatever
## holds the bottom right corner: the ammo card (314 units on the smallest canvas, more on a wider
## one, so a big gain keeps its big type), or for a left hand the points and health column, which
## is wider.
func _fit_gains() -> void:
	var corner := HudStyle.COLUMN if mirrored else HudAmmo.WIDTH
	gains.set_room(size.x * 0.5 - float(HudStyle.margin()) - corner - GAINS_GAP - GAINS_OFFSET.x)


## Mirrors a batch of rules events (what `GameRules.apply` returned, or what a server broadcast).
func feed(events: Array) -> void:
	state.apply_events(events)


## Every part, for binding and for tools that walk them.
func all_parts() -> Array[HudPart]:
	return [
		damage,
		revive,
		markers,
		reticle,
		crosshair,
		round_part,
		objective,
		fuel,
		events_feed,
		notices,
		points,
		health,
		perks,
		slots,
		ammo,
		banner,
		marquee,
		boss_bar,
		prompt,
		gains,
		challenge,
		popups,
		scoreboard
	]


## The cards of the corners, which a world marker's words stay out of (#1192): the round and the
## objective, the feeds, the players and the health, the perks, the weapon slots and the ammo, and
## the challenge on the left edge. The cards that come and go in the middle of the screen are in
## `centre_cards`.
func corner_cards() -> Array[Control]:
	return [
		round_part,
		objective,
		fuel,
		events_feed,
		notices,
		points,
		health,
		perks,
		slots,
		ammo,
		challenge
	]


## The cards that come and go in the middle of the screen, which a world marker also keeps clear of
## while they are up (#1230): the round banner, the marquee, the boss bar, the prompt and the lane
## of the progression's cards.
func centre_cards() -> Array[Control]:
	return [banner, marquee, boss_bar, prompt, popups]


## The parts that take a rectangle on screen (not the full-screen overlays): for layout checks.
func boxed_parts() -> Array[Control]:
	return [
		round_part,
		objective,
		fuel,
		events_feed,
		notices,
		points,
		health,
		perks,
		slots,
		ammo,
		banner,
		marquee,
		boss_bar,
		prompt,
		gains,
		challenge,
		popups
	]


## Holds `part` in the middle of the screen, over everything else.
func _centre(part: Control) -> void:
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(part)
	add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## A column anchored at (ax, ay) of the screen, grown away from the anchor, `parts` top to bottom.
func _stack(parts: Array, ax: float, ay: float, dx: float, dy: float, gap: int) -> Dictionary:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", gap)
	column.alignment = BoxContainer.ALIGNMENT_END if ay == 1.0 else BoxContainer.ALIGNMENT_BEGIN
	for part in parts:
		column.add_child(part)
	add_child(column)
	var entry := {&"node": column, &"parts": parts, &"ax": ax, &"ay": ay, &"dx": dx, &"dy": dy}
	_columns.append(entry)
	_place(entry)
	return entry


## Anchors a column, flipped to the other side when `mirrored` (only the side columns flip).
func _place(entry: Dictionary) -> void:
	var column: VBoxContainer = entry[&"node"]
	var ax: float = entry[&"ax"]
	var ay: float = entry[&"ay"]
	var dx: float = entry[&"dx"]
	var flip := mirrored and ax != 0.5
	var at := 1.0 - ax if flip else ax
	var offset := -dx if flip else dx
	for part: Control in entry[&"parts"]:
		if ax == 1.0:
			part.size_flags_horizontal = (
				Control.SIZE_SHRINK_BEGIN if flip else Control.SIZE_SHRINK_END
			)
		elif ax == 0.5:
			part.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.anchor_left = at
	column.anchor_right = at
	column.anchor_top = ay
	column.anchor_bottom = ay
	# A column on the middle of the screen (the point gains beside the reticle) stays on the
	# screen's middle, not on the middle of the cards' area.
	var shift := Vector2.ZERO
	if ax == 0.5 and ay == 0.5:
		shift = Vector2(_insets.x - _insets.z, _insets.y - _insets.w) * 0.5
	column.offset_left = offset - shift.x
	column.offset_right = offset - shift.x
	column.offset_top = entry[&"dy"] - shift.y
	column.offset_bottom = entry[&"dy"] - shift.y
	column.grow_horizontal = (
		Control.GROW_DIRECTION_BEGIN
		if at == 1.0
		else (Control.GROW_DIRECTION_BOTH if at == 0.5 else Control.GROW_DIRECTION_END)
	)
	column.grow_vertical = (
		Control.GROW_DIRECTION_BEGIN if ay == 1.0 else Control.GROW_DIRECTION_END
	)
