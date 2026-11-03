class_name ElementDef
extends Resource
## One element a re-cut weapon can carry, as data (`defs/<id>.tres`): what a hit of the weapon does
## besides its own damage, and how it is drawn. The re-cut profile names it
## (`RecutProfile.element`); the combat server reads it from the weapon in the shooter's hand
## (`ElementPlay`); a client finds it again by the id the events carry (`ElementCatalog`). A new
## element is a new file, a new id in the catalogue and, when it does something new, a new group
## here: no weapon's code changes.
##
## Every damage an element makes is one more `hit` for the zombie it reaches (the rules own the
## health, the points and the kill), so the pay and the rounds' health stay the rules'.

@export var id: StringName = &""
## The name the card and the feed use ("EXPLOSIVE ROUNDS").
@export var display_name: String = ""
## The colour of the effect it draws (the burst, the arc, the fire) and of the card's line.
@export var tint: Color = Color(1.0, 0.6, 0.2, 1.0)

## Whether the damage it makes sprays blood (a burst and an arc hit a body; a fire does not
## bleed it).
@export var bleeds: bool = true

@export_group("Blast")
## Every hit that lands bursts here for `blast_fraction` of the weapon's hit at the centre, sliding
## to `blast_edge_fraction` of that at the edge, on the other zombies only (the zombie hit takes the
## hit alone); the shooter and the team take nothing. 0 is no blast.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var blast_radius: float = 0.0
@export_range(0.0, 2.0, 0.05) var blast_fraction: float = 0.0
@export_range(0.0, 1.0, 0.05) var blast_edge_fraction: float = 0.5

@export_group("Arc")
## Every hit arcs to up to `arc_targets` other zombies within `arc_radius`, nearest first, for
## `arc_fraction` of the weapon's hit each: one arc, an instant, never a chain. 0 targets is no arc.
@export_range(0, 10, 1, "or_greater") var arc_targets: int = 0
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var arc_radius: float = 0.0
@export_range(0.0, 2.0, 0.05) var arc_fraction: float = 0.0

@export_group("Ground")
## The burst of the weapon's projectile leaves a fire patch of `ground_radius` for the weapon's
## whole
## lure time: every zombie in it takes `ground_dps` a second, in a hit every `tick_seconds`.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var ground_radius: float = 0.0
@export_range(0.0, 500.0, 1.0, "or_greater", "suffix:/s") var ground_dps: float = 0.0
@export_range(0.05, 5.0, 0.05, "suffix:s") var tick_seconds: float = 0.5


func has_blast() -> bool:
	return blast_radius > 0.0 and blast_fraction > 0.0


func has_arc() -> bool:
	return arc_targets > 0 and arc_radius > 0.0 and arc_fraction > 0.0


func has_ground() -> bool:
	return ground_radius > 0.0 and ground_dps > 0.0


## One line for the bench's card, from the numbers above ("EVERY HIT BURSTS 2.0 M ROUND").
func card_line() -> String:
	var parts := PackedStringArray()
	if has_blast():
		parts.append("EVERY HIT BURSTS %s M ROUND" % String.num(blast_radius, 1))
	if has_arc():
		parts.append(
			"EVERY HIT ARCS TO %d MORE WITHIN %s M" % [arc_targets, String.num(arc_radius, 1)]
		)
	if has_ground():
		parts.append(
			(
				"THE BURST LEAVES FIRE, %s A SECOND, %s M ROUND"
				% [String.num(ground_dps, 0), String.num(ground_radius, 1)]
			)
		)
	return ", ".join(parts)
