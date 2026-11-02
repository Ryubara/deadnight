# The firewall around the bots (bots plan, phase 1): a bot is a client, so its code never names the
# rules, the zombie simulation, the weapons server or the night server, takes nothing but a
# `ClientState`, a profile, a seed, a callable to send with and the static level, and draws its
# chance only from its own seeded stream. A source scan, so the build fails when someone reaches
# around the filter. It also holds the coverage matrix (scenario 28): every shop item, weapon and
# prompt has a rule or a written waiver.
extends GdUnitTestSuite

const BOTS_DIR := "res://gameplay/bots/"
## What bot code must never name. The one `apply` callable it is given is a `Callable`, so it
## names none of them.
const FORBIDDEN := ["GameRules", "ZombieSim", "CombatServer", "NightServer"]
## Chance only from the bot's own stream, time only from the step: the global dice, the clock and
## the engine are out. The clock may be read to *time* a think, in the client alone.
const GLOBAL_RANDOM := (
	"(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|randomize|"
	+ "rand_from_seed|shuffle)\\("
)
const CLOCK_FILE := "bot_client.gd"
const SOURCES_OF_TRUTH := [
	"res://gameplay/night/night_server.gd",
	"res://gameplay/night/use_offers.gd",
	"res://gameplay/night/machine_offers.gd",
]


func _scripts() -> Dictionary:
	var found := {}
	for file in DirAccess.get_files_at(BOTS_DIR):
		if file.ends_with(".gd"):
			found[file] = FileAccess.get_file_as_string(BOTS_DIR + file)
	return found


func test_bot_code_names_nothing_of_the_server_side() -> void:
	var scripts := _scripts()
	assert_int(scripts.size()).is_greater(8)
	for file: String in scripts:
		for word: String in FORBIDDEN:
			var found := RegEx.create_from_string("\\b%s\\b" % word).search(scripts[file])
			(
				assert_bool(found == null)
				. override_failure_message(
					"%s names %s: a bot reads only what a client is told" % [file, word]
				)
				. is_true()
			)


func test_bot_code_draws_its_chance_and_its_time_from_the_steps_it_is_given() -> void:
	var dice := RegEx.create_from_string(GLOBAL_RANDOM)
	for file: String in _scripts():
		var text: String = _scripts()[file]
		(
			assert_bool(dice.search(text) == null)
			. override_failure_message(
				"%s uses the global dice: use the bot's own RandomNumberGenerator" % file
			)
			. is_true()
		)
		if file != CLOCK_FILE:
			for word in ["Time.", "OS.", "Engine.", "Input."]:
				(
					assert_bool(text.contains(word))
					. override_failure_message(
						"%s uses %s: time is the step the bot is given" % [file, word]
					)
					. is_false()
				)


func test_the_client_takes_a_state_a_profile_a_seed_a_sender_and_the_level_and_nothing_else(
) -> void:
	var script := load(BOTS_DIR + CLOCK_FILE) as GDScript
	var names: Array[String] = []
	for method in script.get_script_method_list():
		if method["name"] == "_init":
			for arg in method["args"]:
				names.append(arg["name"])
	assert_array(names).is_equal(["p_state", "p_profile", "bot_seed", "p_send", "p_level"])


func test_every_shop_item_weapon_and_prompt_has_a_rule_or_a_written_waiver() -> void:
	assert_array(BotCoverage.SHOP_KINDS.keys()).contains_exactly_in_any_order(ShopItem.Kind.keys())
	var weapons: Array[String] = []
	for id in WeaponCatalog.IDS:
		weapons.append(String(id))
	assert_array(BotCoverage.WEAPONS.keys()).contains_exactly_in_any_order(weapons)
	for table: Dictionary in [BotCoverage.SHOP_KINDS, BotCoverage.WEAPONS, BotCoverage.PROMPTS]:
		for key: String in table:
			(
				assert_bool(BotCoverage.is_written(table[key]))
				. override_failure_message(
					"%s has neither a bot rule nor a waiver naming an issue" % key
				)
				. is_true()
			)


func test_every_prompt_the_server_can_show_is_in_the_coverage_table() -> void:
	var kinds := {}
	var pattern := RegEx.create_from_string('"kind": &"([a-z_]+)"')
	for path in SOURCES_OF_TRUTH:
		for found in pattern.search_all(FileAccess.get_file_as_string(path)):
			kinds[found.get_string(1)] = true
	assert_int(kinds.size()).is_greater(10)
	for kind: String in kinds:
		(
			assert_bool(BotCoverage.PROMPTS.has(kind))
			. override_failure_message(
				(
					"the server shows a '%s' prompt that BotCoverage does not list: add a rule or a waiver"
					% kind
				)
			)
			. is_true()
		)
	for kind: String in BotCoverage.PROMPTS:
		(
			assert_bool(kinds.has(kind))
			. override_failure_message(
				"BotCoverage lists a '%s' prompt the server no longer shows" % kind
			)
			. is_true()
		)
