class_name GoalBrain
extends BotBrain
## A brain for the movement tests: it wants to be at `goal` and nothing else (no fighting, no
## follow), or at the first of `errands` the legs have not marked blocked. The bot's own legs, path
## and stuck ladder do the rest.

## Where to be (`Vector3.INF` for nowhere).
var goal := Vector3.INF
## A list of goals in order of preference: the first one not blocked is the goal.
var errands: Array[Vector3] = []
## The legs the bot walks on (the test sets it from the client).
var legs: BotLegs
## Whether to run to the goal.
var run := false
## The radius at which the bot counts as there.
var radius := 1.0
var _now := 0.0


func think(beliefs: BotBeliefs, _state: ClientState) -> BotIntent:
	_now = beliefs.now
	var intent := BotIntent.new()
	intent.goal = goal
	for errand in errands:
		if legs == null or not legs.path.is_blocked(errand, _now):
			intent.goal = errand
			break
	intent.goal_radius = radius
	intent.run = run
	intent.note = "errand"
	return intent
