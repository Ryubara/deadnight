class_name GameClient
extends Node
## The client: sends one input per tick, predicts its own capsule by running the shared movement
## immediately, and corrects (reconciles) when a snapshot says where the server really put it.
## Other players are shown about 100 ms in the past, interpolated between snapshots.

const INTERP_TICKS_DEFAULT := 3.0  # 100 ms at 30 Hz
const SNAP_DISTANCE_TICKS := 6.0
const PING_EVERY_TICKS := 15
const REPORT_EVERY_TICKS := GameSim.TICK_RATE * 2
const SAMPLE_LIMIT := 16
const HISTORY_LIMIT := 64

var input_redundancy := 1
var interp_ticks := INTERP_TICKS_DEFAULT

var _transport: ClientTransport
var _conditioned: ConditionedTransport
var _view: WorldView
var _sampler: InputSampler
var _player_id := 0
var _tick := 0
var _seq := 0
var _welcomed := false
var _playing := false
var _predicted := Vector2i.ZERO
var _pending: Array[Array] = []  # [seq, dir] sent but not yet acknowledged
var _inputs_sent: Array[Vector2i] = []
var _history: Dictionary[int, Dictionary] = {}
var _latest_tick := 0
var _render_tick := 0.0
var _remotes: Dictionary[int, Array] = {}  # id -> [[tick, Vector2 metres], ...]
var _pings: Dictionary[int, bool] = {}
var _stats := ClientStats.new()


func start(transport: ClientTransport, url: String, view: WorldView, sampler: InputSampler) -> void:
	_transport = transport
	_conditioned = transport as ConditionedTransport
	_view = view
	_sampler = sampler
	transport.connected.connect(_on_connected)
	transport.disconnected.connect(func() -> void: print("[client] disconnected"))
	transport.packet_received.connect(_on_packet)
	var error := transport.connect_to(url)
	if error != OK:
		push_error("client could not connect to %s: %s" % [url, error_string(error)])
		get_tree().quit(1)
		return
	print("[client] connecting to %s" % url)


func status_text() -> String:
	if not _playing:
		return "connecting..."
	return (
		"player %d   rtt %.0f ms   up %.0f B/s   down %.0f B/s   corrections %.1f cm avg\n%s"
		% [
			_player_id,
			_stats.rtt_average_ms(),
			_stats.up_rate(),
			_stats.down_rate(),
			_stats.correction_average_cm(),
			"WASD / arrows to move",
		]
	)


func final_report() -> String:
	return _stats.summary(_player_id)


func _physics_process(delta: float) -> void:
	if _transport == null:
		return
	if _conditioned:
		_conditioned.advance(delta)
	_tick += 1
	_transport.poll()
	if _playing:
		_send_input()
	if _welcomed and _tick % PING_EVERY_TICKS == 0:
		_pings[_tick] = true
		_send(Protocol.ping(_tick))
	if _tick % REPORT_EVERY_TICKS == 0:
		print(_report_line())
		_stats.roll_window()


func _exit_tree() -> void:
	if _transport:
		_transport.close()


func _process(delta: float) -> void:
	if not _playing:
		return
	_render_tick += delta * GameSim.TICK_RATE
	_view.show_local(_player_id, _predicted)
	for id in _remotes:
		_view.show_remote(id, _sample_remote(_remotes[id]))


func _on_connected() -> void:
	_send(Protocol.hello())


func _on_packet(data: PackedByteArray) -> void:
	_stats.bytes_down += data.size()
	var message := Protocol.decode(data)
	if message.is_empty():
		return
	match message["type"]:
		Protocol.Type.WELCOME:
			_player_id = message["player_id"]
			_welcomed = true
			print("[client] welcome: player %d, tick %d Hz" % [_player_id, message["tick_rate"]])
		Protocol.Type.SNAPSHOT:
			_on_snapshot(message)
		Protocol.Type.EVENT:
			if message["kind"] == Protocol.EventKind.LEFT:
				_forget(message["player_id"])
		Protocol.Type.PONG:
			if _pings.erase(message["client_tick"]):
				_stats.add_rtt_ticks(_tick - message["client_tick"])


func _send_input() -> void:
	_seq += 1
	var dir := _sampler.sample()
	_pending.append([_seq, dir])
	_predicted = GameSim.integrate(_predicted, dir)
	_inputs_sent.append(dir)
	while _inputs_sent.size() > input_redundancy:
		_inputs_sent.pop_front()
	_send(Protocol.input(_latest_tick, _seq - _inputs_sent.size() + 1, _inputs_sent))


func _on_snapshot(message: Dictionary) -> void:
	var tick: int = message["tick"]
	if tick <= _latest_tick:
		return  # stale or reordered
	var state := _decode_state(message)
	if state.is_empty() and message["baseline_tick"] != 0:
		return  # a delta against a snapshot we no longer have: wait for a full one
	_stats.snapshots += 1
	_history[tick] = state
	for old in _history.keys():
		if old < tick - HISTORY_LIMIT:
			_history.erase(old)
	_latest_tick = tick
	_sync_render_clock(tick)
	_reconcile(state, message["ack_seq"])
	_collect_remote_samples(tick, state, message["baseline_tick"] == 0)


func _decode_state(message: Dictionary) -> Dictionary[int, Vector2i]:
	var entries: Dictionary[int, Vector2i] = message["entries"]
	if message["baseline_tick"] == 0:
		return entries
	var base: Dictionary = _history.get(message["baseline_tick"], {})
	var state: Dictionary[int, Vector2i] = {}
	state.assign(base)
	for id in entries:
		state[id] = state.get(id, Vector2i.ZERO) + entries[id]
	return state


func _reconcile(state: Dictionary[int, Vector2i], ack_seq: int) -> void:
	if not state.has(_player_id):
		return
	var authoritative := state[_player_id]
	_view.show_ghost(authoritative)
	if not _playing:
		_playing = true
		_predicted = authoritative
		return
	while not _pending.is_empty() and _pending[0][0] <= ack_seq:
		_pending.pop_front()
	var replayed := authoritative
	for item in _pending:
		replayed = GameSim.integrate(replayed, item[1])
	_stats.add_correction_cm(Vector2(replayed - _predicted).length())
	_stats.pending_total += _pending.size()
	_predicted = replayed


func _collect_remote_samples(tick: int, state: Dictionary[int, Vector2i], is_full: bool) -> void:
	for id in state:
		if id == _player_id:
			continue
		var samples: Array = _remotes.get(id, [])
		samples.append([tick, Vector2(state[id])])
		while samples.size() > SAMPLE_LIMIT:
			samples.pop_front()
		_remotes[id] = samples
	if is_full:
		for id in _remotes.keys():
			if not state.has(id):
				_forget(id)


func _sync_render_clock(tick: int) -> void:
	var target := float(tick) - interp_ticks
	if _render_tick == 0.0 or absf(target - _render_tick) > SNAP_DISTANCE_TICKS:
		_render_tick = target
	else:
		_render_tick = lerpf(_render_tick, target, 0.1)


func _sample_remote(samples: Array) -> Vector2:
	if samples.is_empty():
		return Vector2.ZERO
	for i in range(samples.size() - 1, 0, -1):
		var a: Array = samples[i - 1]
		var b: Array = samples[i]
		if _render_tick >= a[0] and _render_tick <= b[0]:
			return a[1].lerp(b[1], (_render_tick - a[0]) / float(b[0] - a[0]))
	var last: Array = samples.back()
	var first: Array = samples.front()
	return last[1] if _render_tick > last[0] else first[1]


func _forget(id: int) -> void:
	_remotes.erase(id)
	_view.remove_avatar(id)


func _send(data: PackedByteArray) -> void:
	_stats.bytes_up += data.size()
	_transport.send(data)


func _report_line() -> String:
	var parts: PackedStringArray = []
	var state: Dictionary = _history.get(_latest_tick, {})
	var ids := state.keys()
	ids.sort()
	for id in ids:
		parts.append("%d=(%.2f,%.2f)" % [id, state[id].x / 100.0, state[id].y / 100.0])
	return (
		"[client %d] %s | auth %s | predicted=(%.2f,%.2f)"
		% [
			_player_id,
			_stats.window_line(),
			" ".join(parts),
			_predicted.x / 100.0,
			_predicted.y / 100.0
		]
	)
