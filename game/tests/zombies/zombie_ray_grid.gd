class_name ZombieRayGrid
extends RefCounted
## Fires a grid of parallel rays at a posed zombie's visible mesh (`ZombieMeshProbe`) from many
## directions, and asks a shooter (`Callable(origin, dir) -> StringName`: the zone it registers, or
## empty) what each ray that touches the mesh counts as. A shot the player aimed at the body they
## see must register, and on the part they touched (head, body, limb): the stats say how often it
## does, per part. The shooter is the hit zones alone (`Hitbox`) or the whole server's trace.

## Distance behind the target the rays start from, metres.
const START := 12.0
## Compass directions (45 degrees apart) and how far above the horizon the shot comes from
## (the camera looks down on a zombie from a few metres away).
const AZIMUTHS := 8
const ELEVATIONS: Array[float] = [0.0, 15.0, 30.0]

## How many compass directions and which heights above the horizon (degrees) a run shoots from.
var azimuths := AZIMUTHS
var elevations: Array[float] = ELEVATIONS.duplicate()

## Per mesh part (`ZombieMeshProbe.Part`): rays that touched it, registered anything, and
## registered the zone that part is.
var touched := [0, 0, 0, 0]
var registered := [0, 0, 0, 0]
var matched := [0, 0, 0, 0]
## Rays that touch the mesh but whose shot a zone registers on another part, by touched part.
var wrong_zone := {}
## Rays that miss the mesh: how many, and how many of those a zone registers anyway.
var missed := 0
var spurious := 0
## The same, by the zone the shot registered as.
var spurious_by_zone := {}


## Runs the grid over the probe's current pose. `spacing` metres between rays.
func run(probe: ZombieMeshProbe, shooter: Callable, spacing: float = 0.04) -> void:
	var box := probe.bounds()
	var centre := box.get_center()
	var reach := box.size.length() * 0.5 + 0.05
	for a in azimuths:
		for elevation in elevations:
			var azimuth := TAU * float(a) / float(azimuths)
			var dir := (
				(
					Vector3(
						sin(azimuth) * cos(deg_to_rad(elevation)),
						0.0,
						cos(azimuth) * cos(deg_to_rad(elevation))
					)
					- Vector3(0.0, sin(deg_to_rad(elevation)), 0.0)
				)
				. normalized()
			)
			var side := dir.cross(Vector3.UP).normalized()
			var up := side.cross(dir).normalized()
			var steps := int(ceil(reach * 2.0 / spacing))
			for i in steps:
				for j in steps:
					var offset := (
						side * (-reach + (float(i) + 0.5) * spacing)
						+ up * (-reach + (float(j) + 0.5) * spacing)
					)
					var origin := centre + offset - dir * START
					var seen := probe.ray(origin, dir)
					if seen.is_empty():
						missed += 1
						var stray: StringName = shooter.call(origin, dir)
						if stray != &"":
							spurious += 1
							spurious_by_zone[stray] = spurious_by_zone.get(stray, 0) + 1
						continue
					_count(seen["part"], shooter.call(origin, dir))


func _count(part: int, zone: StringName) -> void:
	touched[part] += 1
	if zone == &"":
		return
	registered[part] += 1
	if zone == zone_of(part):
		matched[part] += 1
	else:
		wrong_zone[[part, zone]] = wrong_zone.get([part, zone], 0) + 1


## The zone a touched part counts as.
static func zone_of(part: int) -> StringName:
	match part:
		ZombieMeshProbe.Part.HEAD:
			return Hitbox.HEAD
		ZombieMeshProbe.Part.BODY:
			return Hitbox.BODY
	return Hitbox.LIMB


## Share (0 to 1) of the rays that touched `part` (all parts when -1) that registered anything.
func registered_rate(part: int = -1) -> float:
	return _rate(registered, part)


## Share of the rays that touched `part` (all parts when -1) that registered its own zone.
func matched_rate(part: int = -1) -> float:
	return _rate(matched, part)


func touched_count(part: int = -1) -> int:
	return _sum(touched, part)


## Share (0 to 1) of the shots a zone registers that miss the visible mesh.
func spurious_rate() -> float:
	var landed := spurious + _sum(registered, -1)
	return float(spurious) / float(landed) if landed > 0 else 0.0


func _rate(counts: Array, part: int) -> float:
	var all := _sum(touched, part)
	return float(_sum(counts, part)) / float(all) if all > 0 else 1.0


func _sum(counts: Array, part: int) -> int:
	if part >= 0:
		return counts[part]
	return counts[0] + counts[1] + counts[2] + counts[3]


## One line a log carries.
func summary() -> String:
	var names := ["head", "body", "arm", "leg"]
	var out := PackedStringArray()
	for part in 4:
		if touched[part] == 0:
			continue
		out.append(
			(
				"%s %d rays: any %.1f%%, own zone %.1f%%"
				% [
					names[part],
					touched[part],
					registered_rate(part) * 100.0,
					matched_rate(part) * 100.0
				]
			)
		)
	out.append("off the mesh by zone %s" % [spurious_by_zone])
	out.append(
		(
			"all: any %.1f%%, own zone %.1f%%, registered but off the mesh %.1f%%"
			% [registered_rate() * 100.0, matched_rate() * 100.0, spurious_rate() * 100.0]
		)
	)
	return " | ".join(out)
