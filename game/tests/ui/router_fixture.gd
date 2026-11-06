class_name RouterFixture
extends RefCounted
## Leaves the global router empty, so a suite neither inherits nor leaves behind a screen.
##
## The router is an autoload shared by every suite in one run. A screen it still shows keeps going:
## the main menu, for one, used to grab focus when its entrance timer (`MainMenu.ITEMS_DELAY`)
## ends, in whichever test is running by then. On a slow machine that is a later test than on a
## fast one, which took the focus from the customize screen's rows (#178).


## Frees every screen on the router, top first, and waits until the router has settled.
##
## A caller can be a signal's handler: a test that waits on `Night.ready_to_play` resumes inside the
## signal's emit, and a screen freed there is freed while its own night is still emitting ("Object
## was freed or unreferenced while a signal is being emitted from it", #1355). So it yields one
## frame first, which leaves every emit the caller was in; nothing in the game frees a screen like
## that (the router frees its screens between its own jobs).
static func clear(tree: SceneTree) -> void:
	await tree.process_frame
	if UIRouter.busy:
		await UIRouter.idle
	var screens := UIRouter.screens()
	screens.reverse()
	for screen in screens:
		if is_instance_valid(screen):
			screen.free()
	# The router notices an emptied stack on the next idle moment.
	await tree.process_frame
	await tree.process_frame


## Forgets the server a lobby or the join screen chose for the next night. `NightScreen` keeps it in
## statics and takes it once, when a night opens; a suite that only fills it (a lobby's Start with
## the opener stubbed) leaves it, and the next suite's solo night then tries a server that is not
## there: no `ready_to_play`, and its first test runs into the five minute limit (#1220).
static func forget_join() -> void:
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	NightScreen.join_map = ""
	NightScreen.join_as_bot = false
	# And the lobby a night would hold for its Leave button, which a night takes the same way.
	NightScreen.return_lobby = {}
	NightScreen.return_api = null
