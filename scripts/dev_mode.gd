class_name DevMode
extends RefCounted
# Developer mode, as in the other games: ` (~) asks for the passcode (111),
# right once per run; after that ` opens and closes the developer panel
# (scripts/ui/dev_panel.gd). While it is on, campaign progress lives in its
# own save, user://dev_campaign.json, copied from the player's save when the
# mode comes on: nothing done here (cheats or play) ever touches the real
# progress, and turning the mode off goes back to it untouched.
# Tests (-s) keep their own save either way (CampaignSave.path).

const CODE := "111"
const DEV_PATH := "user://dev_campaign.json"

static var auth := false # the passcode was entered this run
static var active := false # the developer save is in use
# Switches the game reads (only while active).
static var unlock_all := false # every campaign level open
static var all_genes := false # designer: every gene, rule piece and organ open
static var free_budget := false # designer: no gene budget limit
static var free_iv := false # interventions cost nothing and never cool down
static var no_tutorial := false # levels start without their guide
static var perf := false # frame / simulation timings on screen
static var _forced: Array = [] # stars the next level finish reports instead


static func on(flag: bool) -> bool:
	return active and flag


# Turn the developer save on (a fresh copy of the player's progress) or off
# (back to the player's own save, as it was).
static func set_active(on_: bool) -> void:
	if on_ == active:
		return
	active = on_
	if on_:
		copy_real()
	else:
		unlock_all = false
		all_genes = false
		free_budget = false
		free_iv = false
		no_tutorial = false
		CampaignSave.load_save()


# The developer save starts over from the player's progress.
static func copy_real() -> void:
	if CampaignSave.path() == CampaignSave.TEST_PATH:
		CampaignSave.load_save() # tests keep to their own file
		return
	var real := ProjectSettings.globalize_path(CampaignSave.REAL_PATH)
	var dev := ProjectSettings.globalize_path(DEV_PATH)
	if FileAccess.file_exists(CampaignSave.REAL_PATH):
		DirAccess.copy_absolute(real, dev)
	elif FileAccess.file_exists(DEV_PATH):
		DirAccess.remove_absolute(dev)
	CampaignSave.load_save()


# The next level finish reports these stars (立即通关 / 立即失败).
static func force_stars(stars: Array) -> void:
	_forced = stars.duplicate()


static func take_stars(got: Array) -> Array:
	if _forced.is_empty() or not active:
		return got
	var s := _forced
	_forced = []
	return s
