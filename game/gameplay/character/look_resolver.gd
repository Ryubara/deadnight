class_name LookResolver
extends RefCounted
## Keeps teammates apart: when two players picked the same look, the one who joined later has the
## main garment colour moved on by `SHIFT_STEP` palette places (and again if that is taken too).
##
## Every client runs this on the same table of looks and gets the same answer, so nobody needs to
## be told: the order is the player id, and the input is only the looks.

## The colour channel that is moved: the main garment, the one most visible from a distance.
const SHIFTED_SLOT := &"primary"
## How many palette places a taken look is moved on: neighbours in the palette are often shades of
## one colour, and a step of 3 reaches every entry of a 16-colour palette before it repeats.
const SHIFT_STEP := 3


## `looks` maps player id (int) to `CharacterLook`; returns a new table with every look distinct.
## The inputs are not changed.
static func resolve(looks: Dictionary) -> Dictionary:
	var ids := looks.keys()
	ids.sort()
	var taken := {}
	var out := {}
	var palette_size := LookCatalog.palette(SHIFTED_SLOT).size()
	for id: int in ids:
		var look: CharacterLook = (looks[id] as CharacterLook).duplicate_look()
		look.shift = 0
		# More players than palette places cannot all differ in the torso colour alone; stop
		# there and let the rest repeat (a lot has at most four players).
		while taken.has(look.key()) and look.shift < palette_size:
			look.shift_colour(SHIFTED_SLOT, SHIFT_STEP)
			look.shift += 1
		taken[look.key()] = true
		out[id] = look
	return out
