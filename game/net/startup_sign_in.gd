class_name StartupSignIn
extends RefCounted
## A returning Guest, or a player in a Discord Activity, signs in when the game opens, in the
## background, so the account and its profile (`ProfileUplink`) are ready before the first Solo
## night: a solo night earns XP only for a player who is signed in (no offline XP, `ProfileStore`),
## and a player who never opens Play together would otherwise earn nothing (#1122). The Activity
## signs in with Discord (`TogetherApi.activity`) and does nothing else here: it makes and reads
## no lobby (#1178).
##
## - **Only a returning guest, or an Activity.** The credential the last visit kept (`GuestAccount`,
##   `user://guest_account.json`) is the sign that this player has an account here. With none,
##   nothing is sent and the player is as before: not signed in. Whether a first Solo makes a
##   Guest account for someone who never asked is the maintainer's call (#1122), and is not made
##   here. An Activity is always signed in: Discord has the player's name.
## - **One request.** The sign-in is the one `TogetherApi.sign_in` makes (`POST /auth/guest` with
##   the credential); the profile read that follows it (`ProfileUplink.sync_after_sign_in`) is
##   the sign-in's own and is not made again here. A screen that signs in meanwhile (Play
##   together) waits for this one and does not send its own (`TogetherApi.sign_in`).
## - **Never in the way.** `begin` returns at once; the menu and a night do not wait for the
##   answer. A sign-in that fails (offline, a backend that is down) is forgotten: the player is as
##   before and Play together signs in when it is opened, as it always did.


## Starts the sign-in under `host`'s root (it outlives the screen that was open), when this player
## has a credential for the backend. Returns the API doing it, or null when nothing was started.
static func begin(
	host: Node, backend: String = "", path: String = GuestAccount.default_path()
) -> TogetherApi:
	var address := backend if backend != "" else TogetherScreen.backend_url()
	var api := TogetherApi.new(host.get_tree().root, address)
	api.guest_path = path
	if not wanted(api):
		return null
	# Not awaited: the caller goes on to the menu.
	run(api)
	return api


## Whether this player has an account to come back to and is not signed in already: a credential
## kept for this backend, and no session in this run; a Discord Activity keeps none and signs in
## with Discord every time.
static func wanted(api: TogetherApi) -> bool:
	if TogetherApi.signed_in():
		return false
	if TogetherApi.activity:
		return true
	return GuestAccount.load_credential(api.base_url, api.guest_path) != ""


## Signs in with the kept credential; the answer is the sign-in's (`{"ok": false, ...}` when the
## backend could not be reached or took no credential, `{"ok": false, "error": "skipped"}` when
## nothing was due). It never throws.
static func run(api: TogetherApi) -> Dictionary:
	if not wanted(api):
		return {"ok": false, "error": "skipped"}
	return await api.sign_in()
