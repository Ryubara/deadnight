class_name BotNeeds
extends RefCounted
## What a bot needs against what it was ordered: one table, `RULES`, that answers "may this bot
## leave its order to see to this need now?" (`docs/research/bots.md#needs-against-orders-692`).
## The brain asks `verdict`; no rule about a need and an order is written anywhere else, so a new
## need (the health stances of #693) is a new key of the table and a function that rates it,
## never a branch in the brain.
##
## A need has a level, from `NONE` up, and an order (`BotOrders`) has a row of three words:
## - `go`: the level at which the bot goes whatever the order says;
## - `near`: the level at which it goes when the place that answers the need is near the people
##   the order keeps it with (`is_near`: within the leash of them, or on the way to them);
## - `say`: whether a bot that is held back says so (the callout of the need).
## Below `near` the bot stays and does not mention it; between `near` and `go` it stays and (when
## the row says so) says it; at `go` it goes. A need a person's ping names is not decided here: a
## ping sits above every order (`BotPings`).
##
## Pure data and arithmetic: no clock, no frame, no server.

## What the bot needs. Another need is another key of `RULES`.
enum Need { AMMO }

## How badly. Ordered: a rule compares levels.
## - `LOW`: a firearm worth rounds is under the profile's floor of magazines in reserve;
## - `SHORT`: one is under a single magazine in reserve;
## - `EMPTY`: no round is left in any firearm worth rounds, magazine and reserve alike.
enum Level { NONE, LOW, SHORT, EMPTY }

## What to do about the need.
## - `GO`: leave the order, see to it, come back;
## - `STAY`: keep the order and say nothing;
## - `STAY_AND_SAY`: keep the order and say the need aloud.
enum Verdict { GO, STAY, STAY_AND_SAY }

## The table: need, then order, then `{go, near, say}`.
## - Roam does its own thing, so it goes freely.
## - Follow goes when the source is near the leader, or when the gun is empty (then it comes back).
## - Hold keeps its spot until the reserve is under a magazine, then goes and comes back.
const RULES := {
	Need.AMMO:
	{
		BotOrders.ROAM: {"go": Level.LOW, "near": Level.LOW, "say": false},
		BotOrders.FOLLOW: {"go": Level.EMPTY, "near": Level.LOW, "say": true},
		BotOrders.HOLD: {"go": Level.SHORT, "near": Level.SHORT, "say": false},
	},
}

## Metres from the people within which a source counts as near them (the follow leash, the same
## number as a chase's), how far off the straight way to them it may lie and still be on the way,
## and the metres a trip already begun is given on top (so a leader at the edge does not turn the
## bot round on every step).
const LEASH := BotCombat.LEASH
const ON_THE_WAY := 3.0
const UNDERWAY_SLACK := 4.0


## What the bot does about `need`, at `level`, under `order`; `near` is whether the place that
## answers it is near the people the order keeps it with (`is_near`).
static func verdict(need: Need, order: StringName, level: Level, near: bool) -> Verdict:
	var row := row_of(need, order)
	if level == Level.NONE or row.is_empty():
		return Verdict.STAY
	if level >= int(row["go"]) or (near and level >= int(row["near"])):
		return Verdict.GO
	if level >= int(row["near"]) and row["say"]:
		return Verdict.STAY_AND_SAY
	return Verdict.STAY


## The row of the table for `need` under `order`, or an empty one (an order or a need the table
## does not know is no reason to go).
static func row_of(need: Need, order: StringName) -> Dictionary:
	return (RULES.get(need, {}) as Dictionary).get(order, {})


## Whether `place` is near `anchor` (where the people the bot is ordered to stay with are): within
## `LEASH` of them, or within `ON_THE_WAY` of the straight way from `here` to them. With nobody to
## stay with (`anchor` not finite) every place is near. `slack` widens the leash.
static func is_near(place: Vector3, here: Vector3, anchor: Vector3, slack := 0.0) -> bool:
	if not anchor.is_finite():
		return true
	if _flat(place, anchor) <= LEASH + slack:
		return true
	return BotPath._distance_to_segment(place, here, anchor) <= ON_THE_WAY


## How badly the bot needs rounds, from the guns it carries (`arms`: catalogue id to `[magazine,
## reserve, tier]`) and the profile's floor of magazines. Only guns worth rounds count
## (`BotEconomy.useful`); a bot with none worth rounds needs none.
static func ammo_level(arms: Dictionary, floor_mags: int) -> Level:
	var level := Level.NONE
	var rounds := 0
	var guns := BotEconomy.useful(arms)
	for id in guns:
		var def := WeaponCatalog.get_def(id)
		var reserve := int(arms[id][1])
		rounds += int(arms[id][0]) + reserve
		if reserve < def.magazine_size:
			level = maxi(level, Level.SHORT) as Level
		elif reserve < def.magazine_size * floor_mags:
			level = maxi(level, Level.LOW) as Level
	if not guns.is_empty() and rounds == 0:
		return Level.EMPTY
	return level


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
