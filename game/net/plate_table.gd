class_name PlateTable
extends RefCounted
## The calling card and the emblem each seat with an account wears in a night, kept by the game
## server and told to every client with the seat's level: in the `account_seated` event and, for a
## client that joins later, in the WELCOME's `plates`. No client message carries one.
##
## What a seat asks for is its ticket's (`TicketVerifier.account_of`: the `card` and `emblem` the
## backend read from the profile, and the `done` list), and the server holds it to what the seat
## owns, as it holds a look to the level (`LookServer`): the tier pieces by the level the ticket's
## XP gives, the challenge pieces by the finished challenges. A piece the seat does not own is
## dropped, so a profile edited by hand wears nothing it did not earn.

## Seat -> `{card, emblem}` (piece ids, `&""` for none).
var _held: Dictionary[int, Dictionary] = {}
var _catalog: PlateCatalog


func _init(catalog: PlateCatalog = null) -> void:
	_catalog = catalog if catalog != null else PlateCatalog.shipped()


## A seat with an account sat down at `level` asking for what `account` (the ticket's) says.
func seat(player_id: int, account: Dictionary, level: int) -> void:
	var done: Array[StringName] = []
	for id: Variant in account.get("done", []):
		done.append(StringName(str(id)))
	var asked := {
		"card": str(account.get("card", "")),
		"emblem": str(account.get("emblem", "")),
	}
	_held[player_id] = _catalog.worn(asked, level, done)


func release(player_id: int) -> void:
	_held.erase(player_id)


## What a seat wears: `{card, emblem}`, empty ids for none.
func of_seat(player_id: int) -> Dictionary:
	return _held.get(player_id, {PlateCatalog.CARD: &"", PlateCatalog.EMBLEM: &""})


## The event that tells every client a seat with an account sat down.
func seated_event(player_id: int, level: int) -> Dictionary:
	var worn := of_seat(player_id)
	return {
		"type": &"account_seated",
		"player_id": player_id,
		"level": level,
		"card": worn[PlateCatalog.CARD],
		"emblem": worn[PlateCatalog.EMBLEM],
	}


## Every seat's plate for a WELCOME: player id -> `{card, emblem}`; a seat that wears nothing is
## left out.
func to_dict() -> Dictionary:
	var out := {}
	for player_id in _held:
		var worn := _held[player_id]
		if worn[PlateCatalog.CARD] != &"" or worn[PlateCatalog.EMBLEM] != &"":
			out[player_id] = {
				"card": worn[PlateCatalog.CARD],
				"emblem": worn[PlateCatalog.EMBLEM],
			}
	return out
