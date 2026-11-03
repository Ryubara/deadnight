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
	"DOOR":
	"rule: BotEconomy buys the doors in the profile's order; BotErrands holds a person's claim",
	"WEAPON": "rule: BotEconomy buys a wall weapon worth more than the one it would replace",
	"CRANE": "rule: BotEconomy plays the crane when a prize it lacks beats the weapon in hand",
	"TONIC":
	"rule: BotEconomy buys the hearty tonic once; a tonic with no health in it is never bought",
	"FUEL": "rule: BotErrands buys a can when the tank is under the low line; one bot at a time",
	"GRENADES": "rule: BotEconomy buys a rack's worth when the pack is under the profile's want",
	"AMMO": "rule: BotEconomy buys rounds for the guns it carries (below a magazine at once)",
	"UPGRADE": "rule: BotEconomy re-cuts the gun in hand at the bench, as many as the profile does",
}
## `WeaponCatalog.IDS`: a weapon is covered when the motor can fire it as it is built.
const WEAPONS := {
	"pistol":
	"rule: BotMotor fires any hitscan weapon inside its hit cone; BotArsenal ranks and swaps",
	"smg": "rule: BotMotor fires it in bursts of three to five (automatic)",
	"shotgun": "rule: BotMotor fires it like the pistol (the cone is for the body, not the spread)",
	"rifle": "rule: BotMotor fires it like the pistol",
	"flare_gun": "waived until #646 (a flare to draw the dead off a downed teammate)",
	"crowbar": "rule: BotMotor swings it at a target inside its reach",
	"baseball_bat": "rule: BotMotor swings it at a target inside its reach (melee)",
	"fire_axe": "rule: BotMotor swings it at a target inside its reach (melee)",
}
## The `kind` of every prompt the server's `use_target` and the machines can show.
const PROMPTS := {
	"door": "rule: BotErrands presses use at the door BotEconomy chose, after the person's claim",
	"weapon": "rule: BotErrands presses use at the wall BotEconomy chose",
	"ammo": "rule: BotErrands presses use at the locker or the wall BotEconomy chose",
	"grenades": "rule: BotErrands presses use at the rack BotEconomy chose",
	"crane": "rule: BotErrands presses use when BotEconomy chose a play",
	"crane_take": "rule: BotErrands takes the prize when it beats the weapon it would give up",
	"crane_busy":
	"rule: BotErrands does not choose the crane while a play runs (it waits for the buyer)",
	"recut": "rule: BotErrands presses use at the bench BotEconomy chose",
	"recut_done": "rule: nothing to do (BotEconomy does not choose a re-cut for a re-cut gun)",
	"recut_none": "rule: nothing to do (BotEconomy re-cuts a firearm only)",
	"tonic": "rule: BotErrands presses use at the fountain when BotEconomy chose the hearty tonic",
	"tonic_owned": "rule: nothing to do (BotEconomy buys a tonic once)",
	"repair":
	"rule: BotErrands holds use at a breach with a board down, in a break, away from people",
	"circuit": "rule: BotErrands throws a breaker the generator care wants the other way",
	"fuel":
	"rule: BotErrands presses use at a can spot while the tank is low and it is the bot's turn",
	"revive":
	"rule: BotRevive holds use beside the downed teammate it claimed, once the risk check passes",
}


## Whether `entry` is a rule or a waiver that names an issue.
static func is_written(entry: String) -> bool:
	if entry.begins_with(RULE):
		return true
	return entry.begins_with(WAIVER) and entry.contains("#")
