class_name ChallengeUplink
extends RefCounted
## A signed-in player's challenge board between this machine and the backend's `challenges` slot
## (`GET` and `PUT /saves/challenges`, docs/design/progression.md#the-save). The slot is the
## account's board; `user://challenges.json` is its cache, with the account it belongs to and the
## revision it was at (`ChallengeSave`).
##
## - **Read at sign-in** (`sync_after_sign_in`, `adopt`): one request. The account's board replaces
##   the cache, so a night another machine (or the game server) played shows in the menu. An account
##   with no board yet takes this machine's, when no other account owns it, and is dealt orders of
##   its own (`ChallengeProfile.seed_of`). A damaged file is set aside and replaced; a file from a
##   newer game, or a slot in a newer layout, is left alone.
## - **Write at a solo night's round ends** (`send`): the whole board on the revision it follows. A
##   stale revision (409) is read again and the board is written on the latest: nothing is merged,
##   so the later round end wins. A board this account does not own is never written.
## - **Online the game server writes** the board in its round reports, so an online night starts no
##   uplink: a second writer would be a board that two counters fight over.
## - A night never waits on any of it.

const SLOT := "challenges"
## How many times a write is put on the latest revision while other writes keep moving it.
const CONFLICT_TRIES := 4

## The board file a sign-in updates; empty (a test, a capture) updates none. The real game's root
## sets it (`Main`), as it does for the profile's.
static var sync_path := ""

var api: TogetherApi

var _busy := false
var _again := false
## The board last taken by the backend, as text: a round end that changed nothing sends nothing.
var _sent := ""


func _init(p_api: TogetherApi) -> void:
	api = p_api


## Reads the account's board after a sign-in, into the board file, in the background (the request
## outlives the screen that signed in: it is made under the root).
static func sync_after_sign_in(signed: TogetherApi) -> void:
	if sync_path == "":
		return
	var parent := signed.owner_node()
	var own := signed.detached(parent.get_tree().root if parent.is_inside_tree() else parent)
	var answer := await own.read_save(SLOT)
	if answer["ok"] and adopt(answer, own.my_id(), sync_path):
		ChallengeBoard.file_replaced(sync_path)


## Puts the account's board, as `TogetherApi.read_save` answers it, in the file at `path`. True when
## the file was written.
static func adopt(answer: Dictionary, account_id: String, path: String) -> bool:
	if account_id == "" or int(answer.get("schema_version", 0)) > ChallengeSave.SCHEMA_VERSION:
		return false
	var held := ChallengeSave.read(path)
	if held["problem"] == ChallengeSave.NEWER_VERSION:
		return false
	var mine: ChallengeProfile = held["profile"]
	var board: ChallengeProfile
	if answer.get("found", false):
		board = ChallengeProfile.from_dict(answer.get("data", {}))
	elif mine != null and mine.account in ["", account_id]:
		# The account has no board: this machine's is its first (a returning player keeps what the
		# nights before sign-in counted), with orders of the account's own.
		board = mine
		if mine.account == "":
			board.order_seed = ChallengeProfile.seed_of(account_id)
	else:
		board = ChallengeProfile.fresh_for(account_id)
	board.account = account_id
	board.account_revision = int(answer.get("revision", 0))
	if mine != null:
		board.revision = mine.revision
	return ChallengeSave.write(board, path)


## Writes `board`'s profile to the account (the whole board, on the revision it follows): true when
## the backend took it. A call while one is out is folded into it: the one in flight goes on to
## the board as it is then.
func send(board: ChallengeBoard) -> bool:
	if _busy:
		_again = true
		return false
	# A Callable does not keep this alive while a request is out, and the night that made it may go.
	@warning_ignore("unused_variable")
	var held := self
	_busy = true
	var taken := false
	while true:
		_again = false
		taken = await _write(board)
		if not _again:
			break
	_busy = false
	return taken


func _write(board: ChallengeBoard) -> bool:
	var profile := board.profile
	var me := api.my_id()
	# Not signed in, a file from a newer game, or the cache of another account: nothing is written.
	var refused := board.problem == ChallengeSave.NEWER_VERSION or profile.account not in ["", me]
	if me == "" or refused:
		return false
	# The save counter of this machine is no part of what the account holds.
	var data := profile.to_dict()
	data.erase("revision")
	var text := JSON.stringify(data)
	if text == _sent and profile.account == me:
		return true
	var revision := profile.account_revision if profile.account == me else -1
	for _try in CONFLICT_TRIES:
		if revision < 0:
			revision = await _latest_revision(profile, me)
			if revision < 0:
				return false
		var answer := await api.write_save(SLOT, revision, ChallengeSave.SCHEMA_VERSION, data)
		if answer["ok"]:
			profile.account = me
			profile.account_revision = int(answer["revision"])
			_sent = text
			board.save()
			return true
		if answer.get("error") != "revision_conflict":
			return false
		# Someone wrote first: read what is there now and write on that.
		revision = -1
	return false


## The revision of the account's slot as it is now, or -1 when the board must not be written: the
## read failed, the slot is in a newer layout than this game reads, or it holds a board this one did
## not come from (the sign-in read, which replaces this one, was missed).
func _latest_revision(profile: ChallengeProfile, me: String) -> int:
	var latest := await api.read_save(SLOT)
	if not latest["ok"] or int(latest["schema_version"]) > ChallengeSave.SCHEMA_VERSION:
		return -1
	if latest["found"] and profile.account != me:
		return -1
	return int(latest["revision"])
