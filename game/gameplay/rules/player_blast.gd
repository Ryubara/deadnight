class_name PlayerBlast
extends RefCounted
## What an explosion does to a player's health, as pure functions: the one rule every blast that can
## hurt a player shares (the grenade's, the ray gun's splash on its shooter), so the curve is built
## once. The maintainer set the shape: the whole blow in the hand and very close, less with
## distance, nothing at the blast's edge.
##
## The damage is a share of the player's `max_health`, so "full" always means down, from full health
## or not, and a tonic that raises the bar does not make a grenade at the feet any safer. Inside
## `full_radius` the share is 1; from there to `edge_radius` it eases out as `(1 - t)^2`, t being
## how far across that span the player stands. A grenade a few metres off hurts (3 m from the blast:
## half the health, 5 m: a fifth) and only close ones down.

## How fast the share falls away across the span (2: a square, steep at first, long at the foot).
const EASE_POWER := 2.0


## The share (0 to 1) of a player's health a blast takes at `distance` from them. 0 for a distance
## that is not a finite number (a blast that is nowhere hurts nothing).
static func share(distance: float, full_radius: float, edge_radius: float) -> float:
	if not is_finite(distance):
		return 0.0
	if distance <= full_radius:
		return 1.0
	if distance >= edge_radius:
		return 0.0
	var across := (distance - full_radius) / maxf(edge_radius - full_radius, 0.001)
	return pow(1.0 - across, EASE_POWER)


## The health a blast takes from a player with `max_health` at `distance`, times `scale` (1 for a
## blast of the full rule, the ray gun's 0.25 for its own shooter).
static func damage(
	max_health: float, distance: float, full_radius: float, edge_radius: float, scale: float = 1.0
) -> float:
	return max_health * share(distance, full_radius, edge_radius) * scale


## The distance at which a blast takes only `at_share` of a player's health: the inverse of `share`,
## for a bot choosing where it may throw. Beyond `edge_radius` for a share of 0, inside
## `full_radius` for a share of 1.
static func distance_for(at_share: float, full_radius: float, edge_radius: float) -> float:
	if at_share >= 1.0:
		return full_radius
	if at_share <= 0.0:
		return edge_radius
	return full_radius + (1.0 - pow(at_share, 1.0 / EASE_POWER)) * (edge_radius - full_radius)
