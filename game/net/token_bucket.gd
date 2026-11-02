class_name TokenBucket
extends RefCounted
## A budget that refills at a steady rate up to a burst: `take(now)` spends one token if there is
## one. Time is the caller's (seconds), so a test steps it by hand and a server feeds it the clock.

var rate: float
var burst: float
var tokens: float
var _at := -1.0


func _init(p_rate: float, p_burst: float) -> void:
	rate = p_rate
	burst = p_burst
	tokens = p_burst


## True (and one token spent) when there is a token at time `now`.
func take(now: float) -> bool:
	if _at >= 0.0:
		tokens = minf(burst, tokens + (now - _at) * rate)
	_at = now
	if tokens < 1.0:
		return false
	tokens -= 1.0
	return true
