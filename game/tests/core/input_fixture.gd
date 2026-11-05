class_name InputFixture
extends RefCounted
## Lets go of every input action a suite may have left held (#1254).
##
## GdUnit runs the suites of a shard one after another in one process, so an action that stays
## down reaches the next suite. `Input.action_press` and an `InputEventAction` or key sent with
## `Input.parse_input_event` both leave one down until something releases it; the event is only
## buffered until the frame's flush, so a release made in the same frame comes first and the
## event presses afterwards.


## The actions that are down now, by name.
static func held() -> Array[StringName]:
	var down: Array[StringName] = []
	for action in InputMap.get_actions():
		if Input.is_action_pressed(action):
			down.append(action)
	return down


## Applies the events still waiting for the frame, then releases every action that is down.
static func release_all() -> void:
	Input.flush_buffered_events()
	for action in held():
		Input.action_release(action)
