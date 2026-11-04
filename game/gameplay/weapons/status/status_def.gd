class_name StatusDef
extends Resource
## One status effect a weapon can put on a zombie, as data (`defs/<id>.tres`): what it does to the
## zombie while it lasts and how a client draws it. The server's `StatusBoard` keeps the seconds
## left; the zombie simulation reads what it does; the views read the wire id and the colour. A new
## element (the re-cut ones, #794) is a new file and a new id in `StatusCatalog`, not new code in
## the board.
##
## How long it lasts is the weapon's (`WeaponDef.status_seconds`): the same status may be held
## longer by one gun than another.

## A status the zombie has none of (the wire id 0).
const NONE := 0
## The ids the zombie's mode byte can carry (3 bits).
const WIRE_MAX := 7
## `boss_status` that means a boss takes nothing.
const IMMUNE_BOSS := &"immune"

@export var id: StringName = &""
## The number a snapshot carries for it, 1 to `WIRE_MAX`. A zombie under several shows the one with
## the highest `priority`.
@export_range(1, 7, 1) var wire: int = 1
@export var priority: int = 0

@export_group("Effect")
## It stops moving and attacking while it lasts (the dead stand still and are drawn still).
@export var halts: bool = false
## Share of its walking speed it keeps while it lasts (1 is no change; ignored while it halts).
@export_range(0.0, 1.0, 0.05) var speed_scale: float = 1.0
## Any hit on it kills it outright and it shatters: no corpse (`zombie_shattered`).
@export var shatters: bool = false
## The zombie kind decides whether it takes it and how many hits it needs (`ZombieType.freezable`
## and `freeze_bolts`); the hits before the last, and a kind that cannot, get `boss_status`.
@export var kind_gated: bool = false
## What a zombie that cannot take it gets instead (another status id), or `IMMUNE_BOSS` for nothing.
## Empty: the same status.
@export var boss_status: StringName = &""

@export_group("Look")
## The shell a client draws over the body (`ZombieView`), and how clear it is.
@export var tint: Color = Color(0.55, 0.85, 1.0, 0.55)


## What a boss of this status gets: this one, another one's id, or `IMMUNE_BOSS`.
func for_boss() -> StringName:
	return id if boss_status == &"" else boss_status
