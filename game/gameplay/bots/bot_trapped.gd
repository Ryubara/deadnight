class_name BotTrapped
extends RefCounted
## A bot with no way out (bots plan, phase 5, `docs/research/bots.md#edge-cases`): it wants to back
## away from the dead and every heading is blocked or leads toward them (`BotSteering.pick` finds
## none) for `SECONDS` seconds on end. Then it fights on with what it has (it was fighting; the
## best weapon is already in hand), reports it once (a callout and a telemetry event), and jumps
## onto a curated place if one stands within `LINK_RANGE` metres (a car roof, `BotLink`). It never
## teleports: there is no such move in the game, and a bot that cannot get out says so.

## Seconds boxed in before the bot counts itself trapped, and the metres to a place to jump from.
const SECONDS := 2.0
const LINK_RANGE := 8.0
## Seconds a free heading must last before the bot counts itself out of it (a flicker is no way
## out).
const FREE_SECONDS := 0.5

var trapped := false

var _since := -1.0
var _free_since := -1.0


## One think: whether the bot found no way out (`boxed`). True on the think it becomes trapped.
func update(boxed: bool, now: float) -> bool:
	if boxed:
		_free_since = -1.0
		if _since < 0.0:
			_since = now
		if not trapped and now - _since >= SECONDS:
			trapped = true
			return true
		return false
	if _free_since < 0.0:
		_free_since = now
	if now - _free_since >= FREE_SECONDS:
		_since = -1.0
		trapped = false
	return false


## The nearest place to jump from within `LINK_RANGE` metres of `here`, or null.
static func nearest_link(here: Vector3, links: Array[BotLink]) -> BotLink:
	var best: BotLink = null
	var best_apart := LINK_RANGE
	for link in links:
		var apart := Vector2(link.from.x - here.x, link.from.z - here.z).length()
		if apart <= best_apart:
			best_apart = apart
			best = link
	return best
