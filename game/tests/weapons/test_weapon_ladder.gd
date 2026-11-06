extends GdUnitTestSuite
## The order of the weapons across and inside the classes (#972): what the bands of one class cannot
## say. Worth is `WeaponWorth.of(def)` with no health: damage a second on the body at point blank,
## reloads included, the number the bots and the balance simulator pick weapons by. The rules and
## their reasons are in docs/design/weapons.md ("The audit").


func _raw(def: WeaponDef) -> float:
	return WeaponWorth.of(def, 0.0)


func _firearms() -> Array[WeaponDef]:
	## Weapons that hurt by their own hit: the flare gun hurts no one, and the specials work by a
	## blast or a freeze that this number does not see.
	var defs: Array[WeaponDef] = []
	for def in WeaponCatalog.all():
		if not def.is_melee() and def.weapon_class != WeaponClass.Id.SPECIAL:
			defs.append(def)
	return defs


func test_a_weapon_a_wall_sells_is_never_worth_more_than_a_box_weapon_of_its_class() -> void:
	# The wall tier's rule (#858) is that a wall sells the weaker guns: inside a class, the older
	# gun on the wall must not out-damage the gun only the box gives.
	for older in _firearms():
		if older.wall_tier > WallTier.MAX_WALL:
			continue
		for newer in _firearms():
			if newer.weapon_class != older.weapon_class or newer.wall_tier <= WallTier.MAX_WALL:
				continue
			(
				assert_float(_raw(older))
				. override_failure_message(
					(
						"%s (a wall's, %.0f a second) out-damages %s (the box's, %.0f): too strong for a wall"
						% [older.display_name, _raw(older), newer.display_name, _raw(newer)]
					)
				)
				. is_less_equal(_raw(newer))
			)


func test_a_melee_weapon_never_out_damages_the_best_gun_the_box_gives() -> void:
	# A melee weapon never runs dry and needs no reload, so it is strong on the axes this number does
	# not see; it must not also be the highest on this one (#910: "too overpowered").
	var best := 0.0
	for def in _firearms():
		if def.wall_tier > WallTier.MAX_WALL:
			best = maxf(best, _raw(def))
	for def in WeaponCatalog.all():
		if def.is_melee():
			(
				assert_float(_raw(def))
				. override_failure_message(
					(
						"%s does %.0f a second, the best gun of the box %.0f: too strong for a melee weapon"
						% [def.display_name, _raw(def), best]
					)
				)
				. is_less_equal(best)
			)


func test_a_carried_gun_is_worth_more_than_the_free_blow() -> void:
	# The free blow (V) is in every player's hands; a weapon that does less than it is not worth a
	# slot. The starter pistol is the weakest gun by design (#898).
	var blow := _raw(WeaponCatalog.quick_melee())
	for def in _firearms():
		if def.weapon_class == WeaponClass.Id.STARTER_PISTOL:
			continue
		(
			assert_float(_raw(def))
			. override_failure_message(
				(
					"%s does %.0f a second, the free blow %.0f: too weak for a carried gun"
					% [def.display_name, _raw(def), blow]
				)
			)
			. is_greater_equal(blow)
		)


func test_the_light_machine_gun_sustains_more_than_any_rifle_or_smg() -> void:
	for lmg in _firearms():
		if lmg.weapon_class != WeaponClass.Id.LMG:
			continue
		for other in _firearms():
			if other.weapon_class in [WeaponClass.Id.RIFLE, WeaponClass.Id.SMG]:
				(
					assert_float(_raw(lmg))
					. override_failure_message(
						(
							"%s does %.0f a second, %s %.0f: too weak for the heavy gun"
							% [lmg.display_name, _raw(lmg), other.display_name, _raw(other)]
						)
					)
					. is_greater(_raw(other))
				)
