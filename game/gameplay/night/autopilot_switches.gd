class_name AutopilotSwitches
extends RefCounted
## When the bot throws a breaker. It sees what a client sees: the frame's circuits and tank, the
## doors open, and the prompt at a post. The rule is the one a player would use:
##   - a circuit that lights an area whose door is bought goes on, because the dead now spawn
##     there and lit ground slows them;
##   - the field's circuit stays on, because that is where it fights;
##   - when the tank runs low it throws off every circuit that is not the field's, and holds them
##     off until the tank has come back past `resume_above` (so it does not flicker at the line).
## A trip to turn a circuit on is made at once; one to turn a circuit off waits for a break, when
## nothing is chasing it.

## Fractions of a full tank: below `save_below` it saves fuel; it lights again above `resume_above`.
var save_below := 0.25
var resume_above := 0.4
## Units in a full tank.
var capacity := 100.0
## Where to stand to use the post of each circuit, and the shop door of the area it lights (empty
## for the field, which no door guards).
var goals: Dictionary[StringName, Vector3] = {}
var doors: Dictionary[StringName, StringName] = {}


## Whether the bot wants `circuit_id` on, given the latest `frame`.
func wanted(circuit_id: StringName, frame: Dictionary) -> bool:
	var door: StringName = doors.get(circuit_id, &"")
	if door == &"":
		return true
	if not frame.get("doors", []).has(door):
		return false
	var fraction: float = frame.get("fuel", capacity) / capacity
	var on_now: bool = frame.get("circuits", {}).get(circuit_id, false)
	return fraction >= (save_below if on_now else resume_above)


## Whether the post it stands at (the frame's `prompt`) is thrown the wrong way for the bot.
func wants_use(prompt: Dictionary, frame: Dictionary) -> bool:
	return prompt.get("kind", &"") == &"circuit" and prompt["on"] != wanted(prompt["id"], frame)


## The standing place of the nearest post worth a trip from `here`, or `Vector3.INF` for none.
func next_goal(frame: Dictionary, here: Vector3, in_break: bool) -> Vector3:
	var best := Vector3.INF
	var best_distance := INF
	var circuits: Dictionary = frame.get("circuits", {})
	for circuit_id in goals:
		var on_now: bool = circuits.get(circuit_id, false)
		var want := wanted(circuit_id, frame)
		if on_now == want or (on_now and not in_break):
			continue
		var distance := Vector2(here.x - goals[circuit_id].x, here.z - goals[circuit_id].z).length()
		if distance < best_distance:
			best_distance = distance
			best = goals[circuit_id]
	return best
