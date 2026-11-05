class_name HttpJson
extends RefCounted
## One JSON request over HTTP(S), awaited: what the game server says to the backend (heartbeats) and
## what the game says to it (guest sign-in, rooms). It makes an `HTTPRequest` under `parent`, frees
## it when the answer comes and never throws: a network failure is `status` 0.
##
## `await HttpJson.send(self, "POST", url, {"Authorization": "Bearer ..."}, {"name": "Ann"})` gives
## `{"status": 200, "json": <parsed body, or null>, "retry_after": 0.0}`; `retry_after` is the
## seconds a
## `Retry-After` header asked the caller to wait (0 when there is none).

const TIMEOUT_SECONDS := 10.0

## For a test: `Callable(method, url, headers, body) -> Dictionary` answers a request instead of the
## network (`{"status", "json"}`); an empty one lets the request go out as usual.
static var responder := Callable()


static func send(
	parent: Node,
	method: String,
	url: String,
	headers: Dictionary = {},
	body: Variant = null,
	timeout: float = TIMEOUT_SECONDS
) -> Dictionary:
	if responder.is_valid():
		var canned: Dictionary = responder.call(method, url, headers, body)
		if not canned.is_empty():
			return canned
	var http := HTTPRequest.new()
	http.timeout = timeout
	# The browser decodes gzip itself, but the answer still names `Content-Encoding: gzip` and Godot
	# would decode it a second time and fail (Discord's proxy compresses the backend's answers).
	http.accept_gzip = false
	parent.add_child(http)
	var lines := PackedStringArray()
	for key: String in headers:
		lines.append("%s: %s" % [key, headers[key]])
	var payload := ""
	if body != null:
		lines.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	var started := http.request(url, lines, _method(method), payload)
	if started != OK:
		http.queue_free()
		return {"status": 0, "json": null}
	var answer: Array = await http.request_completed
	http.queue_free()
	var text := (answer[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	# A transport failure (the result is not RESULT_SUCCESS) has no status worth reading.
	var status: int = answer[1] if answer[0] == HTTPRequest.RESULT_SUCCESS else 0
	return {"status": status, "json": parsed, "retry_after": _retry_after(answer[2])}


## The seconds a `Retry-After: N` header names, or 0.
static func _retry_after(headers: PackedStringArray) -> float:
	for line in headers:
		if line.to_lower().begins_with("retry-after:"):
			var value := line.substr(line.find(":") + 1).strip_edges()
			return maxf(0.0, value.to_float()) if value.is_valid_float() else 0.0
	return 0.0


static func _method(name: String) -> HTTPClient.Method:
	match name:
		"GET":
			return HTTPClient.METHOD_GET
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
	return HTTPClient.METHOD_POST
