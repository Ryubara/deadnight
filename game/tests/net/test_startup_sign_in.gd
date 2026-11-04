extends GdUnitTestSuite
## A returning Guest signs in when the game opens (`StartupSignIn`, #1122), so a Solo night earns
## XP for a player who never opens Play together. Four things are proved: a kept credential signs
## in once and no credential sends nothing; a Play together sign-in started meanwhile waits for it
## and sends no second request; a sign-in that fails leaves the player as before, and Play together
## still signs in; and, against the real backend (`spikes/backend`), the player is back in the
## account they had, with its XP in the profile file, through the call `Main` makes (`begin`).

const DIR := "user://test_startup_sign_in/"
const FILE := DIR + "guest_account.json"
const PROFILE := DIR + "profile.json"
const WAIT_SECONDS := 20.0
const NEEDS := "needs node 24 and npm ci in spikes/backend"
const BACKEND := "https://backend.example"
const OPENED := {"xp": 50, "equipped": {}, "done": ["a"], "opening_night": true, "bonus_day": -1}

var _backend: BackendFixture


## A backend that answers a guest sign-in after a moment (so a second caller can come meanwhile),
## or fails as an offline one does, and keeps what it was sent.
class Slow:
	extends TogetherApi
	var sent: Array = []
	var offline := false

	func _call(
		_method: String, path: String, body: Variant = null, _authorised: bool = true
	) -> Dictionary:
		sent.append({"path": path, "body": body})
		await _parent.get_tree().create_timer(0.2).timeout
		if offline:
			return TogetherApi._failed("network")
		return {
			"ok": true,
			"token": "session",
			"user": {"id": "guest-1", "name": "Ann"},
			"guestToken": "renewed",
			"returning": true,
		}


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_clear_files()
	TogetherApi.forget()


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


func _api(offline := false) -> Slow:
	var api := Slow.new(self, BACKEND)
	api.guest_path = FILE
	api.offline = offline
	return api


func _until(done: Callable) -> void:
	var began := Time.get_ticks_msec()
	while not done.call() and (Time.get_ticks_msec() - began) / 1000.0 < WAIT_SECONDS:
		await get_tree().create_timer(0.05).timeout
	assert_bool(done.call()).is_true()


func test_a_kept_credential_signs_in_once() -> void:
	GuestAccount.save_credential(BACKEND, "kept", FILE)
	var api := _api()
	assert_bool(StartupSignIn.wanted(api)).is_true()
	var answer := await StartupSignIn.run(api)
	assert_bool(answer["ok"]).is_true()
	assert_bool(TogetherApi.signed_in()).is_true()
	assert_str(TogetherApi.account_id()).is_equal("guest-1")
	# One request, to the guest sign-in, with the credential the last visit kept.
	assert_int(api.sent.size()).is_equal(1)
	assert_str(api.sent[0]["path"]).is_equal("/auth/guest")
	assert_str(api.sent[0]["body"]["guestToken"]).is_equal("kept")
	# The renewed credential is kept for the next visit.
	assert_str(GuestAccount.load_credential(BACKEND, FILE)).is_equal("renewed")
	# Nothing more once signed in: the player is not signed in twice.
	assert_bool(StartupSignIn.wanted(api)).is_false()
	assert_str((await StartupSignIn.run(api))["error"]).is_equal("skipped")
	assert_int(api.sent.size()).is_equal(1)


func test_no_credential_sends_nothing() -> void:
	var api := _api()
	assert_bool(StartupSignIn.wanted(api)).is_false()
	var answer := await StartupSignIn.run(api)
	assert_bool(answer["ok"]).is_false()
	assert_str(answer["error"]).is_equal("skipped")
	assert_array(api.sent).is_empty()
	assert_bool(TogetherApi.signed_in()).is_false()
	# The call `Main` makes starts nothing either, and writes no file.
	assert_object(StartupSignIn.begin(self, BACKEND, FILE)).is_null()
	assert_bool(FileAccess.file_exists(FILE)).is_false()


func test_a_run_with_no_credential_file_starts_nothing() -> void:
	# A test run, a capture: `GuestAccount.default_path` is empty and nothing is read.
	assert_object(StartupSignIn.begin(self, BACKEND)).is_null()


func test_a_discord_activity_is_not_signed_in_at_start_up() -> void:
	GuestAccount.save_credential(BACKEND, "kept", FILE)
	var api := _api()
	api.instance_id = "activity-1"
	assert_bool(StartupSignIn.wanted(api)).is_false()


func test_play_together_signing_in_meanwhile_sends_no_second_request() -> void:
	GuestAccount.save_credential(BACKEND, "kept", FILE)
	var startup := _api()
	var screen := _api()
	var started := []
	var begin := func() -> void: started.append(await StartupSignIn.run(startup))
	begin.call()
	assert_bool(TogetherApi.signed_in()).is_false()
	# Play together opens while the start-up sign-in is out.
	var answer := await screen.sign_in("Bo")
	assert_bool(answer["ok"]).is_true()
	await _until(func() -> bool: return started.size() == 1)
	assert_bool(started[0]["ok"]).is_true()
	assert_bool(TogetherApi.signed_in()).is_true()
	assert_int(startup.sent.size()).is_equal(1)
	assert_array(screen.sent).is_empty()
	# And a third, later, finds the session.
	var later := _api()
	assert_bool((await later.sign_in())["ok"]).is_true()
	assert_array(later.sent).is_empty()


func test_a_failed_sign_in_leaves_the_player_as_before_and_play_together_signs_in() -> void:
	GuestAccount.save_credential(BACKEND, "kept", FILE)
	var startup := _api(true)
	var failed := await StartupSignIn.run(startup)
	assert_bool(failed["ok"]).is_false()
	assert_str(failed["error"]).is_equal("network")
	assert_bool(TogetherApi.signed_in()).is_false()
	# The credential is not lost by a backend that could not be reached.
	assert_str(GuestAccount.load_credential(BACKEND, FILE)).is_equal("kept")
	# Play together, opened later, signs in as it always did.
	var screen := _api()
	var answer := await screen.sign_in("Bo")
	assert_bool(answer["ok"]).is_true()
	assert_int(screen.sent.size()).is_equal(1)
	assert_bool(TogetherApi.signed_in()).is_true()


func test_play_together_opened_during_a_start_up_sign_in_that_fails_signs_in_itself() -> void:
	GuestAccount.save_credential(BACKEND, "kept", FILE)
	var startup := _api(true)
	var screen := _api()
	var started := []
	var begin := func() -> void: started.append(await StartupSignIn.run(startup))
	begin.call()
	var answer := await screen.sign_in("Bo")
	assert_bool(answer["ok"]).is_true()
	assert_bool(TogetherApi.signed_in()).is_true()
	assert_int(screen.sent.size()).is_equal(1)
	await _until(func() -> bool: return started.size() == 1)
	assert_bool(started[0]["ok"]).is_false()


# --- Against the real backend ---


func test_a_returning_guest_is_back_in_its_account_with_its_xp_from_the_game_opening(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	_backend = BackendFixture.new()
	assert_bool(await _backend.start(self)).is_true()
	ProfileUplink.sync_path = PROFILE
	# A first visit (Play together): a guest account that holds 50 XP, its credential kept.
	var first := TogetherApi.new(self, _backend.url)
	first.guest_path = FILE
	assert_bool((await first.sign_in("Gus"))["ok"]).is_true()
	assert_bool((await first.write_save(ProfileUplink.SLOT, 0, 1, OPENED))["ok"]).is_true()
	var account := TogetherApi.account_id()
	# The game is opened again: no session in memory, no profile file, only the credential.
	TogetherApi.forget()
	await get_tree().create_timer(0.3).timeout
	if FileAccess.file_exists(PROFILE):
		DirAccess.remove_absolute(PROFILE)
	var api := StartupSignIn.begin(self, _backend.url, FILE)
	assert_object(api).is_not_null()
	# `begin` returned at once: the menu did not wait for the answer.
	assert_bool(TogetherApi.signed_in()).is_false()
	await _until(func() -> bool: return TogetherApi.signed_in())
	assert_str(TogetherApi.account_id()).is_equal(account)
	assert_bool(TogetherApi.returned_to_account()).is_true()
	await _until(func() -> bool: return ProfileStore.open(PROFILE).profile.xp == 50)
	assert_str(ProfileStore.open(PROFILE).account).is_equal(account)
	# Play together, opened after, has its session already.
	assert_bool((await TogetherApi.new(self, _backend.url).sign_in("Gus"))["ok"]).is_true()
