class_name XpReportQueue
extends RefCounted
## The reports of what a night's seats earned, waiting to reach the backend. A report is made once
## (at a round's end, at the night's end) and sent as it is made, so the same path and body go out
## on every retry and the backend's key on the match and the round makes a retry harmless. One is in
## flight at a time and in the order they were made, so a round is never reported after the one
## after it. The backend being down never stops a night: a report that could not be taken waits and
## is sent again after a growing pause, and the oldest is dropped only past `MAX_WAITING`.
##
## The queue sends nothing itself: `next` says what to send and `answered` takes the answer, so the
## clock is the caller's and a test steps it by hand.

## Statuses that mean the backend took the report (a repeat of one it already has answers 200).
const TAKEN: Array[int] = [200, 201, 204]
## Statuses that will never change (a report the backend refuses as it is): dropped and logged.
const REFUSED_FROM := 400
## Reports kept while the backend does not answer.
const MAX_WAITING := 200

## Seconds to wait before the next try of a report, by how many tries it has had (the last repeats).
var retry_after: Array[float] = [2.0, 5.0, 15.0, 30.0, 60.0]
## Reports made, taken by the backend, refused for good, and dropped to make room.
var made := 0
var taken := 0
var refused := 0
var dropped := 0
## The waiting reports: `{path, body, tries, at}`, oldest first.
var waiting: Array[Dictionary] = []

var _in_flight := false


## A report is made: `path` is the backend's address for it (the key is in it), `body` what it says.
func push(path: String, body: Dictionary) -> void:
	made += 1
	waiting.append({"path": path, "body": body, "tries": 0, "at": 0.0})
	while waiting.size() > MAX_WAITING:
		waiting.pop_front()
		dropped += 1


## The oldest report when it is time to send it and none is in flight, else an empty dictionary. It
## is then in flight until `answered`.
func next(now: float) -> Dictionary:
	if _in_flight or waiting.is_empty() or waiting[0]["at"] > now:
		return {}
	_in_flight = true
	return waiting[0]


## The backend's answer to the report `next` gave (`status` 0 is no answer at all).
func answered(status: int, now: float) -> void:
	_in_flight = false
	if waiting.is_empty():
		return
	if status in TAKEN:
		waiting.pop_front()
		taken += 1
	elif status >= REFUSED_FROM and status < 500 and status != 408 and status != 429:
		waiting.pop_front()
		refused += 1
	else:
		var report := waiting[0]
		var tries: int = report["tries"]
		report["at"] = now + retry_after[mini(tries, retry_after.size() - 1)]
		report["tries"] = tries + 1


func is_idle() -> bool:
	return waiting.is_empty() and not _in_flight
