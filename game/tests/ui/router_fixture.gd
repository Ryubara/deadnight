class_name RouterFixture
extends RefCounted
## Leaves the global router empty, so a suite neither inherits nor leaves behind a screen.
##
## The router is an autoload shared by every suite in one run. A screen it still shows keeps going:
## the main menu, for one, used to grab focus when its entrance timer (`MainMenu.ITEMS_DELAY`)
## ends, in whichever test is running by then. On a slow machine that is a later test than on a
## fast one, which took the focus from the customize screen's rows (#178).


## Frees every screen on the router, top first, and waits until the router has settled.
static func clear(tree: SceneTree) -> void:
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
