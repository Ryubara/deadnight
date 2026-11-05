class_name ProfileFeed
extends RefCounted
## Tells the screens that the profile file changed under them: the account's profile was read
## (`ProfileUplink.adopt_and_tell`) after a menu was built from the older cache, as it is at every
## start-up sign-in (the menu does not wait for it). A screen that shows what the XP decides (the
## level plate, the wardrobe's locks) connects to `adopted` and reads the file again. One shared
## feed, since the read is made under the root and knows no screen; a screen that is freed leaves
## it by itself (a Callable of a freed object is dropped).

signal adopted

static var shared := ProfileFeed.new()
