class_name CraneOdds
extends RefCounted
## When a shopper pays for a crane play (#1322, #1331): the one rule the hosted bots
## (`BotEconomy._crane`) and the balance simulator's shoppers (`NightSim`) both read, so the crane
## costs them the same. Each play costs the same and the draw is blind, so a shopper that would
## take one prize in ten spends ten plays' points to get one and leaves the rest on the glass.

## The least share of the draw (`share`) a shopper takes for a play to be worth paying for; the
## default of `BotProfile.crane_min_odds` and of `SimSkill.crane_min_odds`.
const MIN_SHARE := 0.25


## The share of the crane's draw the shopper would take: the weight of the prizes it lacks that
## `takes` says yes to, over the weight of all it lacks. The server draws among the prizes the
## buyer lacks by these weights (`ShopItem.roll`), so this is the chance one play gives a prize the
## shopper takes; 0 when it lacks none. `owned(prize) -> bool` and `takes(prize) -> bool` are asked
## about the item's pool ids.
static func share(item: ShopItem, owned: Callable, takes: Callable) -> float:
	var total := 0.0
	var wanted := 0.0
	for prize in item.pool:
		if bool(owned.call(prize)):
			continue
		var weight := item.weight_of(prize)
		total += weight
		if bool(takes.call(prize)):
			wanted += weight
	return wanted / total if total > 0.0 else 0.0


## Whether a share of the draw is worth a play: some chance at all, and at least `min_share`.
static func worth_playing(odds: float, min_share: float) -> bool:
	return odds > 0.0 and odds >= min_share
