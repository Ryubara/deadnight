class_name BotStuck
extends RefCounted
## Whether a walking bot is stuck, and how far up the recovery ladder it is. Fed one sample a tick:
## the speed the bot is commanded to walk at and the progress it made along its way this tick
## (metres, negative when it lost ground). Pure data in, a rung out, so a test feeds it a position
## trace and reads the answer (`docs/research/bots.md#stuck-detection-and-recovery`).
##
## Stuck means: commanded to walk faster than `MIN_SPEED` and making less than `MIN_PROGRESS`
## metres a second of progress over the last `WINDOW` seconds. From then on the ladder climbs one
## rung every `RUNG_SECONDS` while the bot still makes no progress:
##
##   1 sidestep    2 repath from scratch to a jittered goal    3 jump while moving
##   4 drop the goal    5 walk back along the breadcrumb trail    6 report (`bot_stuck`)
##
## The ladder never ends in a teleport (decision 1 of the plan). After rung 6 it starts again from
## rung 1, and the episode goes on being counted until the bot moves again.

## Metres a second a bot must be commanded to walk at for its lack of progress to count.
const MIN_SPEED := 1.0
## Metres a second of progress below which a walking bot is stuck.
const MIN_PROGRESS := 0.25
## Seconds of samples the progress is averaged over.
const WINDOW := 0.5
## Seconds on a rung before the next.
const RUNG_SECONDS := 1.5
const REPORT_RUNG := 6

## The rung in force: 0 when the bot is not stuck, 1 to 6 on the ladder.
var rung := 0
## Seconds on the current rung.
var rung_age := 0.0
## Whether the bot is stuck now.
var stuck := false
## Seconds of the stuck episode in progress (the window that showed it included), and the longest
## so far.
var episode_seconds := 0.0
var longest_episode := 0.0
## Seconds stuck in all, seconds commanded to walk in all, episodes counted, highest rung reached.
var stuck_seconds := 0.0
var walking_seconds := 0.0
var episodes := 0
var depth_max := 0
## Set for one sample when the ladder reaches the report rung: the caller reports and clears it.
var report_due := false
## Rungs reached in the current episode, in order (for the report).
var climbed: Array[int] = []

var _samples: Array[Vector2] = []
var _span := 0.0
var _gain := 0.0


## One tick. `speed` is the speed the bot is commanded to walk at (0 when it stands), `progress`
## the metres it gained toward where it goes this tick. Returns the rung.
func feed(delta: float, speed: float, progress: float) -> int:
	if speed < MIN_SPEED:
		_end_episode()
		_clear_window()
		return rung
	walking_seconds += delta
	_samples.append(Vector2(delta, progress))
	_span += delta
	_gain += progress
	while _samples.size() > 1 and _span - _samples[0].x >= WINDOW:
		_span -= _samples[0].x
		_gain -= _samples[0].y
		_samples.pop_front()
	var full := _span >= WINDOW - 0.0001
	var slow := full and _gain / _span < MIN_PROGRESS
	if slow and not stuck:
		_begin_episode()
	elif not slow and stuck and full:
		_end_episode()
	if stuck:
		episode_seconds += delta
		stuck_seconds += delta
		rung_age += delta
		if rung_age >= RUNG_SECONDS:
			rung_age = 0.0
			rung = 1 if rung >= REPORT_RUNG else rung + 1
			_note_rung()
	return rung


## The longest episode so far, the one in progress included.
func longest() -> float:
	return maxf(longest_episode, episode_seconds)


## The bot stopped on purpose, or its goal changed: nothing is being tried any more.
func reset() -> void:
	_end_episode()
	_clear_window()


## Closes the report: the caller has dealt with `report_due`.
func reported() -> void:
	report_due = false


func _begin_episode() -> void:
	stuck = true
	episodes += 1
	rung = 1
	rung_age = 0.0
	# The window that showed it was already time spent not getting anywhere.
	episode_seconds = _span
	stuck_seconds += _span
	climbed.clear()
	_note_rung()


func _end_episode() -> void:
	if not stuck:
		return
	stuck = false
	rung = 0
	rung_age = 0.0
	longest_episode = maxf(longest_episode, episode_seconds)
	episode_seconds = 0.0
	report_due = false


func _note_rung() -> void:
	depth_max = maxi(depth_max, rung)
	climbed.append(rung)
	if rung == REPORT_RUNG:
		report_due = true


func _clear_window() -> void:
	_samples.clear()
	_span = 0.0
	_gain = 0.0
