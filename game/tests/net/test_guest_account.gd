# A Guest account lasts across visits (#1080). The file the credential is kept in (`GuestAccount`)
# is tested alone; the sign-in path (`TogetherApi.sign_in`) against the real backend
# (`spikes/backend`, run by Node on a free port with memory storage): a first visit makes a
# guest and keeps its credential, a second visit with a new API object (a new page load: no
# session in memory, only the file) is the same account, and a credential the backend does not
# know gets a new guest without losing the file.
#
# The backend half needs Node 24 and the backend's packages (`npm ci` in `spikes/backend`); without
# them those tests are skipped with a line saying so.
extends GdUnitTestSuite

const BACKEND_DIR := "res://../spikes/backend"
const SESSION_SECRET := "session-secret-of-at-least-32-characters-a"
const TICKET_SECRET := "ticket-secret-of-at-least-32-characters-b"
const GAME_SERVER_SECRET := "server-secret-of-at-least-32-characters-c"
const FILE := "user://test_guest_account.json"

var _pid := 0
var _backend := ""


## A backend nobody can reach.
class Offline:
	extends TogetherApi
	var sent: Array = []

	func _call(
		_method: String, _path: String, body: Variant = null, _authorised: bool = true
	) -> Dictionary:
		sent.append(body)
		return TogetherApi._failed("network")


func before_test() -> void:
	_remove_file()


func after_test() -> void:
	_remove_file()
	if _pid != 0:
		OS.kill(_pid)
		_pid = 0
	TogetherApi.forget()


func _remove_file() -> void:
	for path in [FILE, FILE + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# --- The file ---


func test_a_credential_is_kept_for_its_backend_and_read_back() -> void:
	assert_str(GuestAccount.load_credential("https://a.example", FILE)).is_empty()
	assert_bool(GuestAccount.save_credential("https://a.example/", "tok-a", FILE)).is_true()
	assert_bool(GuestAccount.save_credential("https://b.example", "tok-b", FILE)).is_true()
	# The trailing slash does not make another backend; each backend has its own credential.
	assert_str(GuestAccount.load_credential("https://a.example", FILE)).is_equal("tok-a")
	assert_str(GuestAccount.load_credential("https://b.example", FILE)).is_equal("tok-b")
	# A newer credential replaces the older one.
	GuestAccount.save_credential("https://a.example", "tok-a2", FILE)
	assert_str(GuestAccount.load_credential("https://a.example", FILE)).is_equal("tok-a2")
	GuestAccount.forget("https://a.example", FILE)
	assert_str(GuestAccount.load_credential("https://a.example", FILE)).is_empty()
	assert_str(GuestAccount.load_credential("https://b.example", FILE)).is_equal("tok-b")


func test_a_file_that_cannot_be_read_is_no_credential() -> void:
	for text in [
		"", "not json", "[1,2]", '{"accounts": 5}', '{"accounts": {"https://a.example": 7}}'
	]:
		var file := FileAccess.open(FILE, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		assert_str(GuestAccount.load_credential("https://a.example", FILE)).is_empty()
	# And a new credential still goes in over it.
	assert_bool(GuestAccount.save_credential("https://a.example", "tok", FILE)).is_true()
	assert_str(GuestAccount.load_credential("https://a.example", FILE)).is_equal("tok")


func test_a_run_with_no_file_keeps_nothing() -> void:
	(
		assert_bool(GuestAccount.save_credential("https://a.example", "tok", GuestAccount.NO_FILE))
		. is_false()
	)
	assert_str(GuestAccount.load_credential("https://a.example", GuestAccount.NO_FILE)).is_empty()
	# A test run is such a run: no suite touches the file the person plays with.
	assert_str(GuestAccount.default_path()).is_equal(GuestAccount.NO_FILE)
	assert_str(TogetherApi.new(self).guest_path).is_equal(GuestAccount.NO_FILE)


# --- The sign-in path against the real backend ---


func test_a_guest_comes_back_to_its_account_with_the_credential_it_kept(
	_do_skip := _why_not() != "", _skip_reason := "needs node 24 and npm ci in spikes/backend"
) -> void:
	await _start_backend()

	# First visit: a new guest, and its credential is written to the file.
	var first := _visit()
	var signed := await first.sign_in("Ann")
	assert_bool(signed["ok"]).is_true()
	assert_bool(signed["returning"]).is_false()
	var account := first.my_id()
	assert_str(account).is_not_empty()
	var credential := GuestAccount.load_credential(_backend, FILE)
	assert_str(credential).is_not_empty()
	assert_str(credential).is_equal(signed["guestToken"])
	assert_int(int(signed["guestExpiresIn"])).is_equal(7 * 24 * 3600)

	# It writes a save under this account (the `challenges` slot: the backend checks `profile`).
	var wrote: Dictionary = await first.call(
		"_call",
		"PUT",
		"/saves/challenges",
		{"revision": 0, "schemaVersion": 1, "data": {"xp": 120}}
	)
	assert_bool(wrote["ok"]).is_true()

	# Second visit: nothing of the first one is in memory but the file.
	var second := _visit()
	var back := await second.sign_in("")
	assert_bool(back["ok"]).is_true()
	assert_bool(back["returning"]).is_true()
	assert_str(second.my_id()).is_equal(account)
	assert_str(back["user"]["name"]).is_equal("Ann")
	var read: Dictionary = await second.call("_call", "GET", "/saves/challenges")
	assert_bool(read["ok"]).is_true()
	assert_int(int(read["data"]["xp"])).is_equal(120)
	# The credential was renewed and kept.
	assert_str(GuestAccount.load_credential(_backend, FILE)).is_equal(back["guestToken"])

	# A new name given on a visit is the name from then on.
	var third := _visit()
	var renamed := await third.sign_in("Ann Lee")
	assert_str(third.my_id()).is_equal(account)
	assert_str(renamed["user"]["name"]).is_equal("Ann Lee")


func test_a_credential_the_backend_does_not_know_gets_a_new_guest_and_is_replaced(
	_do_skip := _why_not() != "", _skip_reason := "needs node 24 and npm ci in spikes/backend"
) -> void:
	await _start_backend()
	var first := _visit()
	await first.sign_in("Ann")
	var account := first.my_id()

	# A credential from another backend's secret, or damaged, is nobody's: a new guest, never Ann.
	GuestAccount.save_credential(_backend, "aaa.bbb.ccc", FILE)
	var stranger := _visit()
	var signed := await stranger.sign_in("Bo")
	assert_bool(signed["ok"]).is_true()
	assert_bool(signed["returning"]).is_false()
	assert_str(stranger.my_id()).is_not_equal(account)
	# The file now holds the new guest's credential.
	assert_str(GuestAccount.load_credential(_backend, FILE)).is_equal(signed["guestToken"])


func test_a_visit_that_cannot_reach_the_backend_keeps_the_credential() -> void:
	var offline := Offline.new(self, "https://backend.example")
	offline.isolated = true
	offline.guest_path = FILE
	GuestAccount.save_credential(offline.base_url, "kept", FILE)
	var failed := await offline.sign_in("Ann")
	assert_bool(failed["ok"]).is_false()
	assert_str(failed["error"]).is_equal("network")
	# The credential was sent each time the request was tried, and the file is as it was.
	assert_int(offline.sent.size()).is_equal(TogetherApi.SIGN_IN_TRIES)
	for body in offline.sent:
		assert_str(body["guestToken"]).is_equal("kept")
	assert_str(GuestAccount.load_credential(offline.base_url, FILE)).is_equal("kept")


func test_a_discord_activity_keeps_no_guest_credential() -> void:
	# Inside an Activity the player signs in with Discord; a guest fallback there is not kept.
	var api := TogetherApi.new(self, "http://127.0.0.1:1")
	api.guest_path = FILE
	api.instance_id = "activity-1"
	assert_str(api.call("_kept_credential")).is_empty()
	GuestAccount.save_credential(api.base_url, "tok", FILE)
	assert_str(api.call("_kept_credential")).is_empty()
	api.call("_remember", {"guestToken": "other"})
	assert_str(GuestAccount.load_credential(api.base_url, FILE)).is_equal("tok")


# --- The stack ---


## An API that behaves as a new page load: no session in memory, the file the only memory.
func _visit() -> TogetherApi:
	var api := TogetherApi.new(self, _backend)
	api.isolated = true
	api.guest_path = FILE
	return api


static func _backend_path() -> String:
	return ProjectSettings.globalize_path(BACKEND_DIR).simplify_path()


static func _why_not() -> String:
	var out := []
	if OS.execute("node", ["--version"], out) != OK:
		return "no node on this machine"
	var major := str(out[0]).strip_edges().trim_prefix("v").split(".")[0].to_int()
	if major < 24:
		return "node %d is too old (the backend needs 24)" % major
	if not DirAccess.dir_exists_absolute(_backend_path() + "/node_modules/fastify"):
		return "run `npm ci` in spikes/backend first"
	return ""


func _free_port() -> int:
	var probe := TCPServer.new()
	assert_int(probe.listen(0, "127.0.0.1")).is_equal(OK)
	var port := probe.get_local_port()
	probe.stop()
	return port


func _start_backend() -> void:
	var port := _free_port()
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
	_pid = OS.create_process("node", [_backend_path() + "/src/main.ts"])
	for key: String in env:
		OS.unset_environment(key)
	assert_int(_pid).is_greater(0)
	_backend = "http://127.0.0.1:%d" % port
	var began := Time.get_ticks_msec()
	while true:
		var health := await HttpJson.send(self, "GET", _backend + "/health")
		if health["status"] == 200:
			return
		if (Time.get_ticks_msec() - began) / 1000.0 > 90.0:
			fail("the backend did not come up")
			return
		await get_tree().create_timer(0.1).timeout
