extends Control
## What the popup lane costs a frame in the browser (#1064): a HUD with the round banner and a boss
## bar up, then four moments in real time (a level, a tier, a stack of five unlocks with a level
## and a challenge, a level again) as the server's events would arrive. The length of every frame
## is read in the page; the run is judged on the longest frame with cards up against the longest
## of the quiet HUD before them. Not part of the game.
##
## In the web build `tools/web_smoke/popups_web.py` reads `window.__popups`; the same numbers print
## as `POPUPWEB {json}`. Windowed it plays once and quits.

const QUIET_SECONDS := 3.0
const MOMENTS: Array[Dictionary] = [
	{"at": 3.5, "level": 12},
	{"at": 8.0, "level": 16},
	{"at": 13.0, "level": 20},
	{"at": 19.0, "level": 21},
]
const LENGTH := 24.0

var _hud: Hud
var _clock := 0.0
var _last_usec := 0
var _next := 0
var _quiet: Array[float] = []
var _busy: Array[float] = []
var _cards_seen := 0
var _done := false


func _ready() -> void:
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	add_child(_hud)
	_hud.state.local_player_id = 1
	_hud.banner.show_banner("ROUND 7 SURVIVED", "CATCH YOUR BREATH", HudBanner.Rank.ROUND)
	(
		_hud
		. state
		. apply_event(
			{
				"type": &"zombie_spawn_requested",
				"zombie_id": 9,
				"zombie_type": &"headliner",
				"boss": true,
				"health": 1000.0,
			}
		)
	)
	_hud.popups.cue.connect(func(_sound: StringName) -> void: _cards_seen += 1)
	_last_usec = Time.get_ticks_usec()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame := float(now - _last_usec) / 1000.0
	_last_usec = now
	_clock += delta
	if _done:
		return
	if _clock > 0.5:
		if _hud.popups.queue.is_idle() and _next == 0:
			_quiet.append(frame)
		elif _clock > QUIET_SECONDS:
			_busy.append(frame)
	if _next < MOMENTS.size() and _clock >= float(MOMENTS[_next]["at"]):
		_hud.feed(_events(int(MOMENTS[_next]["level"])))
		_next += 1
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__popups = {stage: %d};" % _next)
	if _clock >= LENGTH:
		_finish()


## The events a level brings: the level, a tier when it opens one, two unlocks, a challenge.
func _events(level: int) -> Array:
	var events: Array = [{"type": &"level_up", "player_id": 1, "level": level, "total": 0}]
	if LevelCurve.tier_of(level) > LevelCurve.tier_of(level - 1):
		(
			events
			. append(
				{
					"type": &"tier_up",
					"player_id": 1,
					"tier": LevelCurve.tier_of(level),
					"tier_name": LevelCurve.tier_name(level),
					"level": level,
				}
			)
		)
	for item in [&"boots", &"goggles", &"helmet", &"teal", &"pink"]:
		(
			events
			. append(
				{
					"type": &"unlock_earned",
					"player_id": 1,
					"level": level,
					"slot": &"colour" if item in [&"teal", &"pink"] else &"top",
					"item": item,
				}
			)
		)
	(
		events
		. append(
			{
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
		)
	)
	return events


func _finish() -> void:
	_done = true
	var counts := {
		"quiet_frames": _quiet.size(),
		"quiet_max_ms": _quiet.max() if not _quiet.is_empty() else 0.0,
		"busy_frames": _busy.size(),
		"busy_max_ms": _busy.max() if not _busy.is_empty() else 0.0,
		"busy_mean_ms": _mean(_busy),
		"quiet_mean_ms": _mean(_quiet),
		"cards_started": _cards_seen,
		"web": OS.has_feature("web"),
		"renderer": RenderingServer.get_current_rendering_method(),
	}
	var text := JSON.stringify(counts)
	print("POPUPWEB ", text)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__popups = {done: true, counts: %s};" % text)
	else:
		get_tree().quit()


func _mean(list: Array[float]) -> float:
	if list.is_empty():
		return 0.0
	var total := 0.0
	for value in list:
		total += value
	return total / list.size()
