# Every prompt the game can put on the interaction card is shown in full: no ellipsis, no line wider
# than its room, no line taller than the card holds, and the card stays on the screen and clear of
# the other parts. The prompts are the ones the night makes (`NightServer.use_target` dictionaries
# through `NightHudBinding.show_prompt`, over the shipped tuning and weapons), the reasons a
# purchase or a crane take is refused, and the card's own kinds, at desktop and phone-landscape
# windows (#308).
extends GdUnitTestSuite

const Layout := preload("res://tests/ui/test_hud_layout.gd")
## Desktop 720p and 1080p, then phone landscape: a 19.5:9 phone, a 20:9 one and a 16:9 one.
const WINDOWS: Array[Vector2] = [
	Vector2(1280, 720),
	Vector2(1920, 1080),
	Vector2(844, 390),
	Vector2(915, 412),
	Vector2(667, 375),
]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
const ELLIPSIS := "…"
## Rounds at which prices are read: the first, and a deep night where a price has risen.
const ROUNDS: Array[int] = [1, 100]
## A name at the name limit, as a revive prompt would carry it.
const LONG_NAME := "Maximiliana Rosewood"

var _night: Night


func before_test() -> void:
	UIMotion.reduced = false
	HudFonts.reset()


func after_test() -> void:
	HudFonts.reset()
	UIMotion.reduced = false
	if _night != null:
		_night.queue_free()
		_night = null


## Every `use_target` dictionary the shipped night can produce, named for the report.
func _uses(tuning: RulesTuning) -> Array[Dictionary]:
	var uses: Array[Dictionary] = []
	var economy := tuning.economy
	for item in economy.items:
		for round_number in ROUNDS:
			var price := item.price_at(round_number)
			match item.kind:
				ShopItem.Kind.DOOR:
					uses.append(
						_use("door %s r%d" % [item.id, round_number], &"door", item.id, price)
					)
				ShopItem.Kind.FUEL:
					for space in [item.amount, 7.0, 0.0]:
						var offer := item.fuel_offer(round_number, space)
						var use := _use("fuel %s r%d" % [space, round_number], &"fuel", item.id)
						use["item"] = item.id
						use["price"] = offer["price"]
						use["units"] = offer["units"]
						uses.append(use)
	uses.append(_use("door unknown", &"door", &"door_nowhere", 99999))
	uses.append(_use("repair", &"repair", &"breach_a"))
	var crane := economy.item(&"crane_play")
	for round_number in ROUNDS:
		uses.append(
			_use("crane r%d" % round_number, &"crane", crane.id, crane.price_at(round_number))
		)
	uses.append(_use("crane own", &"crane_busy", crane.id, 0, {"buyer": 1}))
	uses.append(_use("crane other", &"crane_busy", crane.id, 0, {"buyer": 2}))
	for weapon_id in WeaponCatalog.IDS:
		var shop_id := StringName(WeaponCatalog.SHOP_PREFIX + String(weapon_id))
		var wall := economy.item(shop_id)
		var wall_price := wall.price_at(ROUNDS[-1]) if wall != null else 99999
		uses.append(
			_use("wall %s" % weapon_id, &"weapon", shop_id, wall_price, {"weapon": weapon_id})
		)
		uses.append(_use("take %s" % weapon_id, &"crane_take", crane.id, 0, {"weapon": weapon_id}))
		var ammo := economy.ammo_item_for(weapon_id)
		if ammo == null:
			continue
		for round_number in ROUNDS:
			for rounds in [int(ammo.amount), 3]:
				var price := ammo.ammo_price(round_number, rounds)
				uses.append(
					_use(
						"ammo %s %d r%d" % [weapon_id, rounds, round_number],
						&"ammo",
						ammo.id,
						price,
						{"weapon": weapon_id, "rounds": rounds}
					)
				)
	for circuit in tuning.fuel.circuit_drain:
		for on in [true, false]:
			uses.append(_use("circuit %s %s" % [circuit, on], &"circuit", circuit, 0, {"on": on}))
	return uses


func _use(label: String, kind: StringName, id: StringName, price := 0, more := {}) -> Dictionary:
	var use := {"label": label, "kind": kind, "id": id, "price": price}
	use.merge(more)
	return use


## What the card's own kinds say with a long name and the biggest price, apart from the night.
func _direct_kinds() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for kind in HudPrompt.DETAILS:
		list.append({"label": "direct %s" % kind, "kind": kind, "text": LONG_NAME, "cost": 99999})
	return list


## The card as it stands: every visible text, and a sentence for each way it is cut.
func _labels(node: Node, found: Array[Label]) -> void:
	if node is Label and (node as Label).is_visible_in_tree() and (node as Label).text != "":
		found.append(node as Label)
	for child in node.get_children():
		_labels(child, found)


## How one label is clipped, or "" when all its text shows.
func _clip_of(label: Label) -> String:
	if label.text.contains(ELLIPSIS):
		return "has an ellipsis"
	var font := label.get_theme_font(&"font")
	var size_px := label.get_theme_font_size(&"font_size")
	var room := label.size.x
	var lines := 1
	var widest := HudStyle.text_width(font, label.text, size_px)
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
		flags |= TextServer.BREAK_ADAPTIVE
		var block := font.get_multiline_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, room, size_px, -1, flags
		)
		widest = block.x
		lines = label.get_line_count()
	if widest > room + 0.5:
		return "is %.0f wide in %.0f" % [widest, room]
	if label.get_visible_line_count() < label.get_line_count():
		return "shows %d of %d lines" % [label.get_visible_line_count(), label.get_line_count()]
	if label.size.y + 0.5 < font.get_height(size_px) * lines:
		return "is %.0f tall for %d lines of %.0f" % [label.size.y, lines, font.get_height(size_px)]
	return ""


## What is wrong with the card now: clipped text, texts that are not the prompt's, and a card off
## the screen, squashed, or over another part.
func _problems(hud: Hud, canvas: Vector2, expected: Array[String]) -> Array[String]:
	var found: Array[String] = []
	var card := hud.prompt
	if not card.visible:
		return ["the card is not shown"]
	var labels: Array[Label] = []
	_labels(card, labels)
	var shown := {}
	for label in labels:
		shown[label.text] = true
		var clip := _clip_of(label)
		if clip != "":
			found.append('"%s" %s' % [label.text, clip])
		if not card.get_global_rect().encloses(label.get_global_rect()):
			found.append('"%s" leaves the card' % label.text)
	for text in expected:
		if text != "" and not shown.has(text):
			found.append('"%s" is not on the card' % text)
	if not Rect2(Vector2.ZERO, canvas).encloses(card.get_global_rect()):
		found.append("the card %s leaves the canvas %s" % [card.get_global_rect(), canvas])
	if card.size.y + 0.5 < card.get_combined_minimum_size().y:
		found.append(
			"the card is %.0f tall, needs %.0f" % [card.size.y, card.get_combined_minimum_size().y]
		)
	for part in hud.boxed_parts():
		if part != card and part.is_visible_in_tree():
			if card.get_global_rect().intersects(part.get_global_rect()):
				found.append("the card overlaps %s" % part.name)
	return found


func _canvases() -> Array[Vector2]:
	var seen := {}
	var list: Array[Vector2] = []
	for window in WINDOWS:
		for ui_scale in UI_SCALES:
			var canvas := Layout.canvas_for(window, ui_scale)
			var key := Vector2i(canvas.round())
			if not seen.has(key):
				seen[key] = true
				list.append(canvas)
	return list


## A HUD on `canvas` with the cards the prompt sits between (health, points, ammo) showing.
func _hud_on(canvas: Vector2) -> Hud:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	host.add_child(hud)
	hud.state.set_player_name(1, "Ruby")
	hud.state.set_health(100.0, 100.0)
	hud.state.set_ammo(30, 150, "Double-Barrel Coach Gun")
	hud.state.apply_event({"type": &"points_changed", "player_id": 1, "total": 99999, "delta": 0})
	hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
	return hud


func _expected(hud: Hud) -> Array[String]:
	var prompt := hud.state.prompt
	var detail := str(prompt.get("detail", ""))
	var texts: Array[String] = [str(prompt["label"]).to_upper()]
	texts.append(
		detail.to_upper() if detail != "" else str(HudPrompt.DETAILS.get(prompt["kind"], ""))
	)
	return texts


## The binding hears a client of its own, so the running night's frames do not clear the card.
func _walk(face: StringName) -> void:
	if not HudFonts.apply(face):
		return
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	var tuning := _night.server.rules.tuning
	var uses := _uses(tuning)
	var direct := _direct_kinds()
	var problems: Array[String] = []
	var checked := 0
	for canvas in _canvases():
		var hud := _hud_on(canvas)
		var binding := NightHudBinding.new(hud, ClientState.new(), _night.server)
		for use in uses:
			binding.show_prompt(use)
			await await_idle_frame()
			await await_idle_frame()
			checked += 1
			for problem in _problems(hud, canvas, _expected(hud)):
				problems.append("%s, canvas %s, %s: %s" % [face, canvas, use["label"], problem])
		for item in direct:
			hud.state.set_prompt(item["kind"], item["text"], item["cost"])
			await await_idle_frame()
			await await_idle_frame()
			checked += 1
			for problem in _problems(hud, canvas, _expected(hud)):
				problems.append("%s, canvas %s, %s: %s" % [face, canvas, item["label"], problem])
		# The price line says why a purchase or a take was refused, over the longest prompt.
		hud.state.set_prompt(&"buy_weapon", LONG_NAME, 99999, "Two barrels, one very loud night")
		for result in GameRules.BuyResult.values():
			if result == GameRules.BuyResult.OK:
				continue
			hud.state.apply_event({"type": &"purchase_denied", "player_id": 1, "result": result})
			await await_idle_frame()
			await await_idle_frame()
			checked += 1
			var say := [HudPrompt.DENIED_TEXT.get(result, "NOT POSSIBLE")]
			var expected: Array[String] = [str(say[0])]
			for problem in _problems(hud, canvas, expected):
				problems.append("%s, canvas %s, denied %d: %s" % [face, canvas, result, problem])
		for reason in HudPrompt.TAKE_DENIED_TEXT:
			hud.state.apply_event({"type": &"crane_take_denied", "player_id": 1, "reason": reason})
			await await_idle_frame()
			await await_idle_frame()
			checked += 1
			var expected: Array[String] = [HudPrompt.TAKE_DENIED_TEXT[reason]]
			for problem in _problems(hud, canvas, expected):
				problems.append(
					"%s, canvas %s, take denied %s: %s" % [face, canvas, reason, problem]
				)
		hud.get_parent().queue_free()
	HudFonts.reset()
	assert_int(checked).is_greater(500)
	assert_array(problems).is_empty()


func test_every_prompt_shows_in_full_at_desktop_and_phone_sizes() -> void:
	await _walk(HudFonts.FALLBACK)


func test_every_prompt_shows_in_full_in_the_marquee_typeface_when_its_files_exist() -> void:
	await _walk(HudFonts.MARQUEE)
