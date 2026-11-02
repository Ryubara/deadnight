class_name HttpJson
extends RefCounted
## One JSON request over HTTP(S), awaited: what the game server says to the backend (heartbeats) and
## what the game says to it (guest sign-in, rooms). It makes an `HTTPRequest` under `parent`, frees
## it when the answer comes and never throws: a network failure is `status` 0.
##
## `await HttpJson.send(self, "POST", url, {"Authorization": "Bearer ..."}, {"name": "Ann"})` gives
## `{"status": 200, "json": <parsed body, or null>}`.

const TIMEOUT_SECONDS := 10.0


static func send(
	parent: Node, method: String, url: String, headers: Dictionary = {}, body: Variant = null
) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
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
	return {"status": status, "json": parsed}


static func _method(name: String) -> HTTPClient.Method:
	match name:
		"GET":
			return HTTPClient.METHOD_GET
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
	return HTTPClient.METHOD_POST
