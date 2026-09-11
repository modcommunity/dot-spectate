extends Node

## Exercises dot-spectate with no camera, no world and no transport.
##
## Positions, teams and liveness are dictionaries — the seam a real game fills — so what
## is checked here is what this addon promises: that a server's force-camera policy is
## enforced on the machine that decides, that the death-cam chain hands over rather than
## stopping, that a spectator whose target leaves is moved rather than left looking at
## nothing, and that a delayed camera really does show the past.
##
## [codeblock]
## godot --headless --path . res://examples/spectate_selftest.tscn
## [/codeblock]

const SECTIONS := 9
const CHECKS := 71

const RATE := 64

var _passed := 0
var _failed := 0
var _section_count := 0

var _teams: Dictionary = {}
var _alive: Dictionary = {}
var _poses: Dictionary = {}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-spectate self-test")
	_line("")

	_test_rules()
	_test_view()
	_test_history()
	_test_policy()
	_test_cycling()
	_test_death_chain()
	_test_retargeting()
	_test_cameras()
	_test_delay_and_wire()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function, and the counter is satisfied because the section had already
	# announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _world(names: Dictionary) -> void:
	_teams.clear()
	_alive.clear()
	_poses.clear()
	for key: Variant in names.keys():
		_teams[key] = int(names[key])
		_alive[key] = true
		_poses[key] = Transform3D(Basis.IDENTITY, Vector3.ZERO)


func _manager() -> DotSpectatorManager:
	var m := DotSpectatorManager.new()
	m.participants_fn = func() -> PackedStringArray:
		var out := PackedStringArray()
		var ids: Array = _teams.keys()
		ids.sort()
		for id: Variant in ids:
			out.append(str(id))
		return out
	m.team_fn = func(key: String) -> int: return int(_teams.get(key, 0))
	m.alive_fn = func(key: String) -> bool: return bool(_alive.get(key, false))
	m.pose_fn = func(key: String) -> Transform3D:
		return _poses.get(key, Transform3D.IDENTITY)
	add_child(m)
	return m


# --- Rules ------------------------------------------------------------------

func _test_rules() -> void:
	_section("rules")

	var rules := DotSpectatorRules.new()
	_check(rules.validate().ok, "the defaults validate")
	_check(
		rules.force_camera == 1,
		"and restrict the camera to your own side, which is what a competitive server "
		+ "wants and a demo does not"
	)
	_check(not rules.allow_roaming, "with roaming off")
	_check(rules.forces_first_person(), "which forces first person")

	rules.allow_roaming = true
	_check(
		not rules.validate().ok,
		"roaming with a restricted camera is refused: a roaming camera goes anywhere, "
		+ "which is the whole thing the restriction is for"
	)

	rules.force_camera = 0
	_check(rules.validate().ok, "and is fine once the camera is unrestricted")

	rules.delay_ticks = 200
	rules.history_ticks = 100
	_check(
		not rules.validate().ok,
		"a delay longer than the history is refused, or the camera silently shows the "
		+ "oldest frame it still has"
	)


func _test_view() -> void:
	_section("a view")

	var v := DotSpectatorView.new("ada")
	_check(not v.is_watching(), "a fresh view is not watching")
	_check(not v.is_timed(), "and is not timed")

	v.mode = DotSpectatorView.Mode.CHASE
	_check(v.is_watching(), "a mode makes it one")
	_check(v.follows_target(), "and a chase follows a target")

	v.mode = DotSpectatorView.Mode.ROAMING
	_check(
		not v.follows_target(),
		"and roaming does not, which is what decides whether losing a target matters"
	)

	v.mode = DotSpectatorView.Mode.FIRST_PERSON
	v.target = "bob"
	v.until_tick = 500
	var round_trip := DotSpectatorView.new("ada")
	round_trip.apply_wire(v.to_wire())
	_check(
		round_trip.mode == v.mode and round_trip.target == "bob",
		"and it round-trips through the wire"
	)


func _test_history() -> void:
	_section("history")

	var h := DotSpectatorHistory.new(4)
	for t in range(10):
		h.record(t, {"ada": Transform3D(Basis.IDENTITY, Vector3(float(t), 0, 0))})

	_check(h.size() == 4, "the ring is bounded, because a history that grows with the "
		+ "round is a memory leak with a plausible name")

	var got := h.sample(9, 2, "ada")
	_check(bool(got[1]), "a sample two ticks back is found")
	_check(
		is_equal_approx((got[0] as Transform3D).origin.x, 7.0),
		"and it is where they were, not where they are"
	)

	var missing := h.sample(9, 2, "nobody")
	_check(
		not bool(missing[1]),
		"somebody with no history reports not-found rather than the origin — a camera "
		+ "at the world origin looking down X is the 'sky in every direction' bug"
	)

	var early := h.sample(6, 100, "ada")
	_check(
		bool(early[1]),
		"asking further back than the history goes gives the oldest frame rather than "
		+ "nothing, which is what the first seconds of a round look like"
	)

	h.clear()
	_check(h.size() == 0, "and it can be emptied")


# --- Policy -----------------------------------------------------------------

func _test_policy() -> void:
	_section("who may watch whom")

	_world({"ada": 1, "bob": 1, "cid": 2})
	var m := _manager()
	var _s := m.setup()

	_alive["ada"] = false

	_check(
		not m.may_watch("ada", "ada").ok,
		"nobody watches themselves"
	)
	_check(m.may_watch("ada", "bob").ok, "a dead player may watch their own side")
	var refused := m.may_watch("ada", "cid")
	_check(
		not refused.ok,
		"and not the other side, on a server with force_camera 1"
	)
	_check(refused.code() == DotError.CODE_FORBIDDEN, "with a forbidden code")

	m.rules.force_camera = 0
	_check(m.may_watch("ada", "cid").ok, "unrestricted lets them")

	m.rules.force_camera = 2
	_check(
		not m.may_watch("ada", "bob").ok,
		"and 'nobody' means nobody, including their own side"
	)
	m.rules.force_camera = 1

	_check(
		not m.may_watch("bob", "ada").ok,
		"a living player is playing rather than watching"
	)
	m.rules.allow_while_alive = true
	_alive["ada"] = true
	_check(
		m.may_watch("bob", "ada").ok,
		"unless the server allows it, which is what a replay viewer is"
	)
	m.rules.allow_while_alive = false

	_alive["ada"] = false
	_alive["bob"] = false
	_check(
		not m.may_watch("ada", "bob").ok,
		"a dead target is skipped by default, because a camera on a corpse is not a "
		+ "camera on the game"
	)
	m.rules.cycle_includes_dead = true
	_check(m.may_watch("ada", "bob").ok, "unless the server includes them")
	m.rules.cycle_includes_dead = false
	_alive["bob"] = true

	m.target_filter = func(_viewer: String, target: String) -> bool:
		return target != "bob"
	_check(
		not m.may_watch("ada", "bob").ok,
		"and a game's own extra rule is consulted"
	)
	m.target_filter = Callable()

	# The mode the policy actually gives, against the one that was asked for.
	var _w := m.watch("ada", "bob", DotSpectatorView.Mode.CHASE)
	_check(
		m.view("ada").mode == DotSpectatorView.Mode.FIRST_PERSON,
		"'own side only' also forces first person, because a chase camera behind a "
		+ "team-mate sees round corners they cannot"
	)

	m.queue_free()


func _test_cycling() -> void:
	_section("cycling")

	_world({"ada": 1, "bob": 1, "cid": 1, "dee": 2})
	_alive["ada"] = false
	var m := _manager()
	var _s := m.setup()

	var list := m.targets_for("ada")
	_check(list.size() == 2, "the list is everybody they may watch")
	_check(not list.has("ada"), "and not themselves")
	_check(not list.has("dee"), "and not the other side")
	_check(
		list[0] == "bob" and list[1] == "cid",
		"in a stable order, so pressing next twice moves two places rather than going "
		+ "round in a circle of one"
	)

	var first := m.next_target("ada")
	_check(first.ok, "next picks somebody")
	_check(m.view("ada").target == "bob", "the first of them")
	var _n2 := m.next_target("ada")
	_check(m.view("ada").target == "cid", "and next moves on")
	var _n3 := m.next_target("ada")
	_check(m.view("ada").target == "bob", "and wraps")
	var _p := m.previous_target("ada")
	_check(m.view("ada").target == "cid", "and goes back")

	_alive["bob"] = false
	_alive["cid"] = false
	var none := m.next_target("ada")
	_check(
		not none.ok,
		"with nobody left to watch it says so rather than pointing at a corpse"
	)

	m.queue_free()


func _test_death_chain() -> void:
	_section("the death camera chain")

	_world({"ada": 1, "bob": 1, "cid": 2})
	var m := _manager()
	m.rules.death_cam_ticks = RATE
	m.rules.freeze_cam_ticks = RATE
	var _s := m.setup()

	var modes: Array[int] = []
	m.view_changed.connect(func(_k: String, mode: int, _t: String) -> void:
		modes.append(mode))

	_alive["ada"] = false
	m.on_death("ada", Vector3(5, 0, 5), "cid", 0)
	_check(
		m.view("ada").mode == DotSpectatorView.Mode.DEATH_CAM,
		"dying starts the death camera"
	)

	for t in range(1, RATE):
		m.advance(t)
	_check(
		m.view("ada").mode == DotSpectatorView.Mode.DEATH_CAM,
		"which holds for as long as it says"
	)

	m.advance(RATE)
	_check(
		m.view("ada").mode == DotSpectatorView.Mode.FREEZE_CAM,
		"then hands over to the freeze camera"
	)
	_check(m.view("ada").target == "cid", "on whoever did it")

	for t in range(RATE + 1, RATE + 10):
		m.advance(t)
	_check(
		m.view("ada").target == "cid",
		"and STAYS on them, even though a killer is on the other side and every "
		+ "restrictive camera policy forbids watching that side — a timed camera is "
		+ "the server's own choice and the retarget rule must not touch it"
	)

	for t in range(RATE + 10, 3 * RATE):
		m.advance(t)
	_check(
		m.view("ada").mode == DotSpectatorView.Mode.FIRST_PERSON,
		"and then hands over to a real target — the hand-over every game that writes "
		+ "this itself gets wrong, leaving the player looking at their killer until "
		+ "they respawn"
	)
	_check(m.view("ada").target == "bob", "somebody on their own side")

	m.on_spawn("ada")
	_alive["ada"] = true
	_check(not m.is_spectating("ada"), "respawning stops it")

	# With no killer and no freeze camera, it goes straight to a target.
	m.rules.death_cam_ticks = 0
	m.rules.freeze_cam_ticks = 0
	_alive["bob"] = false
	m.on_death("bob", Vector3.ZERO, "", 100)
	_check(
		m.view("bob").mode == DotSpectatorView.Mode.FIRST_PERSON,
		"and with both cameras turned off it goes straight to somebody"
	)

	# And with nobody left to watch it does not sit in a mode that shows nothing.
	_world({"cid": 2})
	m.on_death("cid", Vector3.ZERO, "", 200)
	_check(
		m.view("cid").mode == DotSpectatorView.Mode.FIXED,
		"with nobody at all it falls back to a fixed camera rather than a first-person "
		+ "view of nobody"
	)

	m.queue_free()


func _test_retargeting() -> void:
	_section("retargeting")

	_world({"ada": 1, "bob": 1, "cid": 1})
	_alive["ada"] = false
	var m := _manager()
	var _s := m.setup()

	var moves: Array[String] = []
	m.retargeted.connect(
		func(_k: String, _from: String, to: String, _r: StringName) -> void:
			moves.append(to)
	)

	var _w := m.watch("ada", "bob")
	_check(m.view("ada").target == "bob", "watching somebody")

	_alive["bob"] = false
	m.advance(1)
	_check(m.view("ada").target == "cid", "a target who dies is replaced")
	_check(moves.size() == 1, "and it is announced")

	# The roster drops them first, which is the documented order: the replacement is
	# chosen from participants_fn, so reporting the departure before removing the player
	# picks the player who just left.
	_teams.erase("cid")
	_alive.erase("cid")
	m.on_leave("cid")
	_check(
		m.view("ada").target != "cid",
		"a target who leaves is replaced too"
	)

	m.rules.auto_retarget = false
	_world({"ada": 1, "bob": 1, "cid": 1})
	_alive["ada"] = false
	var _w2 := m.watch("ada", "bob")
	_alive["bob"] = false
	m.advance(2)
	_check(
		m.view("ada").target == "bob",
		"and a server that turns it off keeps the camera where it was put"
	)

	m.queue_free()


func _test_cameras() -> void:
	_section("cameras")

	_world({"ada": 1, "bob": 1})
	_alive["ada"] = false
	_poses["bob"] = Transform3D(Basis.IDENTITY, Vector3(10, 2, 0))
	var m := _manager()
	m.rules.force_camera = 0
	m.rules.allow_roaming = true
	var _s := m.setup()

	var _w := m.watch("ada", "bob", DotSpectatorView.Mode.FIRST_PERSON)
	_check(
		m.camera_of("ada").origin.is_equal_approx(Vector3(10, 2, 0)),
		"first person is the target's eye transform"
	)

	var _c := m.watch("ada", "bob", DotSpectatorView.Mode.CHASE)
	var chase := m.camera_of("ada")
	_check(
		chase.origin.distance_to(Vector3(10, 2, 0)) > 1.0,
		"chase is behind them"
	)
	_check(
		chase.origin.y > 2.0,
		"and above, so it is not derived from a capsule origin and sitting in the floor"
	)

	var flat := m.camera_2d_of("ada")
	_check(
		(flat[0] as Vector2).is_equal_approx(Vector2(chase.origin.x, chase.origin.z)),
		"and the 2D form is the same camera on the XZ plane"
	)

	var _r := m.set_mode("ada", DotSpectatorView.Mode.ROAMING)
	_check(m.view("ada").mode == DotSpectatorView.Mode.ROAMING, "roaming is allowed here")
	var _mv := m.move_free("ada", Vector3(1, 2, 3), Basis.IDENTITY)
	_check(
		m.camera_of("ada").origin.is_equal_approx(Vector3(1, 2, 3)),
		"and the game drives it, because what a free camera's controls are is not this "
		+ "addon's decision"
	)

	m.rules.allow_roaming = false
	var refused := m.set_mode("ada", DotSpectatorView.Mode.ROAMING)
	_check(not refused.ok, "and a server that forbids roaming refuses it")

	m.fixed_cameras = [Transform3D(Basis.IDENTITY, Vector3(0, 20, 0))]
	var _f := m.set_mode("ada", DotSpectatorView.Mode.FIXED)
	_check(
		m.camera_of("ada").origin.is_equal_approx(Vector3(0, 20, 0)),
		"a fixed camera is one the map placed"
	)

	m.on_death("ada", Vector3(4, 0, 4), "bob", 0)
	var death := m.camera_of("ada")
	_check(
		death.origin.y > 4.0 * 0.0 + 1.0,
		"and the death camera is above where they fell rather than inside them"
	)

	m.queue_free()


func _test_delay_and_wire() -> void:
	_section("delay, and the wire")

	_world({"ada": 1, "bob": 1})
	_alive["ada"] = false
	var m := _manager()
	m.rules.delay_ticks = 30
	m.rules.history_ticks = 64
	var res := m.setup()
	_check(res.ok, "a delayed server sets up")

	var _w := m.watch("ada", "bob")

	for t in range(0, 60):
		_poses["bob"] = Transform3D(Basis.IDENTITY, Vector3(float(t), 0, 0))
		m.advance(t)

	var seen := m.camera_of("ada").origin.x
	_check(
		is_equal_approx(seen, 29.0),
		"and the camera shows where they were thirty ticks ago (%.0f), not where they "
		+ "are now (59) — which is the whole reason a spectator is not a live "
		+ "intelligence feed" % seen
	)

	# The mirror.
	var mirror := DotSpectatorManager.new()
	mirror.authoritative = false
	add_child(mirror)
	var _ms := mirror.setup()
	mirror.apply_wire(m.to_wire("ada"))
	_check(
		mirror.view("ada").target == "bob"
		and mirror.view("ada").mode == m.view("ada").mode,
		"a view travels to a client"
	)
	_check(
		not mirror.watch("ada", "bob").ok,
		"and a mirror decides nothing — it is told"
	)

	var before := mirror.history.size()
	mirror.advance(9999)
	_check(
		mirror.history.size() == before,
		"and records no history of its own, because the delay is the server's decision"
	)

	var lines := m.describe_lines()
	_check(lines.size() > 1, "and it describes itself")

	m.queue_free()
	mirror.queue_free()


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
