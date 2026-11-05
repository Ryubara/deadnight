class_name ProfileUplink
extends RefCounted
## A signed-in player's profile between this machine and the backend's `profile` slot
## (`PUT /saves/profile`, docs/design/progression.md#storage-and-trust). The backend takes the
## whole profile on a revision and holds how fast its XP may rise, so:
##
## - **Read at sign-in** (`sync_after_sign_in`, `read`): the account's profile replaces the cached
##   one (`ProfileStore.adopt`), so the XP on the plate is the account's, never a file's. A night
##   does not wait for it.
## - **Send** (`send`, the `ProgressSession.uploader`): a queued write is a change, not a profile.
##   It is put on top of the account's own latest profile and written on that revision; a stale
##   revision (409) is read again and the change put on the new latest, nothing merged from a file.
##   A write the backend finds too fast for the time since the last one (422 `implausible_progress`)
##   stays queued and goes again at the next round's end, when the allowance has grown with the
##   clock. A first-game day the backend does not accept (`implausible_day`: a clock a day off) is
##   sent without it, and without its XP.

const SLOT := "profile"
## How many times a write is put on the latest profile while other writes keep moving it.
const CONFLICT_TRIES := 4

## The profile file a sign-in updates; empty (a test, a capture) updates none. The real game's
## root sets it (`Main`), as it does for the night's.
static var sync_path := ""

var api: TogetherApi
var store: ProfileStore


func _init(p_api: TogetherApi, p_store: ProfileStore) -> void:
	api = p_api
	store = p_store


## Reads the account's profile after a sign-in, into the profile file, in the background (the
## request outlives the screen that signed in: it is made under the root).
static func sync_after_sign_in(signed: TogetherApi) -> void:
	if sync_path == "":
		return
	var parent := signed.owner_node()
	var own := signed.detached(parent.get_tree().root if parent.is_inside_tree() else parent)
	var answer := await own.read_save(SLOT)
	if answer["ok"]:
		adopt_and_tell(ProfileStore.open(sync_path, TogetherApi.signed_in), answer, own.my_id())


## Reads the account's profile into the store. True when it was read.
func read() -> bool:
	var answer := await api.read_save(SLOT)
	if not answer["ok"]:
		return false
	adopt_and_tell(store, answer, api.my_id())
	return true


## Puts the account's profile in the store (`ProfileStore.adopt`) and tells the menu of the levels
## it holds beyond what this machine knew: the cache's level, and the highest a card was shown for
## (`ProgressNews`). A cache that was not this account's is no baseline. The screens that were built
## from the older file read it again (`ProfileFeed`).
static func adopt_and_tell(store: ProfileStore, answer: Dictionary, account_id: String) -> void:
	var cached := store.profile.level() if account_id != "" and store.account == account_id else 0
	store.adopt(answer, account_id)
	ProfileFeed.shared.adopted.emit()
	if account_id != "":
		MenuPopups.announce(
			ProgressNews.levels_after_read(account_id, cached, store.profile.level())
		)


## Sends a queued write (`ProfileStore.flush` calls this): true when the backend took it.
func send(write: Dictionary) -> bool:
	if not store.has_account():
		return false
	# A Callable does not keep this alive while a request is out, and the night that made it may go.
	@warning_ignore("unused_variable")
	var held := self
	for _try in CONFLICT_TRIES:
		var latest := await api.read_save(SLOT)
		if not latest["ok"] or int(latest["schema_version"]) > ProfileSave.SCHEMA_VERSION:
			return false
		var next := Profile.from_dict(latest["data"])
		next.apply_write(write)
		var answer := await api.write_save(
			SLOT, int(latest["revision"]), ProfileSave.SCHEMA_VERSION, next.to_dict()
		)
		if answer["ok"]:
			store.account_revision = int(answer["revision"])
			if store.account == "":
				store.account = api.my_id()
			return true
		match answer.get("error"):
			"revision_conflict":
				continue
			"implausible_day":
				# The player's clock is a day off the backend's: no first-game bonus, in the day or in XP.
				write["bonus_day"] = Profile.NO_DAY
				write["xp"] = maxi(int(write["xp"]) - XpRules.FIRST_GAME_OF_THE_DAY_XP, 0)
			_:
				return false
	return false
