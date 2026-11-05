class_name HudChallenge
extends HudPart
## The challenge prompt: a small card on the left edge, in the free band between the round column
## above and the players' column below, that says one challenge moved a step (a quarter mark of a
## daily or an order, or a milestone step). It hears `challenge_advanced` events (the advance
## dictionaries from `ChallengeProfile.apply`), queues them (`ChallengePromptQueue`) and shows
## them one at a time: in from the edge, held, out. It never takes the middle of the screen, where
## the reticle and the gains are, nor any corner. The player's setting can limit it to finished
## challenges and milestones or turn it off (`mode`).

## A card appeared and asks for its sound: a tick for a quarter mark, a pair (`finished`) for a
## finish or a milestone step.
signal cue(finished: bool)

enum Mode { ALL, FINISHED_ONLY, OFF }

const EVENT := &"challenge_advanced"

## How far the card starts off the edge, as a share of its width.
const SLIDE := 0.6
## How fast the finish flash runs, flashes a second.
const FLASH_RATE := 1.6

var mode: Mode = Mode.ALL
## The popup lane shows a finished challenge as a card (`Hud` sets it): this prompt then says only
## the steps, so the finish is not told twice.
var finish_in_lane := false
var queue := ChallengePromptQueue.new()
## The prompt's card, made the first time a challenge moves (the part is hidden the rest of the
## night, and the late-round budget counts every canvas item of the tree, shown or not).
var card: HudChallengeCard:
	get:
		if _card == null:
			_card = HudChallengeCard.new()
			add_child(_card)
			_card.modulate.a = 0.0
			update_minimum_size()
		return _card

var _card: HudChallengeCard
var _clock := 0.0
var _stamp := -1.0
var _shown_id: StringName = &""


func _init() -> void:
	super()
	visible = false


func _get_minimum_size() -> Vector2:
	return _card.get_combined_minimum_size() if _card != null else Vector2.ZERO


func on_event(event: Dictionary) -> void:
	if (
		event.get("type") != EVENT
		or mode == Mode.OFF
		or not ChallengePromptQueue.is_worth_showing(event)
	):
		return
	if finish_in_lane and bool(event.get("completed", false)):
		return
	if mode == Mode.FINISHED_ONLY and not ChallengePromptQueue.is_milestone_or_completion(event):
		return
	queue.push(event)


func _process(delta: float) -> void:
	advance(delta)


## Moves the prompt on by `delta` seconds (tests and captures step it by hand).
func advance(delta: float) -> void:
	_clock += delta
	queue.advance(delta, state != null and state.is_local_downed())
	var current := queue.current
	if current.is_empty():
		_shown_id = &""
		_stamp = -1.0
	elif float(current["_at"]) != _stamp:
		_stamp = float(current["_at"])
		card.show_advance(current)
		if current["id"] != _shown_id:
			cue.emit(ChallengePromptQueue.is_milestone_or_completion(current))
		_shown_id = current["id"]
	_present()


func _present() -> void:
	var amount := queue.shown()
	visible = amount > 0.0
	if not visible:
		return
	card.modulate.a = amount
	var slide := 0.0
	if not UIMotion.reduced:
		slide = (1.0 - ease(amount, 0.4)) * SLIDE * card.size.x
	card.position.x = -slide
	var flash := 0.0
	var finished := bool(queue.current.get("completed", false))
	if finished and not UIMotion.reduced and queue.phase == ChallengePromptQueue.Phase.HOLD:
		flash = 0.5 + 0.5 * sin(_clock * TAU * FLASH_RATE)
	card.set_flash(flash)
