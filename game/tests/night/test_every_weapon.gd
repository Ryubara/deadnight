# Every weapon the game has is reachable, and reaches the hand (docs/design/weapons.md, "The
# roster"): each definition has a source (the start, a wall buy or the prize crane); the crane's
# pool is every crane weapon and, over seeded plays, draws each one; and each weapon a play gives is
# taken, equipped, swung or fired with the real command and drawn in the Soldier's hand.
extends GdUnitTestSuite

## Plays of the crane (one seed each) that must draw every prize in its pool: the rarest has 0.5 of
## 11 of the weight (4.5%), so 400 plays miss it about once in 10^8 runs, and the seeds are fixed.
const SEEDS := 400
## Frames the Equip clip is given to bring the weapon up.
const EQUIP_FRAMES := 120
## Ticks the trigger is held to see the attack.
const ATTACK_TICKS := 12


## Where each catalogue weapon comes from: id to the list of sources (`start`, `wall`, `crane`).
func _sources(tuning: RulesTuning) -> Dictionary:
	var sources := {}
	for id: StringName in tuning.economy.start_weapons:
		_add(sources, WeaponCatalog.catalog_id(id), &"start")
	for item: ShopItem in tuning.economy.items:
		match item.kind:
			ShopItem.Kind.WEAPON:
				_add(sources, WeaponCatalog.catalog_id(item.id), &"wall")
			ShopItem.Kind.CRANE:
				for prize in item.pool:
					_add(sources, WeaponCatalog.catalog_id(prize), &"crane")
	return sources


func _add(sources: Dictionary, id: StringName, source: StringName) -> void:
	if not sources.has(id):
		sources[id] = []
	sources[id].append(source)


func _crane_pool(tuning: RulesTuning) -> Array[StringName]:
	return tuning.economy.item(&"crane_play").pool


func test_every_definition_has_a_source_and_every_source_a_definition() -> void:
	var sources := _sources(RulesFixture.tuning())
	for id in WeaponCatalog.IDS:
		(
			assert_bool(sources.has(id))
			. override_failure_message("%s is defined but no start, wall or crane gives it" % id)
			. is_true()
		)
	for id: StringName in sources:
		(
			assert_bool(id in WeaponCatalog.IDS)
			. override_failure_message("%s is given but is not in the catalogue" % id)
			. is_true()
		)


func test_the_crane_holds_every_weapon_the_shop_and_the_start_do_not_give() -> void:
	# What no start or wall gives must come from the crane; and a weapon already owned at the start
	# is never a prize, since the crane never gives a weapon the buyer has.
	var tuning := RulesFixture.tuning()
	var sources := _sources(tuning)
	for id in WeaponCatalog.IDS:
		if &"start" in sources[id] or &"wall" in sources[id]:
			continue
		assert_array(sources[id]).contains([&"crane"])
	for prize in _crane_pool(tuning):
		assert_bool(WeaponCatalog.catalog_id(prize) in WeaponCatalog.IDS).is_true()
	assert_int(tuning.economy.item(&"crane_play").weights().size()).is_equal(
		_crane_pool(tuning).size()
	)


func test_the_bat_and_the_axe_come_only_from_the_crane() -> void:
	# The maintainer's rule (#461): never at the start, never on a wall, and so a strong blow
	# (not a free spare) for the slot they take.
	var sources := _sources(RulesFixture.tuning())
	for id: StringName in [&"baseball_bat", &"fire_axe"]:
		assert_array(sources[id]).is_equal([&"crane"])


func test_seeded_plays_draw_every_prize_of_the_crane() -> void:
	var tuning := RulesFixture.steady_crane_tuning()
	var drawn := {}
	for seed_value in SEEDS:
		var rules := RulesFixture.make_rules(1, seed_value, tuning)
		rules.apply(RulesAction.start())
		rules.apply(RulesAction.grant_points(1, 5000))
		# Empty hands: the revolver and the crowbar are prizes too, once they are given up.
		(rules.players[1] as PlayerState).weapons.clear()
		var ready := RulesFixture.first(RulesFixture.play_crane(rules, 1), &"crane_prize_ready")
		drawn[ready["weapon"]] = true
	for prize in _crane_pool(tuning):
		(
			assert_bool(drawn.has(prize))
			. override_failure_message("%s was never drawn" % prize)
			. is_true()
		)


func _start() -> Night:
	var tuning := RulesFixture.steady_crane_tuning()
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.grant_points(1, 50000))
	NightFixture.run(night, 2)
	return night


func _animation(night: Night) -> PlayerAnimation:
	return night.player().get_node("AnimationTree") as PlayerAnimation


## Waits for the Equip clip to bring the weapon up.
func _wait_for_the_weapon(animation: PlayerAnimation) -> void:
	for _i in EQUIP_FRAMES:
		if animation.weapon() != null and animation.weapon().visible:
			return
		await get_tree().process_frame


## Holds the trigger for a few ticks and reports whether the server answered with a shot of
## `weapon_id` and the Soldier played the attack clip of its class.
func _attack(night: Night, weapon_id: StringName) -> Dictionary:
	var result := {"shot": false, "clip": false}
	var seen: Array[Dictionary] = []
	var listener := func(event: Dictionary) -> void: seen.append(event)
	night.state.event_received.connect(listener)
	var animation := _animation(night)
	var attack := (
		&"Swing_Melee"
		if WeaponCatalog.get_def(weapon_id).is_melee()
		else StringName("Fire_%s" % animation.weapon_class)
	)
	var target := night.state.position() + Vector3(0.0, 0.0, -3.0)
	var command := NightFixture.shoot_at(night, target)
	for _i in ATTACK_TICKS:
		NightFixture.run(night, 1, command)
		result["clip"] = result["clip"] or animation.action_clip == attack
		await get_tree().process_frame
	night.state.event_received.disconnect(listener)
	result["shot"] = seen.any(
		func(e: Dictionary) -> bool:
			return e["type"] == &"shot_fired" and e["weapon_id"] == weapon_id
	)
	return result


## Takes the weapon in hand the way the game does and checks the view: its hold's model is in the
## hand, visible, and the attack button makes the server's shot and the class's clip.
func _check_in_hand(night: Night, weapon_id: StringName) -> void:
	night.server.combat.apply(CombatAction.equip(1, weapon_id))
	NightFixture.run(night, 3)
	var animation := _animation(night)
	await _wait_for_the_weapon(animation)
	var tag := "%s: " % weapon_id
	(
		assert_str(String(night.state.me()["weapon"]))
		. override_failure_message(tag + "not equipped")
		. is_equal(String(weapon_id))
	)
	var hold := WeaponHoldMap.hold_for(weapon_id)
	assert_object(hold).override_failure_message(tag + "no hold file with a model").is_not_null()
	var weapon := animation.weapon()
	assert_object(weapon).override_failure_message(tag + "the hand is empty").is_not_null()
	assert_bool(weapon.visible).override_failure_message(tag + "hidden").is_true()
	assert_str(weapon.scene_file_path).override_failure_message(tag + "another model").is_equal(
		hold.scene
	)
	var attack := await _attack(night, weapon_id)
	assert_bool(attack["shot"]).override_failure_message(tag + "no shot or blow").is_true()
	assert_bool(attack["clip"]).override_failure_message(tag + "no attack clip").is_true()
	# Let the cooldown and the clip pass before the next weapon.
	NightFixture.run(night, 90)


func test_a_crane_prize_is_taken_equipped_attacked_and_drawn_in_the_hand() -> void:
	# A player holds two weapons (#410): each prize replaces the one in hand, so they are checked
	# one after the other, each from a real play.
	var night := await _start()
	for _i in 4:
		night.server.buy(1, &"crane_play")
		NightFixture.run(night, 300)
		var prize := WeaponCatalog.catalog_id(night.server.rules.crane.weapon)
		night.server.rules.apply(RulesAction.crane_take(1, night.state.me()["weapon"]))
		NightFixture.run(night, 3)
		assert_array(night.server.combat.carried(1)).has_size(WeaponCatalog.CARRY_LIMIT)
		assert_array(night.server.combat.carried(1)).contains([prize])
		await _check_in_hand(night, prize)
	night.queue_free()


func test_every_weapon_is_equipped_attacked_and_drawn_in_the_hand() -> void:
	# Every catalogue weapon, given the way the wall and the crane give it (the combat server's
	# `give_weapon`, replacing the one in hand once both hands are full).
	var night := await _start()
	for id in WeaponCatalog.IDS:
		night.server.combat.apply(CombatAction.give_weapon(1, id))
		NightFixture.run(night, 2)
		assert_array(night.server.combat.carried(1)).contains([id])
		await _check_in_hand(night, id)
	night.queue_free()
