class_name BotCoverage
extends RefCounted
## What a person can do in the night and what the bots do about it: every shop item kind, every
## weapon and every prompt the server shows has either a rule that handles it or a written waiver
## naming the phase that will. A test fails when the game gains one of these and this table does
## not (`docs/research/bots.md`, scenario 28), so a bot never quietly lacks a job a human has.

const RULE := "rule: "
const WAIVER := "waived until "

## `ShopItem.Kind` by name.
const SHOP_KINDS := {
	"DOOR": "waived until #228 (economy: doors in the planned order)",
	"WEAPON": "waived until #228 (economy: wall weapons)",
	"CRANE": "waived until #228 (economy: the prize crane)",
	"TONIC": "waived until #228 (economy: the hearty tonic)",
	"FUEL": "waived until #228 (the generator: a fuel can when the tank runs low)",
	"GRENADES": "waived until #227 (combat: grenades)",
	"AMMO": "waived until #227 (ammunition: rounds for the gun in hand)",
	"UPGRADE": "waived until #228 (economy: the re-cut bench)",
}
## `WeaponCatalog.IDS`: a weapon is covered when the motor can fire it as it is built.
const WEAPONS := {
	"pistol": "rule: BotMotor fires any hitscan weapon at a target inside its hit cone",
	"smg": "rule: BotMotor fires it in bursts of three to five (automatic)",
	"shotgun": "rule: BotMotor fires it like the pistol (the cone is for the body, not the spread)",
	"rifle": "rule: BotMotor fires it like the pistol",
	"flare_gun": "waived until #227 (combat: the flare lures the dead away)",
	"crowbar": "rule: BotMotor swings it at a target inside its reach",
	"baseball_bat": "rule: BotMotor swings it at a target inside its reach (melee)",
	"fire_axe": "rule: BotMotor swings it at a target inside its reach (melee)",
}
## The `kind` of every prompt the server's `use_target` and the machines can show.
const PROMPTS := {
	"door": "waived until #228 (economy)",
	"weapon": "waived until #228 (economy)",
	"ammo": "waived until #227 (ammunition)",
	"crane": "waived until #228 (economy)",
	"crane_take": "waived until #228 (economy)",
	"crane_busy": "waived until #228 (economy: wait for the buyer)",
	"recut": "waived until #228 (economy)",
	"recut_done": "waived until #228 (economy: nothing to do)",
	"recut_none": "waived until #228 (economy: nothing to do)",
	"tonic": "waived until #228 (economy)",
	"tonic_owned": "waived until #228 (economy: nothing to do)",
	"repair": "waived until #228 (repairs: boards at a breach)",
	"circuit": "waived until #228 (the generator: breakers)",
	"fuel": "waived until #228 (the generator: fuel)",
	"revive": "waived until #229 (team play: raising a downed teammate)",
}


## Whether `entry` is a rule or a waiver that names an issue.
static func is_written(entry: String) -> bool:
	if entry.begins_with(RULE):
		return true
	return entry.begins_with(WAIVER) and entry.contains("#")
