extends "res://examples/spectate_selftest_base.gd"

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
##
## [b]One engine error on every green run, on purpose:[/b] "DotSpectatorManager.on_death on
## a mirror". The last section asserts that a mirror REFUSES to start the death chain, and
## the refusal is a [code]push_error[/code] because it is a wiring mistake.

const SECTIONS := 13
const CHECKS := 131


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	await _run()


func _run() -> void:
	_line("dot-spectate self-test")
	_line("(one engine error on purpose: \"on_death on a mirror\", which the last section asserts is refused)")
	_line("")

	_test_rules()
	_test_view()
	_test_history()
	_test_policy()
	_test_cycling()
	_test_death_chain()
	_test_retargeting()
	_test_cameras()
	await _test_cameras_in_a_level()
	_test_delay_and_wire()
	_test_host()
	_test_host_subclass()

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


## The one section with a level: a wall behind the watched player and a low roof over a
## body. Both checks are armed by asking the same question with no level first.
func _test_cameras_in_a_level() -> void:
	_section("chase and death cameras stay out of the level")

	_world({"ada": 1, "bob": 1, "cy": 1})
	_alive["ada"] = false
	_alive["cy"] = false
	_poses["bob"] = Transform3D(Basis.IDENTITY, Vector3(10, 2, 0))
	var m := _manager()
	m.rules.force_camera = 0
	var _s := m.setup()

	var wall := _box(Vector3(10, 2, 2.2), Vector3(10, 6, 0.4))
	var roof := _box(Vector3(30, 1.8, 0), Vector3(6, 0.4, 6))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state

	var _c := m.watch("ada", "bob", DotSpectatorView.Mode.CHASE)
	var through := m.camera_of("ada").origin
	_check(through.z > 2.0, "armed: with no level the chase camera is behind the wall (z %.2f)" % through.z)

	m.camera_world = get_viewport().world_3d
	var chase := m.camera_of("ada").origin
	_check(chase.z < 2.0 - 0.15 and not DotCameraProbe.is_inside(space, chase, 0.15, 1), "with one it is in front of the wall, clear of it (z %.2f)" % chase.z)

	m.on_death("cy", Vector3(30, 0, 0), "bob", 0)
	m.camera_world = null
	var raw := m.camera_of("cy").origin
	_check(DotCameraProbe.is_inside(space, raw, 0.15, 1), "armed: with no level the death camera is inside the roof (y %.2f)" % raw.y)
	m.camera_world = get_viewport().world_3d
	var death := m.camera_of("cy")
	_check(death.origin.y < 1.6 and not DotCameraProbe.is_inside(space, death.origin, 0.15, 1), "with one it is under the roof, clear of it (y %.2f)" % death.origin.y)
	_check((-death.basis.z).dot((Vector3(10, 2, 0) - death.origin).normalized()) > 0.99, "and still looking at the killer")

	# Killed through a gap by somebody the wall now hides: looking at them would be a frame
	# of the wall. The camera stands back on the open side and looks at the body.
	m.on_death("cy", Vector3(10, 0, 4), "bob", 0)
	m.camera_world = null
	var blind := m.camera_of("cy")
	var into_wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(blind.origin, Vector3(10, 2, 0), 1))
	_check(not into_wall.is_empty(), "armed: with no level the death camera looks at the killer through the wall")
	m.camera_world = get_viewport().world_3d
	var back := m.camera_of("cy")
	var to_body := (Vector3(10, 0.5, 4) - back.origin).normalized()
	_check(back.origin.z > 4.5 and not DotCameraProbe.is_inside(space, back.origin, 0.15, 1),
		"with one, the killer behind the wall, it stands back from the body on the open side (z %.2f)" % back.origin.z)
	_check((-back.basis.z).dot(to_body) > 0.99 and space.intersect_ray(PhysicsRayQueryParameters3D.create(back.origin, Vector3(10, 0.5, 4), 1)).is_empty(),
		"and looks at the body, with nothing in the way")

	var _again := m.camera_of("ada")
	_check(m._probes.size() == 2, "one probe per viewer, so two viewers do not ease each other")

	wall.queue_free()
	roof.queue_free()
	m.queue_free()


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child(body)
	return body


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
		("and the camera shows where they were thirty ticks ago (%.0f), not where they "
		+ "are now (59) — which is the whole reason a spectator is not a live "
		+ "intelligence feed") % seen
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
		"and a mirror with no delay records no history, because nothing samples it"
	)

	# The death camera, through the wire. Its place is the one thing in a view that is not
	# a player the mirror already draws, and a wire without it drew every death camera on
	# every client from the world origin.
	_world({"ada": 1, "bob": 2})
	var server := _manager()
	server.rules.death_cam_ticks = 64
	var _ss := server.setup()
	server.on_death("ada", Vector3(40, 0, -12), "bob", 0)
	var client := _manager()
	client.authoritative = false
	var _cs := client.setup()
	client.apply_wire(server.to_wire("ada"))
	_check(
		client.view("ada").death_position == Vector3(40, 0, -12),
		"a death camera's place travels to a client (it had %s)"
			% client.view("ada").death_position
	)
	var eye := client.camera_of("ada").origin
	_check(
		is_equal_approx(eye.x, 40.0) and is_equal_approx(eye.z, -12.0),
		"and the mirror draws it where they fell, not at the origin (%s)" % eye
	)
	var old_wire := server.to_wire("ada")
	(old_wire["v"] as Dictionary).erase("d")
	client.apply_wire(old_wire)
	_check(
		client.view("ada").death_position == Vector3(40, 0, -12),
		"and a view from an older build, with no place in it, keeps the one it had"
	)

	# A chain started on a mirror is a death camera nothing ends, because a mirror's
	# advance runs no timers. Refused rather than started — the error it pushes on
	# purpose is named in the suite's header.
	client.on_death("bob", Vector3(1, 0, 1), "ada", 0)
	client.advance(10000)
	_check(
		not client.is_spectating("bob"),
		"a mirror refuses to start the death chain itself, rather than holding it for ever"
	)

	# The delay, on a mirror. The camera is computed where it is drawn, and with a delay it
	# samples only the history — so a mirror that recorded none drew every followed camera
	# at identity the moment the server turned the delay on.
	_world({"ada": 1, "bob": 1})
	_alive["ada"] = false
	var delayed := _manager()
	delayed.authoritative = false
	delayed.rules.delay_ticks = 10
	var _ds := delayed.setup()
	delayed.apply_wire({"k": "ada", "v": {"m": int(DotSpectatorView.Mode.FIRST_PERSON), "t": "bob"}})
	for t in range(0, 30):
		_poses["bob"] = Transform3D(Basis.IDENTITY, Vector3(float(t), 0, 0))
		delayed.advance(t)
	var shown := delayed.camera_of("ada").origin.x
	_check(
		is_equal_approx(shown, 19.0),
		"and a delayed mirror shows the past too, from a history of its own (%.0f; live is 29)"
			% shown
	)

	server.queue_free()
	client.queue_free()
	delayed.queue_free()

	var lines := m.describe_lines()
	_check(lines.size() > 1, "and it describes itself")

	m.queue_free()
	mirror.queue_free()


class _Host:
	extends DotSpectatorHost
	var teams: Dictionary = {}
	var alive: Dictionary = {}
	var tick: int = 0

	func _participants() -> PackedStringArray:
		var out := PackedStringArray(teams.keys())
		out.sort()
		return out

	func _team_of(key: String) -> int:
		return int(teams.get(key, 0))

	func _is_alive(key: String) -> bool:
		return bool(alive.get(key, false))

	func _pose_of(key: String) -> Transform3D:
		return eye_pose(Vector3(float(teams.get(key, 0)), 0.0, 0.0), 0.0, 90.0)

	func _current_tick() -> int:
		return tick

	func _tune_rules(r: DotSpectatorRules) -> DotSpectatorRules:
		r.cycle_includes_dead = false
		return r


## A game keyed by StringName that wraps the viewer calls: what a per-game spectate script is.
class _LoggingHost:
	extends _Host
	var watched: Array = []

	func watch(key: String, target: String) -> DotResult:
		watched.append(key)
		return super.watch(key, target)

	func stop(key: String) -> void:
		watched.append("stop " + key)
		super.stop(key)


## Stands in for a DotTouchButtons button, which takes a touch press in _input when it hits.
class _TouchTaker extends Node:
	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed:
			get_viewport().set_input_as_handled()


func _test_host_subclass() -> void:
	_section("a game subclass of the host")
	var h := _LoggingHost.new()
	h.teams = {"a": 1, "b": 1}
	h.alive = {"a": false, "b": true}
	add_child(h)
	_check(h.setup().ok, "the subclass sets up")
	var sn_viewer: StringName = &"a"
	var sn_target: StringName = &"b"
	_check(h.watch(sn_viewer, sn_target).ok, "StringName keys are accepted by the String-keyed calls")
	_check(h.watching("a") == "b" and h.watched == ["a"], "an override sees the call and super does the work")
	h.stop(sn_viewer)
	_check(not h.is_spectating("a") and h.watched == ["a", "stop a"], "stop goes through the override too")
	h.queue_free()


func _test_host() -> void:
	_section("the shared host")
	var h := _Host.new()
	h.tick_rate = 10
	h.death_cam_seconds = 1.0
	h.freeze_cam_seconds = 2.0
	h.prefer_own_side = true
	h.teams = {"a": 1, "b": 1, "c": 2}
	h.alive = {"a": true, "b": true, "c": true}
	_check(h.watch("a", "b").error.code == DotError.CODE_STATE, "a call before setup fails with CODE_STATE, not a null deref")
	_check(h.camera_for("a") == Transform3D.IDENTITY, "no camera before setup")
	add_child(h)
	_check(h.setup().ok, "setup succeeds")
	_check(h.manager.rules.death_cam_ticks == 10 and h.manager.rules.freeze_cam_ticks == 20, "seconds become ticks at the tick rate")
	_check(not h.manager.rules.cycle_includes_dead, "the _tune_rules hook ran")
	_check(h.camera_for("a") == Transform3D.IDENTITY and not h.is_spectating("a"), "a player is not a spectator")
	var pose := h.eye_pose(Vector3.ZERO, 0.0, 0.0)
	_check(is_equal_approx(pose.origin.y, 1.6), "eye_pose lifts by eye_height")

	var seen: Array = []
	h.view_changed.connect(func(k: String) -> void: seen.append(k))
	h.alive["a"] = false
	h.death("a", Vector3.ZERO, "c")
	_check(h.is_spectating("a") and h.mode_of("a") == int(DotSpectatorView.Mode.DEATH_CAM), "death starts the death cam from the host's tick")
	h.tick = 10
	h.advance_live()
	_check(h.mode_of("a") == int(DotSpectatorView.Mode.FREEZE_CAM), "advance_live hands the death cam to the freeze cam")
	h.tick = 30
	h.advance_live()
	_check(h.watching("a") == "b", "the chain ends on a team-mate: own side preferred over the first key")
	_check(not seen.is_empty(), "view_changed is re-emitted by the host")
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	var emu := InputEventMouseButton.new()
	emu.pressed = true
	emu.button_index = MOUSE_BUTTON_LEFT
	emu.device = InputEvent.DEVICE_ID_EMULATION
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	_check(DotSpectatorHost.is_next_press(tap) and DotSpectatorHost.is_next_press(click), "a touch and a left click both mean next")
	_check(not DotSpectatorHost.is_next_press(emu), "the mouse a touch emulates is not a second press")
	h.tap_key = "a"
	var before := h.watching("a")
	h._unhandled_input(tap)
	_check(h.watching("a") != before, "a synthetic tap advances the target")
	var taker := _TouchTaker.new()
	add_child(taker)
	before = h.watching("a")
	get_viewport().push_input(tap)
	_check(h.watching("a") == before, "a touch an on-screen button handled in _input does not step")
	taker.free()
	get_viewport().push_input(tap)
	_check(h.watching("a") != before, "the same touch with no button under it steps through the viewport")
	h.tap_key = ""
	var tp := DotPlatform.touch_override
	DotPlatform.touch_override = 1
	var spectating_line := h.line_for("a")
	DotPlatform.touch_override = tp
	_check(spectating_line.contains("tap: next") and not spectating_line.contains("click"), "line_for says tap: next on touch while watching")

	var cycled := h.step("a", 0)
	_check(cycled.ok or cycled.error.code == DotError.CODE_FORBIDDEN, "step 0 cycles the camera or says why not")
	_check(h.step("zzz", 1).error.code == DotError.CODE_STATE, "step refuses a viewer who is playing")
	var roam := h.toggle_roam("a")
	_check(roam.ok and h.is_roaming("a"), "toggle_roam enters free roam when allowed")
	_check(h.line_for("a").contains("free camera"), "line_for names the roam camera")
	var was_touch := DotPlatform.touch_override
	DotPlatform.touch_override = 1
	var tl := h.line_for("a")
	DotPlatform.touch_override = 0
	var dl := h.line_for("a")
	DotPlatform.touch_override = was_touch
	_check(tl != "" and not tl.contains("click") and not tl.contains("F5") and not tl.contains(h.roam_key + ":"), "line_for on touch names no keys")
	_check(dl.contains("free camera") and dl.contains(h.roam_key), "line_for on desktop keeps the key hints")
	_check(h.line_for("zzz") == "", "line_for is empty for a player on any platform")
	h.manager.rules.allow_roaming = false
	_check(h.toggle_roam("a").error.code == DotError.CODE_FORBIDDEN, "roam refused with CODE_FORBIDDEN when off")

	h.manager.rules.allow_roaming = true
	_check(not h.guard_roam and h.can_roam("zzz") == h.manager.can_roam("zzz"), "an unguarded host answers can_roam as the manager does")
	h.guard_roam = true
	_check(h.toggle_roam("zzz").error.code == DotError.CODE_STATE, "guard_roam refuses a playing viewer with CODE_STATE")
	_check(not h.can_roam("zzz") and h.can_roam("a"), "guard_roam: can_roam is false for a player, true for a spectator")
	h.authoritative = false
	_check(h.toggle_roam("a").error.code == DotError.CODE_STATE, "guard_roam refuses a mirror with CODE_STATE")
	h.authoritative = true
	_check(h.toggle_roam("a").ok, "guard_roam lets a spectator on an authority roam")
	h.guard_roam = false
	_check(h.can_roam("zzz") == h.manager.can_roam("zzz"), "without guard_roam can_roam is the manager's")

	h.alive["a"] = true
	h.spawned("a")
	_check(not h.is_spectating("a"), "spawned returns the viewer to playing")

	h.alive["b"] = false
	h.death("b", Vector3.ZERO, "")
	h.advance_client(h.tick)
	h.alive["b"] = true
	h.advance_client(h.tick)
	_check(not h.is_spectating("b"), "a client sees the respawn from liveness alone")

	h.set_force_camera(9)
	_check(h.manager.rules.force_camera == 2, "set_force_camera clamps")
	h.authoritative = false
	_check(h.step("a", 1).error.code == DotError.CODE_STATE, "a mirror host refuses step")
	h.queue_free()
