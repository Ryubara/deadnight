extends GdUnitTestSuite
## A signed-in player's challenge board on its way to and from the account's `challenges` slot
## (`ChallengeUplink`), against the real backend (`spikes/backend`, run by Node on a free port with
## memory storage; see `BackendFixture`): the board read at sign-in is the account's; a solo night's
## round end writes one board; a stale revision (409) is read again and the board written on the
## latest; a night with no account writes nothing; two new accounts are dealt different orders; and
## the day the dailies follow is UTC's for the client and the server.

const DIR := "user://test_challenge_uplink/"
const DAY := 20401
const WAIT_SECONDS := 20.0
const NEEDS := "needs node 24 and npm ci in spikes/backend"

var _backend: BackendFixture
var _catalog: ChallengeCatalog
var _uplink: ChallengeUplink
var _session: ChallengeSession


## An API that lets another writer go first, once armed, between the revision it holds and the write
## it sends: the stale revision a second device (or a game server's report) makes.
class Racing:
	extends TogetherApi
	var rival: TogetherApi
	var armed := false
	var reads := 0
	var writes := 0

	func read_save(slot: String) -> Dictionary:
		reads += 1
		return await super.read_save(slot)

	func write_save(
		slot: String, revision: int, schema_version: int, data: Dictionary
	) -> Dictionary:
		writes += 1
		if armed:
			armed = false
			var latest := await rival.read_save(slot)
			var theirs: Dictionary = latest["data"].duplicate(true)
			theirs["order_draws"] = 99
			await rival.write_save(slot, int(latest["revision"]), schema_version, theirs)
		return await super.write_save(slot, revision, schema_version, data)


## A backend that takes everything and counts: for the number of writes a night makes.
class Fake:
	extends TogetherApi
	var account := "fake-account"
	var reads := 0
	var writes: Array[Dictionary] = []
	var revision := 0
	var data := {}

	func my_id() -> String:
		return account

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


class AheadFake:
	extends Fake

	func read_save(_slot: String) -> Dictionary:
		reads += 1
		return {"ok": true, "found": true, "revision": 4, "schema_version": 99, "data": {}}


class SlowFake:
	extends Fake
	var gate: Dictionary

	func write_save(
		slot: String, revision: int, schema_version: int, p_data: Dictionary
	) -> Dictionary:
		while not gate["open"] and not writes.is_empty():
			await Engine.get_main_loop().process_frame
		return await super.write_save(slot, revision, schema_version, p_data)


func before_test() -> void:
	_catalog = ChallengeCatalog.load_default()
	DirAccess.make_dir_recursive_absolute(DIR)
	_clear_files()


func after_test() -> void:
	if _backend != null:
		_backend.stop()
		_backend = null
	TogetherApi.forget()
	ChallengeUplink.sync_path = ""
	_clear_files()


func _clear_files() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)


func _path(name: String) -> String:
	return DIR + name + ".json"


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
	var read := await api.read_save(ChallengeUplink.SLOT)
	assert_bool(read["ok"]).is_true()
	return read


func _until(done: Callable) -> void:
	var began := Time.get_ticks_msec()
	while not done.call() and (Time.get_ticks_msec() - began) / 1000.0 < WAIT_SECONDS:
		await get_tree().create_timer(0.05).timeout
	assert_bool(done.call()).is_true()


## The board of a machine that played `kills` kills for `account` on DAY: what is in the slot.
func _played(account: String, kills: int) -> ChallengeProfile:
	var profile := ChallengeProfile.fresh_for(account)
	profile.refresh(_catalog, DAY)
	profile.apply(_catalog, &"kills", kills, kills)
	return profile


func _open(path: String) -> ChallengeBoard:
	return ChallengeBoard.open(path, ChallengeFixture.clock_on(DAY), _catalog)


## A session of one player on `board`, its uplink on `api`, listening to a state it returns.
func _night(board: ChallengeBoard, api: TogetherApi) -> ClientState:
	var state := ClientState.new()
	state.player_id = 1
	_session = ChallengeSession.new(board)
	# A Callable does not keep its object: the session holds the uplink, as the night does.
	_uplink = ChallengeUplink.new(api)
	_session.uplink = _uplink
	_session.attach(state)
	return state


func _round_one(state: ClientState) -> void:
	var made := ChallengeFixture.night(1)
	state.apply_events(made["events"])
	state.apply_events(ChallengeFixture.play_round_one(made["rules"], 1))


func _order_ids(profile: ChallengeProfile) -> Array:
	return profile.orders.map(func(entry: Dictionary) -> String: return str(entry["id"]))


# --- What a round's end sends ---


func test_a_solo_rounds_end_writes_one_board_and_the_next_event_none() -> void:
	var api := Fake.new(self)
	var board := _open(_path("one_write"))
	var state := _night(board, api)
	_round_one(state)
	assert_int(int(board.profile.lifetime[&"kills"])).is_greater(0)
	# One round end, one write, on the account's slot as it was read: one read, one write.
	assert_int(api.writes.size()).is_equal(1)
	assert_int(api.reads).is_equal(1)
	assert_int(int(api.data["lifetime"]["kills"])).is_equal(int(board.profile.lifetime[&"kills"]))
	assert_bool(api.data.has("revision")).is_false()
	# A board that has not changed since is not sent again (a night's end right after a round's).
	assert_bool(await _uplink.send(board)).is_true()
	assert_int(api.writes.size()).is_equal(1)
	assert_int(api.reads).is_equal(1)
	# The night's end counts the last round, which is a change: one more write, on the revision it
	# was given, with no read.
	state.apply_events([{"type": &"game_over", "reason": "test", "round_reached": 3}])
	assert_int(api.writes.size()).is_equal(2)
	assert_int(api.reads).is_equal(1)
	# What the file holds is the board and the account it is the cache of.
	var cached: ChallengeProfile = ChallengeSave.read(board.path)["profile"]
	assert_str(cached.account).is_equal("fake-account")
	assert_int(cached.account_revision).is_equal(2)


func test_a_night_with_no_account_writes_nothing() -> void:
	var api := Fake.new(self)
	api.account = ""
	var board := _open(_path("no_account"))
	var state := _night(board, api)
	_round_one(state)
	assert_int(int(board.profile.lifetime[&"kills"])).is_greater(0)
	assert_int(api.writes.size()).is_equal(0)
	assert_int(api.reads).is_equal(0)
	assert_str((ChallengeSave.read(board.path)["profile"] as ChallengeProfile).account).is_equal("")


func test_a_board_another_account_owns_is_never_written() -> void:
	var api := Fake.new(self)
	var board := _open(_path("other"))
	board.profile.account = "an-old-guest"
	var state := _night(board, api)
	_round_one(state)
	assert_int(api.writes.size()).is_equal(0)
	assert_int(api.reads).is_equal(0)


func test_a_board_in_a_newer_layout_than_this_game_reads_is_not_written() -> void:
	var path := _path("newer")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"revision": 3, "schemaVersion": 99, "data": {}}')
	file.close()
	var api := Fake.new(self)
	var board := _open(path)
	assert_str(board.problem).is_equal(ChallengeSave.NEWER_VERSION)
	var state := _night(board, api)
	_round_one(state)
	assert_int(api.writes.size()).is_equal(0)
	assert_str(FileAccess.get_file_as_string(path)).contains('"schemaVersion": 99')


func test_a_slot_in_a_newer_layout_is_not_written_over() -> void:
	var api := AheadFake.new(self)
	var board := _open(_path("newer_slot"))
	var ahead := {"ok": true, "found": true, "revision": 4, "schema_version": 99, "data": {}}
	# The read at sign-in leaves the file alone...
	assert_bool(ChallengeUplink.adopt(ahead, "fake-account", board.path)).is_false()
	# ...and a write that finds the slot ahead of this game does not go.
	_uplink = ChallengeUplink.new(api)
	assert_bool(await _uplink.send(board)).is_false()
	assert_int(api.writes.size()).is_equal(0)


func test_what_a_signed_in_night_does_while_a_request_is_out_is_sent_after() -> void:
	var gate := {"open": false}
	var slow := SlowFake.new(self)
	slow.gate = gate
	var board := _open(_path("slow"))
	board.profile.account = "fake-account"
	board.profile.account_revision = 0
	_uplink = ChallengeUplink.new(slow)
	board.profile.apply(_catalog, &"kills", 3, 3)
	_uplink.send(board)
	board.profile.apply(_catalog, &"kills", 4, 4)
	# The second round end finds a write out: it does not start another, and the first goes on.
	_uplink.send(board)
	assert_int(slow.writes.size()).is_equal(1)
	gate["open"] = true
	await _until(func() -> bool: return slow.writes.size() == 2)
	assert_int(int(slow.writes[1]["lifetime"]["kills"])).is_equal(7)


func test_the_night_hands_its_uplink_to_its_session_and_a_round_end_writes() -> void:
	# The real hand-over: a night that runs here, with the uplink the screen gives it.
	var api := Fake.new(self)
	var board := _open(_path("night"))
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.economy.item(&"door_concession").price = 250
	var night := Night.new()
	night.challenge_board = board
	night.challenge_uplink = ChallengeUplink.new(api)
	add_child(night)
	await night.start(Night.Mode.AUTOPILOT, 7, tuning)
	assert_object(night.challenges.uplink).is_same(night.challenge_uplink)
	night.ticks_per_frame = 40
	var began := Time.get_ticks_msec()
	while api.writes.is_empty() and (Time.get_ticks_msec() - began) / 1000.0 < 300.0:
		await get_tree().physics_frame
	assert_int(api.writes.size()).is_greater_equal(1)
	assert_int(int(api.data["lifetime"]["kills"])).is_greater(0)
	night.queue_free()


# --- The board read at sign-in ---


func test_a_night_another_machine_played_shows_in_the_menu_after_sign_in(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var path := _path("sign_in")
	var credentials := DIR + "guest.json"
	ChallengeUplink.sync_path = path
	# The menu is up on a board of this machine before the sign-in lands.
	var menu := _open(path)
	menu.watch_file()
	var changed := {"count": 0}
	menu.changed.connect(func() -> void: changed["count"] += 1)
	# A first visit: a guest account with a board of 40 kills, played elsewhere.
	var first := TogetherApi.new(self, _backend.url)
	first.guest_path = credentials
	assert_bool((await first.sign_in("Gus"))["ok"]).is_true()
	var account := TogetherApi.account_id()
	var elsewhere := _played(account, 40)
	await _until(func() -> bool: return menu.profile.account == account)
	(
		assert_bool((await first.write_save(ChallengeUplink.SLOT, 0, 1, elsewhere.to_dict()))["ok"])
		. is_true()
	)
	# A second visit: the same account, and its board is the menu's, which said so.
	TogetherApi.forget()
	var second := TogetherApi.new(self, _backend.url)
	second.guest_path = credentials
	var back := await second.sign_in("")
	assert_bool(back["returning"]).is_true()
	await _until(func() -> bool: return int(menu.profile.lifetime.get(&"kills", 0)) == 40)
	assert_int(changed["count"]).is_greater(0)
	assert_str(menu.profile.account).is_equal(account)
	assert_int(menu.profile.account_revision).is_equal(1)
	# The file is the account's board too, for the next start and for a night.
	var cached := _open(path)
	assert_int(int(cached.profile.lifetime[&"kills"])).is_equal(40)
	assert_array(_order_ids(cached.profile)).is_equal(_order_ids(elsewhere))


func test_an_isolated_api_reads_no_board_at_sign_in(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	ChallengeUplink.sync_path = _path("isolated")
	await _guest("Hal")
	await get_tree().create_timer(0.3).timeout
	assert_bool(FileAccess.file_exists(ChallengeUplink.sync_path)).is_false()


func test_an_account_with_no_board_takes_this_machines_with_orders_of_its_own(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var path := _path("first_board")
	ChallengeUplink.sync_path = path
	# Played before any sign-in: this board has kills and the seed every new board used to get.
	var before := _open(path)
	before.profile.apply(_catalog, &"kills", 12, 12)
	before.save()
	assert_int(before.profile.order_seed).is_equal(1)
	var first := TogetherApi.new(self, _backend.url)
	first.guest_path = DIR + "guest.json"
	assert_bool((await first.sign_in("Ida"))["ok"]).is_true()
	var account := TogetherApi.account_id()
	await _until(func() -> bool: return _open(path).profile.account == account)
	var claimed := _open(path)
	assert_int(int(claimed.profile.lifetime[&"kills"])).is_equal(12)
	assert_int(claimed.profile.order_seed).is_equal(ChallengeProfile.seed_of(account))
	assert_int(claimed.profile.account_revision).is_equal(0)
	# Its first round end creates the slot, on revision 0 and with no read first.
	var state := _night(claimed, first.detached(self))
	_round_one(state)
	await _until(func() -> bool: return claimed.profile.account_revision == 1)
	var held := await _held(first)
	assert_int(held["revision"]).is_equal(1)
	assert_int(int(held["data"]["lifetime"]["kills"])).is_greater(12)


# --- Against the real backend ---


func test_a_stale_revision_is_read_again_and_the_board_written_on_the_latest(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var api: Racing = await _guest("Bo", Racing)
	api.rival = api.detached(self)
	var board := _open(_path("conflict"))
	board.profile.account = api.my_id()
	_uplink = ChallengeUplink.new(api)
	board.profile.apply(_catalog, &"kills", 5, 5)
	assert_bool(await _uplink.send(board)).is_true()
	assert_int(board.profile.account_revision).is_equal(1)
	assert_int(api.reads).is_equal(1)
	assert_int(api.writes).is_equal(1)
	# Another writer (a second machine) goes first between this one's revision and its write.
	api.armed = true
	board.profile.apply(_catalog, &"kills", 6, 6)
	assert_bool(await _uplink.send(board)).is_true()
	# This API wrote three times (the first round's, the refused one, the one on the latest) and
	# read twice (before the first write, and again after the 409): the 409 was read again, not merged.
	assert_int(api.writes).is_equal(3)
	assert_int(api.reads).is_equal(2)
	var held := await _held(api)
	assert_int(held["revision"]).is_equal(3)
	assert_int(int(held["data"]["lifetime"]["kills"])).is_equal(11)
	assert_int(int(held["data"]["order_draws"])).is_not_equal(99)
	assert_int(board.profile.account_revision).is_equal(3)


func test_a_board_the_account_already_has_is_not_written_over_by_an_unclaimed_one(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	await _start_backend()
	var api := await _guest("Cy")
	var theirs := _played(api.my_id(), 40)
	(
		assert_bool((await api.write_save(ChallengeUplink.SLOT, 0, 1, theirs.to_dict()))["ok"])
		. is_true()
	)
	# This machine's board never heard of the account (the sign-in read was missed).
	var board := _open(_path("missed"))
	board.profile.apply(_catalog, &"kills", 3, 3)
	_uplink = ChallengeUplink.new(api)
	assert_bool(await _uplink.send(board)).is_false()
	var held := await _held(api)
	assert_int(held["revision"]).is_equal(1)
	assert_int(int(held["data"]["lifetime"]["kills"])).is_equal(40)


# --- The seed and the day ---


func test_two_new_accounts_are_dealt_different_orders() -> void:
	var seeds := {}
	var order_sets := {}
	for n in 24:
		var account := "11111111-2222-4333-8444-%012d" % n
		var board := ChallengeProfile.fresh_for(account)
		board.refresh(_catalog, DAY)
		seeds[board.order_seed] = true
		order_sets[str(_order_ids(board))] = true
		# The same account is dealt the same wherever its board is first made.
		var again := ChallengeProfile.fresh_for(account)
		again.refresh(_catalog, DAY)
		assert_array(_order_ids(again)).is_equal(_order_ids(board))
	assert_int(seeds.size()).is_equal(24)
	assert_int(order_sets.size()).is_greater_equal(18)
	assert_int(ChallengeProfile.fresh_for("a").order_seed).is_not_equal(1)


func test_a_new_board_for_an_account_with_no_file_is_seeded_from_it() -> void:
	var path := _path("seeded")
	var answer := {"ok": true, "found": false, "revision": 0, "schema_version": 0, "data": {}}
	assert_bool(ChallengeUplink.adopt(answer, "account-one", path)).is_true()
	var board := _open(path)
	assert_int(board.profile.order_seed).is_equal(ChallengeProfile.seed_of("account-one"))
	assert_str(board.profile.account).is_equal("account-one")


func test_another_accounts_cache_is_replaced_by_a_fresh_board_of_the_new_account() -> void:
	var path := _path("switch")
	var answer := {"ok": true, "found": false, "revision": 0, "schema_version": 0, "data": {}}
	assert_bool(ChallengeUplink.adopt(answer, "account-one", path)).is_true()
	var one := _open(path)
	one.profile.apply(_catalog, &"kills", 30, 30)
	one.save()
	assert_bool(ChallengeUplink.adopt(answer, "account-two", path)).is_true()
	var two := _open(path)
	assert_str(two.profile.account).is_equal("account-two")
	assert_int(int(two.profile.lifetime.get(&"kills", 0))).is_zero()
	assert_int(two.profile.order_seed).is_equal(ChallengeProfile.seed_of("account-two"))


func test_a_file_from_a_newer_game_is_left_alone_by_the_sign_in() -> void:
	var path := _path("newer_file")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"revision": 3, "schemaVersion": 99, "data": {}}')
	file.close()
	var answer := {"ok": true, "found": true, "revision": 2, "schema_version": 1, "data": {}}
	assert_bool(ChallengeUplink.adopt(answer, "someone", path)).is_false()
	assert_str(FileAccess.get_file_as_string(path)).contains('"schemaVersion": 99')


func test_a_damaged_file_is_set_aside_and_the_accounts_board_takes_its_place() -> void:
	var path := _path("damaged")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	var theirs := _played("someone", 8)
	var answer := {
		"ok": true, "found": true, "revision": 5, "schema_version": 1, "data": theirs.to_dict()
	}
	assert_bool(ChallengeUplink.adopt(answer, "someone", path)).is_true()
	assert_bool(FileAccess.file_exists(path + ".broken")).is_true()
	var board := _open(path)
	assert_int(int(board.profile.lifetime[&"kills"])).is_equal(8)
	assert_int(board.profile.account_revision).is_equal(5)


func test_the_day_of_the_dailies_is_utc_s_for_the_client_and_the_server() -> void:
	# The client's clock never reads the machine's zone: the same instant is the same day on every
	# machine, and the game server's clock (no offset) says that day too.
	var client := ChallengeClock.system()
	var server := ChallengeClock.from_source(Time.get_unix_time_from_system)
	assert_int(client.offset_seconds).is_zero()
	assert_int(client.day()).is_equal(server.day())
	assert_int(client.day()).is_equal(floori(Time.get_unix_time_from_system() / 86400.0))
	# 01:30 UTC is the evening before in a zone eight hours behind: for both it is one day.
	var evening := ChallengeClock.fixed(float(DAY + 1) * 86400.0 + 1.5 * 3600.0)
	assert_int(evening.day()).is_equal(DAY + 1)
