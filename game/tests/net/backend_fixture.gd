class_name BackendFixture
extends RefCounted
## The real platform backend (`spikes/backend`) run by Node on a free port with memory storage, for
## a suite that tests what the game says to it. Needs Node 24 and the backend's packages
## (`npm ci` in `spikes/backend`): `why_not` says what is missing, and a test that skips on it
## reads `0 skipped` only where both are there.
##
## `await fixture.start(self)` in the test, `fixture.stop()` in `after_test`.

const BACKEND_DIR := "res://../spikes/backend"
const SESSION_SECRET := "session-secret-of-at-least-32-characters-a"
const TICKET_SECRET := "ticket-secret-of-at-least-32-characters-b"
const GAME_SERVER_SECRET := "server-secret-of-at-least-32-characters-c"
const COME_UP_SECONDS := 90.0

## The address once started.
var url := ""

var _pid := 0


static func backend_path() -> String:
	return ProjectSettings.globalize_path(BACKEND_DIR).simplify_path()


## What stops the backend from running here, or "".
static func why_not() -> String:
	var out := []
	if OS.execute("node", ["--version"], out) != OK:
		return "no node on this machine"
	var major := str(out[0]).strip_edges().trim_prefix("v").split(".")[0].to_int()
	if major < 24:
		return "node %d is too old (the backend needs 24)" % major
	if not DirAccess.dir_exists_absolute(backend_path() + "/node_modules/fastify"):
		return "run `npm ci` in spikes/backend first"
	return ""


## Starts it and waits until it answers `/health`; false when it did not come up.
func start(parent: Node) -> bool:
	var probe := TCPServer.new()
	if probe.listen(0, "127.0.0.1") != OK:
		return false
	var port := probe.get_local_port()
	probe.stop()
	var env := {
		"HOST": "127.0.0.1",
		"PORT": str(port),
		"DISCORD_MODE": "off",
		"GUEST_SIGN_IN": "1",
		"NODE_ENV": "test",
		"LOG_LEVEL": "warn",
		"SESSION_SECRET": SESSION_SECRET,
		"TICKET_SECRET": TICKET_SECRET,
		"GAME_SERVER_SECRET": GAME_SERVER_SECRET,
	}
	for key: String in env:
		OS.set_environment(key, env[key])
	_pid = OS.create_process("node", [backend_path() + "/src/main.ts"])
	for key: String in env:
		OS.unset_environment(key)
	if _pid <= 0:
		return false
	url = "http://127.0.0.1:%d" % port
	var began := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - began) / 1000.0 < COME_UP_SECONDS:
		var health := await HttpJson.send(parent, "GET", url + "/health")
		if health["status"] == 200:
			return true
		await parent.get_tree().create_timer(0.1).timeout
	return false


## Stops it (by its process id).
func stop() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = 0
