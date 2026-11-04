class_name PointSteps
extends RefCounted
## The one rule that keeps every score and price a multiple of `STEP` (5): 5, 15, 20, 25, 50, never
## 31 or 34 (Deadnight #916). Every number a multiplier, a share or a fraction makes passes through
## here, once, after the last multiplier, on the server (`GameRules._award`, `ShopCounter`):
##
## - an **award** (a hit, a kill, a repair, a bonus, a refund) rounds to the nearest step, halves
##   up, and never drops below one step: a hit worth 1.2 points still pays 5;
## - a **price** (a part purchase of ammunition, fuel or grenades, a price with a rise) rounds up
##   to the next step, so a part purchase never costs less than its share, and 0 stays 0 (nothing
##   sold);
## - a **loss** (the penalty for being down) rounds down to the step, so it never takes more than
##   the fraction said, and may be 0.
##
## The tuning's own numbers are multiples of 5 too (`@export_range(..., 5)`), so these only act on
## what a multiplier made; a table test (`test_point_steps.gd`) holds both.

const STEP := 5


## Points earned for the unrounded `amount`: the nearest step, at least one step when there is any.
static func award(amount: float) -> int:
	if amount <= 0.0:
		return 0
	return maxi(roundi(amount / STEP), 1) * STEP


## Points charged for the unrounded `amount`: up to the next step; 0 stays 0.
static func price(amount: float) -> int:
	if amount <= 0.0:
		return 0
	return ceili(amount / STEP - 0.0001) * STEP


## Points taken off for the unrounded `amount`: down to the step, 0 when under one.
static func loss(amount: float) -> int:
	if amount <= 0.0:
		return 0
	return floori(amount / STEP + 0.0001) * STEP


static func is_step(points: int) -> bool:
	return points % STEP == 0
