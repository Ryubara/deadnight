class_name Hud
extends Control
## The in-game HUD for a night. It reads a `HudState` and nothing else: feed the state the rules'
## events (`hud.state.apply_event(event)`), a snapshot, and the local player's own readings, and the
## parts draw them. Nothing here touches a game object, so a client runs it from replicated data.
##
## Layout is anchored in canvas units (the project stretches the canvas to at least 1920 x 1080);
## the corners hold the always-on readouts, the centre stays clear for the view.

const SCENE := "res://ui/hud/hud.tscn"
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
## Space kept between the gains and the ammo card they must stay clear of.
const GAINS_GAP := 9.0

## Scene-tree names of the parts, by the variable that holds each.
const PART_NAMES := {
	&"round_part": "Round",
	&"objective": "Objective",
	&"fuel": "Fuel",
	&"events_feed": "Events",
	&"notices": "Notices",
	&"points": "Points",
	&"health": "Health",
	&"ammo": "Ammo",
	&"banner": "Banner",
	&"boss_bar": "BossBar",
	&"marquee": "Marquee",
	&"prompt": "Prompt",
	&"gains": "Gains",
	&"challenge": "Challenge",
	&"reticle": "Reticle",
	&"crosshair": "Crosshair",
	&"damage": "Damage",
	&"markers": "Markers",
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
			if is_node_ready():
				_fit_gains()
var round_part := HudRound.new()
var objective := HudObjective.new()
var fuel := HudFuel.new()
var events_feed := HudFeed.new()
var notices := HudFeed.new()
var points := HudPoints.new()
var health := HudHealth.new()
var ammo := HudAmmo.new()
var banner := HudBanner.new()
var boss_bar := HudBossBar.new()
var marquee := HudMarquee.new()
var prompt := HudPrompt.new()
var gains := HudGains.new()
var challenge := HudChallenge.new()
var reticle := HudReticle.new()
var crosshair := HudCrosshair.new()
var damage := HudDamage.new()
var markers := HudMarkers.new()

var _tokens := UITokens.active()
## Each stacked column: {node, parts, ax, ay, dx, dy}, kept so a mirror can place it again.
var _columns: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	notices.kind = HudFeed.Kind.NOTICES
	for part_name in PART_NAMES:
		(get(part_name) as Node).name = PART_NAMES[part_name]
	reticle.style = reticle_style
	for overlay in [damage, markers, reticle, crosshair]:
		add_child(overlay)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := float(HudStyle.margin())
	var gap := HudStyle.GAP
	_stack([round_part, objective], 0.0, 0.0, margin, margin, gap)
	_stack([fuel, events_feed, notices], 1.0, 0.0, -margin, margin, gap)
	_stack([points, health], 0.0, 1.0, margin, -margin, gap)
	_stack([ammo], 1.0, 1.0, -margin, -margin, gap)
	_stack([banner, marquee, boss_bar], 0.5, 0.0, 0.0, margin, gap)
	_stack([prompt], 0.5, 1.0, 0.0, -margin, gap)
	_stack([gains], 0.5, 0.5, GAINS_OFFSET.x, GAINS_OFFSET.y, gap)
	(gains.get_parent() as Control).grow_horizontal = Control.GROW_DIRECTION_END
	_place_challenge(margin)
	for part in all_parts():
		part.bind(state)
	resized.connect(_fit_gains)
	_fit_gains()


func _process(delta: float) -> void:
	state.tick(delta)


func _input(event: InputEvent) -> void:
	UIInputMode.track(event)


## The challenge prompt sits on the left edge at mid height, in the band between the round column
## and the players' column, and stays there for a left hand too (the corner buttons are at the
## bottom; the gains and the reticle are at the middle of the screen, a card's width away).
func _place_challenge(margin: float) -> void:
	add_child(challenge)
	challenge.anchor_left = 0.0
	challenge.anchor_right = 0.0
	challenge.anchor_top = 0.5
	challenge.anchor_bottom = 0.5
	challenge.offset_left = margin
	challenge.offset_right = margin + HudChallengeCard.WIDTH
	challenge.offset_top = 0.0
	challenge.offset_bottom = 0.0
	challenge.grow_vertical = Control.GROW_DIRECTION_BOTH


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
		ammo,
		banner,
		marquee,
		boss_bar,
		prompt,
		gains,
		challenge
	]


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
		ammo,
		banner,
		marquee,
		boss_bar,
		prompt,
		gains,
		challenge
	]


## A column anchored at (ax, ay) of the screen, grown away from the anchor, `parts` top to bottom.
func _stack(parts: Array, ax: float, ay: float, dx: float, dy: float, gap: int) -> void:
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
	column.offset_left = offset
	column.offset_right = offset
	column.offset_top = entry[&"dy"]
	column.offset_bottom = entry[&"dy"]
	column.grow_horizontal = (
		Control.GROW_DIRECTION_BEGIN
		if at == 1.0
		else (Control.GROW_DIRECTION_BOTH if at == 0.5 else Control.GROW_DIRECTION_END)
	)
	column.grow_vertical = (
		Control.GROW_DIRECTION_BEGIN if ay == 1.0 else Control.GROW_DIRECTION_END
	)
