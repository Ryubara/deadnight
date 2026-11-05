class_name PopupLane
extends HudPart
## The popup lane: the cards of the progression, live. It hears the server's events (`level_up`,
## `tier_up`, `unlock_earned`, from `XpAward`), a finished challenge (`challenge_advanced`) and a
## finished poster set (`poster_set_done`, from `ChallengeAward`),
## turns each into a card (`PopupQueue`) and shows them one under the other, centred at the top of
## its parent: in the HUD, under whichever of the round banner, the marquee and the boss bar is up
## (it slides up when that one leaves, and down when one comes), in a menu at the top of the
## screen. It never takes a click (the mouse filter is `ignore` all the way down) and never draws
## over the HUD's other parts: the queue shows only the cards that fit between its top and the box
## round the crosshair, and a test measures it against every part at every canvas the HUD runs at.
## Time-driven (`advance`), so captures and tests step it by hand.
##
## The HUD part hears only its own player's events (`HudState.local_player_id`); a lane that is
## bound to no state (the menu's) takes every event it is given. The player's setting limits it
## (`Mode`). While the lane's column is hidden (the helicopter drop is on the screen) the queue is
## blocked: cards that came wait for the screen to be back.

## A card started and asks for its sound: `level_up`, `tier_up`, `unlock`, `card_earned` or
## `challenge_done` (the cues of `UiSoundTable.PROGRESS_CUES`).
signal cue(cue: StringName)
## The setting changed (the HUD tells the challenge prompt whether the lane takes finished
## challenges).
signal mode_changed

enum Mode { ALL, BIG_ONLY, OFF }

## Marquee bulbs of a tier card move this many steps a second.
const CHASE := 5.0
## How fast the lane follows the part above it (the share of the way it covers each second, as an
## exponential rate: about a quarter second to settle).
const FOLLOW_RATE := 12.0

var mode: Mode = Mode.ALL:
	set(value):
		if value != mode:
			mode = value
			if mode == Mode.OFF:
				_drop_everything()
			mode_changed.emit()
var queue := PopupQueue.new()
## The lowest the cards may reach, canvas units down the screen (a global y): the HUD sets it to
## the top of the box round the crosshair. Infinite where there is none (a menu).
var limit_y := INF
## The parts the lane stands under while they are up (the HUD's banner, marquee and boss bar), and
## the space it keeps from the top of its parent and between itself and them.
var above: Array[Control] = []
var margin := float(HudStyle.margin())

var _cards: Dictionary[PopupQueue.Card, PopupCard] = {}
var _clock := 0.0
var _extent := -1.0
## Where the lane is now, in its parent: negative while it has no card (it starts at its place).
var _y := -1.0


func _init() -> void:
	super()
	size = Vector2(PopupCard.WIDTH, 0.0)
	visible = false
	set_process(false)


## The cards standing now (a test's), oldest first.
func cards() -> Array[PopupCard]:
	var out: Array[PopupCard] = []
	for card in queue.shown:
		if _cards.has(card):
			out.append(_cards[card])
	return out


func on_event(event: Dictionary) -> void:
	if mode == Mode.OFF:
		return
	var type := StringName(event.get("type", &""))
	if type == &"challenge_advanced":
		if event.get("completed", false):
			_push(
				PopupQueue.Kind.CHALLENGE,
				{"text": String(event.get("text", "")), "family": int(event.get("family", 0))}
			)
		return
	if not _is_mine(event):
		return
	match type:
		&"poster_set_done":
			_push(PopupQueue.Kind.SET, PopupCard.set_data(event))
		&"level_up":
			_push(PopupQueue.Kind.LEVEL, {"level": int(event["level"])})
		&"tier_up":
			var level := int(event["level"])
			var tier_name := String(event["tier_name"])
			if queue.upgrade_to_tier(level, tier_name):
				_rebuild(level)
				set_process(true)
			else:
				_push(PopupQueue.Kind.TIER, {"level": level, "tier_name": tier_name})
		&"unlock_earned":
			if mode == Mode.ALL:
				_push(
					PopupQueue.Kind.UNLOCK,
					{
						"slot": StringName(event["slot"]),
						"item": StringName(event["item"]),
						"level": int(event["level"]),
					}
				)


func _process(delta: float) -> void:
	advance(delta)


## Moves the lane on by `delta` seconds. A lane in a hidden column holds still.
func advance(delta: float) -> void:
	var parent := get_parent_control()
	var blocked := parent != null and not parent.is_visible_in_tree()
	_clock += delta
	var target := _top()
	queue.room = limit_y - _parent_top() - target
	for started in queue.advance(delta, blocked):
		_show(started)
	var reduced := UIMotion.reduced
	var step := int(_clock * CHASE)
	for card in queue.shown:
		var node: PopupCard = _cards[card]
		var look := queue.look_of(card, reduced)
		node.position = Vector2((size.x - node.size.x) * 0.5, card.y + float(look["dy"]))
		node.modulate.a = float(look["alpha"])
		node.icon.scale = Vector2.ONE * queue.stamp_of(card, reduced)
		if (card.kind == PopupQueue.Kind.TIER or card.kind == PopupQueue.Kind.SET) and not reduced:
			node.set_chase(step)
	for card: PopupQueue.Card in _cards.keys():
		if not queue.shown.has(card):
			_cards[card].queue_free()
			_cards.erase(card)
	_fit()
	_follow(target, delta)
	if queue.is_idle():
		set_process(false)


## Where the lane's top belongs in its parent: under the parts it stands under that are up and laid
## out (their column lays itself out a frame late), else at the margin.
func _top() -> float:
	var parent := get_parent_control()
	if parent == null:
		return margin
	var origin := parent.get_global_rect().position.y
	var top := margin
	for part in above:
		var column := part.get_parent_control()
		if part.visible and column != null and column.size.x > 0.0:
			top = maxf(top, part.get_global_rect().end.y - origin + float(HudStyle.GAP))
	return top


func _parent_top() -> float:
	var parent := get_parent_control()
	return 0.0 if parent == null else parent.get_global_rect().position.y


## Puts the lane at the top centre of its parent, easing toward `target` (it snaps while it has no
## card, and with reduced motion).
func _follow(target: float, delta: float) -> void:
	var parent := get_parent_control()
	if parent == null:
		return
	if _y < 0.0 or UIMotion.reduced:
		_y = target
	else:
		_y = lerpf(_y, target, 1.0 - exp(-FOLLOW_RATE * delta))
	position = Vector2((parent.size.x - size.x) * 0.5, _y)


## Forgets every card, showing and waiting (a new night).
func clear() -> void:
	_drop_everything()


func _push(kind: PopupQueue.Kind, data: Dictionary) -> void:
	queue.push(kind, data)
	set_process(true)


func _is_mine(event: Dictionary) -> bool:
	if state == null or not event.has("player_id"):
		return true
	return int(event["player_id"]) == state.local_player_id


## A card of the queue starts: its node, and its sound.
func _show(card: PopupQueue.Card) -> void:
	var node := PopupCard.new()
	add_child(node)
	# The older card is over the newer: a card comes out from under the one above it.
	move_child(node, 0)
	node.setup(card.kind, card.data)
	_cards[card] = node
	var sound := _cue_of(card)
	if sound != &"":
		cue.emit(sound)


## A level card that became a tier card while it showed: its node says so, and the bigger sound
## plays (the level up under it is over; `UiSounds` keeps the one from hiding the other).
func _rebuild(level: int) -> void:
	for card in queue.shown:
		if card.kind == PopupQueue.Kind.TIER and int(card.data.get("level", 0)) == level:
			if _cards.has(card) and _cards[card].kind != PopupQueue.Kind.TIER:
				_cards[card].setup(card.kind, card.data)
				cue.emit(&"tier_up")


func _cue_of(card: PopupQueue.Card) -> StringName:
	match card.kind:
		PopupQueue.Kind.LEVEL:
			return &"level_up"
		PopupQueue.Kind.TIER:
			return &"tier_up"
		PopupQueue.Kind.UNLOCK:
			return PopupLadder.cue_of(card.data["slot"])
		PopupQueue.Kind.CHALLENGE:
			return &"challenge_done"
		PopupQueue.Kind.SET:
			return &"card_earned"
	return &""


## Asks the screen for what the cards need, and hides the lane while it has none.
func _fit() -> void:
	var extent := queue.extent()
	visible = not _cards.is_empty()
	if not is_equal_approx(extent, _extent):
		_extent = extent
		size = Vector2(PopupCard.WIDTH, extent)
	if not visible:
		_y = -1.0


func _drop_everything() -> void:
	queue.clear()
	for node: PopupCard in _cards.values():
		node.queue_free()
	_cards.clear()
	_extent = 0.0
	_y = -1.0
	visible = false
	set_process(false)
