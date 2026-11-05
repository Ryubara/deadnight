class_name NightListFeed
extends Node
## Keeps the Server Browser's list current: asks the backend for the public nights
## (`TogetherApi.list_nights`) every `EVERY` seconds while it runs, again when the player presses
## Refresh, and says what came back.
##
## The backend answers one account 20 asks in 10 seconds and then `429 too_many_requests` with a
## `Retry-After`. The feed stays well inside that on its own: the timer asks about every 4 seconds,
## a press of Refresh is turned away inside `MIN_GAP` of the last ask, and no more than `BUDGET`
## asks are ever sent in any `WINDOW` seconds, whoever asks. A `429` that comes anyway (another tab
## of the same account) holds the feed for the seconds the header named and says so; the list the
## player sees is kept meanwhile.
##
## One ask at a time. Three answers: `updated` (the rows, in the backend's order, and how many
## nights there are), `failed` (the words to show; the rows already on show are kept) and `waiting`
## (held back by the rate limit).

signal loading
signal updated(entries: Array[NightEntry], total: int)
signal failed(text: String, reason: String)
signal waiting(seconds: float)

enum State { IDLE, LOADING, LOADED, FAILED }

## Seconds between the feed's own asks.
const EVERY := 4.0
## Least seconds between two asks that a player's press made.
const MIN_GAP := 1.5
## The backend's window and the most this feed uses of it (it allows 20).
const WINDOW := 10.0
const BUDGET := 14
## The wait when the backend answers 429 without a `Retry-After`.
const BACKOFF := 10.0

var state := State.IDLE
var entries: Array[NightEntry] = []
var total := 0
var running := false
## For a test: seconds as a clock reads them, in place of the engine's.
var clock := Callable()

var _api: TogetherApi
var _timer: Timer
var _asking := false
var _asked: Array[float] = []
var _held_until := 0.0
var _last_ask := -1000.0
## Counts the starts and stops: an answer that comes after a stop is not told to anyone.
var _generation := 0


## Starts asking through `api` (the list needs a signed-in account). The first ask goes out at once.
func start(api: TogetherApi) -> void:
	_api = api
	running = true
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = false
		_timer.timeout.connect(_on_tick)
		add_child(_timer)
	_timer.start(EVERY)
	refresh()


func stop() -> void:
	running = false
	_generation += 1
	if _timer != null:
		_timer.stop()


## Asks now, if the rate allows it. `by_player` is a press of Refresh: it is turned away inside
## `MIN_GAP` of the last ask. False when nothing was asked (an ask is out, the limit holds it, or it
## is too soon).
func refresh(by_player := false) -> bool:
	if not running or _api == null or _asking:
		return false
	var now := _now()
	if now < _held_until:
		waiting.emit(_held_until - now)
		return false
	if by_player and now - _last_ask < MIN_GAP:
		return false
	if asks_in_window(now) >= BUDGET:
		return false
	_ask(now)
	return true


## How many asks this feed sent in the last `WINDOW` seconds.
func asks_in_window(now: float = -1.0) -> int:
	var at := _now() if now < 0.0 else now
	var count := 0
	for when in _asked:
		if at - when < WINDOW:
			count += 1
	return count


func is_asking() -> bool:
	return _asking


func _on_tick() -> void:
	refresh()


func _ask(now: float) -> void:
	_asking = true
	_last_ask = now
	_asked.append(now)
	while not _asked.is_empty() and now - _asked[0] >= WINDOW:
		_asked.pop_front()
	if state != State.LOADED:
		state = State.LOADING
		loading.emit()
	var generation := _generation
	var answer := await _api.list_nights()
	_asking = false
	if generation != _generation or not running:
		return
	if answer["ok"]:
		state = State.LOADED
		entries = NightEntry.parse(answer)
		total = int(answer.get("total", entries.size()))
		updated.emit(entries, total)
		return
	if str(answer.get("error", "")) == "too_many_requests":
		var wait := float(answer.get("retry_after", 0.0))
		_held_until = _now() + (wait if wait > 0.0 else BACKOFF)
		waiting.emit(_held_until - _now())
		return
	state = State.FAILED
	failed.emit(str(answer.get("text", "Something went wrong.")), str(answer.get("error", "")))


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_ticks_msec() / 1000.0
