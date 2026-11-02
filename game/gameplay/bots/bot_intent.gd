class_name BotIntent
extends RefCounted
## What the brain wants this moment, as plain data the motor turns into a `NightCommand`: who to
## shoot, which way to walk, where to look when there is nothing to shoot, and the button edges.
## It stays in force until the next think; the motor follows the target's id every tick.

## The believed contact to shoot at, by id; -1 for none.
var target_id := -1
## Where to walk to (`Vector3.INF` for nowhere), and how near counts as there (0 for the legs'
## own radius). The legs find the way: a cached path over the walking mesh.
var goal := Vector3.INF
var goal_radius := 0.0
## A heading to take as it is, flat, already chosen on the mesh by the steering (a retreat, a
## dodge); it takes the place of the goal. Zero for none.
var reflex := Vector3.ZERO
## Whether the brain wants to run (sprint) to get there.
var run := false
## What the legs made of it this tick, which the motor turns into the stick: the way to walk (a
## flat world direction, zero to stand still), whether to sprint, whether to jump.
var wish := Vector3.ZERO
var sprint := false
var jump := false
## How hard to push the stick, 0 to 1.
var pace := 1.0
## A view yaw to turn toward when there is no target; NAN to keep the view.
var look_yaw := NAN
var reload := false
var swap := false
var use := false
## Whether a melee swing may be made (false inside a pack the bot is not forced to fight).
var melee_ok := true
## A grenade to throw, or nothing: the style (`over` or `under`), the view to throw along, and the
## clock when it was ordered. The motor turns, pulls the pin when the view is there, and lets go.
var throw_style: StringName = &""
var throw_yaw := 0.0
var throw_pitch := 0.0
## The brain takes back a throw it ordered whose view is still turning (a teammate walked in).
var throw_abort := false
## A short reason, for the ring buffer of decisions.
var note := ""


## False for an intent no motor should obey: a number that is not one, or a wish that is huge.
func is_sane() -> bool:
	return (
		wish.is_finite()
		and wish.length() < 1000.0
		and reflex.is_finite()
		and reflex.length() < 1000.0
		and (goal == Vector3.INF or goal.is_finite())
		and (is_nan(look_yaw) or is_finite(look_yaw))
	)


func to_dict() -> Dictionary:
	return {
		"target": target_id,
		"goal": goal,
		"reflex": reflex,
		"run": run,
		"wish": wish,
		"sprint": sprint,
		"look": look_yaw,
		"reload": reload,
		"swap": swap,
		"use": use,
		"throw": throw_style,
		"note": note,
	}
