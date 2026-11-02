class_name StallGuard
extends RefCounted
## Notices that this client's own game loop stopped for a while (a hitch while an effect loads for
## the first time, a tab put to the back) and says what to do with the ticks that follow. After
## such a freeze the engine runs the ticks it owes together, up to eight in one frame. Each of them
## would move the predicted body a step and send a command, and the server takes only the newest of
## commands that arrive together, so the body would be several steps ahead of the server for no
## reason, and what the server said meanwhile is a second or more old.
##
## `check(now)` is called once per tick with the clock in milliseconds: the first tick after the
## freeze is a `RESYNC` (put the body where the server says, forget the commands in flight), the
## ticks the engine ran to catch up with the freeze are `SKIP`ped (no body step, no command), and
## every other tick is a `RUN`. Time is the caller's, so a test steps it by hand.

enum Verdict { RUN, RESYNC, SKIP }

## A gap between two ticks over this many milliseconds is a freeze (a tick is 16.7).
const STALL_MS := 250.0
## A tick this close to the one before it, straight after a freeze, is a catch-up tick.
const CATCH_UP_MS := 8.0

## Freezes seen, and ticks skipped, for the numbers of a run.
var stalls := 0
var skipped := 0
## The longest gap seen, in milliseconds.
var longest_ms := 0.0

var _last_ms := -1.0
var _catching_up := false


func check(now_ms: float) -> Verdict:
	var gap := now_ms - _last_ms if _last_ms >= 0.0 else 0.0
	_last_ms = now_ms
	longest_ms = maxf(longest_ms, gap)
	if gap > STALL_MS:
		stalls += 1
		_catching_up = true
		return Verdict.RESYNC
	if _catching_up and gap < CATCH_UP_MS:
		skipped += 1
		return Verdict.SKIP
	_catching_up = false
	return Verdict.RUN
