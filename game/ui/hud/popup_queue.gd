class_name PopupQueue
extends RefCounted
## What the popup lane shows and when: the cards of the progression (a level, a tier, an unlock, a
## finished challenge), their order, their motion and their limits, as plain data and a clock the
## caller moves with `advance(delta)`, so a test steps it by hand and a capture repeats frame for
## frame (docs/design/progression.md#popups-motion-and-sound).
##
## - A card drops in over `popup_in` with a small overshoot, holds, and leaves over `popup_out`:
##   a level card 2.6 s, an unlock 2.0 s, a tier 3.6 s, a finished challenge 3.0 s.
## - Cards start 0.15 s apart, in the order they arrived; the older ones stand above.
## - At most `MAX_VISIBLE` are up, and no more than fit in `room` (the lane sets it to the space
##   under the banner and the boss bar and above the crosshair; one card always may stand). A card
##   that waits sends the oldest one away once it has been up for `popup_min_show`, and shortens the
##   hold of the one that starts (`popup_hold_busy`).
## - At most `MAX_WAITING` wait. Past that the lowest cards (unlocks first, the newest first) are
##   merged into one `MORE` card, "3 new items", which stands last.
## - A tier is the level card of its level made longer (`upgrade_to_tier`): one card for the
##   moment, not two.
## - While blocked (the HUD is hidden: the arrival drop is on) nothing starts and nothing ages, so
##   a card that came then is still there when the screen is back.

enum Kind { LEVEL, UNLOCK, TIER, CHALLENGE, MORE }
enum Phase { IN, HOLD, OUT }

const MAX_VISIBLE := 3
const MAX_WAITING := 8
## Space between two cards of the stack, canvas units.
const GAP := 6.0
## The overshoot of the drop (the easing's own constant: about a tenth of the distance).
const OVERSHOOT := 1.70158
## How far a leaving card rises while it fades, canvas units.
const RISE := 10.0
## A card leaving has faded enough for another to stand in its place after this share of its exit.
const LEAVING_CLEAR := 0.6
## A stack has settled when its cards have slid this share of the way.
const SETTLED := 0.6
## The icon's stamp: its scale at the start, at its peak and when it lands, and when each is.
const STAMP_FROM := 0.8
const STAMP_PEAK := 1.1
const STAMP_START := 0.1
const STAMP_PEAK_AT := 0.25
const STAMP_LAND_AT := 0.45

## The cards up now, the oldest first, and the cards waiting for a place.
var shown: Array[Card] = []
var waiting: Array[Card] = []

## How far down the cards may reach, canvas units from the lane's top (the lane sets it).
var room := INF

var _t := HudTuning.current()
var _since_start := 1.0e9


## One card: what it says (`data`) and where it is in its life.
class Card:
	extends RefCounted
	var kind: Kind
	var data: Dictionary
	var phase := Phase.IN
	## Seconds since it started, and since its phase began.
	var age := 0.0
	var phase_time := 0.0
	var hold := 0.0
	## Where its place in the stack is now, and the slide on the way to a new one.
	var y := 0.0
	var y_from := 0.0
	var y_to := 0.0
	var slide := 1.0

	func _init(p_kind: Kind, p_data: Dictionary) -> void:
		kind = p_kind
		data = p_data


## How much a kind matters when the queue is over its limit: the lowest are merged first.
static func priority(kind: Kind) -> int:
	match kind:
		Kind.TIER:
			return 4
		Kind.LEVEL, Kind.CHALLENGE:
			return 3
		Kind.MORE:
			return 2
	return 1


static func ease_out_back(t: float) -> float:
	var x := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + (OVERSHOOT + 1.0) * x * x * x + OVERSHOOT * x * x


static func ease_in_out(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Adds a card. A kind the lane has no use for (`MORE` is made here) is never pushed.
func push(kind: Kind, data: Dictionary) -> void:
	var card := Card.new(kind, data)
	var more := _more_card()
	if more != null:
		waiting.insert(waiting.size() - 1, card)
	else:
		waiting.append(card)
	_merge_overflow()


## The level card of `level` (waiting or up, not leaving) becomes the tier card of `tier_name`;
## false when there is none.
func upgrade_to_tier(level: int, tier_name: String) -> bool:
	for list: Array[Card] in [waiting, shown]:
		for card in list:
			if (
				card.kind == Kind.LEVEL
				and int(card.data.get("level", 0)) == level
				and card.phase != Phase.OUT
			):
				card.kind = Kind.TIER
				card.data = {"level": level, "tier_name": tier_name}
				card.hold = maxf(card.hold, _hold_of(Kind.TIER)) if card in shown else 0.0
				if card in shown and card.phase == Phase.HOLD:
					card.phase_time = 0.0
				return true
	return false


## Moves time on by `delta`; returns the cards that started now (the lane makes their nodes and
## plays their sounds).
func advance(delta: float, blocked := false) -> Array[Card]:
	var started: Array[Card] = []
	if blocked:
		return started
	_since_start += delta
	for card in shown:
		card.age += delta
		card.phase_time += delta
		if card.slide < 1.0:
			card.slide = minf(card.slide + delta / maxf(_t.popup_slide, 0.001), 1.0)
			card.y = lerpf(card.y_from, card.y_to, ease_in_out(card.slide))
		match card.phase:
			Phase.IN:
				if card.phase_time >= _t.popup_in:
					card.phase = Phase.HOLD
					card.phase_time -= _t.popup_in
			Phase.HOLD:
				if card.phase_time >= card.hold:
					card.phase = Phase.OUT
					card.phase_time = 0.0
					_layout()
			Phase.OUT:
				pass
	var gone := shown.filter(
		func(card: Card) -> bool: return card.phase == Phase.OUT and card.phase_time >= _t.popup_out
	)
	if not gone.is_empty():
		for card: Card in gone:
			shown.erase(card)
		_layout()
	_send_the_oldest_away()
	while (
		not waiting.is_empty()
		and _fits(waiting[0])
		and _since_start >= _t.popup_start_gap
		and _settled()
	):
		started.append(_start(waiting.pop_front()))
	return started


## Whether `card` may start now: a place is free, it fits in `room` under the cards up (one card
## always fits), and no card still shows through where it would stand.
func _fits(card: Card) -> bool:
	var up := _up_count()
	if up >= MAX_VISIBLE:
		return false
	if up == 0:
		for other in shown:
			if other.phase_time < _t.popup_out * LEAVING_CLEAR:
				return false
		return true
	var bottom := 0.0
	for other in shown:
		if other.phase != Phase.OUT:
			bottom += PopupCard.size_of(other.kind).y + GAP
	return bottom + PopupCard.size_of(card.kind).y <= room


## Whether the cards up have slid most of the way to their places: a card that starts while they
## still move would come out over them.
func _settled() -> bool:
	for card in shown:
		if card.phase != Phase.OUT and card.slide < SETTLED:
			return false
	return true


## How many cards are up and not leaving.
func _up_count() -> int:
	var count := 0
	for card in shown:
		if card.phase != Phase.OUT:
			count += 1
	return count


func is_idle() -> bool:
	return shown.is_empty() and waiting.is_empty()


## How far down the cards reach, their shadows left out: what the lane asks the screen for.
func extent() -> float:
	var bottom := 0.0
	for card in shown:
		var at := card.y if card.phase == Phase.OUT else maxf(card.y, card.y_to)
		bottom = maxf(bottom, at + PopupCard.size_of(card.kind).y)
	return bottom


## How far a card is moved from its place by its entrance or its exit, and how opaque it is.
## Reduced motion fades without moving.
func look_of(card: Card, reduced: bool) -> Dictionary:
	match card.phase:
		Phase.IN:
			var p := clampf(card.phase_time / maxf(_t.popup_in, 0.001), 0.0, 1.0)
			if reduced:
				return {"dy": 0.0, "alpha": p}
			return {"dy": -_t.popup_drop * (1.0 - ease_out_back(p)), "alpha": minf(p * 3.0, 1.0)}
		Phase.OUT:
			var q := clampf(card.phase_time / maxf(_t.popup_out, 0.001), 0.0, 1.0)
			if reduced:
				return {"dy": 0.0, "alpha": 1.0 - q}
			return {"dy": -RISE * ease_in_out(q), "alpha": 1.0 - clampf(q * 1.25, 0.0, 1.0)}
	return {"dy": 0.0, "alpha": 1.0}


## The scale of a level card's icon `age` seconds after the card started: 0.8, up to 1.1 and down
## to 1 (a stamp). Reduced motion keeps it at 1.
func stamp_of(card: Card, reduced: bool) -> float:
	if reduced:
		return 1.0
	var age := card.age
	if age < STAMP_START:
		return STAMP_FROM
	if age < STAMP_PEAK_AT:
		var rise := (age - STAMP_START) / (STAMP_PEAK_AT - STAMP_START)
		return lerpf(STAMP_FROM, STAMP_PEAK, 1.0 - pow(1.0 - rise, 2.0))
	if age < STAMP_LAND_AT:
		var fall := (age - STAMP_PEAK_AT) / (STAMP_LAND_AT - STAMP_PEAK_AT)
		return lerpf(STAMP_PEAK, 1.0, ease_in_out(fall))
	return 1.0


func clear() -> void:
	shown.clear()
	waiting.clear()
	_since_start = 1.0e9


func _start(card: Card) -> Card:
	card.hold = _hold_of(card.kind)
	if not waiting.is_empty():
		card.hold = minf(card.hold, _t.popup_hold_busy)
	card.phase = Phase.IN
	card.phase_time = 0.0
	card.age = 0.0
	shown.append(card)
	_since_start = 0.0
	_layout()
	# A card starts in its place: the drop is its entrance, not a slide.
	card.y = card.y_to
	card.y_from = card.y_to
	card.slide = 1.0
	return card


## Sends the oldest card away when others wait and it has been up long enough.
func _send_the_oldest_away() -> void:
	if waiting.is_empty() or _fits(waiting[0]):
		return
	for card in shown:
		if card.phase == Phase.OUT:
			continue
		if card.phase == Phase.HOLD and card.phase_time >= _t.popup_min_show:
			card.phase = Phase.OUT
			card.phase_time = 0.0
			_layout()
		return


## Gives every card that is not leaving its place in the stack, from the top, and starts the slide
## of those whose place moved.
func _layout() -> void:
	var at := 0.0
	for card in shown:
		if card.phase == Phase.OUT:
			continue
		if not is_equal_approx(card.y_to, at):
			card.y_from = card.y
			card.y_to = at
			card.slide = 0.0
			if UIMotion.reduced:
				card.y = at
				card.slide = 1.0
		at += PopupCard.size_of(card.kind).y + GAP


func _hold_of(kind: Kind) -> float:
	match kind:
		Kind.LEVEL:
			return _t.popup_hold_level
		Kind.TIER:
			return _t.popup_hold_tier
		Kind.CHALLENGE:
			return _t.popup_hold_challenge
	return _t.popup_hold_unlock


func _more_card() -> Card:
	if not waiting.is_empty() and waiting[waiting.size() - 1].kind == Kind.MORE:
		return waiting[waiting.size() - 1]
	return null


## Past `MAX_WAITING`: the lowest card (the newest of the lowest) goes into the `MORE` card.
func _merge_overflow() -> void:
	while waiting.size() > MAX_WAITING:
		var victim := -1
		for i in waiting.size():
			if waiting[i].kind == Kind.MORE:
				continue
			if victim < 0 or priority(waiting[i].kind) <= priority(waiting[victim].kind):
				victim = i
		if victim < 0:
			return
		waiting.remove_at(victim)
		var more := _more_card()
		if more == null:
			waiting.append(Card.new(Kind.MORE, {"count": 1}))
		else:
			more.data["count"] = int(more.data["count"]) + 1
