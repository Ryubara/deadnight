class_name ClientStats
extends RefCounted
## What a client measures about its own connection: payload bytes each way, round trip (in ticks),
## and how far each snapshot moved the predicted position (the correction).

const MS_PER_TICK := 1000.0 / GameSim.TICK_RATE
const WINDOW_SECONDS := 2.0

var bytes_up := 0
var bytes_down := 0
var snapshots := 0
var pending_total := 0

var _window_up := 0
var _window_down := 0
var _window_snapshots := 0
var _window_corrections: Array[float] = []
var _rtt_ticks: Array[int] = []
var _all_corrections: Array[float] = []
var _all_rtt_ticks: Array[int] = []
var _last_up := 0.0
var _last_down := 0.0
var _windows := 0


func add_rtt_ticks(ticks: int) -> void:
	_rtt_ticks.append(ticks)
	_all_rtt_ticks.append(ticks)


func add_correction_cm(cm: float) -> void:
	_window_corrections.append(cm)
	_all_corrections.append(cm)


func rtt_average_ms() -> float:
	return _mean_int(_all_rtt_ticks.slice(-10)) * MS_PER_TICK


func correction_average_cm() -> float:
	return _mean(_window_corrections)


func up_rate() -> float:
	return _last_up


func down_rate() -> float:
	return _last_down


func window_line() -> String:
	return (
		"up %.0f B/s down %.0f B/s snap %.0f/s rtt %.0f ms corr n=%d>1cm mean=%.2f max=%.1f cm"
		% [
			(bytes_up - _window_up) / WINDOW_SECONDS,
			(bytes_down - _window_down) / WINDOW_SECONDS,
			float(snapshots - _window_snapshots) / WINDOW_SECONDS,
			_mean_int(_rtt_ticks) * MS_PER_TICK,
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
	_rtt_ticks = []
	_windows += 1


func summary(player_id: int) -> String:
	var seconds := maxf(_windows * WINDOW_SECONDS, 1.0)
	return (
		(
			"RESULT player=%d seconds=%.0f up=%.0f B/s down=%.0f B/s rtt=%.0f ms "
			+ "corrections>1cm=%d/%d mean=%.2f cm max=%.1f cm"
		)
		% [
			player_id,
			seconds,
			bytes_up / seconds,
			bytes_down / seconds,
			_mean_int(_all_rtt_ticks) * MS_PER_TICK,
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


func _mean_int(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for value in values:
		total += value
	return float(total) / values.size()


func _max(values: Array[float]) -> float:
	return values.max() if not values.is_empty() else 0.0


func _count_above(values: Array[float], limit: float) -> int:
	var count := 0
	for value in values:
		if value > limit:
			count += 1
	return count
