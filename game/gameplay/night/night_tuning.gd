class_name NightTuning
extends Resource
## The numbers of the night that belong to neither the rules, the zombies nor the weapons: how
## hard a player is to kill, how far a hand reaches, where the barrel is.

@export_group("Player")
@export var max_health: float = 100.0
## Seconds without a blow before health comes back.
@export var regen_delay: float = 5.0
@export var regen_per_second: float = 25.0
@export var start_weapon: StringName = &"pistol"
## Magazines of ammunition each carried weapon gets when a round ends (the supply drop).
@export var resupply_magazines: int = 8

@export_group("Hands")
## Metres from the player's feet to a door slab (or a board) that it can be used from.
@export var use_reach: float = 3.2
## Seconds between two boards put back.
@export var repair_interval: float = 1.0

@export_group("Shots")
## The barrel, relative to the player's feet and facing (x right, -z forward).
@export var muzzle_offset: Vector3 = Vector3(0.3, 1.45, -0.4)
## A shot's origin farther than this from the shooter's head is pulled back to it.
@export var origin_slack: float = 3.0
@export var eye_height: float = 1.55
