extends GdUnitTestSuite
## A signed-in solo night's XP on its way to the account's `profile` slot (`ProfileUplink`), against
## the real backend (`spikes/backend`, run by Node on a free port with memory storage; see
## `BackendFixture`): a round's end sends one write of what the night added, on the account's own
## latest profile; a stale revision (409) is read again and sent on the new latest; a write that
## rises too fast (422) stays queued; a night with no account sends nothing; and the profile read
## at sign-in is the account's, not a file's.

const DIR := "user://test_profile_uplink/"
const DAY := 20401
const WAIT_SECONDS := 20.0
const NEEDS := "needs node 24 and npm ci in spikes/backend"
const OPENED := {"xp": 50, "equipped": {}, "done": ["a"], "opening_night": true, "bonus_day": -1}

var _backend: BackendFixture
var _account := true
var _state: ClientState
var _uplink: ProfileUplink


## An API that lets another writer go first, once, between the profile it read and the write it
## sends: the stale revision a second device (or a game server's report) makes.
class Racing:
	extends TogetherApi
	var rival: TogetherApi
	var raced := false
	var reads := 0
	var writes := 0

	func read_save(slot: String) -> Dictionary:
		reads += 1
		return await super.read_save(slot)

	func write_save(
		slot: String, revision: int, schema_version: int, data: Dictionary
	) -> Dictionary:
		writes += 1
		if not raced:
			raced = true
			var latest := await rival.read_save(slot)
			var theirs := Profile.from_dict(latest["data"]).to_dict()
			theirs["done"] = ["from_the_rival"]
			await rival.write_save(slot, int(latest["revision"]), schema_version, theirs)
		return await super.write_save(slot, revision, schema_version, data)


## A backend that takes everything and counts: for the number of writes a night makes.
class Fake:
	extends TogetherApi
	var reads := 0
	var writes: Array[Dictionary] = []
	var revision := 0
	var data := {}

	func my_id() -> String:
		return "fake-account"

	func read_save(_slot: String) -> Dictionary:
		reads += 1
		return {
			"ok": true,
			"found": revision > 0,
			"revision": revision,
			"schema_version": 1 if revision > 0 else 0,
			"data": data,
		}

	func write_save(
		_slot: String, _revision: int, _schema_version: int, p_data: Dictionary
	) -> Dictionary:
		writes.append(p_data)
		revision += 1
		data = p_data
		return {"ok": true, "revision": revision, "schemaVersion": 1, "data": p_data}


func before_test() -> void:
	_account = true
	DirAccess.make_dir_recursive_absolute(DIR)
	_clear_files()


func after_test() -> void:
	if _backend != null:
		_backend.stop()
		_backend = null
	TogetherApi.forget()
	ProfileUplink.sync_path = ""
	_clear_files()


func _clear_files() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)


func _store(name: String, with_account: bool = true) -> ProfileStore:
	_account = with_account
	var store := ProfileStore.open(DIR + name + ".json", func() -> bool: return _account)
	store.seed_ids(5)
	return store


func _start_backend() -> void:
	_backend = BackendFixture.new()
	assert_bool(await _backend.start(self)).is_true()


## A signed-in guest of its own (a second player of the process), on `kind`.
func _guest(name: String, kind: Script = TogetherApi) -> TogetherApi:
	var api: TogetherApi = kind.new(self, _backend.url)
	api.isolated = true
	var signed := await api.sign_in(name)
	assert_bool(signed["ok"]).is_true()
	return api


func _held(api: TogetherApi) -> Dictionary:
	var read := await api.read_save(ProfileUplink.SLOT)
	assert_bool(read["ok"]).is_true()
	return read


## A session of one player, its uploader the uplink's.
func _session(store: ProfileStore, api: TogetherApi, day: int = DAY) -> ProgressSession:
	_state = ClientState.new()
	var session := ProgressSession.new(store, ChallengeFixture.clock_on(day))
	# A Callable does not keep its object: the suite holds the uplink, as the night does.
	_uplink = ProfileUplink.new(api, store)
	session.uploader = _uplink.send
	session.attach(_state)
	return session


func _round_one() -> void:
	var made := ChallengeFixture.night(1)
	_state.apply_events(made["events"])
	_state.apply_events(ChallengeFixture.play_round_one(made["rules"], 1))


func _idle(store: ProfileStore) -> void:
	var began := Time.get_ticks_msec()
	while store.is_flushing() and (Time.get_ticks_msec() - began) / 1000.0 < WAIT_SECONDS:
		await get_tree().process_frame
	assert_bool(store.is_flushing()).is_false()


func _until(done: Callable) -> void:
	var began := Time.get_ticks_msec()
	while not done.call() and (Time.get_ticks_msec() - began) / 1000.0 < WAIT_SECONDS:
		await get_tree().create_timer(0.05).timeout
	assert_bool(done.call()).is_true()


# --- What a round's end sends ---


func test_a_rounds_end_sends_one_profile_write_of_what_the_night_added() -> void:
	var api := Fake.new(self)
	var store := _store("one_write")
	var session := _session(store, api)
	_round_one()
	assert_int(session.credited()).is_greater(0)
	# One round, one write: the account's profile, read once and written once.
	assert_int(api.writes.size()).is_equal(1)
	assert_int(api.reads).is_equal(1)
	assert_int(int(api.data["xp"])).is_equal(session.credited())
	assert_bool(api.data["opening_night"]).is_true()
	assert_int(int(api.data["bonus_day"])).is_equal(DAY)
	assert_bool(store.queue.is_empty()).is_true()
	# The file the next start reads holds nothing waiting.
	assert_bool(ProfileStore.open(store.path).queue.is_empty()).is_true()


func test_a_night_with_no_account_sends_nothing() -> void:
	var api := Fake.new(self)
	var store := _store("no_account", false)
	var session := _session(store, api)
	_round_one()
	assert_int(session.xp()).is_greater(0)
	assert_int(session.credited()).is_zero()
	assert_int(api.writes.size()).is_equal(0)
	assert_int(api.reads).is_equal(0)
	assert_bool(FileAccess.file_exists(store.path)).is_false()


func test_what_waits_in_the_queue_goes_as_one_write() -> void:
	var api := Fake.new(self)
	var store := _store("coalesce")
	store.credit(40, true, DAY)
	store.credit(25)
	store.finished(&"d_kills_40")
	assert_int(store.queue.size()).is_equal(3)
	var uplink := ProfileUplink.new(api, store)
	assert_int(await store.flush(uplink.send, true)).is_equal(1)
	assert_int(api.writes.size()).is_equal(1)
	assert_int(int(api.data["xp"])).is_equal(65)
	assert_bool(api.data["opening_night"]).is_true()
	assert_int(int(api.data["bonus_day"])).is_equal(DAY)
	assert_array(api.data["done"]).is_equal(["d_kills_40"])
	assert_bool(store.queue.is_empty()).is_true()


func test_a_second_flush_while_one_waits_sends_nothing_and_the_first_takes_what_came() -> void:
	var store := _store("overlap")
	store.credit(10)
	var gate := {"open": false, "sent": []}
	var slow := func(write: Dictionary) -> bool:
		gate["sent"].append(write["xp"])
		while not gate["open"]:
			await get_tree().process_frame
		return true
	store.flush(slow, false)
	assert_bool(store.is_flushing()).is_true()
	store.credit(20)
	assert_int(await store.flush(slow, false)).is_zero()
	gate["open"] = true
	await _idle(store)
	assert_array(gate["sent"]).is_equal([10, 20])
	assert_bool(store.queue.is_empty()).is_true()


# --- Against the real backend ---


func test_a_write_goes_on_the_accounts_own_latest_never_on_a_file(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var api := await _guest("Ann")
	# The account has a card worn and nothing else.
	var seed_profile := Profile.new().to_dict()
	seed_profile["equipped"] = {"card": "admit_one"}
	assert_bool((await api.write_save(ProfileUplink.SLOT, 0, 1, seed_profile))["ok"]).is_true()
	# This machine's file claims 9000 XP: it is nobody's to merge.
	var store := _store("on_latest")
	store.profile.xp = 9000
	store.credit(12, true)
	var uplink := ProfileUplink.new(api, store)
	assert_int(await store.flush(uplink.send, true)).is_equal(1)
	var held := await _held(api)
	assert_int(int(held["data"]["xp"])).is_equal(12)
	assert_str(held["data"]["equipped"]["card"]).is_equal("admit_one")
	assert_int(held["revision"]).is_equal(2)
	assert_int(store.account_revision).is_equal(2)
	assert_str(store.account).is_equal(api.my_id())


func test_a_stale_revision_is_read_again_and_sent_on_the_new_latest(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var api: Racing = await _guest("Bo", Racing)
	api.rival = api.detached(self)
	var store := _store("conflict")
	store.credit(30, true)
	var uplink := ProfileUplink.new(api, store)
	assert_int(await store.flush(uplink.send)).is_equal(1)
	# Written twice (the first was refused, 409), read twice, and the rival's change is still there.
	assert_int(api.writes).is_equal(2)
	assert_int(api.reads).is_equal(2)
	var held := await _held(api)
	assert_int(int(held["data"]["xp"])).is_equal(30)
	assert_array(held["data"]["done"]).is_equal(["from_the_rival"])
	assert_bool(held["data"]["opening_night"]).is_true()
	assert_bool(store.queue.is_empty()).is_true()


func test_a_write_that_rises_too_fast_stays_queued_and_the_account_is_untouched(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var api := await _guest("Cy")
	var store := _store("too_fast")
	store.credit(5000)
	var uplink := ProfileUplink.new(api, store)
	assert_int(await store.flush(uplink.send, true)).is_zero()
	assert_int(store.queue.size()).is_equal(1)
	assert_int(store.queue[0]["xp"]).is_equal(5000)
	# The file keeps it too, so a restart sends it again.
	assert_int(ProfileStore.open(store.path).queue.size()).is_equal(1)
	assert_bool((await _held(api))["found"]).is_false()
	# What the clock allows goes through: waiting makes a refused write acceptable.
	store.queue.assign([{"id": "x", "xp": 1, "opening_night": false, "bonus_day": -1}])
	await get_tree().create_timer(1.5).timeout
	assert_int(await store.flush(uplink.send, true)).is_equal(1)
	assert_int(int((await _held(api))["data"]["xp"])).is_equal(1)


func test_a_day_the_backend_does_not_accept_is_sent_without_its_bonus(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var api := await _guest("Di")
	var store := _store("bad_day")
	store.credit(130, true, 3)
	var uplink := ProfileUplink.new(api, store)
	assert_int(await store.flush(uplink.send)).is_equal(1)
	var held := await _held(api)
	assert_int(int(held["data"]["xp"])).is_equal(130 - XpRules.FIRST_GAME_OF_THE_DAY_XP)
	assert_int(int(held["data"]["bonus_day"])).is_equal(Profile.NO_DAY)


func test_a_played_round_leaves_the_account_and_the_queue_holding_the_night_between_them(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var api := await _guest("Ed")
	var store := _store("round")
	# The backend's own date, within a day of which a first game of the day is accepted.
	var today := floori(Time.get_unix_time_from_system() / 86400.0)
	var session := _session(store, api, today)
	_round_one()
	await _idle(store)
	# The backend takes a round as fast as the clock allows since sign-in, plus the two one-offs:
	# whichever it did, the night is in the account or still queued, never lost or counted twice.
	var held := await _held(api)
	var in_account := int(held["data"]["xp"]) if held["found"] else 0
	var waiting := 0
	for write in store.queue:
		waiting += int(write["xp"])
	assert_int(in_account + waiting).is_equal(session.credited())
	assert_int(store.profile.xp).is_equal(session.credited())


# --- Read at sign-in ---


func test_the_profile_read_replaces_the_cached_one_and_keeps_what_is_queued(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var api := await _guest("Flo")
	assert_bool((await api.write_save(ProfileUplink.SLOT, 0, 1, OPENED))["ok"]).is_true()
	var store := _store("read")
	store.profile.xp = 9000
	store.credit(7)
	assert_bool(await ProfileUplink.new(api, store).read()).is_true()
	assert_int(store.profile.xp).is_equal(57)
	assert_array(store.profile.done).is_equal([&"a"])
	assert_bool(store.profile.opening_night).is_true()
	assert_int(store.account_revision).is_equal(1)
	assert_str(store.account).is_equal(api.my_id())
	assert_int(ProfileStore.open(store.path).profile.xp).is_equal(57)


func test_signing_in_puts_the_accounts_profile_in_the_file(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var path := DIR + "sign_in.json"
	var credentials := DIR + "guest.json"
	ProfileUplink.sync_path = path
	# A first visit: a guest account (its credential kept), which then holds 50 XP.
	var first := TogetherApi.new(self, _backend.url)
	first.guest_path = credentials
	assert_bool((await first.sign_in("Gus"))["ok"]).is_true()
	assert_bool((await first.write_save(ProfileUplink.SLOT, 0, 1, OPENED))["ok"]).is_true()
	# The file on this machine says 9000: a stale cache, or somebody's edit.
	await _until(func() -> bool: return ProfileStore.open(path).account == TogetherApi.account_id())
	var stale := ProfileStore.open(path)
	stale.profile.xp = 9000
	stale.save()
	# A second visit, no session in memory but the credential: the same account, and its XP.
	TogetherApi.forget()
	var second := TogetherApi.new(self, _backend.url)
	second.guest_path = credentials
	var back := await second.sign_in("")
	assert_bool(back["returning"]).is_true()
	await _until(func() -> bool: return ProfileStore.open(path).profile.xp == 50)
	assert_str(ProfileStore.open(path).account).is_equal(TogetherApi.account_id())


func test_an_isolated_api_reads_no_file_at_sign_in(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	ProfileUplink.sync_path = DIR + "isolated.json"
	await _guest("Hal")
	await get_tree().create_timer(0.3).timeout
	assert_bool(FileAccess.file_exists(ProfileUplink.sync_path)).is_false()


func test_a_queue_kept_for_another_account_is_dropped_on_the_next_read() -> void:
	var store := _store("other_account")
	store.account = "old-guest"
	store.credit(40)
	var answer := {"found": true, "revision": 3, "schema_version": 1, "data": {"xp": 10}}
	store.adopt(answer, "new-guest")
	assert_bool(store.queue.is_empty()).is_true()
	assert_int(store.profile.xp).is_equal(10)
	# The same account keeps its queue on top; a file with no account yet is read as the same one.
	store.credit(5)
	store.adopt(answer, "new-guest")
	assert_int(store.queue.size()).is_equal(1)
	assert_int(store.profile.xp).is_equal(15)
	var fresh := _store("unknown_account")
	fresh.credit(5)
	fresh.adopt(answer, "someone")
	assert_int(fresh.queue.size()).is_equal(1)
	assert_str(ProfileStore.open(fresh.path).account).is_equal("someone")


func test_a_profile_in_a_newer_layout_is_left_alone() -> void:
	var store := _store("newer_layout")
	store.credit(40)
	store.adopt({"found": true, "revision": 3, "schema_version": 99, "data": {"xp": 10}}, "a")
	assert_int(store.profile.xp).is_equal(40)
