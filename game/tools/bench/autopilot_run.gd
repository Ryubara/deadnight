class_name AutopilotRun
extends Node
## A night the autopilot plays from the page's address (`?autopilot`) or the command line
## (`--autopilot`), frame times kept for each round, to measure big crowds in a browser (#171).
## The game starts it instead of the menu, like `KillBench`. The bot plays from its shoulder camera
## under the shipped rules with a player who cannot die, so the night goes on while the crowd
## grows; the shop, the doors and the generator are the bot's, as in play.
##
## Arguments (`?autopilot&count=3&alive=40`, or `-- --autopilot --count=3`):
##   `rounds=N`   stop once round N has started and been played for `hold` seconds (default 5)
##   `hold=S`     seconds the last round is played (default 20)
##   `count=X`    the match setting's count multiplier (X times as many dead, as fast)
##   `alive=N`    the match setting's most alive at once (0 is the tuned curve)
##   `tough=X`    the dead have X times the health: the bot cannot clear them, so the crowd grows to
##                the cap and stands there (a big crowd without waiting for round 20; default 1)
##   `crowd=N`    the first round brings N zombies (the tuned 6 otherwise); with `tough`, a crowd
##                that stands at once
##   `break=S`    seconds of break between rounds (0 is the tuned break)
##   `bots=N`     N hosted bots beside the autopilot (a night of N + 1 players; default 0)
##   `startround=R` the night starts at round R (the rules' round counter is set to R - 1 before the
##                first round), with `points=P` points for every player (default 20000 once
##                `startround` is given) so the bots have bought what a late round has
##   `ceiling=desktop` the bots say they are not browsers, so the desktop's 120 dead may stand (they
##                count as browsers otherwise: the ceiling is 40)
##   `frames=0`   keep no row per frame (a long run's memory is what it measures)
##   `labels=0`   with `sample=1`, rows without the labelled times and counts (a long run)
##   `sample=1`   a `PerfSampler` row each second (monitors, counts, labelled times) in the report
##   `xp=1`       every player (the bots too: only here) holds an account, so the night awards XP
##                as a game server would and the XP's counts and time are in the rows
##                (`xp.gained`, `server.xp`; tools/perf/budget.json holds them)
##   `signin=1`   sign in as a guest first (`?backend=` names the backend), so the night is a
##                signed-in solo night: its XP is kept in the profile and sent to the account
##   `map=ID`     the map of the night (`MapRegistry`: `drive_in`, `small_indoor`; default the lot)
##   `seconds=S`  stop after S seconds of night whatever round it is (default 600)
##   `out=PATH`   on a desktop: write the report there and quit
## The report is `window.deadnightRounds` (JSON text) in a browser, and a `AUTOPILOT_RUN` line on a
## desktop: for each round the frames, the frame's mean, median, 95th and 99th percentile and
## worst (ms), the worst second (the mean frame time of the worst 1 s of frames), the most and the
## mean zombies on the lot and the seconds played; and the same by the crowd on the lot (0 to 9, 10
## to 19, 20 to 29, 30 to 39, 40 and over). Recorded, never gated. Not part of the play.

const KEY := "autopilot"
const NIGHT := "res://ui/screens/night_screen.tscn"
const DEFAULT_ROUNDS := 5
const DEFAULT_HOLD := 20.0
const DEFAULT_SECONDS := 600.0
const PLAYER_HEALTH := 1.0e6
## A "second" of the worst-second measure, in milliseconds of frame time.
const SECOND_MS := 1000.0
## Frames longer than this are a visible hitch at 60 Hz (two frames).
const HITCH_MS := 33.4
## The crowd buckets of the second summary: zombies on the lot from each of these up to the next.
const BUCKETS: Array[int] = [0, 10, 20, 30, 40, 80, 120]

var _args: NetArgs
var _rounds := DEFAULT_ROUNDS
var _hold := DEFAULT_HOLD
var _cap_seconds := DEFAULT_SECONDS
var _out := ""
## One row per frame of a running night: [frame ms, round, zombies on the lot].
var _rows: Array[Array] = []
var _played := 0.0
var _reached_at := -1.0
var _done := false
var _ablated := false
var _sampler: PerfSampler
var _jumped := false
var _hud_probed := false
var _accounts: Dictionary[int, bool] = {}
## False for a long run (`frames=0`): the per-frame rows would be the growth being measured.
var _keep_frames := true


func _init(args: NetArgs = null) -> void:
	_args = args if args != null else NetArgs.new()


## Whether this run asked for it.
static func requested(args: NetArgs = null) -> bool:
	return (args if args != null else NetArgs.new()).has(KEY)


func _ready() -> void:
	_rounds = _args.get_int("rounds", DEFAULT_ROUNDS)
	_hold = _args.get_float("hold", DEFAULT_HOLD)
	_cap_seconds = _args.get_float("seconds", DEFAULT_SECONDS)
	_out = _args.get_string("out")
	_keep_frames = _args.get_int("frames", 1) != 0
	LotBatcher.enabled = _args.get_string("batch", "1") != "0"
	LotBatcher.keep_sources = _args.get_string("batch") == "toggle"
	LotBatcher.small_range = _args.get_float("smallrange", 0.0)
	NightScreen.match_settings = settings_from(_args)
	NightScreen.start_mode = Night.Mode.AUTOPILOT
	NightScreen.start_seed = Night.SEED
	NightScreen.start_tuning = tuning(_args)
	NightScreen.shoulder_camera = true
	if _args.get_int("signin") == 1:
		# A guest account first, so the night keeps its XP in the profile and sends it to the backend.
		await TogetherApi.new(self, TogetherScreen.backend_url()).sign_in("Autopilot")
	UIRouter.reset(NIGHT, UITransition.Kind.CUT)


func _process(delta: float) -> void:
	var night := _night()
	if _done or night == null or not night.running or night.state == null:
		return
	if not _ablated:
		_ablated = true
		BenchAblation.apply(_args, night, UIRouter.top())
		if _args.get_int("sample") == 1:
			_sampler = PerfSampler.new()
			_sampler.night_state = _state_of_night
			_sampler.keep_labels = _args.get_int("labels", 1) != 0
			add_child(_sampler)
	if not _jumped:
		_jumped = true
		_start_at_round(night)
	if _args.get_int("hudprobe") == 1 and not _hud_probed and night.state.zombies.size() >= 60:
		_hud_probed = true
		_probe_hud(UIRouter.top())
	if _args.get_int("xp") == 1:
		_register_accounts(night)
	_played += delta
	if _keep_frames:
		_rows.append([delta * 1000.0, night.state.round_number(), night.state.zombies.size()])
	if night.state.round_number() >= _rounds and _reached_at < 0.0:
		_reached_at = _played
	if (
		night.state.over
		or _played >= _cap_seconds
		or (_reached_at >= 0.0 and _played - _reached_at >= _hold)
	):
		_done = true
		_publish(night)


## The shipped rules with a player who does not die, so the night outlasts the crowd's growth.
static func tuning(args: NetArgs = null) -> RulesTuning:
	var rules: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	rules.health.max_health = PLAYER_HEALTH
	if args != null:
		rules.rounds.health_base *= maxf(args.get_float("tough", 1.0), 0.01)
		if args.has("crowd"):
			rules.rounds.count_base = args.get_float("crowd")
	return rules


## The match settings the arguments ask for (`count`, `alive`, `break`), pulled into their bounds.
static func settings_from(args: NetArgs) -> MatchSettings:
	var settings := MatchSettings.new()
	settings.bots = args.get_int("bots", settings.bots)
	settings.count_multiplier = args.get_float("count", 1.0)
	settings.max_alive = args.get_int("alive", MatchSettings.AUTO)
	settings.break_seconds = args.get_float("break", 0.0)
	settings.map = args.get_string("map", settings.map)
	return settings.clamped()


## What the rows of a run say, for each round (in order): `rows` are [frame ms, round, zombies].
static func summarize(rows: Array) -> Array[Dictionary]:
	var by_round: Dictionary = {}
	for row: Array in rows:
		(by_round.get_or_add(int(row[1]), []) as Array).append(row)
	var rounds: Array = by_round.keys()
	rounds.sort()
	var out: Array[Dictionary] = []
	for round_number: int in rounds:
		out.append(_round_report(round_number, by_round[round_number]))
	return out


## What the rows say by the crowd on the lot: for each bucket of `BUCKETS` that has frames.
static func summarize_by_alive(rows: Array) -> Array[Dictionary]:
	var by_bucket: Dictionary = {}
	for row: Array in rows:
		var bucket := 0
		for edge in BUCKETS:
			if int(row[2]) >= edge:
				bucket = edge
		(by_bucket.get_or_add(bucket, []) as Array).append(row)
	var edges: Array = by_bucket.keys()
	edges.sort()
	var out: Array[Dictionary] = []
	for edge: int in edges:
		var report := _round_report(0, by_bucket[edge])
		report.erase("round")
		report["alive_from"] = edge
		out.append(report)
	return out


static func _round_report(round_number: int, rows: Array) -> Dictionary:
	var frames: Array[float] = []
	var total := 0.0
	var alive_sum := 0.0
	var alive_peak := 0
	var hitches := 0
	for row: Array in rows:
		var ms: float = row[0]
		frames.append(ms)
		total += ms
		alive_sum += float(row[2])
		alive_peak = maxi(alive_peak, int(row[2]))
		if ms > HITCH_MS:
			hitches += 1
	var sorted := frames.duplicate()
	sorted.sort()
	return {
		"round": round_number,
		"frames": frames.size(),
		"seconds": snappedf(total / 1000.0, 0.1),
		"mean_ms": snappedf(total / maxf(frames.size(), 1.0), 0.01),
		"p50_ms": snappedf(_percentile(sorted, 0.5), 0.01),
		"p95_ms": snappedf(_percentile(sorted, 0.95), 0.01),
		"p99_ms": snappedf(_percentile(sorted, 0.99), 0.01),
		"max_ms": snappedf(sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0, 0.01),
		"worst_second_ms": snappedf(worst_second(frames), 0.01),
		"frames_over_33ms": hitches,
		"alive_peak": alive_peak,
		"alive_mean": snappedf(alive_sum / maxf(frames.size(), 1.0), 0.1),
	}


## The mean frame time (ms) of the worst second: frames are cut into runs of at least a second of
## frame time, and the run whose mean is highest is the worst. A round shorter than a second is one
## run.
static func worst_second(frames: Array[float]) -> float:
	var worst := 0.0
	var run_total := 0.0
	var run_frames := 0
	for ms in frames:
		run_total += ms
		run_frames += 1
		if run_total >= SECOND_MS:
			worst = maxf(worst, run_total / run_frames)
			run_total = 0.0
			run_frames = 0
	if run_frames > 0 and worst == 0.0:
		worst = run_total / run_frames
	return worst


static func _percentile(sorted: Array, share: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[mini(int(sorted.size() * share), sorted.size() - 1)]


## Puts the night at the round `startround` asks for (the counter is set before the first round
## begins, so round R is the first one played) and gives every player `points`.
func _start_at_round(night: Night) -> void:
	var rules := night.server.rules
	if _args.get_string("ceiling") == "desktop":
		# The bots count as browsers (`NightServer._join`): a desktop crowd needs them to say not.
		for id: int in rules.players:
			night.server.crowd.set_platform(id, false)
	if not _args.has("startround"):
		return
	rules.round_number = maxi(_args.get_int("startround") - 1, 0)
	var points := _args.get_int("points", 20000)
	for id: int in rules.players:
		(rules.players[id] as PlayerState).points = points


## Gives every player of the night an account the moment they sit down (`xp=1`).
func _register_accounts(night: Night) -> void:
	var rules := night.server.rules
	for id: int in rules.players:
		if not _accounts.has(id):
			_accounts[id] = true
			night.server.xp.register(id, "bench-%d" % id, 300, rules.round_number)


## Draw calls of the frame with each part of the HUD hidden in turn (`hudprobe=1`), printed as
## `HUDPROBE {json}`: what each part costs in draws, read once the crowd stands.
func _probe_hud(screen: Control) -> void:
	var hud: Node = null
	for child in screen.get_children():
		if child is Hud:
			hud = child
	if hud == null:
		return
	var report := {"all": await _draws()}
	for part in hud.get_children():
		if not (part is CanvasItem) or not (part as CanvasItem).visible:
			continue
		(part as CanvasItem).visible = false
		report[str(part.name)] = await _draws()
		(part as CanvasItem).visible = true
	print("HUDPROBE ", JSON.stringify(report))


## The mean draw calls over five frames.
func _draws() -> int:
	for _i in 3:
		await get_tree().process_frame
	var total := 0
	for _i in 5:
		await get_tree().process_frame
		total += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return total / 5


func _state_of_night() -> Dictionary:
	var night := _night()
	if night == null or night.state == null:
		return {}
	var rules := night.server.rules
	return {
		"round": night.state.round_number(),
		"alive": night.state.zombies.size(),
		"cap":
		rules.settings.alive_cap(
			rules.tuning.rounds,
			rules.round_number,
			rules.get("_round_players"),
			rules.crowd_ceiling
		),
		"players": rules.players.size(),
		"count_multiplier": rules.settings.count_multiplier,
	}


func _night() -> Night:
	var screen := UIRouter.top() as NightScreen
	return screen.night if screen != null else null


func _publish(night: Night) -> void:
	var report := {
		"rounds": summarize(_rows),
		"by_alive": summarize_by_alive(_rows),
		"kills": night.state.kills,
		"round_reached": night.state.round_number(),
		"seconds": snappedf(_played, 0.1),
		"count": _args.get_float("count", 1.0),
		"alive_asked": _args.get_int("alive", MatchSettings.AUTO),
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"debug_build": OS.is_debug_build(),
		"cores": OS.get_processor_count(),
	}
	if _sampler != null:
		report["samples"] = _sampler.rows
	var json := JSON.stringify(report)
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").deadnightRounds = json
		return
	if _sampler != null:
		report.erase("samples")
	print("AUTOPILOT_RUN ", JSON.stringify(report))
	if _out != "":
		var file := FileAccess.open(_out, FileAccess.WRITE)
		file.store_string(json)
		file.close()
		get_tree().quit()
