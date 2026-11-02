class_name BotIntent
extends RefCounted
## What the brain wants this moment, as plain data the motor turns into a `NightCommand`: who to
## shoot, which way to walk, where to look when there is nothing to shoot, and the button edges.
## It stays in force until the next think; the motor follows the target's id every tick.

## The believed contact to shoot at, by id; -1 for none.
var target_id := -1
## The way to walk, a flat world direction (not normalised); zero to stand still.
var wish := Vector3.ZERO
var sprint := false
## A view yaw to turn toward when there is no target; NAN to keep the view.
var look_yaw := NAN
var reload := false
var swap := false
var use := false
## A short reason, for the ring buffer of decisions.
var note := ""


## False for an intent no motor should obey: a number that is not one, or a wish that is huge.
func is_sane() -> bool:
	return wish.is_finite() and wish.length() < 1000.0 and (is_nan(look_yaw) or is_finite(look_yaw))


func to_dict() -> Dictionary:
	return {
		"target": target_id,
		"wish": wish,
		"sprint": sprint,
		"look": look_yaw,
		"reload": reload,
		"swap": swap,
		"use": use,
		"note": note,
	}
