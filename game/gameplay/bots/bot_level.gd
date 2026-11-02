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
## Metres above the ground at which a bot looks for something it cannot walk through.
const KNEE_HEIGHT := 0.5
## The widest a place can be between two walls and still be a passage a bot must not stop in:
## half of it is the distance each side's ray reaches (the lot's gaps are 1.8 to 2.0 m wide).
const PASSAGE_HALF := 1.15
## Metres from a loop within which a bot feels its pull.
const LOOP_REACH := 6.0

## `Callable(from: Vector3, to: Vector3) -> float`: metres to the first wall on the way, or -1.0.
var sight: Callable = Callable()
## `Callable(point: Vector3) -> bool`: whether the ground there is lit.
var lit: Callable = Callable()
## The rounds table: how dark the night is in each round (`ambient_for_round`).
var rounds: RoundTuning
## The navigation mesh of the lot (from phase 2 on).
var map: RID
## Where the dead break in, one point for each gap in the fence: a bot keeps clear of them.
var breaches: Array[Vector3] = []
## Curated places where a bot may jump (a car roof, a ledge), see `BotLink`.
var links: Array[BotLink] = []
## The lot's loops, closed polylines on the ground (see `docs/design/map.md#loops-for-kiting`): a
## bot being chased circles round one.
var loops: Array[PackedVector3Array] = []
## Where a bot falls back to when it backs away (the field in front of the screen); `Vector3.INF`
## for nowhere in particular.
var home := Vector3.INF
## The shop, the breaches, the breaker posts and the fuel crates (`LotBotData.fill` with the rules'
## tuning); null for a bot that does no errands.
var shop: BotShop


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


# --- The walking mesh and the lot's shape, for a bot's feet ---


## The closest point on the walking mesh, or `point` when there is no mesh to ask.
func project(point: Vector3) -> Vector3:
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) < 1:
		return point
	return NavigationServer3D.map_get_closest_point(map, point)


## Metres of open way from `from` along the flat unit `heading`, at most `limit`: how far a bot
## could walk before something solid stops it.
func room(from: Vector3, heading: Vector3, limit: float) -> float:
	if not sight.is_valid():
		return limit
	var low := Vector3(0.0, KNEE_HEIGHT, 0.0)
	var hit := float(sight.call(from + low, from + low + heading * limit))
	return limit if hit < 0.0 else hit


## Whether `point` is inside a gap: walls close in on two opposite sides (a door's opening, the
## 2 m passages between cars). A bot never stops in one.
func in_passage(point: Vector3) -> bool:
	if not sight.is_valid():
		return false
	for axis in 4:
		var direction := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, float(axis) * PI / 4.0)
		var one := room(point, direction, PASSAGE_HALF)
		var other := room(point, -direction, PASSAGE_HALF)
		if one < PASSAGE_HALF and other < PASSAGE_HALF:
			return true
	return false
