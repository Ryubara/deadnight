extends GdUnitTestSuite
## Every weapon against the targets of its class (#972): the pulls and seconds a walker takes on
## rounds 1, 5, 10, 15 and 20 through the real damage path (`WeaponAudit`), the zone multipliers,
## the bodies a shot passes and the magazine. A weapon under the lowest of a band is too strong for
## its class, over the highest too weak. The bands and their reasons are in docs/design/weapons.md
## ("The audit"); a band is only changed with the reason written there.

## A scatter weapon's pellets differ by seed, so its kill is the median of a few; the rest are
## exact.
const SEEDS := 3
## A band written as 0.6 is stored as a 32-bit float: a weapon at 0.6 is on its edge, not over it.
const EPS := 0.0001


func _audited() -> Array[WeaponDef]:
	## The weapons that hurt a walker by themselves: the flare gun draws the dead and does no damage.
	var defs: Array[WeaponDef] = []
	for def in WeaponCatalog.all():
		if def.damage > 0.0 or def.splash_damage > 0.0:
			defs.append(def)
	return defs


func test_every_class_has_complete_targets() -> void:
	for class_id in WeaponClass.all():
		var targets := WeaponClassTargets.of(class_id)
		(
			assert_object(targets)
			. override_failure_message("no classes/%s.tres" % WeaponClass.key(class_id))
			. is_not_null()
		)
		assert_int(targets.weapon_class).is_equal(class_id)
		(
			assert_bool(targets.is_complete())
			. override_failure_message(WeaponClass.title(class_id))
			. is_true()
		)
		assert_str(targets.job).is_not_empty()


func test_no_weapon_kills_a_walker_in_fewer_pulls_or_slower_than_its_class_allows() -> void:
	for def in _audited():
		var targets := WeaponClassTargets.for_weapon(def)
		for round_number in WeaponClassTargets.ROUNDS:
			var recut := round_number >= WeaponClassTargets.RECUT_FROM
			var got := WeaponAudit.measure(
				def.id, round_number, WeaponAudit.CHEST, SEEDS if def.pellets > 1 else 1, recut
			)
			var pulls := targets.pulls_band(round_number)
			var seconds := targets.seconds_band(round_number)
			var tag := (
				"%s (%s) round %d%s"
				% [
					def.display_name,
					WeaponClass.title(def.weapon_class),
					round_number,
					", re-cut" if recut else ""
				]
			)
			if def.pellets == 1:
				# A scatter's pellets land where they land; every other weapon's hit is the body.
				(
					assert_str(String(got["zone"]))
					. override_failure_message(tag + ": not a body hit")
					. is_equal(String(Hitbox.BODY))
				)
			(
				assert_int(got["pulls"])
				. override_failure_message(
					(
						"%s: %d pulls to kill, the class takes %d to %d (%s)"
						% [
							tag,
							got["pulls"],
							pulls.x,
							pulls.y,
							"too strong" if got["pulls"] < pulls.x else "too weak"
						]
					)
				)
				. is_between(pulls.x, pulls.y)
			)
			(
				assert_float(got["seconds"])
				. override_failure_message(
					(
						"%s: %.2f s to kill, the class takes %.2f to %.2f (%s)"
						% [
							tag,
							got["seconds"],
							seconds.x,
							seconds.y,
							"too strong" if got["seconds"] < seconds.x else "too weak"
						]
					)
				)
				. is_between(seconds.x - 0.001, seconds.y + 0.001)
			)


func test_the_zone_multipliers_are_inside_the_class() -> void:
	for def in _audited():
		var targets := WeaponClassTargets.for_weapon(def)
		var head := def.zone_multiplier(Hitbox.HEAD)
		var limb := def.zone_multiplier(Hitbox.LIMB)
		(
			assert_float(head)
			. override_failure_message(
				(
					"%s head x%.2f, the class %.2f to %.2f"
					% [def.display_name, head, targets.head_multiplier.x, targets.head_multiplier.y]
				)
			)
			. is_between(targets.head_multiplier.x - EPS, targets.head_multiplier.y + EPS)
		)
		(
			assert_float(limb)
			. override_failure_message(
				(
					"%s limb x%.2f, the class %.2f to %.2f"
					% [def.display_name, limb, targets.limb_multiplier.x, targets.limb_multiplier.y]
				)
			)
			. is_between(targets.limb_multiplier.x - EPS, targets.limb_multiplier.y + EPS)
		)


func test_the_bodies_a_shot_passes_and_what_it_keeps_are_inside_the_class() -> void:
	for def in WeaponCatalog.all():
		var targets := WeaponClassTargets.for_weapon(def)
		var passes := def.melee_max_targets - 1 if def.is_melee() else def.penetration
		(
			assert_int(passes)
			. override_failure_message(
				(
					"%s passes %d bodies, the class %d to %d"
					% [def.display_name, passes, targets.bodies.x, targets.bodies.y]
				)
			)
			. is_between(targets.bodies.x, targets.bodies.y)
		)
		if passes > 0 and not def.is_melee():
			(
				assert_float(def.penetration_falloff)
				. override_failure_message(
					(
						"%s keeps %.2f, the class %.2f to %.2f"
						% [
							def.display_name,
							def.penetration_falloff,
							targets.kept.x,
							targets.kept.y
						]
					)
				)
				. is_between(targets.kept.x - EPS, targets.kept.y + EPS)
			)


func test_the_magazine_is_inside_the_class() -> void:
	for def in WeaponCatalog.all():
		var targets := WeaponClassTargets.for_weapon(def)
		(
			assert_int(def.magazine_size)
			. override_failure_message(
				(
					"%s holds %d, the class %d to %d"
					% [def.display_name, def.magazine_size, targets.magazine.x, targets.magazine.y]
				)
			)
			. is_between(targets.magazine.x, targets.magazine.y)
		)
