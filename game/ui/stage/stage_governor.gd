class_name StageGovernor
extends RefCounted
## Watches how long the frames take while the stage is live and says when to give it up, and when
## to take it back. Auto mode only. It steps the stage down a level (live, half resolution, a
## still) when the mean frame is too long for two windows running (one busy moment is not a
## trend), and a machine that is far too slow (a software renderer: several frames a second) goes
## straight to the still. From half resolution it climbs back to live once frames have been at the
## display's pace for a few seconds; a climb that fails (live drops again soon after) waits twice
## as long for the next, and after `MAX_FAILED_CLIMBS` the stage stays at half, so a machine that
## really cannot hold live does not flicker between looks. The still is final: nothing is drawn to
## measure.

enum Level { LIVE, HALF, STILL }

## Frames ignored at the start (the scene is still loading and compiling), and until this many
## seconds have gone by, or `WARMUP_SECONDS` when the frames are so long that twelve of them would
## take a minute.
const WARMUP := 12
const WARMUP_MIN_SECONDS := 2.0
const WARMUP_SECONDS := 4.0
## A window ends after this many frames, or after `WINDOW_SECONDS` once it holds `MIN_FRAMES`, so
## a very slow machine is judged in a couple of seconds, not a minute.
const WINDOW := 90
const WINDOW_SECONDS := 1.5
const MIN_FRAMES := 6
## Mean frame time (seconds) above which the level drops: about 40 and 25 frames a second.
const LIMIT_LIVE := 0.025
const LIMIT_HALF := 0.040
## Windows above the limit, one after another, before the level drops.
const SLOW_WINDOWS := 2
## Above this mean frame (about 8 frames a second) the stage goes straight to the still.
const LIMIT_SEVERE := 0.12
## At half resolution, a window at or under this mean frame (50 frames a second: a 60 Hz display
## held, with room for a 50 Hz one) counts towards climbing back to live.
const LIMIT_RECOVER := 0.020
## Seconds of good windows in a row before the first climb (in time, not frames: a fast display
## fills a window in a fraction of a second); each failed climb doubles it.
const RECOVER_SECONDS := 4.5
## A drop this soon (seconds) after a climb is a failed climb.
const PROBATION_SECONDS := 30.0
## Failed climbs after which the stage stays at half for the session.
const MAX_FAILED_CLIMBS := 2
## One frame counts for at most this much, so a single long frame (a shader compiling) is not a
## trend.
const CLAMP := 0.5

var level := Level.LIVE
## Failed climbs so far (read by tests and the capture probe).
var failed_climbs := 0

var _seen := 0
var _elapsed := 0.0
var _sum := 0.0
var _count := 0
var _slow := 0
var _good := 0.0
var _since_climb := INF


## Whether an adapter name is a renderer that draws on the CPU (a browser's SwiftShader, Mesa's
## llvmpipe, Windows' basic render driver): the stage does not go live on one.
static func is_software(adapter: String) -> bool:
	var lower := adapter.to_lower()
	for word in ["swiftshader", "llvmpipe", "softpipe", "software", "basic render"]:
		if lower.contains(word):
			return true
	return false


## Seconds of good frames needed now before climbing back to live.
func seconds_to_climb() -> float:
	return RECOVER_SECONDS * (1 << failed_climbs)


## Whether the stage may still climb back to live.
func can_climb() -> bool:
	return failed_climbs < MAX_FAILED_CLIMBS


## Feeds one frame; returns true when the level changed.
func feed(delta: float) -> bool:
	if level == Level.STILL:
		return false
	_seen += 1
	_elapsed += delta
	_since_climb += delta
	var warming := (_seen <= WARMUP or _elapsed < WARMUP_MIN_SECONDS) and _elapsed < WARMUP_SECONDS
	if warming:
		return false
	_sum += minf(delta, CLAMP)
	_count += 1
	var done := _count >= WINDOW or (_sum >= WINDOW_SECONDS and _count >= MIN_FRAMES)
	if not done:
		return false
	var mean := _sum / _count
	var window_seconds := _sum
	_sum = 0.0
	_count = 0
	return _judge(mean, window_seconds)


func _judge(mean: float, window_seconds: float) -> bool:
	if mean > LIMIT_SEVERE:
		level = Level.STILL
		return true
	if level == Level.LIVE:
		return _judge_live(mean)
	return _judge_half(mean, window_seconds)


func _judge_live(mean: float) -> bool:
	_slow = _slow + 1 if mean > LIMIT_LIVE else 0
	if _slow < SLOW_WINDOWS:
		return false
	if _since_climb < PROBATION_SECONDS:
		failed_climbs += 1
	_step_to(Level.HALF)
	return true


func _judge_half(mean: float, window_seconds: float) -> bool:
	if mean > LIMIT_HALF:
		_slow += 1
		_good = 0.0
		if _slow >= SLOW_WINDOWS:
			_step_to(Level.STILL)
			return true
		return false
	_slow = 0
	_good = _good + window_seconds if mean <= LIMIT_RECOVER and can_climb() else 0.0
	if _good < seconds_to_climb():
		return false
	_step_to(Level.LIVE)
	_since_climb = 0.0
	return true


func _step_to(to: Level) -> void:
	level = to
	_slow = 0
	_good = 0.0
