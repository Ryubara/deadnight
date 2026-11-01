class_name Hud
extends Control
## The in-game HUD for a night. It reads a `HudState` and nothing else: feed the state the rules'
## events (`hud.state.apply_event(event)`), a snapshot, and the local player's own readings, and the
## parts draw them. Nothing here touches a game object, so a client runs it from replicated data.
##
## Layout is anchored in canvas units (the project stretches the canvas to at least 1920 x 1080);
## the corners hold the always-on readouts, the centre stays clear for the view.

const SCENE := "res://ui/hud/hud.tscn"
## Vertical position (0..1 of the screen) of the banner and of the prompt, and the gap beside the
## crosshair where point gains list. Join and leave notices sit under the event list on the right:
## the left column is full with four players on a small screen.
const BANNER_AT := 0.1
const PROMPT_AT := 0.7
const GAINS_OFFSET := Vector2(64.0, -30.0)

## Scene-tree names of the parts, by the variable that holds each.
const PART_NAMES := {
	&"round_part": "Round",
	&"objective": "Objective",
	&"team": "Team",
	&"fuel": "Fuel",
	&"events_feed": "Events",
	&"notices": "Notices",
	&"points": "Points",
	&"health": "Health",
	&"ammo": "Ammo",
	&"banner": "Banner",
	&"prompt": "Prompt",
	&"gains": "Gains",
	&"crosshair": "Crosshair",
	&"damage": "Damage",
	&"markers": "Markers",
}

var state := HudState.new()
var round_part := HudRound.new()
var objective := HudObjective.new()
var team := HudTeam.new()
var fuel := HudFuel.new()
var events_feed := HudFeed.new()
var notices := HudFeed.new()
var points := HudPoints.new()
var health := HudHealth.new()
var ammo := HudAmmo.new()
var banner := HudBanner.new()
var prompt := HudPrompt.new()
var gains := HudGains.new()
var crosshair := HudCrosshair.new()
var damage := HudDamage.new()
var markers := HudMarkers.new()

var _tokens := UITokens.active()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	notices.kind = HudFeed.Kind.NOTICES
	for part_name in PART_NAMES:
		(get(part_name) as Node).name = PART_NAMES[part_name]
	for overlay in [damage, markers, crosshair]:
		add_child(overlay)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := float(HudStyle.margin())
	var gap := _tokens.space_sm
	_stack([round_part, objective, team], 0.0, 0.0, margin, margin, gap)
	_stack([fuel, events_feed, notices], 1.0, 0.0, -margin, margin, gap)
	_stack([points, health], 0.0, 1.0, margin, -margin, gap)
	_stack([ammo], 1.0, 1.0, -margin, -margin, gap)
	_stack([banner], 0.5, BANNER_AT, 0.0, 0.0, gap)
	_stack([prompt], 0.5, PROMPT_AT, 0.0, 0.0, gap)
	_stack([gains], 0.5, 0.5, GAINS_OFFSET.x, GAINS_OFFSET.y, gap)
	(gains.get_parent() as Control).grow_horizontal = Control.GROW_DIRECTION_END
	for part in all_parts():
		part.bind(state)


func _process(delta: float) -> void:
	state.tick(delta)


func _input(event: InputEvent) -> void:
	UIInputMode.track(event)


## Mirrors a batch of rules events (what `GameRules.apply` returned, or what a server broadcast).
func feed(events: Array) -> void:
	state.apply_events(events)


## Every part, for binding and for tools that walk them.
func all_parts() -> Array[HudPart]:
	return [
		damage,
		markers,
		crosshair,
		round_part,
		objective,
		team,
		fuel,
		events_feed,
		notices,
		points,
		health,
		ammo,
		banner,
		prompt,
		gains
	]


## The parts that take a rectangle on screen (not the full-screen overlays): for layout checks.
func boxed_parts() -> Array[Control]:
	return [
		round_part,
		objective,
		team,
		fuel,
		events_feed,
		notices,
		points,
		health,
		ammo,
		banner,
		prompt,
		gains
	]


## A column anchored at (ax, ay) of the screen, grown away from the anchor, `parts` top to bottom.
func _stack(parts: Array, ax: float, ay: float, dx: float, dy: float, gap: int) -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", gap)
	column.alignment = BoxContainer.ALIGNMENT_END if ay == 1.0 else BoxContainer.ALIGNMENT_BEGIN
	for part in parts:
		column.add_child(part)
		if ax == 1.0:
			(part as Control).size_flags_horizontal = Control.SIZE_SHRINK_END
		elif ax == 0.5:
			(part as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.anchor_left = ax
	column.anchor_right = ax
	column.anchor_top = ay
	column.anchor_bottom = ay
	column.offset_left = dx
	column.offset_right = dx
	column.offset_top = dy
	column.offset_bottom = dy
	column.grow_horizontal = (
		Control.GROW_DIRECTION_BEGIN
		if ax == 1.0
		else (Control.GROW_DIRECTION_BOTH if ax == 0.5 else Control.GROW_DIRECTION_END)
	)
	column.grow_vertical = (
		Control.GROW_DIRECTION_BEGIN if ay == 1.0 else Control.GROW_DIRECTION_END
	)
	add_child(column)
