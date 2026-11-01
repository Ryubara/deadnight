class_name ClientStats
extends RefCounted
## What a client measures about its own connection: payload bytes each way, round trip (wall clock,
## so it carries the client's and the server's 33 ms tick polling), the gaps between snapshot
## arrivals (a gap of 3 ticks or more is a stall: TCP head-of-line blocking), and how far each
## snapshot moved the predicted position (the correction).

const MS_PER_TICK := 1000.0 / GameSim.TICK_RATE
const WINDOW_SECONDS := 2.0
const STALL_MS := 100.0  # a snapshot gap of three ticks or more: two snapshots missed

var bytes_up := 0
var bytes_down := 0
var snapshots := 0
var pending_total := 0
var remote_draws := 0  # frames drawn per remote player
var remote_starved := 0  # of those, frames where the render clock was ahead of the newest snapshot

var _window_up := 0
var _window_down := 0
var _window_snapshots := 0
var _window_corrections: Array[float] = []
var _rtt_ms: Array[float] = []
var _all_corrections: Array[float] = []
var _all_rtt_ms: Array[float] = []
var _gaps_ms: Array[float] = []
var _all_gaps_ms: Array[float] = []
var _last_arrival_usec := 0
var _last_up := 0.0
var _last_down := 0.0
var _windows := 0


func add_rtt_ms(ms: float) -> void:
	_rtt_ms.append(ms)
	_all_rtt_ms.append(ms)


## Called for every accepted snapshot with the time it was read from the socket.
func add_snapshot_arrival(now_usec: int) -> void:
	if _last_arrival_usec > 0:
		var gap := (now_usec - _last_arrival_usec) / 1000.0
		_gaps_ms.append(gap)
		_all_gaps_ms.append(gap)
	_last_arrival_usec = now_usec


func add_correction_cm(cm: float) -> void:
	_window_corrections.append(cm)
	_all_corrections.append(cm)


func rtt_average_ms() -> float:
	return _mean(_all_rtt_ms.slice(-10))


func correction_average_cm() -> float:
	return _mean(_window_corrections)


func up_rate() -> float:
	return _last_up


func down_rate() -> float:
	return _last_down


func window_line() -> String:
	return (
		(
			"up %.0f B/s down %.0f B/s snap %.0f/s rtt %.0f/%.0f ms (mean/max) gap max %.0f ms "
			+ "corr n=%d>1cm mean=%.2f max=%.1f cm"
		)
		% [
			(bytes_up - _window_up) / WINDOW_SECONDS,
			(bytes_down - _window_down) / WINDOW_SECONDS,
			float(snapshots - _window_snapshots) / WINDOW_SECONDS,
			_mean(_rtt_ms),
			_max(_rtt_ms),
			_max(_gaps_ms),
			_count_above(_window_corrections, 1.0),
			_mean(_window_corrections),
			_max(_window_corrections),
		]
	)


## Closes the current window: turns its counters into rates.
func roll_window() -> void:
	_last_up = (bytes_up - _window_up) / WINDOW_SECONDS
	_last_down = (bytes_down - _window_down) / WINDOW_SECONDS
	_window_up = bytes_up
	_window_down = bytes_down
	_window_snapshots = snapshots
	_window_corrections = []
	_rtt_ms = []
	_gaps_ms = []
	_windows += 1


func summary(player_id: int) -> String:
	var seconds := maxf(_windows * WINDOW_SECONDS, 1.0)
	var rtt := _all_rtt_ms.duplicate()
	rtt.sort()
	var gaps := _all_gaps_ms.duplicate()
	gaps.sort()
	var stall_ms := 0.0
	for gap in gaps:
		if gap >= STALL_MS:
			stall_ms += gap - MS_PER_TICK
	return (
		(
			"RESULT player=%d seconds=%.0f up=%.0f B/s down=%.0f B/s | "
			+ "rtt n=%d mean=%.1f p50=%.1f p95=%.1f p99=%.1f max=%.1f jitter=%.1f ms | "
			+ "snapshot gap mean=%.1f sd=%.1f p99=%.1f max=%.1f ms, n=%d, "
			+ ">=%dms: %d, >=200ms: %d, >=500ms: %d, stalled %.0f ms | "
			+ "interp buffer starved %d/%d remote draws | "
			+ "corrections>1cm=%d/%d mean=%.2f cm max=%.1f cm"
		)
		% [
			player_id,
			seconds,
			bytes_up / seconds,
			bytes_down / seconds,
			rtt.size(),
			_mean(rtt),
			_percentile(rtt, 0.5),
			_percentile(rtt, 0.95),
			_percentile(rtt, 0.99),
			_max(rtt),
			_stddev(rtt),
			_mean(gaps),
			_stddev(gaps),
			_percentile(gaps, 0.99),
			_max(gaps),
			gaps.size(),
			int(STALL_MS),
			_count_above(gaps, STALL_MS - 1.0),
			_count_above(gaps, 199.0),
			_count_above(gaps, 499.0),
			stall_ms,
			remote_starved,
			remote_draws,
			_count_above(_all_corrections, 1.0),
			_all_corrections.size(),
			_mean(_all_corrections),
			_max(_all_corrections),
		]
	)


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()


func _stddev(values: Array[float]) -> float:
	if values.size() < 2:
		return 0.0
	var mean := _mean(values)
	var total := 0.0
	for value in values:
		total += (value - mean) * (value - mean)
	return sqrt(total / values.size())


## `sorted` must be sorted ascending.
func _percentile(sorted: Array[float], fraction: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[mini(int(fraction * sorted.size()), sorted.size() - 1)]


func _max(values: Array[float]) -> float:
	return values.max() if not values.is_empty() else 0.0


func _count_above(values: Array[float], limit: float) -> int:
	var count := 0
	for value in values:
		if value > limit:
			count += 1
	return count
