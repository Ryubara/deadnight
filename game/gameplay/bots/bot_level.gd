class_name BotLevel
extends RefCounted
## The static data of the lot every client has before the night begins, and the two questions a
## person's eyes answer: is there a wall between here and there (`sight`), and is that ground lit
## (`lit`). A bot is given these and nothing else about the world.

## Metres a player sees at the least, and how many more in full light; the same numbers as the
## balance simulator's view (`VIEW_MIN`, `VIEW_PER_LIGHT` in `tools/balance/night_sim.gd`).
const VIEW_MIN := 8.0
const VIEW_PER_LIGHT := 25.0
## The farthest any bot sees: the lit range.
const MAX_VIEW := VIEW_MIN + VIEW_PER_LIGHT
## Metres from the feet to the eye, and from the feet to the barrel's height.
const EYE_HEIGHT := 1.55
## Metres above the feet of a plain walker at which the bot aims, and of its head.
const CHEST_HEIGHT := 1.1
const HEAD_HEIGHT := 1.6

## `Callable(from: Vector3, to: Vector3) -> float`: metres to the first wall on the way, or -1.0.
var sight: Callable = Callable()
## `Callable(point: Vector3) -> bool`: whether the ground there is lit.
var lit: Callable = Callable()
## The rounds table: how dark the night is in each round (`ambient_for_round`).
var rounds: RoundTuning
## The navigation mesh of the lot (from phase 2 on).
var map: RID
## Where a bot falls back to when it backs away (the field in front of the screen); `Vector3.INF`
## for nowhere in particular.
var home := Vector3.INF


func _init(
	p_sight: Callable = Callable(),
	p_lit: Callable = Callable(),
	p_rounds: RoundTuning = null,
	p_map: RID = RID()
) -> void:
	sight = p_sight
	lit = p_lit
	rounds = p_rounds
	map = p_map


## Metres at which a zombie standing at `point` can be made out in round `round_number`: the
## night closes in with the rounds, and a lit patch of ground is seen from afar.
func view_range(point: Vector3, round_number: int) -> float:
	if lit.is_valid() and lit.call(point):
		return MAX_VIEW
	var ambient := rounds.ambient_for_round(round_number) if rounds != null else 1.0
	return VIEW_MIN + VIEW_PER_LIGHT * ambient


## Whether nothing solid stands between the two points.
func clear(from: Vector3, to: Vector3) -> bool:
	return not sight.is_valid() or float(sight.call(from, to)) < 0.0
