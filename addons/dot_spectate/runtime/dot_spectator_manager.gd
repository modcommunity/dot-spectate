class_name DotSpectatorManager
extends Node

## Who is watching whom, what they are allowed to watch, and where the camera is.
##
## [codeblock]
## var spectate := DotSpectatorManager.new()
## spectate.participants_fn = roster.keys
## spectate.team_fn = match_node.team_of
## spectate.alive_fn = world.is_alive
## spectate.pose_fn = world.eye_transform_of
## add_child(spectate)
##
## # when somebody dies:
## spectate.on_death("ada", where_they_fell, "bob", tick)
##
## # once a tick, and then once a frame for the camera:
## spectate.advance(tick)
## camera.global_transform = spectate.camera_of("ada")
## [/codeblock]
##
## [b]It computes a transform and never touches a camera.[/b] Same rule as dot-ui's "no
## art": a [Camera3D] belongs to the game's rig, a 2D game has a [Camera2D], and a
## replay viewer has neither. [method camera_of] returns a [Transform3D];
## [method camera_2d_of] returns a position and an angle for a game on the XZ plane.
##
## [b]The interesting half is not the camera.[/b] Almost everything here exists because
## somebody used a spectator view to cheat, and the two features that matter are the
## force-camera policy and the delay.

## A viewer changed what they are looking at.
signal view_changed(key: String, mode: int, target: String)

## A viewer's target went away and they were moved to somebody else.
signal retargeted(key: String, from: String, to: String, reason: StringName)

## A timed camera — the death cam, the freeze cam — ran out.
signal timed_out(key: String, mode: int)

@export var rules: DotSpectatorRules = null

@export var authoritative: bool = true

## Cameras a map placed, for [constant DotSpectatorView.Mode.FIXED] and for the
## "nobody may watch" policy, which has to put the camera somewhere.
@export var fixed_cameras: Array[Transform3D] = []

## Everybody who could be watched. [code]() -> PackedStringArray[/code]
var participants_fn: Callable = Callable()

## [code](key: String) -> int[/code]. Zero is no team.
var team_fn: Callable = Callable()

## [code](key: String) -> bool[/code]
var alive_fn: Callable = Callable()

## Where somebody's eyes are. [code](key: String) -> Transform3D[/code]
##
## The eye transform rather than the body's: a chase camera derived from a capsule's
## origin sits in the floor, and a first-person camera derived from one is at the knees.
var pose_fn: Callable = Callable()

## An extra rule about who may be watched. [code](viewer, target) -> bool[/code]
var target_filter: Callable = Callable()

var history: DotSpectatorHistory = null

var _views: Dictionary = {}
var _tick: int = 0


func _init() -> void:
	if rules == null:
		rules = DotSpectatorRules.new()
	history = DotSpectatorHistory.new(rules.history_ticks)


func setup() -> DotResult:
	if rules == null:
		rules = DotSpectatorRules.new()
	var res := rules.validate()
	if not res.ok:
		return res.wrap("spectator rules")

	# The history has to outlast the delay or the camera asks for a tick that has been
	# thrown away and silently shows the oldest one it still has — which looks like a
	# camera that lags, not like a setting that is wrong.
	history.set_capacity(maxi(rules.history_ticks, rules.delay_ticks + 2))
	return DotResult.success(null)


# --- Views -------------------------------------------------------------------

func view(key: String) -> DotSpectatorView:
	var v: DotSpectatorView = _views.get(key, null)
	if v == null:
		v = DotSpectatorView.new(key)
		_views[key] = v
	return v


func is_spectating(key: String) -> bool:
	var v: DotSpectatorView = _views.get(key, null)
	return v != null and v.is_watching()


func viewers() -> PackedStringArray:
	var out := PackedStringArray()
	var ids: Array = _views.keys()
	ids.sort()
	for id: Variant in ids:
		if (_views[id] as DotSpectatorView).is_watching():
			out.append(str(id))
	return out


func forget(key: String) -> void:
	_views.erase(key)


## Whether a viewer is allowed to watch anybody at all, and why not when they are not.
func may_spectate(key: String) -> DotResult:
	if rules.forbids_everything():
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "This server does not allow spectating."
		)

	var alive := bool(alive_fn.call(key)) if alive_fn.is_valid() else false
	if alive and not rules.allow_while_alive:
		return DotResult.fail(
			DotError.CODE_STATE, "A living player is playing, not watching."
		)
	if not alive and not rules.allow_while_dead:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "Dead players may not watch on this server."
		)

	var team := int(team_fn.call(key)) if team_fn.is_valid() else 0
	if team <= 0 and not rules.allow_unassigned:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "Join a side before watching."
		)

	return DotResult.success(null)


## Whether one viewer may watch one target, and why not when they may not.
##
## Public because a client draws the cycle list from it, and a client that guesses the
## rule shows a name the server will refuse.
func may_watch(key: String, target: String) -> DotResult:
	if target == key:
		return DotResult.fail(
			DotError.CODE_INVALID, "Nobody watches themselves."
		)

	var allowed := may_spectate(key)
	if not allowed.ok:
		return allowed

	if not _exists(target):
		return DotResult.fail(
			DotError.CODE_INVALID, "There is nobody called '%s'." % target
		)

	if not rules.cycle_includes_dead and alive_fn.is_valid() \
			and not bool(alive_fn.call(target)):
		return DotResult.fail(
			DotError.CODE_STATE, "%s is dead." % target
		)

	if rules.force_camera == 1 and team_fn.is_valid():
		var mine := int(team_fn.call(key))
		var theirs := int(team_fn.call(target))
		if mine > 0 and mine != theirs:
			return DotResult.fail(
				DotError.CODE_FORBIDDEN,
				"This server only lets you watch your own side."
			)

	if target_filter.is_valid() and not bool(target_filter.call(key, target)):
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "%s may not be watched." % target
		)

	return DotResult.success(null)


## Point a viewer at somebody.
func watch(
	key: String, target: String, mode: int = DotSpectatorView.Mode.FIRST_PERSON
) -> DotResult:
	if not authoritative:
		return DotResult.fail(
			DotError.CODE_STATE, "A mirroring spectator manager is told, not asked."
		)

	var allowed := may_watch(key, target)
	if not allowed.ok:
		return allowed

	var wanted := _permitted_mode(mode)
	var v := view(key)
	v.mode = wanted as DotSpectatorView.Mode
	v.target = target
	v.until_tick = -1
	view_changed.emit(key, int(v.mode), target)
	return DotResult.success(null)


## Change the camera without changing who is being watched.
func set_mode(key: String, mode: int) -> DotResult:
	var v := view(key)
	if mode == DotSpectatorView.Mode.ROAMING and not rules.allow_roaming:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "Roaming is not allowed on this server."
		)
	var allowed := may_spectate(key)
	if not allowed.ok:
		return allowed

	var wanted := _permitted_mode(mode)
	if wanted != mode:
		# Said out loud rather than silently corrected: a player who pressed a key and
		# got a different camera with no explanation reports it as a broken control.
		DotLog.debug(
			"spectate",
			"%s asked for %s and the server's policy gives %s."
				% [
					key,
					DotSpectatorView.Mode.keys()[mode],
					DotSpectatorView.Mode.keys()[wanted],
				]
		)
	v.mode = wanted as DotSpectatorView.Mode
	v.until_tick = -1
	if not v.follows_target():
		v.target = ""
	view_changed.emit(key, int(v.mode), v.target)
	return DotResult.success(wanted)


## What the policy actually permits, given what was asked for.
func _permitted_mode(mode: int) -> int:
	if rules.forbids_everything():
		return DotSpectatorView.Mode.FIXED
	if rules.forces_first_person():
		# Source's rule: "own team only" also means first person, because a chase
		# camera behind a team-mate sees round corners that team-mate cannot.
		if mode == DotSpectatorView.Mode.CHASE \
				or mode == DotSpectatorView.Mode.ROAMING:
			return DotSpectatorView.Mode.FIRST_PERSON
	if mode == DotSpectatorView.Mode.ROAMING and not rules.allow_roaming:
		return DotSpectatorView.Mode.FIRST_PERSON
	return mode


## Stop watching. What a game calls when somebody respawns.
func stop(key: String) -> void:
	var v: DotSpectatorView = _views.get(key, null)
	if v == null:
		return
	v.mode = DotSpectatorView.Mode.NONE
	v.target = ""
	v.until_tick = -1
	v.killer = ""
	view_changed.emit(key, int(v.mode), "")


# --- Cycling ------------------------------------------------------------------

## Everybody this viewer is allowed to watch, in a stable order.
##
## Sorted by key rather than by join order: a list that reorders itself as players die
## makes "next" unpredictable, and a spectator pressing next twice expects to have moved
## two places rather than to be back where they started.
func targets_for(key: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not participants_fn.is_valid():
		return out
	var all: Array = Array(participants_fn.call() as PackedStringArray)
	all.sort()
	for other: Variant in all:
		var name := str(other)
		if may_watch(key, name).ok:
			out.append(name)
	return out


func next_target(key: String) -> DotResult:
	return _cycle(key, 1)


func previous_target(key: String) -> DotResult:
	return _cycle(key, -1)


func _cycle(key: String, step: int) -> DotResult:
	var list := targets_for(key)
	if list.is_empty():
		return DotResult.fail(
			DotError.CODE_STATE, "There is nobody to watch."
		)
	var v := view(key)
	var at := -1
	for i in range(list.size()):
		if list[i] == v.target:
			at = i
			break
	var next := 0 if at < 0 else posmod(at + step, list.size())
	return watch(
		key, list[next],
		v.mode if v.follows_target() else DotSpectatorView.Mode.FIRST_PERSON
	)


# --- Events a game reports -----------------------------------------------------

## Somebody died. Starts the death camera, then the freeze camera, then a target.
##
## [b]The whole chain is here rather than in the game[/b] because it is three timers
## that have to hand over to each other, and every game that writes it itself gets the
## last hand-over wrong: the freeze camera ends and nothing takes over, so the player
## sits looking at their killer until they respawn.
func on_death(
	key: String, where: Vector3, by: String = "", tick: int = -1
) -> void:
	var at := tick if tick >= 0 else _tick
	var v := view(key)
	v.death_position = where
	v.killer = by

	if rules.forbids_everything():
		v.mode = DotSpectatorView.Mode.FIXED
		v.until_tick = -1
		view_changed.emit(key, int(v.mode), "")
		return

	if rules.death_cam_ticks > 0:
		v.mode = DotSpectatorView.Mode.DEATH_CAM
		v.target = ""
		v.until_tick = at + rules.death_cam_ticks
		view_changed.emit(key, int(v.mode), "")
		return

	_after_death_cam(v, at)


## The freeze camera, on whoever did it.
##
## Deliberately not filtered by [method may_watch]: your killer is on the other side,
## which every restrictive policy forbids, and the whole point of this camera is that
## you see them. It is a fixed frame for a fixed time, chosen by the server, and it
## hands over on its own — which is why [method advance] leaves timed cameras alone.
func _after_death_cam(v: DotSpectatorView, at: int) -> void:
	if rules.freeze_cam_ticks > 0 and v.killer != "" and _exists(v.killer):
		v.mode = DotSpectatorView.Mode.FREEZE_CAM
		v.target = v.killer
		v.until_tick = at + rules.freeze_cam_ticks
		view_changed.emit(v.key, int(v.mode), v.target)
		return
	_hand_over(v)


## The end of the chain: find somebody to watch, or sit still.
func _hand_over(v: DotSpectatorView) -> void:
	v.until_tick = -1
	var list := targets_for(v.key)
	if list.is_empty():
		v.mode = DotSpectatorView.Mode.FIXED
		v.target = ""
		view_changed.emit(v.key, int(v.mode), "")
		return
	v.mode = _permitted_mode(DotSpectatorView.Mode.FIRST_PERSON) as DotSpectatorView.Mode
	v.target = list[0]
	view_changed.emit(v.key, int(v.mode), v.target)


## Somebody respawned. Stops them watching.
func on_spawn(key: String) -> void:
	stop(key)


## Somebody left. Moves anybody watching them.
##
## [b]Call it after the roster has dropped them[/b], not before: the replacement is
## chosen from [member participants_fn], so a game that reports the departure first and
## removes the player second picks the player who just left.
func on_leave(key: String) -> void:
	forget(key)
	if not rules.auto_retarget:
		return
	for id: Variant in _views.keys():
		var v: DotSpectatorView = _views[id]
		if v.target != key:
			continue
		_retarget(v, &"left")


func _retarget(v: DotSpectatorView, reason: StringName) -> void:
	var from := v.target
	var list := targets_for(v.key)
	if list.is_empty():
		v.mode = DotSpectatorView.Mode.FIXED
		v.target = ""
		retargeted.emit(v.key, from, "", reason)
		return
	v.target = list[0]
	v.until_tick = -1
	if not v.follows_target():
		v.mode = _permitted_mode(
			DotSpectatorView.Mode.FIRST_PERSON
		) as DotSpectatorView.Mode
	retargeted.emit(v.key, from, v.target, reason)


# --- The tick ------------------------------------------------------------------

func advance(tick: int) -> void:
	_tick = tick
	if not authoritative:
		return

	if rules.delay_ticks > 0:
		history.record(tick, _poses())

	for id: Variant in _views.keys():
		var v: DotSpectatorView = _views[id]
		if not v.is_watching():
			continue

		if v.is_timed() and tick >= v.until_tick:
			var was := v.mode
			if was == DotSpectatorView.Mode.DEATH_CAM:
				_after_death_cam(v, tick)
			else:
				_hand_over(v)
			timed_out.emit(v.key, int(was))
			continue

		if not rules.auto_retarget:
			continue
		if v.is_timed():
			# A timed camera is the SERVER's own choice and hands over on its own when
			# it runs out. Applying the target policy to one breaks the single most
			# important camera in the game: the freeze camera shows your KILLER, who is
			# by definition on the other team — which is exactly the target
			# `force_camera 1` forbids. Retargeting it moved every player off their
			# killer on the tick after they died, so nobody on a competitive server
			# ever saw who shot them, and every check about the camera's *mode* still
			# passed because the mode was right and only the target had moved.
			continue
		if not v.follows_target() or v.target == "":
			continue
		if may_watch(v.key, v.target).ok:
			continue
		# A spectator whose target disconnects or dies is looking at nothing, with no
		# input that obviously fixes it, and reports it as the game freezing.
		_retarget(v, &"unavailable")


func _poses() -> Dictionary:
	var out: Dictionary = {}
	if not pose_fn.is_valid() or not participants_fn.is_valid():
		return out
	for key in (participants_fn.call() as PackedStringArray):
		out[key] = pose_fn.call(key) as Transform3D
	return out


# --- The camera ------------------------------------------------------------------

## Where a viewer's camera is, this tick.
##
## Returns a [Transform3D] and touches nothing. A game assigns it to its own rig, which
## is the only arrangement that works for a 3D camera, a 2D one and a replay viewer at
## the same time.
func camera_of(key: String) -> Transform3D:
	var v: DotSpectatorView = _views.get(key, null)
	if v == null or not v.is_watching():
		return Transform3D.IDENTITY

	match v.mode:
		DotSpectatorView.Mode.ROAMING:
			return Transform3D(v.free_basis, v.free_position)

		DotSpectatorView.Mode.FIXED:
			if fixed_cameras.is_empty():
				return Transform3D.IDENTITY
			return fixed_cameras[posmod(v.fixed_index, fixed_cameras.size())]

		DotSpectatorView.Mode.DEATH_CAM:
			# Fixed on where they fell, looking at whoever did it. A death camera that
			# follows a corpse goes into the floor with it.
			var look := v.death_position + Vector3.UP * 2.0
			var at := v.death_position
			if v.killer != "":
				var killer_pose := _pose_of(v.killer)
				if killer_pose[1]:
					at = (killer_pose[0] as Transform3D).origin
			return _looking_from(look, at)

		DotSpectatorView.Mode.FIRST_PERSON, DotSpectatorView.Mode.FREEZE_CAM:
			var got := _pose_of(v.target)
			if not got[1]:
				return Transform3D.IDENTITY
			return got[0] as Transform3D

		DotSpectatorView.Mode.CHASE:
			var chase := _pose_of(v.target)
			if not chase[1]:
				return Transform3D.IDENTITY
			var pose := chase[0] as Transform3D
			var back := pose.basis.z.normalized() * rules.chase_distance
			var up := Vector3.UP * rules.chase_height
			return Transform3D(pose.basis, pose.origin + back + up)

		_:
			return Transform3D.IDENTITY


## The same answer for a game on the XZ plane: a position and a facing angle.
func camera_2d_of(key: String) -> Array:
	var t := camera_of(key)
	var forward := -t.basis.z
	return [Vector2(t.origin.x, t.origin.z), atan2(forward.x, forward.z)]


## A pose, through the delay if there is one. [code][Transform3D, found][/code].
func _pose_of(key: String) -> Array:
	if key == "":
		return [Transform3D.IDENTITY, false]
	if rules.delay_ticks > 0:
		return history.sample(_tick, rules.delay_ticks, key)
	if not pose_fn.is_valid():
		return [Transform3D.IDENTITY, false]
	return [pose_fn.call(key) as Transform3D, true]


static func _looking_from(from: Vector3, at: Vector3) -> Transform3D:
	var dir := at - from
	if dir.length_squared() < 0.0001:
		return Transform3D(Basis.IDENTITY, from)
	var t := Transform3D(Basis.IDENTITY, from)
	# looking_at with a near-vertical direction produces a degenerate basis, which draws
	# a camera pointing at nothing and reads as the world having vanished.
	var up := Vector3.UP
	if absf(dir.normalized().dot(up)) > 0.999:
		up = Vector3.FORWARD
	return t.looking_at(at, up)


## Move a roaming camera. The game feeds this from its own input sampler, because what
## a free camera's controls are is a game's decision and not this addon's.
func move_free(key: String, position: Vector3, basis: Basis) -> DotResult:
	var v := view(key)
	if v.mode != DotSpectatorView.Mode.ROAMING:
		return DotResult.fail(
			DotError.CODE_STATE, "%s is not roaming." % key
		)
	v.free_position = position
	v.free_basis = basis
	return DotResult.success(null)


func _exists(key: String) -> bool:
	if key == "" or not participants_fn.is_valid():
		return false
	return (participants_fn.call() as PackedStringArray).has(key)


# --- The wire --------------------------------------------------------------------

func to_wire(key: String) -> Dictionary:
	var v: DotSpectatorView = _views.get(key, null)
	return {"k": key, "v": v.to_wire() if v != null else {}}


func apply_wire(w: Dictionary) -> void:
	var key := str(w.get("k", ""))
	if key == "":
		return
	var packed: Dictionary = w.get("v", {})
	if packed.is_empty():
		return
	view(key).apply_wire(packed)


func describe() -> Dictionary:
	return {
		"authoritative": authoritative,
		"viewers": viewers().size(),
		"delay": rules.delay_ticks if rules != null else 0,
		"history": history.size() if history != null else 0,
		"tick": _tick,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append(
		"DotSpectatorManager %s tick=%d force_camera=%d delay=%d"
			% [
				"authoritative" if authoritative else "mirroring",
				_tick,
				rules.force_camera if rules != null else 0,
				rules.delay_ticks if rules != null else 0,
			]
	)
	for key in viewers():
		var v: DotSpectatorView = _views[key]
		out.append(
			"  %-16s %-13s %s%s"
				% [
					key,
					DotSpectatorView.Mode.keys()[v.mode],
					v.target if v.target != "" else "-",
					(" until %d" % v.until_tick) if v.is_timed() else "",
				]
		)
	return out
