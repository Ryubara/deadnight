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
##
## A link that was welcomed and then loses its socket (not by `close()`, and not refused) tries to
## get its seat back: it opens a new socket every `retry_every` seconds for `resume_within` seconds
## and says hello with the resume token. `lost` says it began, `resumed` that the server gave the
## same player back (with the rules' snapshot as they are now; the next frame is whole), and
## `closed` that the time ran out or the server gave the seat to no one.

## The server accepted us: `snapshot` is the rules' state now (`GameRules.to_dict()`).
signal welcomed(snapshot: Dictionary)
signal refused(reason: int)
signal closed
signal lost
## The seat is ours again: `snapshot` is the rules' state now.
signal resumed(snapshot: Dictionary)

## Seconds between pings.
const PING_EVERY := 0.5
## Seconds to keep trying to get the seat back, and between tries (the server holds it for
## `NightHost.RESUME_WITHIN`).
const RESUME_WITHIN := 25.0
const RETRY_EVERY := 1.0
## The close code `drop` ends the socket with (the private range): neither a goodbye nor, for the
## server, a reason to free the seat.
const DROP_CODE := 4000
## A gap between ticks over this many milliseconds is a stall.
const STALL_MS := 100.0

var player_id := 0
var resume_within := RESUME_WITHIN
var retry_every := RETRY_EVERY
## False to give up at once when the socket drops.
var reconnect := true
## True from the socket dropping until the seat is back or given up.
var resuming := false
## What the last WELCOME gave to take the seat back with.
var token := PackedByteArray()
## The platform backend's ticket for this night, said in the hello (empty with no backend).
var ticket := ""
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

## A bad network to put between this client and the server, in each direction (tests and bots).
var conditioner_in: LinkConditioner
var conditioner_out: LinkConditioner

var _ws := WebSocketPeer.new()
var _url := ""
var _active := false
var _closed_by_us := false
var _refused := false
var _lost_at := 0.0
var _next_try := 0.0
var _was_open := false
var _last_tick_usec := 0
var _frame: Dictionary = {}
var _next_ping := 0.0


## Starts connecting; the result is the error of the start, not of the connection.
func connect_to(url: String) -> Error:
	_active = true
	_url = url
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
	_closed_by_us = true
	_ws.close()


## Closes the socket as if the network had gone: unlike `close()`, the link then tries to come
## back. For tests and for a player who asks to reconnect.
func drop() -> void:
	_ws.close(DROP_CODE, "dropped")


## Only commands and the player's look travel from a client; joining and leaving are the
## connection's, and the night starts when the first player arrives.
func send(action: Dictionary) -> void:
	match action.get("type"):
		NightServer.COMMAND:
			_send(NetWire.command(NightCommand.from_dict(action)))
		NightServer.LOOK:
			_send(action["packet"])
		NightServer.PING:
			_send(NetWire.mark(action["kind"], action["pos"], int(action.get("subject", 0))))


func pump() -> void:
	if not _active:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		_send(NetWire.hello(token, ticket))
	# What came before a close is still read: a refusal arrives together with the close.
	while state != WebSocketPeer.STATE_CONNECTING and _ws.get_available_packet_count() > 0:
		var packet := _ws.get_packet()
		if conditioner_in != null:
			conditioner_in.push(packet, _now())
		else:
			_receive(packet)
	if conditioner_in != null:
		for packet in conditioner_in.due(_now()):
			_receive(packet)
	if conditioner_out != null:
		for packet in conditioner_out.due(_now()):
			_put(packet)
	if state == WebSocketPeer.STATE_OPEN:
		_ping_when_due()
	elif state == WebSocketPeer.STATE_CLOSED:
		_on_socket_closed()


## The socket is gone. A link that had a seat tries to take it back; any other is finished.
func _on_socket_closed() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _closed_by_us or _refused:
		resuming = false
		_active = false
		closed.emit()
		return
	if not resuming:
		if not reconnect or not is_welcomed() or token.is_empty():
			_active = false
			closed.emit()
			return
		resuming = true
		_lost_at = now
		_next_try = now
		lost.emit()
	if now - _lost_at > resume_within:
		resuming = false
		_active = false
		closed.emit()
	elif now >= _next_try:
		_next_try = now + retry_every
		_was_open = false
		_ws = WebSocketPeer.new()
		_ws.connect_to_url(_url)


func _send(data: PackedByteArray) -> void:
	if conditioner_out != null:
		conditioner_out.push(data, _now())
	else:
		_put(data)


func _put(data: PackedByteArray) -> void:
	if is_open():
		_ws.send(data, WebSocketPeer.WRITE_MODE_BINARY)
		bytes_out += data.size()


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


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
			if welcome.is_empty():
				return
			if player_id == 0:
				player_id = welcome["player_id"]
				tick_rate = welcome["tick_rate"]
				token = welcome["token"]
				welcomed.emit(welcome["snapshot"])
			elif resuming:
				resuming = false
				if welcome["player_id"] != player_id:
					# The seat was given up: this would be another player, not us.
					close()
					return
				token = welcome["token"]
				# The server begins again from a whole frame.
				_frame = {}
				resumed.emit(welcome["snapshot"])
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
				_refused = true
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
