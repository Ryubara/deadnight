class_name MenuTab
extends RefCounted
## The tabs of the main menu, in the order of the tab bar. One list for the stage's camera, the
## tab bar and the panels, so none of them keeps its own.

enum Id { PLAY, LOADOUT, SHOP, CHALLENGES, MORE }

const ORDER: Array[Id] = [Id.PLAY, Id.LOADOUT, Id.SHOP, Id.CHALLENGES, Id.MORE]
const LABELS := {
	Id.PLAY: "Play",
	Id.LOADOUT: "Loadout",
	Id.SHOP: "Shop",
	Id.CHALLENGES: "Challenges",
	Id.MORE: "More",
}


static func label(tab: Id) -> String:
	return LABELS[tab]


## The tab `step` places along the bar from `tab`, wrapping round (a bumper press is +1 or -1).
static func neighbour(tab: Id, step: int) -> Id:
	return ORDER[posmod(ORDER.find(tab) + step, ORDER.size())]
