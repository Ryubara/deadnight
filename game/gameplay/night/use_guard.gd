class_name UseGuard
extends RefCounted
## Which presses of `use` may buy (#908). The maintainer, boarding a window: "I'll accidentally
## interact with a weapon on the wall or a perk or something else next to it ... losing your
## weapons". A board is put back by holding use, and a person taps it again to go on: a press that
## carries on mending is not a press to buy, and a weapon bought with the hands full throws the one
## in hand away. So, per player:
##
## - no purchase while a held repair goes on, nor `repair_grace` seconds after its last board;
## - a purchase that replaces a weapon carried (`replaces` on the offer) only from a press made once
##   the offer has been the player's prompt for `replace_settle` seconds: the card that says what
##   goes has been on screen, so the press is meant.
##
## Free uses (a board, a breaker, a revive) are never held back.

## The offers that cost points or a weapon.
const PURCHASES: Array[StringName] = [
	&"door",
	&"weapon",
	&"ammo",
	&"grenades",
	&"crane",
	&"crane_take",
	&"recut",
	&"tonic",
	&"fuel",
]
## Why a press was held back.
const HELD_REPAIR := &"repairing"
const UNSETTLED := &"unsettled"

var repair_grace := 1.5
var replace_settle := 0.4

var _board_at: Dictionary[int, float] = {}
var _offer: Dictionary[int, String] = {}
var _since: Dictionary[int, float] = {}


func _init(tuning: NightTuning = null) -> void:
	if tuning != null:
		repair_grace = tuning.repair_grace
		replace_settle = tuning.replace_settle


## A board went back across a breach by this player's hand at `now` (seconds).
func board(player_id: int, now: float) -> void:
	_board_at[player_id] = now


## What the player's prompt is this tick: the time an offer has been on the card counts from the
## tick it first shows.
func see(player_id: int, target: Dictionary, now: float) -> void:
	var key := "%s:%s" % [target.get("kind", &""), target.get("id", &"")]
	if _offer.get(player_id, "") != key:
		_offer[player_id] = key
		_since[player_id] = now


## `&""` when a press at `now` may do what `target` offers, else why not (`HELD_REPAIR`,
## `UNSETTLED`). `repairing`: a held repair of this player's is going on.
func refuses(player_id: int, target: Dictionary, now: float, repairing: bool) -> StringName:
	if not PURCHASES.has(target.get("kind", &"")):
		return &""
	if repairing or now - float(_board_at.get(player_id, -INF)) < repair_grace:
		return HELD_REPAIR
	if StringName(target.get("replaces", &"")) != &"":
		if now - float(_since.get(player_id, now)) < replace_settle:
			return UNSETTLED
	return &""


func forget(player_id: int) -> void:
	_board_at.erase(player_id)
	_offer.erase(player_id)
	_since.erase(player_id)
