extends GdUnitTestSuite
## A suite that counts objects across frames settles first (Deadnight #1138). Sounds an earlier
## suite left playing end during the count, each one freeing its playback in a frame of its own: a
## count that falls by as many as the sounds that end, which fails a test that bounds it both ways
## (#1134) and hides a leak of the same size from one that bounds it upwards. `QuietCount.settle`
## stops them and waits for the mixer. A source scan, so the next count test that skips it fails
## here.

const SUITES_DIR := "res://tests/"
const COUNTS := "Performance.OBJECT_COUNT"
const SETTLES := "QuietCount.settle"
## An await of a frame, a physics frame or a timer: objects counted across one are counted across
## the engine's own motion.
const WAITS := "(process_frame|physics_frame|\\.timeout)"
## This scan names what it looks for in strings.
const SELF := "test_object_count_settle.gd"


## Whether `source` reads the object count after waiting for frames and never settles.
static func counts_unsettled(source: String) -> bool:
	if not source.contains(COUNTS) or source.contains(SETTLES):
		return false
	return RegEx.create_from_string("await\\s[^\\n]*" + WAITS).search(source) != null


func _suites(dir: String = SUITES_DIR) -> Array[String]:
	var found: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_suites(dir + sub + "/"))
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("test_") and file.ends_with(".gd") and file != SELF:
			found.append(dir + file)
	return found


func test_the_scan_tells_a_count_across_frames_from_one_that_settles_or_waits_for_none() -> void:
	var counts := "var n := Performance.get_monitor(%s)\n" % COUNTS
	var frames := "\tawait get_tree().process_frame\n"
	assert_bool(counts_unsettled(counts + frames)).is_true()
	(
		assert_bool(counts_unsettled(counts + "\tawait get_tree().create_timer(1.0).timeout\n"))
		. is_true()
	)
	(
		assert_bool(counts_unsettled("\tawait QuietCount.settle(get_tree())\n" + counts + frames))
		. is_false()
	)
	assert_bool(counts_unsettled(counts)).is_false()
	assert_bool(counts_unsettled(frames)).is_false()


func test_every_suite_that_counts_objects_across_frames_settles_first() -> void:
	var suites := _suites()
	assert_int(suites.size()).is_greater(100)
	var counting := 0
	var unsettled: Array[String] = []
	for path in suites:
		var source := FileAccess.get_file_as_string(path)
		if source.contains(COUNTS):
			counting += 1
		if counts_unsettled(source):
			unsettled.append(path)
	# The scan must find the suites it exists for.
	assert_int(counting).is_greater_equal(7)
	(
		assert_array(unsettled)
		. override_failure_message(
			"counts objects across frames without `QuietCount.settle` (#1138): %s" % [unsettled]
		)
		. is_empty()
	)
