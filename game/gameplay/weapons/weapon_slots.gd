class_name WeaponSlots
extends RefCounted
## The numbered places a player carries weapons in (#682): slot 1 is the first weapon carried,
## slot 2 the second, and a third slot is there for the perk that carries three (#687). A key per
## slot (`1`, `2`, `3`) takes that slot's weapon in hand; the swap button (`F`, the pad's d-pad up,
## the touch SWAP) still goes to the next one. A slot keeps its place: a weapon that takes the place
## of the one it replaces sits in the same slot, so the numbers on the HUD never trade places.

## The most slots there is a key, a command field and a HUD cell for.
const MAX := 3
## The input action of each slot, slot 1 first.
const ACTIONS: Array[StringName] = [&"weapon_slot_1", &"weapon_slot_2", &"weapon_slot_3"]
## The slot field of a command that picks no slot.
const NONE := 0
## The command's slot on the wire (`NetWire`) takes this many bits.
const BITS := 2


## How many slots a player has now: the carry limit (a perk that carries one more raises it).
static func count() -> int:
	return clampi(WeaponCatalog.CARRY_LIMIT, 1, MAX)


## The slot (1 to `MAX`) a pressed action picks, or `NONE`.
static func slot_of(action: StringName) -> int:
	return ACTIONS.find(action) + 1


## The weapon in slot `slot` (1-based) of `carried`, the ids in the order they are carried, or `&""`
## for an empty or unknown slot.
static func weapon_in(carried: Array, slot: int) -> StringName:
	if slot < 1 or slot > carried.size():
		return &""
	return carried[slot - 1]
