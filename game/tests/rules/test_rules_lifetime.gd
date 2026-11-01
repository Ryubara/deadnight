extends GdUnitTestSuite
## The rules and the night around them are freed when their owner lets go. A signal connection
## through a lambda that uses `self` holds the object strongly, so an object that connects to its
## own parts and is then dropped lived until the program ended, and every run closed with
## "resources still in use at exit" and a list of leaked instances.


func test_the_rules_are_freed_when_the_last_reference_goes() -> void:
	var rules := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 2.0)
	var watcher: WeakRef = weakref(rules)
	rules = null
	assert_object(watcher.get_ref()).is_null()


func test_a_night_and_its_servers_are_freed_with_the_night() -> void:
	var night: Night = await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var rules_watcher: WeakRef = weakref(night.server.rules)
	var server_watcher: WeakRef = weakref(night.server)
	night.free()
	await get_tree().process_frame
	assert_object(server_watcher.get_ref()).is_null()
	assert_object(rules_watcher.get_ref()).is_null()
