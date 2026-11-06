extends GdUnitTestSuite
## Every weapon's penetration, stated and held (#972): a line of the dead in front of the shooter,
## through the real combat server and the rules' own zombies. A hitscan shot goes through
## `penetration` bodies after the first and keeps `penetration_falloff` of its damage at each one;
## a melee blow hits `melee_max_targets` bodies; a scatter's pellets never pierce. The table is
## docs/design/weapons.md ("Penetration").

const LINE := 8
const GAP := 1.5
## Melee reach is short: the line stands close.
const MELEE_GAP := 0.4
const MELEE_FIRST := 0.7


func _line(def: WeaponDef) -> Dictionary:
	## Fires `def` once down a line of LINE walkers and returns the damage each took, nearest first.
	var tuning := RulesFixture.tuning()
	tuning.specials.every = 0
	var rules := RulesFixture.make_rules(1, 1234, tuning)
	# The server first: it learns of every zombie from the rules' spawn events.
	var server := CombatServer.new(WeaponCatalog.all(), rules, Callable(), WeaponsFixture.SEED)
	rules.round_number = 4
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 90.0)
	var ids: Array[int] = []
	for id in rules.zombie_ids():
		if ids.size() < LINE and rules.zombie_type(id) == &"walker":
			ids.append(id)
		else:
			RulesFixture.kill(rules, 1, id)
	assert_int(ids.size()).is_equal(LINE)
	server.apply(CombatAction.give_weapon(1, def.id))
	var shooter := Vector3(0.0, 1.1, 0.0)
	var positions := {}
	for i in LINE:
		var depth := (MELEE_FIRST + MELEE_GAP * i) if def.is_melee() else (4.0 + GAP * i)
		positions[ids[i]] = Vector3(0.0, 0.0, -depth)
	WeaponsFixture.step(server, positions, 2)
	var events := server.apply(
		CombatAction.fire(1, 1, shooter, Vector3(0.0, 0.0, -1.0), shooter, server.now)
	)
	var damage: Array[float] = []
	for id in ids:
		var hit := 0.0
		for event in WeaponsFixture.of(events, &"damage_dealt"):
			if event["target_id"] == id:
				hit += event["damage"]
		damage.append(hit)
	return {"damage": damage, "events": events}


func _bodies_hit(damage: Array[float]) -> int:
	var count := 0
	for hit in damage:
		if hit > 0.0:
			count += 1
	return count


func test_a_single_ray_passes_the_stated_bodies_and_keeps_the_stated_damage() -> void:
	for def in WeaponCatalog.all():
		if not def.is_hitscan() or def.pellets > 1:
			continue
		var damage: Array[float] = _line(def)["damage"]
		(
			assert_int(_bodies_hit(damage))
			. override_failure_message(
				(
					"%s: %d bodies hit in a line of %d, it passes %d after the first"
					% [def.display_name, _bodies_hit(damage), LINE, def.penetration]
				)
			)
			. is_equal(1 + def.penetration)
		)
		for i in range(1, 1 + def.penetration):
			(
				assert_float(damage[i])
				. override_failure_message(
					"%s: body %d keeps the wrong share of the first hit" % [def.display_name, i + 1]
				)
				. is_equal_approx(damage[0] * pow(def.penetration_falloff, i), 0.05)
			)


func test_a_scatter_stops_in_the_first_body() -> void:
	# Pellets that pierced would multiply a close shotgun's damage by the line: none does.
	for def in WeaponCatalog.all():
		if def.pellets <= 1:
			continue
		assert_int(def.penetration).override_failure_message(def.display_name).is_equal(0)
		var damage: Array[float] = _line(def)["damage"]
		assert_float(damage[0]).override_failure_message(def.display_name).is_greater(0.0)
		assert_float(damage[LINE - 1]).override_failure_message(def.display_name).is_equal(0.0)


func test_a_melee_blow_hits_as_many_bodies_as_the_weapon_says() -> void:
	var weapons: Array[WeaponDef] = []
	for def in WeaponCatalog.all():
		if def.is_melee():
			weapons.append(def)
	for def in weapons:
		var damage: Array[float] = _line(def)["damage"]
		(
			assert_int(_bodies_hit(damage))
			. override_failure_message(
				(
					"%s: %d bodies hit, the blow hits %d"
					% [def.display_name, _bodies_hit(damage), def.melee_max_targets]
				)
			)
			. is_equal(def.melee_max_targets)
		)
		# Each body after the first takes the blow weaker, as a shot through a line does.
		for i in range(1, def.melee_max_targets):
			(
				assert_float(damage[i])
				. override_failure_message("%s: body %d of the blow" % [def.display_name, i + 1])
				. is_equal_approx(damage[0] * pow(def.penetration_falloff, i), 0.05)
			)
