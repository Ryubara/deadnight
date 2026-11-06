class_name BotCraneWait
extends RefCounted
## What a bot does while its own crane play runs (#1322): it stands at the glass through the dig and
## presses use on the prize when it is held out and it is one the bot would take (a prize it would
## not take is left to fade). A bot the dig, or a teammate's walk, has pushed off the glass walks
## back to its stand first: the prize is held out for the buyer who is in reach of it
## (`NightTuning.spot_reach`), and a bot that stood where the card was not up left it to fade
## whatever it was dealt.

var _shop: BotShop
var _economy: BotEconomy


func _init(shop: BotShop, economy: BotEconomy) -> void:
	_shop = shop
	_economy = economy


## Sets the intent and returns true while the bot's own play is in its dig or its grab; false when
## the crane is anyone else's or free.
func run(intent: BotIntent, me: Dictionary, frame: Dictionary, me_id: int) -> bool:
	var crane: Dictionary = frame.get("crane", {})
	if crane.get("buyer", -1) != me_id:
		return false
	var stage: int = crane.get("stage", CraneState.Stage.READY)
	if stage != CraneState.Stage.SPIN and stage != CraneState.Stage.GRAB:
		return false
	var prompt: Dictionary = me.get("prompt", {})
	intent.note = "crane"
	intent.keep_weapon = true
	var kind: StringName = prompt.get("kind", &"")
	if kind != &"crane_take" and kind != &"crane_busy":
		_back_to_the_glass(intent, me, int(crane.get("spot", 0)))
	if kind == &"crane_take":
		var view := BotEconomy.View.new()
		view.arms = me.get("arms", {})
		view.held = me.get("weapon", &"")
		view.zombie_health = _economy.zombie_health(int(frame.get("round", 1)))
		if BotEconomy.worth_taking(view, WeaponCatalog.catalog_id(prompt.get("weapon", &""))):
			intent.use = true
	return true


## Walks to the stand of the crane at `spot` nearest to the bot, and faces the glass from it.
func _back_to_the_glass(intent: BotIntent, me: Dictionary, spot: int) -> void:
	var here: Vector3 = me["pos"]
	var stand := Vector3.INF
	for place in _shop.spots_of(&"crane_play"):
		if place.get("crane_spot", 0) != spot:
			continue
		if stand == Vector3.INF or _flat(here, place["position"]) < _flat(here, stand):
			stand = place["position"]
	if stand == Vector3.INF:
		return
	intent.goal = stand
	intent.goal_radius = BotErrands.ARRIVE
	intent.run = false
	intent.look_yaw = _shop.thing_yaw(&"crane_play", &"crane", stand, here)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
