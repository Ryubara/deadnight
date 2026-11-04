extends Node
## The popup lane over the menu, through the game's own root scene (`main.tscn` puts the overlay in
## the router's layer): the four storyboard moments a few seconds apart, as the events a game
## server tells (`XpAward`): a level up with its unlock, a tier up, a finished challenge, and a
## stack of five unlocks with a level. Not part of the game.
##
## Arguments after `--`: `--reduced` (reduced motion), `--touch` (a phone: the menu's compact
## layout, record at `--resolution 1560x720`).
## Record: `gds godot -- --path game res://tests/captures/popup_menu.tscn --write-movie <abs>/m.avi
## --fixed-fps 30 --resolution 1280x720`. Prints `POPUP <seconds> <cue>` whenever a card starts.

const FUEL: Array[StringName] = [&"fuel_can"]
const LENGTH := 27.0

var _clock := 0.0
var _plan: Array[Dictionary] = []
var _next := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	UIMotion.reduced = "--reduced" in args
	TouchMode.device_is_touch = "--touch" in args
	Settings.path = "user://popup_menu_capture.cfg"
	Settings.reset_defaults()
	Settings.set_value(SettingsService.REDUCED_MOTION, "--reduced" in args)
	add_child((load("res://main.tscn") as PackedScene).instantiate())
	_plan = [
		{"at": 1.5, "events": _crossing(11, 12)},
		{"at": 8.0, "events": _crossing(15, 16)},
		{"at": 15.0, "events": [_challenge()]},
		{"at": 20.0, "events": _stack_of_five()},
	]
	await get_tree().process_frame
	await UIRouter.idle
	MenuPopups.instance.lane.cue.connect(
		func(sound: StringName) -> void: print("POPUP %.1f %s" % [_clock, sound])
	)
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	if _next < _plan.size() and _clock >= float(_plan[_next]["at"]):
		MenuPopups.announce(_plan[_next]["events"])
		_next += 1
	if _clock >= LENGTH:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
		Settings.reset_defaults()
		UIMotion.reduced = false
		get_tree().quit()


## What the server tells a seat whose XP goes from just past level `from` to level `to`.
func _crossing(from: int, to: int) -> Array:
	var award := XpAward.new(FUEL, ChallengeClock.fixed(20401.0 * ChallengeClock.DAY_SECONDS))
	award.register(1, "ann", LevelCurve.xp_for(from) + 5, 0)
	award.add_xp(1, LevelCurve.xp_for(to) - LevelCurve.xp_for(from), XpAward.CHALLENGE)
	return award.end_tick(true)


func _challenge() -> Dictionary:
	return {
		"type": HudChallenge.EVENT,
		"id": &"d_kills",
		"family": ChallengeDef.Family.DAILY,
		"text": "Put down 40 zombies",
		"before": 39,
		"after": 40,
		"target": 40,
		"checkpoint": 100,
		"completed": true,
		"rung": 0,
		"rungs": 0,
	}


## A level and five things it gives at once (no level of the ladder gives so many yet: the stack
## the queue must hold, made by hand).
func _stack_of_five() -> Array:
	var events: Array = [{"type": &"level_up", "player_id": 1, "level": 20, "total": 0}]
	for item in [&"boots", &"goggles", &"helmet", &"teal", &"pink"]:
		(
			events
			. append(
				{
					"type": &"unlock_earned",
					"player_id": 1,
					"level": 20,
					"slot": &"colour" if item in [&"teal", &"pink"] else &"top",
					"item": item,
				}
			)
		)
	return events
