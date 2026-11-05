class_name PlateEquip
extends RefCounted
## Chooses the calling card or emblem a player wears and sends the choice to their account, from
## the equip screen. The choice is on the profile file at once (`ProfileStore.equip`) and goes to
## the backend in the background (`ProfileUplink`), which is where the game server reads it from
## when the player joins a night: a night never waits on it. A player with no account chooses
## nothing (there is nothing earned to choose from either).


## Puts `id` of `kind` on (`&""` takes it off). True when the choice changed. `root` is the node
## the request is made under, which outlives the screen.
static func choose(root: Node, store: ProfileStore, kind: StringName, id: StringName) -> bool:
	if not store.equip(kind, id):
		return false
	if TogetherApi.signed_in():
		var uplink := ProfileUplink.new(TogetherApi.new(root, TogetherScreen.backend_url()), store)
		# Not awaited: the file has the choice, and a refused write stays queued for the next round's end.
		store.flush(uplink.send, true)
	return true
