class_name WebSocketLink
extends GameLink
## The client's link to a game server (`NetWire`), the same interface `LoopbackLink` has: `send` a
## `NightCommand.to_dict()`, `pump` once per tick, hear the server through `delivered`. It works the
## same on desktop and in the web build.
##
## After `connect_to(url)` it says hello when the socket opens; `welcomed` follows the server's
## WELCOME (with the player id and the rules' snapshot), then ticks arrive as `delivered` events
## with the frame whole (a delta is put together with `FrameDelta`). The look packets for this
## player come in those events (`look_packet`), as over the loopback. `refused` or `closed` say why
## the link is no more.

## The server accepted us: `snapshot` is the rules' state now (`GameRules.to_dict()`).
signal welcomed(snapshot: Dictionary)
signal refused(reason: int)
signal closed

## Seconds between pings.
const PING_EVERY := 0.5
## A gap between ticks over this many milliseconds is a stall.
const STALL_MS := 100.0

var player_id := 0
var tick_rate := 60

# The numbers of this connection.
var bytes_in := 0
var bytes_out := 0
var ticks_in := 0
var frame_bytes_in := 0
var frames_in := 0
var rtt_ms := -1.0
var rtt_samples: Array[float] = []
## The server step of the newest tick heard.
var server_step := 0
## Milliseconds between one TICK arriving and the next (30 a second is 33.3), since `take_stats`.
var tick_gaps_ms: Array[float] = []
## The protocol version a server that turned us away speaks (0 until one has).
var server_version := 0

var _ws := WebSocketPeer.new()
var _active := false
var _was_open := false
var _last_tick_usec := 0
var _frame: Dictionary = {}
var _next_ping := 0.0


## Starts connecting; the result is the error of the start, not of the connection.
func connect_to(url: String) -> Error:
	_active = true
	return _ws.connect_to_url(url)


func is_open() -> bool:
	return _active and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


## The round trips (ping and pong) and the gaps between ticks since the last call, each as
## `{n, mean, p95, max}` in milliseconds; the gaps also say how many were `stalls` (over 100 ms,
## three ticks late). Clears them.
func take_stats() -> Dictionary:
	var out := {"rtt": _summary(rtt_samples), "gaps": _summary(tick_gaps_ms)}
	var stalls := 0
	for gap in tick_gaps_ms:
		if gap > STALL_MS:
			stalls += 1
	out["gaps"]["stalls"] = stalls
	rtt_samples.clear()
	tick_gaps_ms.clear()
	return out


static func _summary(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"n": 0, "mean": 0.0, "p95": 0.0, "max": 0.0}
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {
		"n": sorted.size(),
		"mean": snappedf(total / sorted.size(), 0.1),
		"p95": snappedf(sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)], 0.1),
		"max": snappedf(sorted[-1], 0.1),
	}


func is_welcomed() -> bool:
	return player_id > 0


func close() -> void:
	_ws.close()


## Only commands and the player's look travel from a client; joining and leaving are the
## connection's, and the night starts when the first player arrives.
func send(action: Dictionary) -> void:
	match action.get("type"):
		NightServer.COMMAND:
			_send(NetWire.command(NightCommand.from_dict(action)))
		NightServer.LOOK:
			_send(action["packet"])


func pump() -> void:
	if not _active:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		_send(NetWire.hello())
	# What came before a close is still read: a refusal arrives together with the close.
	while state != WebSocketPeer.STATE_CONNECTING and _ws.get_available_packet_count() > 0:
		_receive(_ws.get_packet())
	if state == WebSocketPeer.STATE_OPEN:
		_ping_when_due()
	elif state == WebSocketPeer.STATE_CLOSED:
		_active = false
		closed.emit()


func _send(data: PackedByteArray) -> void:
	if is_open():
		_ws.send(data, WebSocketPeer.WRITE_MODE_BINARY)
		bytes_out += data.size()


func _ping_when_due() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_ping:
		_next_ping = now + PING_EVERY
		_send(NetWire.ping(Time.get_ticks_msec()))


func _receive(data: PackedByteArray) -> void:
	bytes_in += data.size()
	if data.is_empty():
		return
	match data[0]:
		NetWire.Type.WELCOME:
			var welcome := NetWire.read_welcome(data)
			if not welcome.is_empty() and player_id == 0:
				player_id = welcome["player_id"]
				tick_rate = welcome["tick_rate"]
				welcomed.emit(welcome["snapshot"])
		NetWire.Type.TICK:
			_on_tick(data)
		NetWire.Type.PONG:
			if data.size() == 9:
				rtt_ms = float(Time.get_ticks_msec() - data.decode_u32(1))
				rtt_samples.append(rtt_ms)
		NetWire.Type.REFUSED:
			if data.size() >= 2:
				if data.size() >= 3:
					server_version = data[2]
				refused.emit(data[1])
				close()


func _on_tick(data: PackedByteArray) -> void:
	var tick := NetWire.read_tick(data)
	if tick.is_empty():
		return
	var now := Time.get_ticks_usec()
	if _last_tick_usec > 0:
		tick_gaps_ms.append((now - _last_tick_usec) / 1000.0)
	_last_tick_usec = now
	ticks_in += 1
	server_step = tick["step"]
	var events: Array = tick["events"]
	if not events.is_empty():
		var last: Variant = events[events.size() - 1]
		if last is Dictionary and last.get("type") == &"frame":
			frames_in += 1
			frame_bytes_in += data.size()
			_frame = FrameDelta.apply(_frame, last)
			events[events.size() - 1] = _frame
	delivered.emit(events)
